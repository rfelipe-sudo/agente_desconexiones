import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:agente_desconexiones/services/ont_wifi_service.dart';

const _kBg = Color(0xFF0A1628);
const _kPanel = Color(0xFF0D1B2A);
const _kBorder = Color(0xFF1E3A5F);
const _kDim = Color(0xFF8FA8C8);
const _kAccent = Color(0xFF00D9FF);

enum _Etapa { seleccion, conectando, resultado, error }

/// Mapa de Calor — selección de ONT + scraping + visualización por dispositivo.
class MapaCalorScreen extends StatefulWidget {
  const MapaCalorScreen({super.key});

  @override
  State<MapaCalorScreen> createState() => _MapaCalorScreenState();
}

class _MapaCalorScreenState extends State<MapaCalorScreen> {
  _Etapa _etapa = _Etapa.seleccion;
  String _mensajeProgreso = '';
  String? _mensajeError;
  List<OntDevice> _devices = [];
  OntWifiService? _ont;

  @override
  void dispose() {
    _ont?.logout();
    super.dispose();
  }

  Future<void> _conectarHuawei() async {
    setState(() {
      _etapa = _Etapa.conectando;
      _mensajeProgreso = 'Conectando a la ONT…';
      _mensajeError = null;
    });

    final ont = OntWifiService();
    _ont = ont;

    try {
      final ok = await ont.login();
      if (!ok) {
        setState(() {
          _etapa = _Etapa.error;
          _mensajeError =
              'No se pudo iniciar sesión en la ONT. Verifica IP y credenciales.';
        });
        return;
      }

      setState(() => _mensajeProgreso = 'Leyendo dispositivos conectados…');
      final devices = await ont.getDevices();

      if (!mounted) return;
      setState(() {
        _devices = devices;
        _etapa = _Etapa.resultado;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _etapa = _Etapa.error;
        _mensajeError = 'Error de comunicación: $e';
      });
    }
  }

