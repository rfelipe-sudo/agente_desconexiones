// Generador del HTML del Certificado WiFi.
//
// Sustituye al asset estático `assets/certificado/certificado_wifi_v3.html`
// con uno generado dinámicamente desde la data real del scrape de la ONT.
// Se llama desde `WifiCoberturaScreen` cuando el técnico toca "Certificado".

import 'dart:math' as math;

import 'package:agente_desconexiones/services/ont_wifi_service.dart';
import 'package:agente_desconexiones/services/wifi_neighbor_service.dart';

class CertContext {
  const CertContext({
    required this.devices,
    required this.ontNeighbours,
    required this.localNeighbours,
    required this.score,
    required this.veredicto,
    required this.tipoPropiedad,
    required this.tamano,
    required this.construccion,
    this.ordenTrabajo,
    this.tipoOrden,
    this.ontModelo,
    this.ontSerial,
    this.ontMac,
    this.tecnicoNombre,
    this.tecnicoRut,
    this.fechaIso,
    this.recomendacionExtensor,
  });

  final List<OntDevice> devices;
  final List<OntNeighbour> ontNeighbours;
  final List<WifiNeighbor> localNeighbours;
  final int score;
  final String veredicto;
  final String tipoPropiedad; // 'casa1' | 'casa2' | 'depto' | 'local'
  final String tamano; // 'peq' | 'med' | 'gra'
  final String construccion; // 'Madera' | 'Albañilería' | 'Hormigón'
  final String? ordenTrabajo;
  final String? tipoOrden;
  final String? ontModelo;
  final String? ontSerial;
  final String? ontMac;
  final String? tecnicoNombre;
  final String? tecnicoRut;
  final String? fechaIso;

  /// Texto de recomendación de extensor (p. ej. distancia y motivo).
  final String? recomendacionExtensor;
}

