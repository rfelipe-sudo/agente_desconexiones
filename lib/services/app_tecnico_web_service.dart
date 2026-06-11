import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Extrae `assets/www` del APK embebido en un isolate (no bloquea la UI).
class AppTecnicoWebService {
  AppTecnicoWebService._();

  static const assetApkPath = 'assets/apk/tecnicos.apk';
  static const wwwPrefix = 'assets/www/';
  /// Incrementar si cambia el parche o el APK embebido.
  /// v6: fix cache APK embebida (antes reutilizaba tecnicos_embedded.apk viejo).
  ///     APK VTR 3.3.0 (tecnicos-prod-3.3.0.apk).
  static const cacheVersion = '6';

  static Future<Directory> ensureWwwExtracted({
    void Function(double progress, String status)? onProgress,
  }) async {
    final support = await getApplicationSupportDirectory();
    final wwwDir = Directory('${support.path}/app_tecnico_www');
    final marker = File('${wwwDir.path}/.cache_v$cacheVersion');
    final index = File('${wwwDir.path}/index.html');

    if (marker.existsSync() && index.existsSync()) {
      await _patchBundle(wwwDir);
      onProgress?.call(1, 'Listo');
      return wwwDir;
    }

    onProgress?.call(0.05, 'Preparando App Técnico...');
    await _cleanupLegacyEmbeddedApks(support);
    final tempApk = await _copyEmbeddedApk(support, onProgress: onProgress);

    if (wwwDir.existsSync()) {
      await wwwDir.delete(recursive: true);
    }

    onProgress?.call(0.12, 'Descomprimiendo en segundo plano…');
    final count = await _extractInBackground(
      apkPath: tempApk.path,
      destPath: wwwDir.path,
      onProgress: onProgress,
    );

    if (count <= 0) {
      throw StateError('El APK no contiene archivos en $wwwPrefix');
    }

    await _patchBundle(wwwDir);
    await marker.writeAsString(DateTime.now().toIso8601String());
    onProgress?.call(1, 'Listo');
    return wwwDir;
  }

  /// Copia siempre el APK del asset Flutter (vinculado a [cacheVersion]).
  static Future<File> _copyEmbeddedApk(
    Directory support, {
    void Function(double progress, String status)? onProgress,
  }) async {
    final tempApk = File('${support.path}/tecnicos_embedded_v$cacheVersion.apk');
    onProgress?.call(0.08, 'Copiando APK embebido (v$cacheVersion)…');
    final data = await rootBundle.load(assetApkPath);
    await tempApk.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    return tempApk;
  }