  void _reset() {
    _ont?.logout();
    _ont = null;
    setState(() {
      _etapa = _Etapa.seleccion;
      _devices = [];
      _mensajeError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPanel,
        elevation: 0,
        title: Text(
          'Mapa de Calor',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (_etapa == _Etapa.resultado)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Volver a medir',
              onPressed: () => _conectarHuawei(),
            ),
        ],
      ),
      body: switch (_etapa) {
        _Etapa.seleccion => _buildSeleccion(),
        _Etapa.conectando => _buildConectando(),
        _Etapa.resultado => _buildResultado(),
        _Etapa.error => _buildError(),
      },
    );
  }

  // ---- Etapa 1: selección de marca de ONT --------------------------------

  Widget _buildSeleccion() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Text(
              'Selecciona la marca de la ONT',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solo necesitamos saber el modelo para usar los endpoints correctos.',
              style: GoogleFonts.poppins(fontSize: 13, color: _kDim),
            ),
            const SizedBox(height: 24),
            _ontCard(
              titulo: 'Huawei HG8145X6',
              subtitulo: 'Firmware Claro Chile (CHILECLARO2)',
              descripcion: 'Lectura directa de RSSI por dispositivo y topología completa (LAN + WiFi).',
              disponible: true,
              icon: Icons.router,
              accent: _kAccent,
              onTap: _conectarHuawei,
            ),
            const SizedBox(height: 12),
            _ontCard(
              titulo: 'Askey',
              subtitulo: 'Próximamente',
              descripcion: 'Soporte deshabilitado mientras se valida el flow de login.',
              disponible: false,
              icon: Icons.router,
              accent: const Color(0xFF8FA8C8),
              onTap: null,
            ),
            const SizedBox(height: 12),
            _ontCard(
              titulo: 'ZTE',
              subtitulo: 'Próximamente',
              descripcion: 'Soporte deshabilitado mientras se valida el flow de login.',
              disponible: false,
              icon: Icons.router,
              accent: const Color(0xFF8FA8C8),
              onTap: null,
            ),
            const Spacer(),
            _hint(),
          ],
        ),
      ),
    );
  }

  Widget _ontCard({
    required String titulo,
    required String subtitulo,
    required String descripcion,
    required bool disponible,
    required IconData icon,
    required Color accent,
    VoidCallback? onTap,
  }) {
    return Material(
      color: _kPanel,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: _kBorder),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: Icon(icon, color: accent, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          titulo,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!disponible)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _kDim.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'BETA',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _kDim,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: GoogleFonts.poppins(fontSize: 12, color: _kDim),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      descripcion,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: _kDim,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (disponible)
                const Icon(Icons.chevron_right, color: _kDim),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hint() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: _kDim, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'El mapa de calor se genera automáticamente con la potencia que '
              'cada dispositivo reporta a la ONT. No es necesario caminar la casa.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: _kDim,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Etapa 2: conectando -----------------------------------------------

  Widget _buildConectando() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: _kAccent),
            const SizedBox(height: 24),
            Text(
              _mensajeProgreso,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Etapa de error ----------------------------------------------------

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 56),
            const SizedBox(height: 16),
            Text(
              'No se pudo completar la lectura',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _mensajeError ?? '',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: _kDim, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Etapa 3: resultado (heatmap por dispositivo) ----------------------

  Widget _buildResultado() {
    final ont = _ont;
    final stats = _resumen(_devices);

    // Grupo por AP padre (ONT vs cada repetidor).
    final grupos = <String, List<OntDevice>>{};
    for (final d in _devices) {
      final key = (d.parentMac ?? 'desconocido').toUpperCase();
      grupos.putIfAbsent(key, () => []).add(d);
    }
    final ontMacUpper = (ont?.ontMac ?? '').toUpperCase();

    return RefreshIndicator(
      color: _kAccent,
      onRefresh: () async => _conectarHuawei(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (ont != null) _ontHeader(ont),
          const SizedBox(height: 16),
          _resumenWidget(stats),
          const SizedBox(height: 20),
          if (_devices.isEmpty)
            _empty()
          else
            ..._renderGrupos(grupos, ontMacUpper),
          const SizedBox(height: 16),
          _ayudaUmbrales(),
        ],
      ),
    );
  }

  Widget _ontHeader(OntWifiService ont) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kAccent.withValues(alpha: 0.4)),
            ),
            child: const Icon(Icons.router, color: _kAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ont.ontModel?.isNotEmpty == true
                      ? ont.ontModel!
                      : 'Huawei ONT',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${ont.host.replaceFirst('http://', '')} · ${ont.ontMac ?? '-'}',
                  style: GoogleFonts.poppins(fontSize: 11, color: _kDim),
                ),
                if ((ont.ontSerial ?? '').isNotEmpty)
                  Text(
                    'SN: ${ont.ontSerial}',
                    style: GoogleFonts.poppins(fontSize: 11, color: _kDim),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resumenWidget(_Resumen r) {
    Widget chip(String label, int n, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: _kPanel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              Text(
                '$n',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.poppins(fontSize: 11, color: _kDim),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('Excelente', r.excelente, const Color(0xFF10B981)),
        chip('Buena', r.buena, const Color(0xFFF59E0B)),
        chip('Marginal', r.marginal, const Color(0xFFFF6B35)),
        chip('Crítico', r.critico, const Color(0xFFEF4444)),
      ],
    );
  }

  List<Widget> _renderGrupos(
    Map<String, List<OntDevice>> grupos,
    String ontMacUpper,
  ) {
    // Orden: primero el ONT, luego repetidores por nombre de MAC.
    final keys = grupos.keys.toList()
      ..sort((a, b) {
        if (a == ontMacUpper) return -1;
        if (b == ontMacUpper) return 1;
        return a.compareTo(b);
      });

    final widgets = <Widget>[];
    for (final k in keys) {
      final devices = grupos[k]!;
      final esOnt = k == ontMacUpper;
      widgets.add(_grupoHeader(esOnt, k, devices.length));
      for (final d in devices) {
        widgets.add(_deviceCard(d));
      }
      widgets.add(const SizedBox(height: 12));
    }
    return widgets;
  }

  Widget _grupoHeader(bool esOnt, String mac, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Row(
        children: [
          Icon(
            esOnt ? Icons.router : Icons.wifi_tethering,
            color: _kAccent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            esOnt ? 'Conectados a la ONT' : 'A través de repetidor',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '($count)',
            style: GoogleFonts.poppins(fontSize: 12, color: _kDim),
          ),
          const Spacer(),
          if (!esOnt)
            Text(
              mac,
              style: GoogleFonts.firaMono(
                fontSize: 10,
                color: _kDim,
              ),
            ),
        ],
      ),
    );
  }

  Widget _deviceCard(OntDevice d) {
    final color = d.colorCalidad;
    final tieneRssi = d.rssiKnown && !d.esCableado;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Stack(
        children: [
          // Barra lateral coloreada por calidad.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _emoji(d),
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        d.name.isEmpty ? '(sin nombre)' : d.name,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _calidadBadge(d, color),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${d.mac} · ${d.ip}',
                  style: GoogleFonts.firaMono(
                    fontSize: 11,
                    color: _kDim,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _chip(d.banda, _kAccent),
                    if (d.wirelessMode != null && d.wirelessMode!.isNotEmpty)
                      _chip(d.wirelessMode!, _kDim),
                    if (d.esDecodificador) _chip('Decodificador', const Color(0xFFF59E0B)),
                    if (d.esExtensor) _chip('Repetidor', const Color(0xFF7C4DFF)),
                  ],
                ),
                if (tieneRssi) ...[
                  const SizedBox(height: 10),
                  _rssiBar(d.rssi, color),
                ],
                if (!tieneRssi && !d.esCableado) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Sin lectura directa de RSSI (cuelga de un repetidor).',
                    style: GoogleFonts.poppins(fontSize: 11, color: _kDim),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _calidadBadge(OntDevice d, Color color) {
    final label = d.calidad;
    final extra = d.esCableado
        ? ''
        : (d.rssiKnown ? ' · ${d.rssi} dBm' : '');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$label$extra',
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _rssiBar(int rssi, Color color) {
    // Mapea -90..-30 dBm a 0..1.
    final clamped = math.max(-90, math.min(-30, rssi));
    final pct = (clamped + 90) / 60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: _kBorder,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('-90 dBm',
                style: GoogleFonts.poppins(fontSize: 9, color: _kDim)),
            Text('-30 dBm',
                style: GoogleFonts.poppins(fontSize: 9, color: _kDim)),
          ],
        ),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.wifi_off, color: _kDim, size: 36),
          const SizedBox(height: 8),
          Text(
            'No hay dispositivos conectados',
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _ayudaUmbrales() {
    Widget linea(Color c, String txt) => Row(
          children: [
            Container(width: 10, height: 10, color: c),
            const SizedBox(width: 8),
            Text(txt, style: GoogleFonts.poppins(fontSize: 11, color: _kDim)),
          ],
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Umbrales',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          linea(const Color(0xFF10B981), 'Excelente: ≥ −60 dBm'),
          const SizedBox(height: 4),
          linea(const Color(0xFFF59E0B), 'Buena: −61 a −70 dBm'),
          const SizedBox(height: 4),
          linea(const Color(0xFFFF6B35), 'Marginal: −71 a −75 dBm'),
          const SizedBox(height: 4),
          linea(const Color(0xFFEF4444), 'Crítico: < −75 dBm'),
        ],
      ),
    );
  }

  String _emoji(OntDevice d) {
    if (d.esCableado) return '🔌';
    if (d.esDecodificador) return '📺';
    if (d.esExtensor) return '🔁';
    return '📱';
  }

  _Resumen _resumen(List<OntDevice> devs) {
    var exc = 0, bue = 0, mar = 0, cri = 0;
    for (final d in devs) {
      if (d.esCableado) {
        exc++;
        continue;
      }
      if (!d.rssiKnown) continue;
      if (d.rssi >= -60) {
        exc++;
      } else if (d.rssi >= -70) {
        bue++;
      } else if (d.rssi >= -75) {
        mar++;
      } else {
        cri++;
      }
    }
    return _Resumen(excelente: exc, buena: bue, marginal: mar, critico: cri);
  }
}

class _Resumen {
  const _Resumen({
    required this.excelente,
    required this.buena,
    required this.marginal,
    required this.critico,
  });
  final int excelente;
  final int buena;
  final int marginal;
  final int critico;
}
