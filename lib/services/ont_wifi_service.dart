import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Cliente HTTP para ONTs Huawei HG8145X6 con firmware CHILECLARO2 (Claro Chile).
///
/// Login: token + base64(password). Endpoints:
/// - `/html/amp/wlaninfo/getassociateddeviceinfo.asp` → RSSI dBm de clientes WiFi del ONT
/// - `/html/amp/wificoverinfo/getTopoInfo.asp` → Topología completa (LAN/WiFi + repetidores)
class OntWifiService {
  OntWifiService({
    String host = '192.168.1.50',
    String user = 'root',
    String password = 'DuqzC2mV',
  })  : _host = _normalizeHost(host),
        _user = user,
        _password = password;

  final String _host;
  final String _user;
  final String _password;

  String? _sessionCookie;
  String? _ontSerial;
  String? _ontModel;
  String? _ontMac;

  String? get sessionCookie => _sessionCookie;
  String? get ontSerial => _ontSerial;
  String? get ontModel => _ontModel;
  String? get ontMac => _ontMac;
  String get host => _host;

  static String _normalizeHost(String h) {
    final trimmed = h.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'http://$trimmed';
  }

  /// Login con flow HG8145X6: GET /, POST GetRandCount.asp para token,
  /// luego POST /login.cgi con base64(password).
  Future<bool> login() async {
    try {
      // 1) Init session
      final initResp = await http
          .get(Uri.parse('$_host/'))
          .timeout(const Duration(seconds: 10));
      _absorbCookie(initResp);

      // 2) Get challenge token
      final tokenResp = await http
          .post(
            Uri.parse('$_host/asp/GetRandCount.asp'),
            headers: _baseHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      final token = tokenResp.body.trim().replaceFirst(RegExp(r'^﻿'), '');
      if (token.isEmpty) return false;

      // 3) Submit login
      final pwdB64 = base64.encode(utf8.encode(_password));
      final loginResp = await http
          .post(
            Uri.parse('$_host/login.cgi'),
            headers: {
              ..._baseHeaders(),
              'Content-Type': 'application/x-www-form-urlencoded',
              'Cookie': _mergeCookie('Cookie=body:Language:english:id=-1'),
            },
            body: 'UserName=${Uri.encodeQueryComponent(_user)}'
                '&PassWord=${Uri.encodeQueryComponent(pwdB64)}'
                '&Language=english'
                '&x.X_HW_Token=${Uri.encodeQueryComponent(token)}',
          )
          .timeout(const Duration(seconds: 10));
      _absorbCookie(loginResp);

      // 4) Verify session id != -1
      final sid = _sessionCookie ?? '';
      if (RegExp(r'id=([123])(?:[;,]|$)').hasMatch(sid)) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Logout cortés. Libera el slot de sesión en la ONT.
  Future<void> logout() async {
    if (_sessionCookie == null) return;
    try {
      await http
          .get(Uri.parse('$_host/logout.cgi'), headers: _authHeaders())
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // ignore
    } finally {
      _sessionCookie = null;
    }
  }

  /// Lista de dispositivos LAN/WiFi conectados (clientes y repetidores).
  ///
  /// Usa `getassociateddeviceinfo` como **fuente principal** para los clientes
  /// WiFi del ONT (incluye los que aún no tienen IP — DHCP en curso) y la
  /// topología solo para Ethernet y repetidores.
  Future<List<OntDevice>> getDevices() async {
    if (_sessionCookie == null) return [];
    try {
      final wlanResp = await http
          .get(
            Uri.parse('$_host/html/amp/wlaninfo/getassociateddeviceinfo.asp'),
            headers: _authHeaders(
                referer: '$_host/html/amp/wlaninfo/wlaninfo.asp'),
          )
          .timeout(const Duration(seconds: 15));

      final topoResp = await http
          .get(
            Uri.parse('$_host/html/amp/wificoverinfo/getTopoInfo.asp'),
            headers: _authHeaders(
                referer: '$_host/html/amp/wificoverinfo/wlancoverinfo.asp'),
          )
          .timeout(const Duration(seconds: 15));

      final result = parseDevicesFromResponses(
        wlanResp.statusCode == 200 ? wlanResp.body : '',
        topoResp.statusCode == 200 ? topoResp.body : '',
      );
      _ontMac = result.ontMac;
      _ontModel = result.ontModel;
      _ontSerial = result.ontSerial;
      return result.devices;
    } catch (_) {
      return [];
    }
  }

  /// Lista de redes WiFi vecinas que la ONT escanea (otros routers cercanos).
  /// Útil para detectar interferencia co-canal y graficar congestión RF.
  Future<List<OntNeighbour>> getNeighbours() async {
    if (_sessionCookie == null) return [];
    try {
      final r = await http
          .get(
            Uri.parse('$_host/html/amp/wlaninfo/getneighbourAPinfo.asp'),
            headers: _authHeaders(
                referer: '$_host/html/amp/wlaninfo/wlaninfo.asp'),
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return [];
      return parseNeighboursFromResponse(r.body);
    } catch (_) {
      return [];
    }
  }

  /// Parser puro del endpoint de vecinos. Útil para tests con fixtures.
  static List<OntNeighbour> parseNeighboursFromResponse(String body) {
    final out = <OntNeighbour>[];
    final re = RegExp(r'new\s+stNeighbourAP\s*\(([^)]*)\)');
    for (final m in re.allMatches(body)) {
      final args = _splitQuotedArgs(m.group(1) ?? '');
      if (args.length < 11) continue;
      final fields = args.map(_unescapeJs).toList();
      final domain = fields[0];
      final radioMatch = RegExp(r'Radio\.(\d+)').firstMatch(domain);
      final radioIdx = radioMatch != null
          ? int.tryParse(radioMatch.group(1)!)
          : null;
      final band = radioIdx == 2 ? '5G' : (radioIdx == 1 ? '2.4G' : null);
      out.add(OntNeighbour(
        ssid: fields[1],
        bssid: _normalizeMac(fields[2]),
        kind: fields[3],
        channel: int.tryParse(fields[4]),
        rssiDbm: int.tryParse(fields[5]),
        noiseDbm: int.tryParse(fields[6]),
        security: fields.length > 9 ? fields[9] : null,
        mode: fields.length > 10 ? fields[10] : null,
        maxRateMbps: fields.length > 11 ? int.tryParse(fields[11]) : null,
        band: band,
      ));
    }
    return out;
  }

  /// Parser puro de respuestas crudas. Útil para tests con fixtures.
  ///
  /// Combina la respuesta de `getassociateddeviceinfo.asp` (RSSI dBm) con la
  /// de `getTopoInfo.asp` (topología) y produce una lista plana de
  /// dispositivos junto con metadatos de la ONT.
  static OntScrapeResult parseDevicesFromResponses(
    String wlanBody,
    String topoBody,
  ) {
    final wlanByMac = _parseWlanClientsStatic(wlanBody);
    final topology = _parseTopologyStatic(topoBody);
    return _flattenStatic(topology, wlanByMac);
  }

  @visibleForTesting
  static Map<String, OntWlanReading> parseWlanClientsForTest(String body) =>
      _parseWlanClientsStatic(body);

  @visibleForTesting
  static List<Map<String, dynamic>> parseTopologyForTest(String body) =>
      _parseTopologyStatic(body);

  // --- internal: HTTP/cookie helpers --------------------------------------

  Map<String, String> _baseHeaders() => {
        'User-Agent': 'CREABOX-OntWifi/1.0',
        'Accept': '*/*',
      };

  Map<String, String> _authHeaders({String? referer}) {
    final h = <String, String>{..._baseHeaders()};
    final cookie = _sessionCookie;
    if (cookie != null && cookie.isNotEmpty) h['Cookie'] = cookie;
    if (referer != null) h['Referer'] = referer;
    return h;
  }

  /// Merge a cookie value with the existing session cookie (if any).
  String _mergeCookie(String extra) {
    final existing = _sessionCookie;
    if (existing == null || existing.isEmpty) return extra;
    return '$existing; $extra';
  }

  /// Extract the relevant bits from `Set-Cookie` headers and remember them.
  void _absorbCookie(http.Response r) {
    final raw = r.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;

    // Strategy: split on commas at the boundary between cookies (avoiding
    // expires=...) and accumulate name=value pairs into _sessionCookie.
    final parts = <String>[];
    final pieces = raw.split(',');
    var buf = '';
    for (final piece in pieces) {
      buf = buf.isEmpty ? piece : '$buf,$piece';
      // Heuristic: a cookie chunk ends when the following comma is followed
      // by a "name=" pattern outside of an Expires attribute.
      if (RegExp(r';\s*expires=', caseSensitive: false).hasMatch(buf)) {
        // we are currently inside an expires=... attribute; keep buffering.
        continue;
      }
      parts.add(buf.trim());
      buf = '';
    }
    if (buf.isNotEmpty) parts.add(buf.trim());

    final pairs = <String>[];
    for (final p in parts) {
      final first = p.split(';').first.trim();
      if (first.contains('=')) pairs.add(first);
    }
    if (pairs.isEmpty) return;
    final merged = pairs.join('; ');
    _sessionCookie = _sessionCookie == null || _sessionCookie!.isEmpty
        ? merged
        : '$_sessionCookie; $merged';
  }

  // --- internal: parsers ---------------------------------------------------

  /// Constructor `stAssociatedDevice(...)` — 21 strings posicionales.
  /// Campos relevantes: 1=MAC, 2=Uptime(s), 3=RxRate(kbps), 4=TxRate(kbps),
  /// 5=RSSI(dBm), 6=Noise, 7=SNR, 8=SignalQuality, 9=Mode, 13=IP, 14=Hostname,
  /// 15=Antennas. El campo 0 (domain) trae `WLANConfiguration.N` (1..4=2.4G,
  /// 5..8=5G).
  static final _stAssociatedRe =
      RegExp(r'new\s+stAssociatedDevice\s*\(([^)]*)\)');

  static String _unescapeJs(String s) {
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == r'\' && i + 1 < s.length) {
        final next = s[i + 1];
        if (next == 'x' && i + 3 < s.length) {
          final hex = s.substring(i + 2, i + 4);
          final code = int.tryParse(hex, radix: 16);
          if (code != null) {
            buf.writeCharCode(code);
            i += 3;
            continue;
          }
        }
        if (next == 'u' && i + 5 < s.length) {
          final hex = s.substring(i + 2, i + 6);
          final code = int.tryParse(hex, radix: 16);
          if (code != null) {
            buf.writeCharCode(code);
            i += 5;
            continue;
          }
        }
        if (next == 'n') { buf.write('\n'); i++; continue; }
        if (next == 't') { buf.write('\t'); i++; continue; }
        if (next == r'\') { buf.write(r'\'); i++; continue; }
        if (next == '"') { buf.write('"'); i++; continue; }
        if (next == "'") { buf.write("'"); i++; continue; }
      }
      buf.write(c);
    }
    return buf.toString();
  }

  static Map<String, OntWlanReading> _parseWlanClientsStatic(String body) {
    final result = <String, OntWlanReading>{};
    for (final m in _stAssociatedRe.allMatches(body)) {
      final raw = m.group(1) ?? '';
      final args = _splitQuotedArgs(raw);
      if (args.length < 15) continue;
      final fields = args.map(_unescapeJs).toList();
      final mac = _normalizeMac(fields[1]);
      if (mac.isEmpty) continue;
      final domain = fields[0];
      final ssidIdxMatch =
          RegExp(r'WLANConfiguration\.(\d+)').firstMatch(domain);
      final ssidIdx = ssidIdxMatch != null
          ? int.tryParse(ssidIdxMatch.group(1)!)
          : null;
      final band = ssidIdx == null ? null : (ssidIdx <= 4 ? '2.4G' : '5G');
      result[mac] = OntWlanReading(
        mac: mac,
        rssiDbm: int.tryParse(fields[5]),
        snrDb: int.tryParse(fields[7]),
        signalQualityPct: int.tryParse(fields[8]),
        wirelessMode: fields[9],
        ip: fields[13],
        hostname: fields[14],
        antennas: fields.length > 15 ? fields[15] : null,
        band: band,
        ssidIndex: ssidIdx,
      );
    }
    return result;
  }

  /// Extrae args entre comillas dobles tolerando escapes JS hex.
  static List<String> _splitQuotedArgs(String raw) {
    final out = <String>[];
    final re = RegExp(r'"((?:[^"\\]|\\.)*)"');
    for (final m in re.allMatches(raw)) {
      out.add(m.group(1) ?? '');
    }
    return out;
  }

  /// Convierte el object literal JS de `getTopoInfo.asp` a JSON real,
  /// añadiendo comillas a las keys, y lo parsea.
  static List<Map<String, dynamic>> _parseTopologyStatic(String body) {
    var text = body.trim().replaceFirst(RegExp(r'^﻿'), '');
    if (text.isEmpty || text.startsWith('"NONE"')) return [];

    // Quote bare keys: { foo: "x" }  →  { "foo": "x" }
    text = text.replaceAllMapped(
      RegExp(r'(?<=[{,])\s*([A-Za-z_]\w*)\s*:'),
      (m) => '"${m.group(1)}":',
    );

    try {
      final parsed = jsonDecode(text);
      if (parsed is List) {
        return parsed.whereType<Map<String, dynamic>>().toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Aplana topología + lectura WLAN en un [OntScrapeResult].
  ///
  /// Estrategia:
  /// - **WiFi clientes del ONT principal**: salen de `wlanByMac` (endpoint A).
  ///   Es la fuente verdadera porque incluye clientes que aún no tienen IP
  ///   asignada por DHCP (no aparecen en topología).
  /// - **Ethernet clientes del ONT principal**: salen de la topología (no hay
  ///   otro endpoint que los reporte).
  /// - **Repetidores y sus clientes**: salen de la topología.
  static OntScrapeResult _flattenStatic(
    List<Map<String, dynamic>> topology,
    Map<String, OntWlanReading> wlanByMac,
  ) {
    final devices = <OntDevice>[];
    final seen = <String>{};

    String? ontMac, ontModel, ontSerial;

    if (topology.isNotEmpty) {
      final main = topology.first;
      ontMac = _normalizeMac((main['MAC'] ?? '').toString());
      ontModel = (main['DevType'] ?? '').toString();
      ontSerial = (main['SN'] ?? '').toString();

      // Sub_sta del ONT principal (para indexar y para Ethernet)
      final mainSubs = (main['sub_sta'] is List)
          ? List<Map<String, dynamic>>.from(main['sub_sta'])
          : <Map<String, dynamic>>[];
      final mainSubByMac = <String, Map<String, dynamic>>{};
      for (final s in mainSubs) {
        final m = _normalizeMac((s['MAC'] ?? '').toString());
        if (m.isNotEmpty) mainSubByMac[m] = s;
      }

      // 1) Ethernet del ONT principal: solo de topología (wlanByMac no los tiene).
      for (final s in mainSubs) {
        final mac = _normalizeMac((s['MAC'] ?? '').toString());
        if (mac.isEmpty || seen.contains(mac)) continue;
        final accessRaw = (s['AccessType'] ?? '').toString().toLowerCase();
        if (accessRaw == 'wireless') continue; // los WiFi se emiten desde wlanByMac
        seen.add(mac);
        devices.add(OntDevice(
          name: (s['HostName'] ?? '').toString(),
          mac: mac,
          ip: (s['IP'] ?? '').toString(),
          port: 'ETH',
          rssi: 0,
          rssiKnown: true,
          isWired: true,
          band: null,
          wirelessMode: null,
          snrDb: null,
          signalQualityPct: null,
          parentMac: ontMac,
          parentIsOnt: true,
          uptimeSec: int.tryParse((s['OnTime'] ?? '0').toString()) ?? 0,
          security: null,
        ));
      }

      // 2) WiFi del ONT principal: fuente = wlanByMac (incluye sin-IP).
      for (final wlan in wlanByMac.values) {
        if (seen.contains(wlan.mac)) continue;
        seen.add(wlan.mac);
        final topoSub = mainSubByMac[wlan.mac];
        // Hostname: prefer topology if non-empty, else WLAN reading.
        final hostnameTopo = (topoSub?['HostName'] ?? '').toString();
        final hostnameWlan = wlan.hostname ?? '';
        final hostname =
            hostnameTopo.isNotEmpty ? hostnameTopo : hostnameWlan;
        // IP: prefer topology (real DHCP entry); else WLAN if not 0.0.0.0.
        final ipTopo = (topoSub?['IP'] ?? '').toString();
        final ipWlan = wlan.ip ?? '';
        final ip = ipTopo.isNotEmpty
            ? ipTopo
            : (ipWlan.isNotEmpty && ipWlan != '0.0.0.0' ? ipWlan : '');
        final band = wlan.band ?? (topoSub?['WifiFreq'] ?? '').toString();
        final mode =
            (topoSub?['WirelessMode'] ?? wlan.wirelessMode ?? '').toString();
        final security = (topoSub?['Security'] ?? '').toString();
        final ssidIdx = wlan.ssidIndex;
        final port = ssidIdx != null && ssidIdx > 4
            ? 'SSID5_$ssidIdx'
            : 'SSID2_${ssidIdx ?? 0}';
        final uptime = int.tryParse(
                (topoSub?['OnTime'] ?? '0').toString()) ??
            0;
        devices.add(OntDevice(
          name: hostname,
          mac: wlan.mac,
          ip: ip,
          port: port,
          rssi: wlan.rssiDbm ?? -90,
          rssiKnown: wlan.rssiDbm != null,
          isWired: false,
          band: band.isEmpty ? null : band,
          wirelessMode: mode.isEmpty ? null : mode,
          snrDb: wlan.snrDb,
          signalQualityPct: wlan.signalQualityPct,
          parentMac: ontMac,
          parentIsOnt: true,
          uptimeSec: uptime,
          security: security.isEmpty ? null : security,
        ));
      }

      // 3) Repetidores y sus clientes: topología solamente (no tenemos dBm).
      for (final ap in topology.skip(1)) {
        final apMac = _normalizeMac((ap['MAC'] ?? '').toString());
        final subs = (ap['sub_sta'] is List)
            ? List<Map<String, dynamic>>.from(ap['sub_sta'])
            : <Map<String, dynamic>>[];
        for (final s in subs) {
          final mac = _normalizeMac((s['MAC'] ?? '').toString());
          if (mac.isEmpty || seen.contains(mac)) continue;
          seen.add(mac);
          final accessRaw = (s['AccessType'] ?? '').toString().toLowerCase();
          final isWireless = accessRaw == 'wireless';
          final port = _portFromTopology(s, isWireless);
          devices.add(OntDevice(
            name: (s['HostName'] ?? '').toString(),
            mac: mac,
            ip: (s['IP'] ?? '').toString(),
            port: port,
            rssi: isWireless ? -90 : 0,
            rssiKnown: !isWireless,
            isWired: !isWireless,
            band: isWireless ? (s['WifiFreq'] ?? '').toString() : null,
            wirelessMode:
                isWireless ? (s['WirelessMode'] ?? '').toString() : null,
            snrDb: null,
            signalQualityPct: int.tryParse((s['rssi'] ?? '').toString()),
            parentMac: apMac,
            parentIsOnt: false,
            uptimeSec: int.tryParse((s['OnTime'] ?? '0').toString()) ?? 0,
            security: isWireless ? (s['Security'] ?? '').toString() : null,
          ));
        }
      }
    } else {
      // Sin topología pero podríamos tener WLAN (caso raro pero posible).
      for (final wlan in wlanByMac.values) {
        if (seen.contains(wlan.mac)) continue;
        seen.add(wlan.mac);
        final ssidIdx = wlan.ssidIndex;
        final port = ssidIdx != null && ssidIdx > 4
            ? 'SSID5_$ssidIdx'
            : 'SSID2_${ssidIdx ?? 0}';
        devices.add(OntDevice(
          name: wlan.hostname ?? '',
          mac: wlan.mac,
          ip: (wlan.ip != null && wlan.ip != '0.0.0.0') ? wlan.ip! : '',
          port: port,
          rssi: wlan.rssiDbm ?? -90,
          rssiKnown: wlan.rssiDbm != null,
          isWired: false,
          band: wlan.band,
          wirelessMode: wlan.wirelessMode,
          snrDb: wlan.snrDb,
          signalQualityPct: wlan.signalQualityPct,
          parentMac: null,
          parentIsOnt: true,
          uptimeSec: 0,
          security: null,
        ));
      }
    }

    return OntScrapeResult(
      ontMac: (ontMac == null || ontMac.isEmpty) ? null : ontMac,
      ontModel: (ontModel == null || ontModel.isEmpty) ? null : ontModel,
      ontSerial:
          (ontSerial == null || ontSerial.isEmpty) ? null : ontSerial,
      devices: devices,
    );
  }

  /// Genera un identificador de puerto compatible con la versión previa
  /// (la pantalla `wifi_cobertura_screen` discrimina por substring).
  static String _portFromTopology(Map<String, dynamic> sub, bool isWireless) {
    if (!isWireless) return 'ETH';
    final freq = (sub['WifiFreq'] ?? '').toString();
    final port = (sub['AccessPort'] ?? '').toString();
    if (freq.contains('5')) return 'SSID5_$port';
    return 'SSID2_$port';
  }

  static String _normalizeMac(String mac) {
    final hex = mac.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    if (hex.length != 12) return mac.toUpperCase();
    final parts = <String>[];
    for (var i = 0; i < 12; i += 2) {
      parts.add(hex.substring(i, i + 2));
    }
    return parts.join(':');
  }
}

/// Resultado del parser puro [OntWifiService.parseDevicesFromResponses].
class OntScrapeResult {
  const OntScrapeResult({
    required this.ontMac,
    required this.ontModel,
    required this.ontSerial,
    required this.devices,
  });

  final String? ontMac;
  final String? ontModel;
  final String? ontSerial;
  final List<OntDevice> devices;
}

/// Red WiFi vecina escaneada por la ONT (otro AP cercano).
///
/// Endpoint: `getneighbourAPinfo.asp`. Útil para diagnosticar interferencia
/// co-canal o congestión RF.
class OntNeighbour {
  const OntNeighbour({
    required this.ssid,
    required this.bssid,
    this.kind,
    this.channel,
    this.rssiDbm,
    this.noiseDbm,
    this.security,
    this.mode,
    this.maxRateMbps,
    this.band,
  });

  final String ssid;
  final String bssid;
  final String? kind;
  final int? channel;
  final int? rssiDbm;
  final int? noiseDbm;
  final String? security;
  final String? mode;
  final int? maxRateMbps;

  /// "2.4G" o "5G" según el radio del ONT que lo detecta.
  final String? band;

  String get bandaUI {
    if (band == '5G') return '5 GHz';
    if (band == '2.4G') return '2.4 GHz';
    return '?';
  }

  String get displayName => ssid.isEmpty ? '(oculta)' : ssid;
}

/// Lectura RSSI dBm de un cliente WiFi del ONT (endpoint A).
class OntWlanReading {
  const OntWlanReading({
    required this.mac,
    this.rssiDbm,
    this.snrDb,
    this.signalQualityPct,
    this.wirelessMode,
    this.ip,
    this.hostname,
    this.antennas,
    this.band,
    this.ssidIndex,
  });

  final String mac;
  final int? rssiDbm;
  final int? snrDb;
  final int? signalQualityPct;
  final String? wirelessMode;
  final String? ip;
  final String? hostname;
  final String? antennas;
  final String? band;
  final int? ssidIndex;
}

/// Dispositivo conectado a la ONT (cliente WiFi, cliente cableado o repetidor).
///
/// Mantiene la API pública previa (`name`, `mac`, `ip`, `port`, `rssi`,
/// `es5GHz`, `esCableado`, etc.) para no romper a `wifi_cobertura_screen`.
/// Suma campos nuevos (`band`, `parentMac`, `rssiKnown`, etc.) que el nuevo
/// `mapa_calor_screen.dart` aprovecha.
class OntDevice {
  const OntDevice({
    required this.name,
    required this.mac,
    required this.ip,
    required this.port,
    required this.rssi,
    this.rssiKnown = true,
    this.isWired = false,
    this.band,
    this.wirelessMode,
    this.snrDb,
    this.signalQualityPct,
    this.parentMac,
    this.parentIsOnt = true,
    this.uptimeSec = 0,
    this.security,
  });

  final String name;
  final String mac;
  final String ip;
  final String port;
  final int rssi;

  /// `false` cuando el device cuelga de un repetidor y no tenemos lectura
  /// real de dBm (el `rssi` quedará en -90 como placeholder, pero se debe
  /// mostrar como "Sin lectura" en UI).
  final bool rssiKnown;

  /// Cliente cableado (Ethernet) — no tiene RSSI WiFi.
  final bool isWired;

  /// "2.4G" o "5G" (solo WiFi).
  final String? band;
  final String? wirelessMode;
  final int? snrDb;
  final int? signalQualityPct;

  /// MAC del AP padre (ONT o repetidor) al que está conectado este device.
  final String? parentMac;
  final bool parentIsOnt;
  final int uptimeSec;
  final String? security;

  // -- legacy getters consumidos por wifi_cobertura_screen.dart -------------

  String get banda {
    if (isWired) return 'Cable';
    if (band == '5G' || port.contains('5') || port.contains('SSID5')) {
      return '5 GHz';
    }
    return '2.4 GHz';
  }

  bool get es5GHz => banda == '5 GHz';

  bool get esCableado => isWired || port.contains('ETH');

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
    // Décodificadores y APs típicos del operador
    if (macUpper.startsWith('3C:A8:2A') || macUpper.startsWith('D4:05:98')) {
      return 'Arris';
    }
    if (macUpper.startsWith('F4:6D:04') || macUpper.startsWith('70:54:D2')) {
      return 'Technicolor';
    }
    if (macUpper.startsWith('B4:C0:F5') || macUpper.startsWith('48:46:FB')) {
      return 'Huawei';
    }
    if (macUpper.startsWith('A8:C8:3A') || macUpper.startsWith('78:EB:46')) {
      return 'Huawei ONT';
    }
    // Apple
    if (macUpper.startsWith('08:6D:41') ||
        macUpper.startsWith('A4:83:E7') ||
        macUpper.startsWith('F0:18:98') ||
        macUpper.startsWith('14:7D:DA') ||
        macUpper.startsWith('40:33:1A') ||
        macUpper.startsWith('B8:E8:56')) {
      return 'Apple';
    }
    // Samsung
    if (macUpper.startsWith('00:12:FB') ||
        macUpper.startsWith('38:AA:3C') ||
        macUpper.startsWith('5C:0A:5B') ||
        macUpper.startsWith('E4:7C:F9')) {
      return 'Samsung';
    }
    // Xiaomi
    if (macUpper.startsWith('64:09:80') ||
        macUpper.startsWith('98:FA:E3') ||
        macUpper.startsWith('A0:86:C6')) {
      return 'Xiaomi';
    }
    // LG
    if (macUpper.startsWith('00:E0:91') || macUpper.startsWith('CC:FA:00')) {
      return 'LG';
    }
    // MAC privadas/aleatorias (segundo nibble = 2,6,A,E)
    if (macUpper.length >= 2) {
      final second = macUpper[1];
      if (second == '2' || second == '6' || second == 'A' || second == 'E') {
        return 'MAC privada';
      }
    }
    return 'Desconocido';
  }

  /// Nombre amigable a mostrar — usa hostname si existe, sino fabricante + sufijo MAC.
  String get displayName {
    if (name.isNotEmpty) return name;
    final clean = mac.replaceAll(':', '').toUpperCase();
    final sufijo = clean.length >= 4 ? clean.substring(clean.length - 4) : clean;
    final fab = fabricante;
    if (esDecodificador) return 'Decodificador · $sufijo';
    if (esExtensor) return 'Repetidor · $sufijo';
    if (esCableado) return '${fab == 'Desconocido' ? 'Cliente' : fab} (cable) · $sufijo';
    return '$fab · $sufijo';
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
    if (!rssiKnown) return 'Sin lectura';
    if (rssi >= -60) return 'Excelente';
    if (rssi >= -70) return 'Buena';
    if (rssi >= -75) return 'Marginal';
    return 'Crítico';
  }

  Color get colorCalidad {
    if (esCableado) return const Color(0xFF00D9FF);
    if (!rssiKnown) return const Color(0xFF8FA8C8);
    if (rssi >= -60) return const Color(0xFF10B981);
    if (rssi >= -70) return const Color(0xFFF59E0B);
    if (rssi >= -75) return const Color(0xFFFF6B35);
    return const Color(0xFFEF4444);
  }
}
