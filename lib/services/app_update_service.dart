import 'dart:convert';
import 'dart:io';

import 'package:agente_desconexiones/config/constants.dart';
import 'package:agente_desconexiones/services/app_version_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    this.mandatory = true,
    this.releaseNotes,
  });

  final String version;
  final int buildNumber;
  final String apkUrl;
  final bool mandatory;
  final String? releaseNotes;

  bool get isNewerThanInstalled =>
      buildNumber > AppVersionService.buildNumberInt;
}

enum AppUpdateResult {
  upToDate,
  installStarted,
  skippedError,
}

/// Comprueba actualizaciones al abrir la app, descarga el APK y abre el instalador.
/// Fuente 1: `configuracion_app` en Supabase (prioridad).
/// Fuente 2: último release de GitHub (`kGitHubRepoOwner` / `kGitHubRepoName`).
class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static const _channel = MethodChannel(
    'com.creacionestecnologicas.agente_desconexiones/app_launcher',
  );

  static const _configClaves = [
    'creabox_apk_url',
    'creabox_version',
    'creabox_build',
    'creabox_actualizacion_forzada',
    'creabox_notas_actualizacion',
  ];

  Future<AppUpdateInfo?> fetchLatestUpdate() async {
    final fromSupabase = await _fetchFromSupabase();
    if (fromSupabase != null) return fromSupabase;
    return _fetchFromGitHub();
  }

  Future<AppUpdateInfo?> _fetchFromSupabase() async {
    try {
      final rows = await Supabase.instance.client
          .from('configuracion_app')
          .select('clave, valor')
          .inFilter('clave', _configClaves);

      final map = <String, String>{};
      for (final row in rows as List) {
        final clave = row['clave']?.toString() ?? '';
        if (clave.isNotEmpty) {
          map[clave] = row['valor']?.toString() ?? '';
        }
      }

      final url = map['creabox_apk_url']?.trim() ?? '';
      final buildStr = map['creabox_build']?.trim() ?? '';
      if (url.isEmpty || buildStr.isEmpty) return null;

      final build = int.tryParse(buildStr);
      if (build == null) return null;

      final version = map['creabox_version']?.trim() ?? '';
      return AppUpdateInfo(
        version: version.isNotEmpty ? version : AppVersionService.version,
        buildNumber: build,
        apkUrl: url,
        mandatory: map['creabox_actualizacion_forzada'] != 'false',
        releaseNotes: map['creabox_notas_actualizacion'],
      );
    } catch (e) {
      print('⚠️ [AppUpdate] Supabase: $e');
      return null;
    }
  }

  Future<AppUpdateInfo?> _fetchFromGitHub() async {
    if (kGitHubRepoOwner.isEmpty || kGitHubRepoName.isEmpty) return null;
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$kGitHubRepoOwner/$kGitHubRepoName/releases/latest',
      );
      final resp = await http
          .get(
            uri,
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        print('⚠️ [AppUpdate] GitHub HTTP ${resp.statusCode}');
        return null;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final assets = data['assets'] as List<dynamic>? ?? [];
      final tag = (data['tag_name'] as String? ?? '').replaceFirst(
        RegExp(r'^v'),
        '',
      );

      Map<String, dynamic>? apkAsset;
      for (final raw in assets) {
        final asset = raw as Map<String, dynamic>;
        final name = asset['name']?.toString() ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apkAsset = asset;
          break;
        }
      }
      if (apkAsset == null) return null;

      final url = apkAsset['browser_download_url']?.toString() ?? '';
      if (url.isEmpty) return null;

      final assetName = apkAsset['name']?.toString() ?? '';
      final build = _parseBuildNumber(assetName) ??
          _parseBuildNumber(tag) ??
          0;
      if (build <= 0) return null;

      return AppUpdateInfo(
        version: _parseVersionLabel(tag) ?? tag,
        buildNumber: build,
        apkUrl: url,
        mandatory: true,
        releaseNotes: data['body'] as String?,
      );
    } catch (e) {
      print('⚠️ [AppUpdate] GitHub: $e');
      return null;
    }
  }

  int? _parseBuildNumber(String text) {
    final match = RegExp(r'\+(\d+)').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  String? _parseVersionLabel(String tag) {
    final clean = tag.replaceFirst(RegExp(r'^v'), '');
    final plus = clean.indexOf('+');
    if (plus > 0) return clean.substring(0, plus);
    return clean.isNotEmpty ? clean : null;
  }

  /// Comprueba, descarga e instala si hay build más reciente.
  Future<AppUpdateResult> checkDownloadAndInstall({
    void Function(double progress)? onProgress,
    void Function(String message)? onStatus,
  }) async {
    if (!Platform.isAndroid) return AppUpdateResult.upToDate;

    onStatus?.call('Buscando actualizaciones...');
    final info = await fetchLatestUpdate();
    if (info == null) {
      print('ℹ️ [AppUpdate] Sin metadatos de release');
      return AppUpdateResult.skippedError;
    }
    if (!info.isNewerThanInstalled) {
      print(
        'ℹ️ [AppUpdate] Al día: build ${AppVersionService.buildNumberInt} '
        '≥ remoto ${info.buildNumber}',
      );
      return AppUpdateResult.upToDate;
    }

    print(
      '📦 [AppUpdate] Nueva versión ${info.version}+${info.buildNumber} '
      '(instalada ${AppVersionService.versionWithBuild})',
    );
    onStatus?.call('Descargando v${info.version}...');

    final path = await _downloadApk(info.apkUrl, onProgress: onProgress);
    if (path == null) return AppUpdateResult.skippedError;

    onStatus?.call('Abriendo instalador...');
    await _channel.invokeMethod<void>('installApkFromPath', path);
    return AppUpdateResult.installStarted;
  }

  Future<String?> _downloadApk(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/apk/creabox_update.apk');
      await file.parent.create(recursive: true);
      if (await file.exists()) await file.delete();

      final dio = Dio();
      await dio.download(
        url,
        file.path,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
        options: Options(
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
          receiveTimeout: const Duration(minutes: 15),
          headers: const {'Accept': 'application/octet-stream'},
        ),
      );

      if (!await file.exists()) return null;
      final size = await file.length();
      if (size < 1024 * 100) {
        print('❌ [AppUpdate] APK demasiado pequeño ($size bytes)');
        return null;
      }
      return file.path;
    } catch (e) {
      print('❌ [AppUpdate] Descarga: $e');
      return null;
    }
  }
}