  /// Elimina copias cacheadas de APKs anteriores (causaban bundle 3.2.3 stale).
  static Future<void> _cleanupLegacyEmbeddedApks(Directory support) async {
    final legacy = File('${support.path}/tecnicos_embedded.apk');
    if (legacy.existsSync()) {
      await legacy.delete();
    }
    try {
      await for (final entity in support.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.startsWith('tecnicos_embedded_v') &&
            name != 'tecnicos_embedded_v$cacheVersion.apk') {
          await entity.delete();
        }
      }
    } catch (_) {}
  }

  static Future<int> _extractInBackground({
    required String apkPath,
    required String destPath,
    void Function(double progress, String status)? onProgress,
  }) async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn(
      _extractIsolateEntry,
      {
        'apkPath': apkPath,
        'destPath': destPath,
        'prefix': wwwPrefix,
        'sendPort': port.sendPort,
      },
    );

    var count = 0;
    try {
      await for (final message in port) {
        if (message is! Map) continue;
        switch (message['type']) {
          case 'progress':
            onProgress?.call(
              0.12 + (0.83 * (message['ratio'] as num).toDouble()),
              message['status'] as String? ?? 'Descomprimiendo…',
            );
          case 'done':
            count = message['count'] as int? ?? 0;
            port.close();
            isolate.kill(priority: Isolate.immediate);
            return count;
          case 'error':
            throw StateError(message['error']?.toString() ?? 'Error al descomprimir');
        }
      }
    } catch (_) {
      port.close();
    }
    return count;
  }

  static Future<void> _patchBundle(Directory wwwDir) async {
    await _patchIndexHtml(wwwDir);
    await _patchMainJsInterceptor(wwwDir);
    await _writeCreaboxBridge(wwwDir);
  }

  /// Corrige `<base href="/">` e inyecta el bridge CREABOX antes de Cordova.
  static Future<void> _patchIndexHtml(Directory wwwDir) async {
    final index = File('${wwwDir.path}/index.html');
    if (!index.existsSync()) return;

    var html = await index.readAsString();
    html = html
        .replaceAll('<base href="/" />', '<base href="./">')
        .replaceAll('<base href="/"/>', '<base href="./">')
        .replaceAll('<base href="/">', '<base href="./">');

    const bridgeTag =
        '<script src="creabox-bridge.js"></script>';
    if (!html.contains('creabox-bridge.js')) {
      html = html.replaceFirst(
        '<script type="text/javascript" src="cordova.',
        '$bridgeTag<script type="text/javascript" src="cordova.',
      );
    }

    await index.writeAsString(html);
  }

  /// Evita que Angular HttpHeaders lance error si device.* viene undefined.
  static Future<void> _patchMainJsInterceptor(Directory wwwDir) async {
    final index = File('${wwwDir.path}/index.html');
    if (!index.existsSync()) return;

    final html = await index.readAsString();
    final match = RegExp(r'main\.[a-f0-9]+\.js').firstMatch(html);
    if (match == null) return;

    final mainFile = File('${wwwDir.path}/${match.group(0)}');
    if (!mainFile.existsSync()) return;

    var js = await mainFile.readAsString();
    const needle =
        '.set("X-manufacturer",this.device.manufacturer)})).clone({headers:e.headers.set("X-model",this.device.model)})).clone({headers:e.headers.set("X-platform",this.device.platform)})).clone({headers:e.headers.set("X-uuid",this.device.uuid)})).clone({headers:e.headers.set("X-version",this.device.version)}';
    const patch =
        '.set("X-manufacturer",this.device.manufacturer||"unknown")})).clone({headers:e.headers.set("X-model",this.device.model||"unknown")})).clone({headers:e.headers.set("X-platform",this.device.platform||"Android")})).clone({headers:e.headers.set("X-uuid",this.device.uuid||"unknown")})).clone({headers:e.headers.set("X-version",this.device.version||"13")}';

    if (js.contains(needle) && !js.contains('this.device.manufacturer||"unknown"')) {
      js = js.replaceFirst(needle, patch);
      await mainFile.writeAsString(js);
    }
  }

  static Future<void> _writeCreaboxBridge(Directory wwwDir) async {
    const bridgeJs = r'''
(function () {
  var defaults = {
    platform: 'Android',
    manufacturer: 'unknown',
    model: 'unknown',
    uuid: 'unknown',
    version: '13',
    isVirtual: false,
    serial: 'unknown',
    available: true,
    cordova: '9.1.0'
  };

  window.__creaboxApplyDevice = function (info) {
    try {
      var merged = {};
      for (var k in defaults) merged[k] = defaults[k];
      if (info) {
        for (var p in info) merged[p] = info[p] == null ? defaults[p] : info[p];
      }
      if (window.device) {
        for (var q in merged) window.device[q] = merged[q];
      }
      window.__CREABOX_DEVICE__ = merged;
    } catch (e) {
      console.log('[creabox] applyDevice', e);
    }
  };

  window.__creaboxApplyDevice(null);

  document.addEventListener('deviceready', function () {
    window.__creaboxApplyDevice(window.__CREABOX_DEVICE__ || null);
  }, false);
})();
''';
    await File('${wwwDir.path}/creabox-bridge.js').writeAsString(bridgeJs);
  }

  /// URL base `file://` para cargar el bundle en WebView.
  static String wwwBaseUrl(Directory wwwDir) {
    final path = wwwDir.absolute.path;
    return path.endsWith('/') ? 'file://$path' : 'file://$path/';
  }
}

/// Entry del isolate — top-level obligatorio.
void _extractIsolateEntry(Map<String, dynamic> args) {
  final sendPort = args['sendPort'] as SendPort;
  try {
    final apkPath = args['apkPath'] as String;
    final destPath = args['destPath'] as String;
    final prefix = args['prefix'] as String;

    Directory(destPath).createSync(recursive: true);

    InputFileStream? input;
    try {
      input = InputFileStream(apkPath);
      final archive = ZipDecoder().decodeStream(input, verify: false);

      final entries = archive.where(
        (e) => e.isFile && e.name.startsWith(prefix),
      ).toList();

      if (entries.isEmpty) {
        sendPort.send({'type': 'error', 'error': 'Sin archivos $prefix'});
        return;
      }

      var done = 0;
      for (final entry in entries) {
        final rel = entry.name.substring(prefix.length);
        if (rel.isEmpty) continue;
        final out = File('$destPath/$rel');
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(entry.content as List<int>);
        done++;
        if (done % 50 == 0 || done == entries.length) {
          sendPort.send({
            'type': 'progress',
            'ratio': done / entries.length,
            'status': 'Copiando ($done/${entries.length})…',
          });
        }
      }

      sendPort.send({'type': 'done', 'count': done});
    } finally {
      input?.close();
    }
  } catch (e) {
    sendPort.send({'type': 'error', 'error': e.toString()});
  }
}
