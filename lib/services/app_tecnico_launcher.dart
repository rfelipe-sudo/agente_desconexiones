import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

typedef AppTecnicoCredentialsErrorCallback = void Function();
typedef AppTecnicoClosedCallback = void Function();

/// Lanza la app legacy VTR Técnicos (`com.vtrapp.tecnico`) embebida en assets.
class AppTecnicoLauncher {
  AppTecnicoLauncher._();

  static const packageName = 'com.vtrapp.tecnico';
  static const assetApkPath = 'assets/apk/tecnicos.apk';

  static const _channel = MethodChannel(
    'com.creacionestecnologicas.agente_desconexiones/app_launcher',
  );

  static AppTecnicoCredentialsErrorCallback? onCredentialsError;
  static AppTecnicoClosedCallback? onClosed;
  static bool _handlerReady = false;

  /// Escucha eventos desde [AppTecnicoActivity] (proceso nativo).
  static void ensureNativeCallbacksRegistered() {
    if (_handlerReady) return;
    _handlerReady = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'credentialsError') {
        onCredentialsError?.call();
      } else if (call.method == 'appTecnicoClosed') {
        onClosed?.call();
      }
    });
  }

  static Future<bool> isInstalled() async {
    final instalado =
        await _channel.invokeMethod<bool>('isInstalled', packageName);
    return instalado ?? false;
  }

  static Future<void> launch() async {
    await _channel.invokeMethod<void>('launchApp', packageName);
  }

  static Future<void> installFromAssets() async {
    final bytes = await rootBundle.load(assetApkPath);
    final cacheDir = await getTemporaryDirectory();
    final apkFile = File('${cacheDir.path}/apk/tecnicos.apk');
    await apkFile.parent.create(recursive: true);
    await apkFile.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    await _channel.invokeMethod<void>('installApkFromPath', apkFile.path);
  }

  /// Abre WebView nativo (proceso aparte) con la URL del servidor local Dart.
  /// Si [autoUsername] y [autoPassword] vienen de Supabase, rellena el login VTR.
  static Future<void> openEmbeddedWebView(
    String url, {
    String? autoUsername,
    String? autoPassword,
  }) async {
    final payload = <String, String>{'url': url};
    final user = autoUsername?.trim();
    final pass = autoPassword;
    if (user != null && user.isNotEmpty && pass != null && pass.isNotEmpty) {
      payload['username'] = user;
      payload['password'] = pass;
    }
    await _channel.invokeMethod<void>('openAppTecnicoWebView', payload);
  }
}