String buildCertificadoHtml(CertContext c) {
  final scoreColor = _scoreColor(c.score);
  final propiedadLabel = _propiedadLabel(c.tipoPropiedad, c.tamano);
  final fecha = c.fechaIso ?? DateTime.now().toIso8601String();
  final fechaCorta = fecha.substring(0, 10);
  final hora = DateTime.now().toString().substring(11, 16);

  final devicesHtml = _devicesHtml(c.devices);
  final neighboursHtml = _neighboursHtml(c.ontNeighbours);
  final observacionesHtml = _observacionesHtml(c);
  final heatmapHtml = _heatmapRadial(c.devices, c.ontMac);

  return '''<!DOCTYPE html>
<html lang="es"><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Certificado WiFi · CREABOX</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:linear-gradient(135deg,#dee5ee 0%,#c0cad8 100%);font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,sans-serif;padding:24px 12px 48px;min-height:100vh;color:#0f172a}
.page{max-width:680px;margin:0 auto;background:#fff;border-radius:18px;overflow:hidden;box-shadow:0 24px 80px rgba(8,15,30,0.28)}
.hdr{background:linear-gradient(135deg,#04091a 0%,#0a1628 50%,#0d2241 100%);padding:28px 28px 24px;color:#fff;position:relative;overflow:hidden}
.hdr::before{content:"";position:absolute;width:380px;height:380px;border-radius:50%;background:radial-gradient(circle,rgba(0,217,255,0.18) 0%,transparent 70%);top:-180px;right:-120px;pointer-events:none}
.hdr::after{content:"";position:absolute;width:260px;height:260px;border-radius:50%;background:radial-gradient(circle,rgba(124,77,255,0.14) 0%,transparent 65%);bottom:-150px;left:-80px;pointer-events:none}
.brand{display:flex;align-items:center;gap:8px;margin-bottom:14px;position:relative;z-index:1}
.brand-dot{width:10px;height:10px;border-radius:50%;background:#00d9ff;box-shadow:0 0 12px #00d9ff}
.brand-name{font-size:11px;letter-spacing:3px;font-weight:700;color:#7dd3fc}
.hdr-title{font-size:24px;font-weight:800;letter-spacing:0.3px;line-height:1.15;position:relative;z-index:1}
.hdr-sub{margin-top:6px;font-size:13px;color:#94a3b8;position:relative;z-index:1}
.hdr-meta{margin-top:14px;font-size:11px;color:#cbd5e1;display:flex;gap:14px;flex-wrap:wrap;position:relative;z-index:1}
.hdr-meta span{display:inline-flex;align-items:center;gap:4px;padding:4px 9px;background:rgba(255,255,255,0.06);border:1px solid rgba(255,255,255,0.1);border-radius:14px}
.score-bar{display:flex;align-items:center;justify-content:space-between;padding:20px 28px;background:#fff;border-bottom:1px solid #e2e8f0;gap:16px}
.score-left{display:flex;align-items:center;gap:16px;flex:1}
.score-ring{width:80px;height:80px;border-radius:50%;background:conic-gradient($scoreColor 0% ${c.score}%,#e2e8f0 ${c.score}% 100%);display:flex;align-items:center;justify-content:center;box-shadow:0 4px 16px rgba(0,0,0,0.08)}
.score-inner{width:64px;height:64px;border-radius:50%;background:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center}
.score-num{font-size:26px;font-weight:800;color:#0a1628;line-height:1}
.score-den{font-size:10px;color:#94a3b8;font-weight:600;margin-top:1px}
.score-info{flex:1;min-width:0}
.score-verdict{font-size:18px;font-weight:800;color:$scoreColor;line-height:1.2}
.score-sub{font-size:11px;color:#64748b;margin-top:4px;line-height:1.4}
.cert-badge{padding:8px 14px;background:$scoreColor;color:#fff;border-radius:8px;font-size:11px;font-weight:800;letter-spacing:0.5px;white-space:nowrap;box-shadow:0 4px 12px ${scoreColor}55}
.body{padding:24px 28px 8px}
.sec{margin-bottom:22px}
.sec-title{display:flex;align-items:center;gap:8px;font-size:11px;font-weight:800;color:#0a1628;text-transform:uppercase;letter-spacing:1.4px;margin-bottom:12px;padding-bottom:8px;border-bottom:2px solid #e2e8f0}
.sec-title::before{content:"";width:4px;height:14px;background:linear-gradient(135deg,#00d9ff,#7c4dff);border-radius:2px}
.sec-count{margin-left:auto;background:#f1f5f9;color:#64748b;padding:2px 9px;border-radius:10px;font-size:10px;font-weight:700;letter-spacing:0.3px}
.info-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.info-box{background:#f8fafc;padding:12px;border-radius:10px;border-left:3px solid #3b82f6;transition:all .2s}
.info-lbl{font-size:9px;color:#64748b;font-weight:700;text-transform:uppercase;letter-spacing:0.6px;display:flex;align-items:center;gap:4px}
.info-val{font-size:14px;color:#0a1628;font-weight:700;margin-top:4px;letter-spacing:-0.2px}
.heatmap{position:relative;width:100%;aspect-ratio:1.6;background:radial-gradient(ellipse at center,#0a1628 0%,#04091a 100%);border-radius:14px;overflow:hidden}
.heat-grid{position:absolute;inset:0;background-image:linear-gradient(rgba(0,217,255,0.05) 1px,transparent 1px),linear-gradient(90deg,rgba(0,217,255,0.05) 1px,transparent 1px);background-size:30px 30px}
.heat-ring{position:absolute;left:14%;top:50%;transform:translate(-50%,-50%);border-radius:50%;border:1px dashed rgba(125,211,252,0.25)}
.heat-ring-lbl{position:absolute;left:14%;top:50%;transform:translate(-50%,-50%);font-size:8px;color:rgba(125,211,252,0.5);font-weight:600;pointer-events:none}
.heat-ont{position:absolute;left:14%;top:50%;transform:translate(-50%,-50%);width:14px;height:14px;border-radius:50%;background:#00d9ff;box-shadow:0 0 16px #00d9ff,0 0 28px rgba(0,217,255,0.4);z-index:5}
.heat-ont-lbl{position:absolute;left:14%;top:50%;transform:translate(0,18px);font-size:9px;color:#7dd3fc;font-weight:700;letter-spacing:0.5px}
.heat-dot{position:absolute;width:18px;height:18px;border-radius:50%;background:var(--c);box-shadow:0 0 14px var(--c),0 0 22px var(--c) inset;border:2px solid rgba(255,255,255,0.18);transform:translate(-50%,-50%);z-index:4}
.heat-dot::after{content:"";position:absolute;inset:-8px;border-radius:50%;background:radial-gradient(circle,var(--c) 0%,transparent 70%);opacity:0.4;z-index:-1}
.heat-lbl{position:absolute;font-size:9px;color:#fff;font-weight:600;background:rgba(10,22,40,0.85);padding:2px 6px;border-radius:4px;transform:translate(-50%,16px);white-space:nowrap;z-index:5;border:1px solid rgba(255,255,255,0.1)}
.heat-legend{padding:10px 12px;background:#f8fafc;border-bottom-left-radius:14px;border-bottom-right-radius:14px;display:flex;gap:14px;flex-wrap:wrap;font-size:10px;color:#475569}
.heat-legend-dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:5px;vertical-align:-1px}
.dev-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.dev-card{background:#fff;padding:12px;border-radius:10px;border:1px solid #e2e8f0;border-left:4px solid var(--c);transition:transform .15s}
.dev-row{display:flex;justify-content:space-between;align-items:center;gap:6px}
.dev-name{font-size:12px;font-weight:700;color:#0a1628;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1}
.dev-rssi{font-size:15px;font-weight:800;color:var(--c);letter-spacing:-0.3px}
.dev-meta{font-size:10px;color:#64748b;margin-top:5px;line-height:1.3}
.dev-quality{font-size:9px;color:#fff;background:var(--c);padding:2px 7px;border-radius:4px;text-transform:uppercase;font-weight:800;letter-spacing:0.5px}
.dev-mac{font-family:'SF Mono',Menlo,monospace;font-size:9px;color:#94a3b8;letter-spacing:0.2px;margin-top:6px}
.dev-bar{height:4px;background:#e2e8f0;border-radius:2px;margin-top:8px;overflow:hidden;position:relative}
.dev-bar-fill{height:100%;background:linear-gradient(90deg,var(--c),var(--c));border-radius:2px;transition:width .4s}
.tbl{width:100%;border-collapse:collapse;font-size:11px}
.tbl thead tr{background:linear-gradient(135deg,#0a1628,#1e3a5f)}
.tbl th{color:#7dd3fc;padding:8px 10px;text-align:left;font-weight:700;text-transform:uppercase;letter-spacing:0.6px;font-size:9px}
.tbl th:first-child{border-top-left-radius:8px}
.tbl th:last-child{border-top-right-radius:8px}
.tbl td{padding:7px 10px;border-bottom:1px solid #e2e8f0;color:#0a1628;font-size:11px}
.tbl tr:nth-child(even) td{background:#f8fafc}
.alert{background:linear-gradient(135deg,#fef2f2 0%,#fef2f2 100%);border:1px solid #fecaca;border-left:4px solid #ef4444;padding:12px 14px;border-radius:10px;margin-bottom:10px;color:#7f1d1d}
.alert-title{font-size:12px;font-weight:800;margin-bottom:5px;display:flex;align-items:center;gap:6px}
.alert-body{font-size:11px;line-height:1.55}
.rec{background:linear-gradient(135deg,#eff6ff 0%,#dbeafe 100%);border:1px solid #93c5fd;border-left:4px solid #3b82f6;padding:12px 14px;border-radius:10px;margin-bottom:10px;color:#1e3a8a}
.rec-title{font-size:12px;font-weight:800;margin-bottom:5px;display:flex;align-items:center;gap:6px}
.rec-body{font-size:11px;line-height:1.55}
.foot{padding:18px 28px;background:linear-gradient(135deg,#04091a,#0a1628);color:#94a3b8;font-size:10px;text-align:center;border-top:2px solid #1e3a5f}
.foot strong{color:#7dd3fc;font-weight:700;letter-spacing:0.5px}
.empty{font-size:12px;color:#94a3b8;font-style:italic;padding:14px;text-align:center;background:#f8fafc;border-radius:8px}
</style></head><body>
<div class="page">
  <div class="hdr">
    <div class="brand"><div class="brand-dot"></div><div class="brand-name">CREABOX · CERTIFICACIÓN WIFI</div></div>
    <div class="hdr-title">Cobertura WiFi Residencial</div>
    <div class="hdr-sub">${c.ordenTrabajo != null && c.ordenTrabajo!.isNotEmpty ? "Orden de trabajo <strong style='color:#fff'>${_esc(c.ordenTrabajo!)}</strong>" : "Lectura directa de ONT"}</div>
    <div class="hdr-meta">
      <span>📅 $fechaCorta</span>
      <span>🕒 $hora</span>
      ${c.tecnicoRut != null && c.tecnicoRut!.isNotEmpty ? '<span>👷 ${_esc(c.tecnicoRut!)}</span>' : ''}
      ${c.tipoOrden != null && c.tipoOrden!.isNotEmpty ? '<span>🔧 ${_esc(c.tipoOrden!)}</span>' : ''}
    </div>
  </div>
  <div class="score-bar">
    <div class="score-left">
      <div class="score-ring">
        <div class="score-inner">
          <div class="score-num">${c.score}</div>
          <div class="score-den">/100</div>
        </div>
      </div>
      <div class="score-info">
        <div class="score-verdict">${_esc(c.veredicto)}</div>
        <div class="score-sub">${c.devices.where((d) => !d.esCableado).length} WiFi · ${c.devices.where((d) => d.esCableado).length} cableado · ${c.ontNeighbours.length} vecino${c.ontNeighbours.length == 1 ? '' : 's'} detectada${c.ontNeighbours.length == 1 ? '' : 's'}</div>
      </div>
    </div>
    <div class="cert-badge">${c.score >= 75 ? '✓ APROBADO' : '⚠ OBSERVADO'}</div>
  </div>
  <div class="body">
    <div class="sec">
      <div class="sec-title">Mapa de cobertura<span class="sec-count">${c.devices.where((d) => !d.esCableado).length} WiFi</span></div>
      $heatmapHtml
    </div>
    $observacionesHtml
    <div class="sec">
      <div class="sec-title">Información de la instalación</div>
      <div class="info-grid">
        <div class="info-box"><div class="info-lbl">📋 Orden</div><div class="info-val">${_esc(c.ordenTrabajo ?? '—')}</div></div>
        <div class="info-box"><div class="info-lbl">🔧 Tipo orden</div><div class="info-val">${_esc(c.tipoOrden ?? '—')}</div></div>
        <div class="info-box"><div class="info-lbl">🏠 Propiedad</div><div class="info-val">${_esc(propiedadLabel)}</div></div>
        <div class="info-box"><div class="info-lbl">🧱 Construcción</div><div class="info-val">${_esc(c.construccion)}</div></div>
        <div class="info-box"><div class="info-lbl">📡 ONT</div><div class="info-val">${_esc(c.ontModelo ?? '—')}</div></div>
        <div class="info-box"><div class="info-lbl">🔢 SN</div><div class="info-val">${_esc(c.ontSerial ?? '—')}</div></div>
      </div>
    </div>
    <div class="sec">
      <div class="sec-title">Dispositivos conectados<span class="sec-count">${c.devices.length}</span></div>
      $devicesHtml
    </div>
    <div class="sec">
      <div class="sec-title">Redes vecinas (vista de la ONT)<span class="sec-count">${c.ontNeighbours.length}</span></div>
      $neighboursHtml
    </div>
  </div>
  <div class="foot">
    Generado por <strong>CREABOX</strong> · $fechaCorta $hora · ONT ${_esc(c.ontMac ?? '')}
  </div>
</div></body></html>''';
}

