import 'package:package_info_plus/package_info_plus.dart';

/// Versión de la app leída desde `pubspec.yaml` (campo `version`).
/// Ej.: `1.5.2+7` → version `1.5.2`, build `7`.
class AppVersionService {
  AppVersionService._();

  static String _version = '1.5.2';
  static String _buildNumber = '0';

  static String get version => _version;
  static String get buildNumber => _buildNumber;
  static String get versionLabel => 'v$_version';
  static String get versionWithBuild => '$_version+$_buildNumber';
  static int get buildNumberInt => int.tryParse(_buildNumber) ?? 0;

  static Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    _version = info.version;
    _buildNumber = info.buildNumber;
  }
}
