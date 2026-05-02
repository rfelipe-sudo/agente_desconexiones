import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agente_desconexiones/constants/app_constants.dart';
import 'package:agente_desconexiones/services/nyquist_service.dart';

const String _keplerEndpoint =
    'https://kepler.sbip.cl/api/v1/toa/get_data_toa_other_enterprise';

// ── Colores globales ────────────────────────────────────────────────────────
const _bgColor      = Color(0xFF0D1B2A);
const _surfaceColor = Color(0xFF1A2C3D);
const _cyanColor    = Color(0xFF00BCD4);
const _alertRed     = Color(0xFFE53935);

// ── Modelo combinado ────────────────────────────────────────────────────────
class _PuertoCombinado {
  final int numero;
  final double? inicial;
  final double? rxActual;
  final bool isCurrent;
  final String? portId;

  const _PuertoCombinado({
    required this.numero,
    required this.inicial,
    required this.rxActual,
    required this.isCurrent,
    this.portId,
  });

  double? get diferencia {
    if (rxActual == null || inicial == null) return null;
    return rxActual! - inicial!;
  }

  bool get esAlerta {
    if (inicial == null) return false;
    if (rxActual == null || rxActual == 0.0) return true;
    final diff = diferencia;
    return diff != null && diff < -3.0;
  }
}

// ── Widget principal ─────────────────────────────────────────────────────────

class AsistenteCtoScreen extends StatefulWidget {
  const AsistenteCtoScreen({super.key});

  @override
  State<AsistenteCtoScreen> createState() => _AsistenteCtoScreenState();
}

/// Vista actual de la pantalla
enum _Vista { inicio, potencias }

class _AsistenteCtoScreenState extends State<AsistenteCtoScreen> {
  final NyquistService _nyquist = NyquistService();
  final TextEditingController _otManualController = TextEditingController();

  _Vista _vista = _Vista.inicio;

  bool _cargando = false;
  bool _actualizandoEndpoint = false;
  bool _esSupervisor = false;
  String? _error;
  String? _tipoRedError;
  EstadoCTO? _resultado;
  List<PuertoKepler>? _iniciales;
  String? _otActiva;
  String? _accessIdCorto;
  String? _accessIdNyquist;
  String? _nyquistError;
  String? _horaInicial;
  String? _horaFinal;

  static const _ctoChannel = MethodChannel(
    'com.creacionestecnologicas.agente_desconexiones/cto_scan',
  );

  @override
  void initState() {
    super.initState();
    _initRol();
  }

  Future<void> _initRol() async {
    final prefs = await SharedPreferences.getInstance();
    final rol = prefs.getString('user_rol') ?? 'tecnico';
    if (mounted) setState(() => _esSupervisor = rol == 'supervisor' || rol == 'ito');
  }

  @override
  void dispose() {
    _otManualController.dispose();
    super.dispose();
  }

  // ── Canal nativo ────────────────────────────────────────────────────────────