/// Heatmap radial (visualmente similar al demo) pero con data REAL.
/// Cada device se posiciona usando hash(MAC) como ángulo y RSSI como radio.
String _heatmapRadial(List<OntDevice> devices, String? ontMac) {
  final wifi = devices.where((d) => !d.esCableado && d.rssiKnown).toList();
  if (wifi.isEmpty) {
    return '<div class="empty">Sin clientes WiFi para graficar.</div>';
  }
  // Mapeo: RSSI -30 → radio 0%, RSSI -90 → radio 100%.
  String pos(OntDevice d) {
    final rssi = d.rssi.clamp(-90, -30);
    final radial = (-30 - rssi) / 60.0; // 0..1
    final hash = d.mac.hashCode.abs();
    final angle = (hash % 360) * math.pi / 180.0;
    // Centro del ONT: 14% horizontal, 50% vertical. Radio horizontal max 70%, vertical max 35%.
    final left = 14 + (radial * 70 * math.cos(angle));
    final top = 50 + (radial * 35 * math.sin(angle));
    return 'left:${left.toStringAsFixed(1)}%;top:${top.toStringAsFixed(1)}%';
  }

  String dot(OntDevice d) {
    final color = _qualityColorHex(d.rssi, d.rssiKnown);
    final p = pos(d);
    return '<div class="heat-dot" style="$p;--c:$color"></div>'
        '<div class="heat-lbl" style="$p">${_esc(_shortName(d))} · ${d.rssi}dBm</div>';
  }

  return '''
<div class="heatmap">
  <div class="heat-grid"></div>
  <div class="heat-ring" style="width:34%;aspect-ratio:1"></div>
  <div class="heat-ring" style="width:60%;aspect-ratio:1"></div>
  <div class="heat-ring" style="width:90%;aspect-ratio:1"></div>
  <div class="heat-ring-lbl" style="margin-left:17%">−60</div>
  <div class="heat-ring-lbl" style="margin-left:30%">−70</div>
  <div class="heat-ring-lbl" style="margin-left:45%">−80</div>
  <div class="heat-ont"></div>
  <div class="heat-ont-lbl">📡 ONT</div>
  ${wifi.map(dot).join()}
</div>
<div class="heat-legend">
  <span><span class="heat-legend-dot" style="background:#10b981"></span>Excelente</span>
  <span><span class="heat-legend-dot" style="background:#f59e0b"></span>Buena</span>
  <span><span class="heat-legend-dot" style="background:#ff6b35"></span>Marginal</span>
  <span><span class="heat-legend-dot" style="background:#ef4444"></span>Crítico</span>
</div>''';
}

