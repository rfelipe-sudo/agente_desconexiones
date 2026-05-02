import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Cliente HTTP a la ONT (192.168.1.1) para listar dispositivos LAN/WiFi.
class OntWifiService {
  static const String _ip = '192.168.1.1';
  static const String _user = 'root';
  static const String _pass = 'VAdtzq39';

  String? _sessionCookie;

  static String get _base => 'http://$_ip';

  String? get sessionCookie => _sessionCookie;

  String? _cookieFromResponse(http.Response r) {
    final raw = r.headers['set-cookie'];
    if (raw == null || raw.trim().isEmpty) return null;
    final first = raw.split(';').first.trim();
    if (first.contains('=')) return first;
    return null;
  }

  /// POST login; guarda cookie si existe.
  Future<bool> login() async {
    try {
      final loginUri = Uri.parse('$_base/login.cgi');
      final loginResp = await http
          .post(
            loginUri,
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: 'UserName=$_user&PassWord=$_pass',
          )
          .timeout(const Duration(seconds: 20));

      final cookie = _cookieFromResponse(loginResp);
      if (cookie != null && cookie.isNotEmpty) {
        _sessionCookie = cookie;
        return true;
      }
      if (loginResp.statusCode == 200) {
        _sessionCookie = cookie;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Lista dispositivos: metadatos desde BBSP [GetLanUserDevInfo.asp] (`USERDevice`)
  /// y RSSI cruzado por MAC desde [WlanBasic.asp].
  Future<List<OntDevice>> getDevices() async {
    final cookie = _sessionCookie;
    if (cookie == null || cookie.isEmpty) return [];

    try {
      final uriLan =
          Uri.parse('$_base/html/bbsp/common/GetLanUserDevInfo.asp');
      final uriWlan =
          Uri.parse('$_base/html/amp/wlanbasic/WlanBasic.asp');
      final headers = {'Cookie': cookie};

      final results = await Future.wait([
        http.get(uriLan, headers: headers).timeout(const Duration(seconds: 20)),
        http.get(uriWlan, headers: headers).timeout(const Duration(seconds: 20)),
      ]);

      final lanResp = results[0];
      final wlanResp = results[1];

      if (lanResp.statusCode != 200) return [];

      final rssiByMac = wlanResp.statusCode == 200
          ? _parseRssiFromWlanBasic(wlanResp.body)
          : <String, int>{};

      return _parseDevicesFromLanHtml(lanResp.body, rssiByMac);
    } catch (_) {
      return [];
    }
  }

  /// `USERDevice` en BBSP (5 o 6 argumentos; el RSSI del LAN no se usa).
  static final _userDeviceRe6 = RegExp(
    r'new\s+USERDevice\s*\(\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*(-?\d+)\s*\)',
    caseSensitive: false,
  );

  static final _userDeviceRe5 = RegExp(
    r'new\s+USERDevice\s*\(\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)"\s*\)',
    caseSensitive: false,
  );

  /// Fallback si el firmware aún expone `stWlanUser` en la misma página LAN.
  static final _wlanUserMetaRe = RegExp(
    r'new\s+stWlanUser\s*\(\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*(-?\d+)\s*\)',
    caseSensitive: false,
  );

  static String _macKey(String mac) {
    final hex = mac.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    if (hex.length != 12) return mac.toUpperCase();
    final parts = <String>[];
    for (var i = 0; i < 12; i += 2) {
      parts.add(hex.substring(i, i + 2));
    }
    return parts.join(':');
  }

  /// Misma forma que [_wlanUserMetaRe]; MAC en grupo 3, RSSI en grupo 6.
  static final _wlanUserRssiRe = RegExp(
    r'new\s+stWlanUser\s*\(\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*(-?\d+)\s*\)',
    caseSensitive: false,
  );

  static final _wlanStationRssiRe = RegExp(
    r'new\s+stWlanStation\s*\(\s*"[^"]*",\s*"((?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})"\s*,\s*(-?\d+)',
    caseSensitive: false,
  );

  static final _wlanAssocRssiRe = RegExp(
    r'new\s+stWlanAssocDevice\s*\(\s*"[^"]*",\s*"((?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})"\s*,\s*(-?\d+)',
    caseSensitive: false,
  );

  /// Mejor RSSI por MAC (menos negativo gana) si hay varias entradas.
  Map<String, int> _parseRssiFromWlanBasic(String html) {
    final best = <String, int>{};

    void put(String? macRaw, int? rssi) {
      if (macRaw == null || rssi == null) return;
      final k = _macKey(macRaw);
      final prev = best[k];
      if (prev == null || rssi > prev) best[k] = rssi;
    }

    for (final m in _wlanUserRssiRe.allMatches(html)) {
      put(m.group(3), int.tryParse(m.group(6) ?? ''));
    }
    for (final m in _wlanStationRssiRe.allMatches(html)) {
      put(m.group(1), int.tryParse(m.group(2) ?? ''));
    }
    for (final m in _wlanAssocRssiRe.allMatches(html)) {
      put(m.group(1), int.tryParse(m.group(2) ?? ''));
    }

    return best;
  }

  List<OntDevice> _parseDevicesFromLanHtml(
    String html,
    Map<String, int> rssiByMac,
  ) {
    final list = <OntDevice>[];
    final seen = <String>{};

    void addRow(String name, String mac, String ip, String port) {
      if (mac.trim().isEmpty) return;
      final k = _macKey(mac);
      if (seen.contains(k)) return;
      seen.add(k);
      final rssi = _rssiForPortAndMac(port, mac, rssiByMac);
      list.add(
        OntDevice(
          name: name,
          mac: mac,
          ip: ip,
          port: port,
          rssi: rssi,
        ),
      );
    }

    for (final m in _userDeviceRe6.allMatches(html)) {
      addRow(
        m.group(2) ?? '',
        m.group(3) ?? '',
        m.group(4) ?? '',
        m.group(5) ?? '',
      );
    }
    for (final m in _userDeviceRe5.allMatches(html)) {
      addRow(
        m.group(2) ?? '',
        m.group(3) ?? '',
        m.group(4) ?? '',
        m.group(5) ?? '',
      );
    }

    if (list.isEmpty) {
      for (final m in _wlanUserMetaRe.allMatches(html)) {
        addRow(
          m.group(2) ?? '',
          m.group(3) ?? '',
          m.group(4) ?? '',
          m.group(5) ?? '',
        );
      }
    }

    return list;
  }

  int _rssiForPortAndMac(String port, String mac, Map<String, int> rssiByMac) {
    if (port.contains('ETH')) return 0;
    final k = _macKey(mac);
    return rssiByMac[k] ?? -90;
  }
}

class OntDevice {
  const OntDevice({
    required this.name,
    required this.mac,
    required this.ip,
    required this.port,
    required this.rssi,
  });

  final String name;
  final String mac;
  final String ip;
  final String port;
  final int rssi;

  String get banda {
    if (port.contains('ETH')) return 'Cable';
    if (port.contains('5') || port.contains('SSID5')) return '5 GHz';
    return '2.4 GHz';
  }

  bool get es5GHz => banda == '5 GHz';

  bool get esCableado => banda == 'Cable';

  bool get esDecodificador {
    final macUpper = mac.toUpperCase();
    return macUpper.startsWith('3C:A8:2A') ||
        macUpper.startsWith('00:1A:C3') ||
        macUpper.startsWith('D4:05:98') ||
        macUpper.startsWith('F4:6D:04') ||
        macUpper.startsWith('70:54:D2') ||
        name.toLowerCase().contains('deco') ||
        name.toLowerCase().contains('stb') ||
        name.toLowerCase().contains('arris');
  }

  bool get esExtensor {
    final macUpper = mac.toUpperCase();
    return macUpper.startsWith('B4:C0:F5') ||
        macUpper.startsWith('48:46:FB') ||
        macUpper.startsWith('54:89:98') ||
        name.toLowerCase().contains('extensor') ||
        name.toLowerCase().contains('repeater') ||
        name.toLowerCase().contains('ws5200');
  }

  String get fabricante {
    final macUpper = mac.toUpperCase();
    if (macUpper.startsWith('3C:A8:2A') || macUpper.startsWith('D4:05:98')) {
      return 'Arris';
    }
    if (macUpper.startsWith('F4:6D:04') || macUpper.startsWith('70:54:D2')) {
      return 'Technicolor';
    }
    if (macUpper.startsWith('B4:C0:F5') || macUpper.startsWith('48:46:FB')) {
      return 'Huawei';
    }
    if (macUpper.startsWith('A8:C8:3A')) return 'Huawei ONT';
    return 'Desconocido';
  }

  String get serieEstimada {
    final clean = mac.replaceAll(':', '');
    final sufijo = clean.length >= 6
        ? clean.substring(6).toUpperCase()
        : clean.toUpperCase();
    final fab = fabricante.toUpperCase();
    final pref = fab.length >= 3 ? fab.substring(0, 3) : fab.padRight(3, 'X');
    return '$pref-2024-$sufijo';
  }

  /// Modelo log-distance con factor de material [n].
  double distanciaMetros(double factorN) {
    if (esCableado) return 0;
    const txPower = 20;
    return math.pow(10, (txPower - rssi) / (10 * factorN)).toDouble();
  }

  String get calidad {
    if (esCableado) return 'Cableado';
    if (rssi >= -60) return 'Excelente';
    if (rssi >= -70) return 'Buena';
    if (rssi >= -75) return 'Marginal';
    return 'Crítico';
  }

  Color get colorCalidad {
    if (esCableado) return const Color(0xFF00D9FF);
    if (rssi >= -60) return const Color(0xFF10B981);
    if (rssi >= -70) return const Color(0xFFF59E0B);
    if (rssi >= -75) return const Color(0xFFFF6B35);
    return const Color(0xFFEF4444);
  }
}