  Future<void> _abrirAsistenteVisual() async {
    final prefs = await SharedPreferences.getInstance();
    final rut = prefs.getString('rut_tecnico') ?? '';
    try {
      await _ctoChannel.invokeMethod('openCtoScan', {'rut': rut});
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir escáner CTO: ${e.message}'),
            backgroundColor: _alertRed,
          ),
        );
      }
    }
  }

  // ── Carga de potencias ──────────────────────────────────────────────────────

  Future<void> _cargarPotencias() async {
    setState(() {
      _cargando = true;
      _error = null;
      _tipoRedError = null;
      _nyquistError = null;
      _resultado = null;
      _vista = _Vista.potencias;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final rut = prefs.getString('rut_tecnico') ?? '';

      if (rut.isEmpty) {
        setState(() { _cargando = false; _error = 'sin_trabajo'; });
        return;
      }

      debugPrint('🔍 [AsistenteCTO] Buscando access_id para RUT: $rut');
      final supabaseResult = await _nyquist.buscarAccessIdPorRut(rut);
      debugPrint('🔍 [AsistenteCTO] Supabase resultado: $supabaseResult');

      if (supabaseResult == null) {
        setState(() { _cargando = false; _error = 'sin_trabajo'; });
        return;
      }

      final tipoRed = (supabaseResult['tipo_red_producto'] ?? '').toString();
      if (tipoRed.isNotEmpty && tipoRed.toUpperCase() != 'NFTT') {
        setState(() {
          _cargando = false;
          _error = 'tecnologia_incompatible';
          _tipoRedError = tipoRed.toUpperCase();
        });
        return;
      }

      final accessIdPrefijado = (supabaseResult['access_id'] ?? '').toString();
      if (accessIdPrefijado.isEmpty) {
        setState(() { _cargando = false; _error = 'tecnologia_incompatible'; _tipoRedError = null; });
        return;
      }

      _accessIdNyquist = accessIdPrefijado;
      final ot = (supabaseResult['orden_de_trabajo'] ?? '').toString().trim();
      _accessIdCorto = ot.isNotEmpty
          ? ot
          : accessIdPrefijado.replaceFirst(RegExp(r'^\d{1,2}-'), '');
      _otActiva = supabaseResult['id_actividad']?.toString() ?? _accessIdCorto;

      if (_iniciales == null) {
        try {
          _iniciales = await _nyquist.fetchIniciales(_accessIdCorto!);
          _horaInicial = _nyquist.lastKeplerHoraInicial;
        } catch (_) {
          _iniciales = [];
        }
      }

      try {
        final resultado = await _nyquist.consultarEstado(_accessIdNyquist!);
        if (mounted) setState(() { _resultado = resultado; _horaFinal = _formatHoraAhora(); _cargando = false; });
      } catch (e) {
        if (mounted) setState(() { _nyquistError = e.toString().replaceFirst('Exception: ', ''); _cargando = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _cargando = false; });
    }
  }

  Future<void> _actualizarEndpoint() async {
    if (_accessIdNyquist == null) return;
    setState(() => _actualizandoEndpoint = true);
    try {
      final resultado = await _nyquist.consultarEstado(_accessIdNyquist!);
      if (mounted) {
        setState(() {
          _resultado = resultado;
          _horaFinal = _formatHoraAhora();
          _actualizandoEndpoint = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actualizandoEndpoint = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar: ${e.toString().replaceFirst("Exception: ", "")}'),
            backgroundColor: _alertRed,
          ),
        );
      }
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _surfaceColor,
        leading: IconButton(
          icon: Icon(
            _vista == _Vista.inicio ? Icons.arrow_back : Icons.arrow_back,
            color: Colors.white,
          ),
          onPressed: () {
            if (_vista == _Vista.potencias) {
              setState(() { _vista = _Vista.inicio; _error = null; });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Row(
          children: [
            Icon(
              _vista == _Vista.inicio ? Icons.router : Icons.bar_chart,
              color: _cyanColor,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              _vista == _Vista.inicio ? 'Asistente de CTO' : 'Potencias CTO',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: _vista == _Vista.inicio ? _buildInicio() : _buildPotencias(),
    );
  }

  // ── Vista inicio: dos tarjetas ──────────────────────────────────────────────

  Widget _buildInicio() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),

          // Título descriptivo
          const Text(
            '¿Qué deseas hacer?',
            style: TextStyle(color: Colors.white70, fontSize: 14, letterSpacing: 0.5),
          ),
          const SizedBox(height: 20),

          // ── Tarjeta 1: Escanear CTO ───────────────────────────────────
          _buildTarjeta(
            icono: Icons.camera_enhance,
            titulo: 'Escanear CTO',
            descripcion: 'Apunta la cámara a la caja CTO. La IA detectará el tipo de caja y mostrará el pelo asignado con los niveles de señal.',
            color: _cyanColor,
            onTap: _abrirAsistenteVisual,
          ),

          const SizedBox(height: 16),

          // ── Tarjeta 2: Revisar Potencias ──────────────────────────────
          _buildTarjeta(
            icono: Icons.bar_chart,
            titulo: 'Revisar Potencias',
            descripcion: 'Consulta los niveles de señal actuales de todos los puertos de tu CTO asignada sin necesidad de escanear.',
            color: const Color(0xFF7C4DFF),
            onTap: _cargarPotencias,
          ),

          const SizedBox(height: 32),

          // Nota informativa
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.info_outline, color: Colors.white38, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'El Asistente CTO requiere una orden en estado "Iniciado". '
                    'Si no tienes trabajo activo, las potencias no estarán disponibles.',
                    style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTarjeta({
    required IconData icono,
    required String titulo,
    required String descripcion,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.35), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ícono con fondo circular
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icono, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              // Texto
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        color: color,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      descripcion,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: color.withOpacity(0.6), size: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Vista potencias ─────────────────────────────────────────────────────────

  Widget _buildPotencias() {
    if (_cargando) return _buildCargando();
    if (_error == 'sin_trabajo') return _buildSinTrabajo();
    if (_error == 'tecnologia_incompatible' || _error == 'otra_tecnologia') return _buildTecnologiaIncompatible();
    if (_error != null) return _buildError();
    if (_iniciales != null || _resultado != null || _nyquistError != null) return _buildResultado();
    return _buildCargando();
  }

  Widget _buildCargando() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: _cyanColor),
          const SizedBox(height: 20),
          Text(
            _iniciales == null ? 'Cargando niveles iniciales...' : 'Actualizando medición final...',
            style: const TextStyle(color: Colors.white70, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSinTrabajo() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.work_off_outlined, size: 72, color: Colors.white30),
            const SizedBox(height: 24),
            const Text('Sin trabajo activo',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 12),
            const Text(
              'No se encontró ninguna orden en estado "Iniciado".\nEl Asistente CTO requiere una orden activa.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.white54, height: 1.5),
            ),
            const SizedBox(height: 32),
            _buildBotonActualizar(onPressed: _cargarPotencias),
          ],
        ),
      ),
    );
  }

  Widget _buildTecnologiaIncompatible() {
    final tipo = _tipoRedError ?? '';
    final String mensaje;
    final IconData icono;
    final Color color;

    if (tipo.contains('FTTH')) {
      mensaje = 'ORDEN FTTH\nSOLO PUEDO MEDIR RED NEUTRA';
      icono = Icons.settings_input_component;
      color = Colors.purple[300]!;
    } else if (tipo.contains('HFC')) {
      mensaje = 'ORDEN HFC\nSOLO PUEDO MEDIR RED NEUTRA';
      icono = Icons.cable;
      color = Colors.orange[300]!;
    } else {
      mensaje = 'Este trabajo pertenece a una tecnología\ndiferente a NFTT';
      icono = Icons.fiber_manual_record;
      color = Colors.orange;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, size: 72, color: color),
            const SizedBox(height: 24),
            Text(
              tipo.isNotEmpty ? 'Orden $tipo detectada' : 'Tecnología no compatible',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withOpacity(0.45)),
              ),
              child: Text(
                mensaje,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color, height: 1.5),
              ),
            ),
            const SizedBox(height: 32),
            _buildBotonActualizar(onPressed: _cargarPotencias),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: _alertRed),
            const SizedBox(height: 20),
            const Text('Error al consultar CTO',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _alertRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _alertRed.withOpacity(0.4)),
              ),
              child: Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: _alertRed, fontSize: 13, height: 1.4)),
            ),
            const SizedBox(height: 24),
            _buildBotonActualizar(onPressed: _cargarPotencias),
          ],
        ),
      ),
    );
  }

  Widget _buildResultado() {
    final puertos = _buildPuertosCombinados();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _actualizandoEndpoint
              ? const SizedBox(height: 48, child: Center(child: CircularProgressIndicator(color: _cyanColor)))
              : _buildBotonActualizar(onPressed: _actualizarEndpoint),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.table_chart, color: _cyanColor, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Detalles de Alertas y Niveles de Puertos',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ]),
                if (_accessIdCorto != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _cyanColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _cyanColor.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cable, color: _cyanColor, size: 14),
                        const SizedBox(width: 6),
                        Text('Orden: $_accessIdCorto',
                            style: const TextStyle(color: _cyanColor, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                ],
                if (_nyquistError != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.4)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                      SizedBox(width: 8),
                      Expanded(child: Text('Medición final no disponible. Presiona Actualizar para reintentar.',
                          style: TextStyle(color: Colors.orange, fontSize: 12))),
                    ]),
                  ),
                ],
                const SizedBox(height: 16),
                _buildTablaPuertos(puertos),
                const SizedBox(height: 16),
                _buildHorasConsulta(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Tabla de puertos ────────────────────────────────────────────────────────

  List<_PuertoCombinado> _buildPuertosCombinados() {
    final keplerMap = { for (final k in (_iniciales ?? [])) k.portNumber: k };

    final nyquistBySuffix = <String, PuertoCTO>{};
    final nyquistByNum    = <int, PuertoCTO>{};
    for (final p in (_resultado?.puertos ?? [])) {
      final suffix = p.portSuffix;
      if (suffix != null) nyquistBySuffix[suffix] = p;
      nyquistByNum[p.numero] = p;
    }

    final nyquistNumerosConsumidos = <int>{};
    for (int pn = 1; pn <= 8; pn++) {
      final kSuffix = keplerMap[pn]?.portSuffix;
      if (kSuffix != null) {
        final matched = nyquistBySuffix[kSuffix];
        if (matched != null) nyquistNumerosConsumidos.add(matched.numero);
      }
    }

    return List.generate(8, (i) {
      final portNum = i + 1;
      final k = keplerMap[portNum];

      PuertoCTO? n;
      final kSuffix = k?.portSuffix;
      if (kSuffix != null) {
        n = nyquistBySuffix[kSuffix];
      } else {
        final candidate = nyquistByNum[portNum];
        if (candidate != null && !nyquistNumerosConsumidos.contains(candidate.numero)) n = candidate;
      }

      return _PuertoCombinado(
        numero: portNum,
        inicial: k?.inicial,
        rxActual: n?.rxActual,
        isCurrent: k?.isCurrent ?? false,
        portId: null,
      );
    });
  }

  Widget _buildTablaPuertos(List<_PuertoCombinado> puertos) {
    return Container(
      decoration: BoxDecoration(color: _surfaceColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0D2137),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            ),
            child: Row(children: [
              _thCell('Pto', flex: 2),
              _thCell('C1\nInicial', flex: 3),
              _thCell('C2\nFinal', flex: 3),
              _thCell('Dif.', flex: 3),
              _thCell('Ok', flex: 2),
            ]),
          ),
          ...puertos.asMap().entries.map((entry) =>
              _buildFilaPuerto(entry.value, isLast: entry.key == puertos.length - 1)),
        ],
      ),
    );
  }

  Widget _buildFilaPuerto(_PuertoCombinado p, {required bool isLast}) {
    final esAlerta = p.esAlerta;
    final diff = p.diferencia;
    final consulta1 = p.inicial != null ? p.inicial!.toStringAsFixed(2) : '-';
    final consulta2 = p.rxActual != null ? p.rxActual!.toStringAsFixed(2) : '-';
    final diferencia = diff != null ? diff.toStringAsFixed(2) : '0.00';
    final diffColor = diff == null ? Colors.white54 : diff >= -3.0 ? Colors.green : _alertRed;

    return Container(
      decoration: BoxDecoration(
        color: esAlerta ? _alertRed.withOpacity(0.15) : Colors.transparent,
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(color: Colors.white.withOpacity(0.07)),
        ),
        borderRadius: isLast
            ? const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12))
            : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Row(children: [
        Expanded(flex: 2, child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: esAlerta ? _alertRed : p.isCurrent ? _cyanColor : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${p.numero}', textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontWeight: (esAlerta || p.isCurrent) ? FontWeight.bold : FontWeight.normal, fontSize: 14)),
          ),
        )),
        Expanded(flex: 3, child: Text(consulta1, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'))),
        Expanded(flex: 3, child: Text(consulta2, textAlign: TextAlign.center,
            style: TextStyle(color: p.rxActual == null ? Colors.white30 : Colors.white, fontSize: 12, fontFamily: 'monospace'))),
        Expanded(flex: 3, child: Text(diferencia, textAlign: TextAlign.center,
            style: TextStyle(color: diffColor, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace'))),
        Expanded(flex: 2, child: Center(
          child: esAlerta
              ? const Icon(Icons.warning_amber_rounded, color: _alertRed, size: 18)
              : const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
        )),
      ]),
    );
  }

  Widget _buildHorasConsulta() {
    if (_horaInicial == null && _horaFinal == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.access_time, color: _cyanColor, size: 16),
          SizedBox(width: 6),
          Text('Tiempos de Consulta',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _buildHoraItem(label: 'Consulta Inicial', hora: _horaInicial ?? '--:--', color: Colors.green[300]!)),
          const SizedBox(width: 12),
          Expanded(child: _buildHoraItem(label: 'Consulta Final', hora: _horaFinal ?? '--:--', color: _cyanColor)),
        ]),
      ]),
    );
  }

  Widget _buildHoraItem({required String label, required String hora, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: color.withOpacity(0.75), fontSize: 10, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(hora, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ]),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _formatHoraAhora() {
    final now = TimeOfDay.now();
    final h = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
    final m = now.minute.toString().padLeft(2, '0');
    final period = now.period == DayPeriod.am ? 'AM' : 'PM';
    return '${h.toString().padLeft(2, '0')}:$m $period';
  }

  Widget _thCell(String text, {int flex = 1}) => Expanded(
    flex: flex,
    child: Text(text, textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600, height: 1.3)),
  );

  Widget _buildBotonActualizar({required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.refresh, color: Colors.white),
        label: const Text('Actualizar', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _cyanColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