String _shortName(OntDevice d) {
  final name = d.displayName;
  if (name.length <= 14) return name;
  return '${name.substring(0, 13)}…';
}

String _devicesHtml(List<OntDevice> devices) {
  if (devices.isEmpty) {
    return '<div class="empty">No se detectaron dispositivos conectados a la ONT.</div>';
  }
  final wifi = devices.where((d) => !d.esCableado).toList()
    ..sort((a, b) => a.rssi.compareTo(b.rssi));
  final cable = devices.where((d) => d.esCableado).toList();

  final cards = <String>[];
  for (final d in wifi) {
    final color = _qualityColorHex(d.rssi, d.rssiKnown);
    final rssiStr = d.rssiKnown ? '${d.rssi} dBm' : '—';
    final quality = _qualityShortLabel(d.rssi, d.rssiKnown);
    cards.add('''
<div class="dev-card" style="--c:$color">
  <div class="dev-row">
    <span class="dev-name">${_esc(d.name.isEmpty ? '(sin nombre)' : d.name)}</span>
    <span class="dev-rssi">$rssiStr</span>
  </div>
  <div class="dev-row" style="margin-top:6px">
    <span class="dev-meta">${_esc(d.banda)} · ${_esc(d.wirelessMode ?? '')}</span>
    <span class="dev-quality">$quality</span>
  </div>
  <div class="dev-meta">${_esc(d.mac)}${d.ip.isNotEmpty ? ' · ${_esc(d.ip)}' : ''}</div>
</div>''');
  }
  for (final d in cable) {
    cards.add('''
<div class="dev-card" style="--c:#0ea5e9">
  <div class="dev-row">
    <span class="dev-name">${_esc(d.name.isEmpty ? '(sin nombre)' : d.name)}</span>
    <span class="dev-rssi">🔌 LAN</span>
  </div>
  <div class="dev-row" style="margin-top:6px">
    <span class="dev-meta">Cable Ethernet</span>
    <span class="dev-quality" style="background:#0ea5e9">CABLE</span>
  </div>
  <div class="dev-meta">${_esc(d.mac)}${d.ip.isNotEmpty ? ' · ${_esc(d.ip)}' : ''}</div>
</div>''');
  }
  return '<div class="dev-grid">${cards.join()}</div>';
}

String _neighboursHtml(List<OntNeighbour> ns) {
  if (ns.isEmpty) {
    return '<div class="empty">No se detectaron redes vecinas.</div>';
  }
  final sorted = [...ns]
    ..sort((a, b) => (b.rssiDbm ?? -200).compareTo(a.rssiDbm ?? -200));
  final rows = sorted.take(15).map((v) {
    final rssi = v.rssiDbm ?? -200;
    final cls = rssi >= -50 ? ';color:#dc2626;font-weight:700'
        : rssi >= -65 ? ';color:#d97706;font-weight:600' : '';
    return '<tr><td>${_esc(v.displayName)}</td><td>${_esc(v.bandaUI)}</td><td>${v.channel ?? '-'}</td><td style="$cls">${v.rssiDbm ?? '-'} dBm</td><td>${_esc(v.security ?? '')}</td></tr>';
  }).join();
  return '<table class="tbl"><thead><tr><th>SSID</th><th>Banda</th><th>Canal</th><th>RSSI</th><th>Seguridad</th></tr></thead><tbody>$rows</tbody></table>';
}

String _observacionesHtml(CertContext c) {
  final obs = <String>[];
  final fuertes = c.ontNeighbours.where((v) => (v.rssiDbm ?? -200) > -40).toList();
  if (fuertes.isNotEmpty) {
    obs.add('<div class="alert"><div class="alert-title">⚠ Interferencia RF severa</div>'
        '<div class="alert-body">Se detectaron ${fuertes.length} red${fuertes.length == 1 ? '' : 'es'} vecina${fuertes.length == 1 ? '' : 's'} con señal mayor a −40 dBm: '
        '${fuertes.map((v) => '"${_esc(v.displayName)}" (${_esc(v.bandaUI)}, ${v.rssiDbm} dBm)').join(', ')}. '
        'Esto degrada el rendimiento WiFi del cliente, especialmente si comparten canal.</div></div>');
  }

  final decoMal = c.devices.where((d) => d.esDecodificador && !d.es5GHz && !d.esCableado).toList();
  if (decoMal.isNotEmpty) {
    obs.add('<div class="alert"><div class="alert-title">⚠ Decodificador en 2.4 GHz</div>'
        '<div class="alert-body">${decoMal.map((d) => '"${_esc(d.name.isEmpty ? d.mac : d.name)}"').join(', ')} '
        'está${decoMal.length == 1 ? '' : 'n'} conectado${decoMal.length == 1 ? '' : 's'} a la banda 2.4 GHz. '
        'Migrar a 5 GHz para mejor rendimiento.</div></div>');
  }

  final criticos = c.devices.where((d) => !d.esCableado && d.rssiKnown && d.rssi < -75).toList();
  if (criticos.isNotEmpty) {
    obs.add('<div class="alert"><div class="alert-title">⚠ Señal crítica</div>'
        '<div class="alert-body">${criticos.map((d) => '"${_esc(d.name.isEmpty ? d.mac : d.name)}" (${d.rssi} dBm)').join(', ')} '
        'tiene${criticos.length == 1 ? '' : 'n'} RSSI por debajo de −75 dBm por debilitamiento de señal a distancia. Considerar reubicar el dispositivo o agregar un repetidor.</div></div>');
  }

  final rec = c.recomendacionExtensor?.trim() ?? '';
  if (rec.isNotEmpty) {
    obs.add('<div class="rec"><div class="rec-title">💡 Recomendación de extensor</div>'
        '<div class="rec-body">${_esc(rec)}</div></div>');
  }

  if (obs.isEmpty) return '';
  return '<div class="sec"><div class="sec-title">Observaciones</div>${obs.join()}</div>';
}

String _scoreColor(int score) {
  if (score >= 90) return '#10b981';
  if (score >= 75) return '#10b981';
  if (score >= 60) return '#f59e0b';
  return '#ef4444';
}

String _qualityColorHex(int rssi, bool known) {
  if (!known) return '#94a3b8';
  if (rssi >= -60) return '#10b981';
  if (rssi >= -70) return '#f59e0b';
  if (rssi >= -75) return '#ff6b35';
  return '#ef4444';
}

String _qualityShortLabel(int rssi, bool known) {
  if (!known) return 'S/L';
  if (rssi >= -60) return 'EXC';
  if (rssi >= -70) return 'OK';
  if (rssi >= -75) return 'MARG';
  return 'CRIT';
}

String _propiedadLabel(String tipo, String tamano) {
  final t = switch (tipo) {
    'casa1' => 'Casa 1 piso',
    'casa2' => 'Casa 2 pisos',
    'depto' => 'Departamento',
    'local' => 'Local',
    _ => tipo,
  };
  final s = switch (tamano) {
    'peq' => 'pequeño',
    'med' => 'mediano',
    'gra' => 'grande',
    _ => tamano,
  };
  return '$t · $s';
}

/// Escape HTML para evitar inyección.
String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
