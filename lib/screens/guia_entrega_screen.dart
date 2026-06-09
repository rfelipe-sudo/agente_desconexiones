import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:printing/printing.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/config/constants.dart';
import 'package:agente_desconexiones/models/solicitud_material.dart';
import 'package:agente_desconexiones/screens/pin_entry_screen.dart';
import 'package:agente_desconexiones/services/alerta_sistema_service.dart';
import 'package:agente_desconexiones/services/guia_pdf_service.dart';
import 'package:agente_desconexiones/services/logistica_service.dart';
import 'package:agente_desconexiones/services/combustible_material_ruta_service.dart';
import 'package:agente_desconexiones/services/material_solicitud_service.dart';
import 'package:agente_desconexiones/services/solicitud_estado_monitor.dart';

/// Pantalla de guía de entrega — se abre SOLO en el dispositivo del entregador
/// (receptor). Ambas firmas se capturan en el mismo dispositivo.
class GuiaEntregaScreen extends StatefulWidget {
  final SolicitudMaterial solicitud;
  final String rutPropio;
  final String nombrePropio;
  final Position? posicion;

  const GuiaEntregaScreen({
    super.key,
    required this.solicitud,
    required this.rutPropio,
    required this.nombrePropio,
    this.posicion,
  });

  @override
  State<GuiaEntregaScreen> createState() => _GuiaEntregaScreenState();
}

class _GuiaEntregaScreenState extends State<GuiaEntregaScreen> {
  static const Color _bg      = Color(0xFF0A1628);
  static const Color _surface = Color(0xFF0D1B2A);
  static const Color _accent  = Color(0xFF00D9FF);
  static const Color _border  = Color(0xFF1E3A5F);
  static const Color _textDim = Color(0xFF8FA8C8);
  static const Color _green   = Color(0xFF22C55E);
  static const Color _orange  = Color(0xFFF59E0B);
  static const Color _red     = Color(0xFFEF4444);

  late final SignatureController _firmaCtrl;
  bool _guardando = false;
  bool _paso2     = false;
  String? _guiaId;
  bool _completada = false;
  bool _pinGenerado = false;
  bool _firmaSolicitanteGuardada = false;

  // Firma del entregador guardada para incluir en el PDF
  String? _firmaEntregadorB64;
  // Bytes del PDF generado — disponible en pantalla de confirmación
  Uint8List? _pdfBytes;

  // Series ingresadas por el entregador
  final List<String> _series = [];

  // id_material resuelto al escanear la primera serie válida (seriados)
  int? _idMaterialResuelto;

  // Validación de series contra el stock del técnico
  TecnicoStock? _stockCache;
  bool   _validandoSerie = false;
  String? _errorSerie;
  bool   _falloEscaneo = false;

  final _db = Supabase.instance.client;
  final SolicitudEstadoMonitor _estadoMonitor = SolicitudEstadoMonitor();
  bool _transaccionCerrada = false;

  @override
  void initState() {
    super.initState();
    _firmaCtrl = SignatureController(
      penStrokeWidth: 2.5,
      penColor: Colors.white,
      exportBackgroundColor: const Color(0xFF0D1B2A),
    );

    if (widget.solicitud.esSeriado && widget.solicitud.series.isNotEmpty) {
      _series.addAll(widget.solicitud.series);
    }

    _estadoMonitor.start(
      solicitudId: widget.solicitud.id,
      onEstado: _onEstadoSolicitud,
    );
  }

  void _onEstadoSolicitud(String estado) {
    if (!mounted || _transaccionCerrada) return;
    if (estado == 'cancelada') {
      _transaccionCerrada = true;
      _estadoMonitor.stop();
      unawaited(_cerrarPorCancelacion());
      return;
    }
    if (estado == 'completada' && !_guardando) {
      _transaccionCerrada = true;
      _estadoMonitor.stop();
      unawaited(_cerrarPorCompletada());
    }
  }

  Future<void> _cerrarPorCancelacion() async {
    if (!mounted) return;
    await MaterialTransaccionUi.mostrarCancelada(context);
    if (!mounted) return;
    MaterialTransaccionUi.cerrarFlujoEntregador(context);
  }

  Future<void> _cancelarGuia() async {
    if (_transaccionCerrada || _guardando || !mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Cancelar entrega',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          '¿Cancelar la guía de ${widget.solicitud.tipoMaterial}?\n'
          'Se notificará a ambas partes.',
          style: const TextStyle(color: _textDim, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No', style: TextStyle(color: _textDim)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _red),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await MaterialSolicitudService().cancelarSolicitud(
        solicitudId:   widget.solicitud.id,
        rutCancelador: widget.rutPropio,
      );
      _transaccionCerrada = true;
      _estadoMonitor.stop();
      if (!mounted) return;
      await MaterialTransaccionUi.mostrarCancelada(context);
      if (!mounted) return;
      MaterialTransaccionUi.cerrarFlujoEntregador(context);
    } catch (e) {
      if (!mounted) return;
      _snack(e is StateError ? e.message : 'Error al cancelar: $e');
    }
  }

  Future<void> _cerrarPorCompletada() async {
    if (!mounted) return;
    await MaterialTransaccionUi.mostrarCompletada(context);
    if (!mounted) return;
    MaterialTransaccionUi.cerrarFlujoEntregador(context);
  }

  @override
  void dispose() {
    _estadoMonitor.stop();
    _firmaCtrl.dispose();
    super.dispose();
  }

  // ── Series ───────────────────────────────────────────────────

  Future<TecnicoStock?> _cargarStockTecnico({bool refrescar = false}) async {
    if (!refrescar && _stockCache != null) return _stockCache;
    _stockCache = await LogisticaService().fetchStockTecnico(
      widget.rutPropio,
      nombreDisplay: widget.nombrePropio,
    );
    return _stockCache;
  }

  void _registrarSerieValida(ItemStock item, String serieNormalizada) {
    if (_series.contains(serieNormalizada)) return;
    _idMaterialResuelto ??= item.idMaterial;
    setState(() {
      _series.add(serieNormalizada);
      _errorSerie = null;
      _falloEscaneo = false;
      _validandoSerie = false;
    });
  }

  Future<void> _agregarSerieDesdeLista(ItemStock item) async {
    final serie = item.serie;
    if (serie == null || serie.isEmpty) return;
    final s = LogisticaService.normalizeSerie(serie);
    if (s.isEmpty || _series.contains(s)) return;

    final sol = widget.solicitud;
    if (item.categoria != sol.tipoMaterial) {
      setState(() {
        _errorSerie =
            'Ese equipo es ${item.categoria}.\nLa solicitud pide ${sol.tipoMaterial}.';
      });
      return;
    }
    _registrarSerieValida(item, s);
  }

  void _marcarErrorEscaneo(String mensaje) {
    setState(() {
      _validandoSerie = false;
      _errorSerie = mensaje;
      _falloEscaneo = true;
    });
  }

  Future<void> _agregarSerie(String serie, {bool desdeEscaneo = false}) async {
    final s = LogisticaService.normalizeSerie(serie);
    if (s.isEmpty || _series.contains(s)) return;

    final sol = widget.solicitud;
    if (!sol.esSeriado) {
      setState(() {
        _series.add(s);
        _errorSerie = null;
        _falloEscaneo = false;
      });
      return;
    }

    setState(() {
      _validandoSerie = true;
      _errorSerie = null;
      if (!desdeEscaneo) _falloEscaneo = false;
    });

    try {
      final tecnico = await _cargarStockTecnico(refrescar: true);

      if (tecnico == null) {
        if (desdeEscaneo) {
          _marcarErrorEscaneo(
              'No se pudo cargar tu saldo desde logística.\n'
              'Verifica que tu RUT esté en nómina.');
        } else {
          setState(() {
            _validandoSerie = false;
            _errorSerie =
                'No se pudo cargar tu saldo desde logística.\n'
                'Verifica que tu RUT esté en nómina.';
          });
        }
        return;
      }

      final itemPorSerie = tecnico.findSerie(serie);

      if (itemPorSerie == null) {
        final disponibles =
            tecnico.seriadosPorCategoria(sol.tipoMaterial).length;
        final msg = disponibles > 0
            ? 'No se reconoció el código escaneado.'
            : 'No hay ${sol.tipoMaterial} con serie en tu saldo Kepler.';
        if (desdeEscaneo) {
          _marcarErrorEscaneo(msg);
        } else {
          setState(() {
            _validandoSerie = false;
            _errorSerie = msg;
          });
        }
        return;
      }

      if (itemPorSerie.categoria != sol.tipoMaterial) {
        final msg =
            'Serie registrada como ${itemPorSerie.categoria},\n'
            'pero la solicitud pide ${sol.tipoMaterial}.';
        if (desdeEscaneo) {
          _marcarErrorEscaneo(msg);
        } else {
          setState(() {
            _validandoSerie = false;
            _errorSerie = msg;
          });
        }
        return;
      }

      final serieReg = itemPorSerie.serie != null
          ? LogisticaService.normalizeSerie(itemPorSerie.serie!)
          : s;
      _registrarSerieValida(itemPorSerie, serieReg);
    } catch (_) {
      final msg =
          'Error al validar serie.\nVerifica conexión e intenta de nuevo.';
      if (desdeEscaneo) {
        _marcarErrorEscaneo(msg);
      } else {
        setState(() {
          _validandoSerie = false;
          _errorSerie = msg;
        });
      }
    }
  }

  void _eliminarSerie(String serie) =>
      setState(() => _series.remove(serie));

  Future<void> _escanearCodigo() async {
    final sol = widget.solicitud;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _BarcodeScannerSheet(
        tipoMaterial: sol.tipoMaterial,
        rutTecnico:   widget.rutPropio,
        nombreTecnico: widget.nombrePropio,
        soloCamara:   true,
      ),
    );
    if (result != null && result.isNotEmpty) {
      await _agregarSerie(result, desdeEscaneo: true);
    }
  }

  Future<void> _elegirDeLista() async {
    final sol = widget.solicitud;
    final result = await showModalBottomSheet<ItemStock>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _BarcodeScannerSheet(
        tipoMaterial: sol.tipoMaterial,
        rutTecnico:   widget.rutPropio,
        nombreTecnico: widget.nombrePropio,
        soloCamara:   false,
        seriesYaUsadas: _series.toSet(),
      ),
    );
    if (result != null) await _agregarSerieDesdeLista(result);
  }

  // ── Paso 1: Entregador firma ─────────────────────────────────

  Future<void> _firmarEntregador() async {
    final sol = widget.solicitud;
    if (sol.esSeriado && _series.length < sol.cantidad) {
      _snack(
          'Debes ingresar ${sol.cantidad} serie(s). Tienes ${_series.length}.');
      return;
    }
    if (_firmaCtrl.isEmpty) {
      _snack('Dibuja tu firma primero');
      return;
    }
    setState(() => _guardando = true);
    try {
      final b64 = await _toBase64(_firmaCtrl);
      _firmaEntregadorB64 = b64; // Guardar para PDF

      final logistica = LogisticaService();
      final nombreEnt = await logistica.nombrePorRut(
        widget.rutPropio,
        fallback: widget.nombrePropio,
      );
      final nombreSol = await logistica.nombrePorRut(
        sol.rutSolicitante,
        fallback: sol.nombreSolicitante,
      );

      final now = DateTime.now();
      final guia = await _db.from('solicitudes_bodega').insert({
        'solicitud_id':       sol.id,
        'rut_solicitante':    sol.rutSolicitante,
        'nombre_solicitante': nombreSol,
        'rut_entregador':     widget.rutPropio,
        'nombre_entregador':  nombreEnt,
        'hora':
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:00',
        'fecha':              now.toIso8601String().substring(0, 10),
        'lugar':              _lugarStr(),
        'latitud':            widget.posicion?.latitude,
        'longitud':           widget.posicion?.longitude,
        'detalle_material':   '${sol.cantidad}× ${sol.tipoMaterial}',
        'series':             _series,
        'cantidad':           sol.cantidad,
        'firma_entregador':   b64,
        'estado':             'pendiente',
      }).select().single();

      final guiaId = (guia as Map)['id'] as String;
      _guiaId = guiaId;

      // 'estado' ya está en 'en_guia' desde EntregaEnCaminoScreen._abrirGuia()
      // (geocerca o botón). Solo actualizamos los campos de la guía.
      await _db.from('solicitudes_material').update({
        'guia_id':  guiaId,
        'series':   _series,
        if (_idMaterialResuelto != null) 'id_material': _idMaterialResuelto,
      }).eq('id', sol.id);

      _firmaCtrl.clear();
      setState(() {
        _paso2    = true;
        _guardando = false;
      });
    } catch (e) {
      setState(() => _guardando = false);
      _snack('Error: $e');
    }
  }

  // ── Paso 2: Solicitante firma ────────────────────────────────

  Future<void> _firmarSolicitante() async {
    if (_firmaCtrl.isEmpty) {
      _snack('Dibuja tu firma primero');
      return;
    }
    if (_guardando || _firmaSolicitanteGuardada) return;

    setState(() => _guardando = true);
    try {
      final b64    = await _toBase64(_firmaCtrl);
      final guiaId = _guiaId ?? widget.solicitud.guiaId;

      await _db.from('solicitudes_bodega').update({
        'firma_solicitante': b64,
        'estado':            'firmada',
      }).eq('id', guiaId!);

      await _db.from('solicitudes_material').update({
        'estado': 'firmada',
      }).eq('id', widget.solicitud.id);

      await _generarPinSiNecesario();

      unawaited(_registrarTramosCombustible());

      if (_firmaEntregadorB64 != null) {
        try {
          _pdfBytes = await _generarPdf(
            firmaEntregadorB64:  _firmaEntregadorB64!,
            firmaSolicitanteB64: b64,
          );
        } catch (_) {}
      }

      _firmaSolicitanteGuardada = true;
      if (!mounted) return;
      setState(() => _guardando = false);

      final solicitudConId = widget.solicitud.copyWith(
        idMaterial: _idMaterialResuelto,
        series: _series.isNotEmpty ? List<String>.from(_series) : null,
      );
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PinEntryScreen(solicitud: solicitudConId),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _guardando = false);
      _snack(_mensajeErrorFirma(e));
    }
  }

  /// Genera PIN una sola vez. Si FCM falla pero el PIN quedó en BD, continúa.
  Future<void> _generarPinSiNecesario() async {
    if (_pinGenerado) return;

    try {
      await _db.functions.invoke('generar-pin', body: {
        'solicitud_id': widget.solicitud.id,
      });
      _pinGenerado = true;
      return;
    } catch (ePm) {
      final pinOk = await _pinVigenteEnBd();
      if (pinOk) {
        _pinGenerado = true;
        debugPrint('[Guia] generar-pin FCM falló pero PIN vigente en BD');
        return;
      }
      unawaited(AlertaSistemaService().registrarFallo(
        modulo:        'generar_pin',
        tipoError:     'edge_function_error',
        mensaje:       ePm.toString(),
        rutTecnico:    widget.rutPropio,
        nombreTecnico: widget.nombrePropio,
        solicitudId:   widget.solicitud.id,
      ));
      rethrow;
    }
  }

  Future<bool> _pinVigenteEnBd() async {
    try {
      final row = await _db
          .from('solicitudes_material')
          .select('pin_codigo, pin_expira_en')
          .eq('id', widget.solicitud.id)
          .maybeSingle();
      if (row == null) return false;
      final pin = row['pin_codigo'] as String?;
      final expiraRaw = row['pin_expira_en'] as String?;
      if (pin == null || pin.isEmpty) return false;
      if (expiraRaw == null) return true;
      return DateTime.parse(expiraRaw).isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  String _mensajeErrorFirma(Object e) {
    final raw = e.toString();
    if (raw.contains('pin_intentos') || raw.contains('pin_expira_en')) {
      return 'Falta configuración PIN en el servidor. '
          'Contacta a soporte (migración solicitudes_material_pin).';
    }
    if (raw.contains('FunctionException')) {
      return 'No se pudo generar el PIN de confirmación. Intenta de nuevo '
          'o contacta a soporte si persiste.';
    }
    return 'Error: $e';
  }

  /// GPS del entregador al firmar = fin del tramo; partida viene de "Voy por el" o aceptación.
  Future<void> _registrarTramosCombustible() async {
    await CombustibleMaterialRutaService.instance.registrarTramosAlFirmar(
      sol: widget.solicitud,
      finLat: widget.posicion?.latitude,
      finLng: widget.posicion?.longitude,
      guiaId: _guiaId ?? widget.solicitud.guiaId,
    );
  }

  // ── Generación de PDF ────────────────────────────────────────

  Future<Uint8List> _generarPdf({
    required String firmaEntregadorB64,
    required String firmaSolicitanteB64,
  }) async {
    final sol = widget.solicitud;
    final logistica = LogisticaService();
    final rutEnt = sol.rutEntregador ?? widget.rutPropio;
    final rutSol = sol.rutSolicitante;
    final nombreEnt = await logistica.nombrePorRut(
      rutEnt,
      fallback: widget.nombrePropio,
    );
    final nombreSol = await logistica.nombrePorRut(
      rutSol,
      fallback: sol.nombreSolicitante,
    );

    final now = DateTime.now();
    return GuiaPdfService.generar(guia: {
      'id': _guiaId,
      'solicitud_id': sol.id,
      'rut_solicitante': rutSol,
      'nombre_solicitante': nombreSol,
      'rut_entregador': rutEnt,
      'nombre_entregador': nombreEnt,
      'fecha': now.toIso8601String().substring(0, 10),
      'hora':
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:00',
      'lugar': _lugarStr(),
      'detalle_material': '${sol.cantidad}× ${sol.tipoMaterial}',
      'cantidad': sol.cantidad,
      'series': _series,
      'firma_entregador': firmaEntregadorB64,
      'firma_solicitante': firmaSolicitanteB64,
      'estado': 'firmada',
    });
  }

  // ── Helpers ──────────────────────────────────────────────────

  String _lugarStr() {
    final p = widget.posicion;
    if (p == null) return 'Sin GPS';
    return '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
  }

  Future<String> _toBase64(SignatureController ctrl) async {
    final img   = await ctrl.toImage();
    final bytes = await img!.toByteData(format: ui.ImageByteFormat.png);
    return base64Encode(bytes!.buffer.asUint8List());
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Guía de Entrega',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        actions: [
          if (!_completada)
            TextButton(
              onPressed: _guardando ? null : _cancelarGuia,
              child: const Text('Cancelar',
                  style: TextStyle(color: _red, fontSize: 13)),
            ),
        ],
      ),
      body: _completada ? _buildConfirmacion() : _buildGuia(),
    );
  }

  // ── Pantalla de confirmación ─────────────────────────────────

  Widget _buildConfirmacion() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle, color: _green, size: 72),
            const SizedBox(height: 20),
            const Text('Guía firmada correctamente',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
                'El registro fue enviado a bodega para confirmar el traspaso.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textDim, fontSize: 13)),
            const SizedBox(height: 28),

            if (_pdfBytes != null) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Printing.sharePdf(
                    bytes: _pdfBytes!,
                    filename: 'guia_entrega_${widget.solicitud.id.substring(0, 8)}.pdf',
                  ),
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('Compartir / Guardar PDF',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context)
                  ..pop()
                  ..pop(),
                style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Listo',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      );

  // ── Guía completa ────────────────────────────────────────────

  Widget _buildGuia() {
    final sol = widget.solicitud;
    final now = DateTime.now();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Encabezado ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border)),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              const Icon(Icons.description_outlined, color: _accent, size: 18),
              const SizedBox(width: 8),
              const Text('GUÍA DE ENTREGA DE MATERIAL',
                  style: TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5)),
            ]),
            const Divider(height: 20, color: Color(0xFF1E3A5F)),
            _campo('Fecha',
                '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}'),
            _campo('Hora',
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'),
            _campo('Lugar', _lugarStr()),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFF1E3A5F)),
            const SizedBox(height: 8),
            _campo('Solicitante', sol.nombreSolicitante),
            _campo('RUT solicitante', sol.rutSolicitante),
            _campo('Entregador',
                sol.nombreEntregador ?? widget.nombrePropio),
            _campo('RUT entregador',
                sol.rutEntregador ?? widget.rutPropio),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFF1E3A5F)),
            const SizedBox(height: 8),
            _campo('Material', '${sol.cantidad}× ${sol.tipoMaterial}'),
            if (_series.isNotEmpty)
              _campo('Series', _series.join('\n')),
          ]),
        ),

        const SizedBox(height: 16),

        // ── Series (solo paso 1, material seriado) ──
        if (!_paso2 && sol.esSeriado)
          _buildSeccionSeries(sol),

        // ── Card de traspaso (paso 2) ──
        if (_paso2) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _orange.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _orange.withValues(alpha: 0.45)),
            ),
            child: Row(children: [
              const Icon(Icons.swap_horiz, color: _orange, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Pasa el teléfono al solicitante',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    '${sol.nombreSolicitante} debe firmar a continuación para confirmar la recepción',
                    style: const TextStyle(color: _textDim, fontSize: 12),
                  ),
                ]),
              ),
            ]),
          ),
        ],

        // ── Sección de firma ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border)),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(
              _paso2
                  ? 'Firma del solicitante (quien recibe)'
                  : 'Firma del entregador (quien entrega)',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              _paso2
                  ? sol.nombreSolicitante
                  : (sol.nombreEntregador ?? widget.nombrePropio),
              style: const TextStyle(color: _textDim, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Signature(
                controller: _firmaCtrl,
                height: 160,
                backgroundColor: const Color(0xFF111D2E),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              TextButton.icon(
                onPressed: _firmaCtrl.clear,
                icon: const Icon(Icons.clear, size: 14),
                label: const Text('Borrar',
                    style: TextStyle(fontSize: 12)),
                style:
                    TextButton.styleFrom(foregroundColor: _textDim),
              ),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _guardando || _firmaSolicitanteGuardada
                    ? null
                    : (_paso2
                        ? _firmarSolicitante
                        : _firmarEntregador),
                icon: _guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black))
                    : const Icon(Icons.check, size: 18),
                label: Text(
                  _guardando
                      ? 'Guardando...'
                      : (_paso2
                          ? 'Confirmar recepción'
                          : 'Confirmar entrega'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _paso2 ? _green : _accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
        ),

        if (!_paso2) ...[
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _accent.withValues(alpha: 0.2))),
            child: const Row(children: [
              Icon(Icons.info_outline, color: _accent, size: 14),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Paso 1 de 2. Después de tu firma, pasa el teléfono al solicitante.',
                  style: TextStyle(color: _accent, fontSize: 11),
                ),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  // ── Sección de series ────────────────────────────────────────

  Widget _buildSeccionSeries(SolicitudMaterial sol) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.qr_code_scanner, color: _accent, size: 16),
          const SizedBox(width: 8),
          Text(
            'Series a entregar (${_series.length}/${sol.cantidad})',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13),
          ),
        ]),
        const SizedBox(height: 12),

        FilledButton.icon(
          onPressed: _validandoSerie ? null : _escanearCodigo,
          icon: _validandoSerie
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.black, strokeWidth: 2))
              : const Icon(Icons.qr_code_scanner, size: 18),
          label: Text(
            _validandoSerie ? 'Validando…' : 'Escanear código',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 12),
            minimumSize: const Size(double.infinity, 44),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Escanea el código de barra del equipo.',
          style: TextStyle(color: _textDim.withValues(alpha: 0.85), fontSize: 11),
        ),

        if (_errorSerie != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _red.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: _red, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorSerie!,
                      style: const TextStyle(
                          color: _red,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          height: 1.4),
                    ),
                  ),
                ]),
                if (widget.solicitud.esSeriado && _falloEscaneo) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _validandoSerie ? null : _elegirDeLista,
                    icon: const Icon(Icons.list_alt, size: 16),
                    label: const Text('Elegir de mi saldo'),
                    style: TextButton.styleFrom(
                      foregroundColor: _accent,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        if (_series.isNotEmpty) ...[
          const SizedBox(height: 10),
          ..._series.map((s) => Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                    color: const Color(0xFF0A1628),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _green.withValues(alpha: 0.3))),
                child: Row(children: [
                  Icon(Icons.check_circle_outline,
                      color: _green, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontFamily: 'monospace')),
                  ),
                  GestureDetector(
                    onTap: () => _eliminarSerie(s),
                    child: const Icon(Icons.close, color: _red, size: 16),
                  ),
                ]),
              )),
        ],

        if (_series.length < sol.cantidad)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Faltan ${sol.cantidad - _series.length} serie(s)',
              style: TextStyle(
                  color: _red.withValues(alpha: 0.8), fontSize: 11),
            ),
          ),
      ]),
    );
  }

  Widget _campo(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          SizedBox(
            width: 120,
            child: Text('$label:',
                style: const TextStyle(color: _textDim, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ),
        ]),
      );
}

// ── Modal escáner de códigos de barra ────────────────────────

class _BarcodeScannerSheet extends StatefulWidget {
  final String tipoMaterial;
  final String rutTecnico;
  final String? nombreTecnico;
  /// Solo cámara (escaneo). Si false, abre directamente la lista del saldo.
  final bool soloCamara;
  final Set<String> seriesYaUsadas;

  const _BarcodeScannerSheet({
    required this.tipoMaterial,
    required this.rutTecnico,
    this.nombreTecnico,
    this.soloCamara = true,
    this.seriesYaUsadas = const {},
  });

  @override
  State<_BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<_BarcodeScannerSheet>
    with SingleTickerProviderStateMixin {
  static const _surface = Color(0xFF0D1B2A);
  static const _border  = Color(0xFF1E3A5F);
  static const _accent  = Color(0xFF00D9FF);
  static const _textDim = Color(0xFF8FA8C8);

  final MobileScannerController _ctrl = MobileScannerController();
  bool _scanned        = false;
  bool _mostrandoLista = false;
  bool _cargando       = false;
  List<ItemStock> _seriesDisponibles = [];

  late final AnimationController _lineCtrl;
  late final Animation<double>    _lineAnim;

  @override
  void initState() {
    super.initState();
    _lineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _lineAnim = CurvedAnimation(parent: _lineCtrl, curve: Curves.easeInOut);
    if (!widget.soloCamara) {
      _cargarSeries();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _lineCtrl.dispose();
    super.dispose();
  }

  List<ItemStock> _filtrarDisponibles(List<ItemStock> items) {
    return items.where((item) {
      final serie = item.serie;
      if (serie == null || serie.isEmpty) return false;
      final norm = LogisticaService.normalizeSerie(serie);
      return !widget.seriesYaUsadas.contains(norm);
    }).toList();
  }

  Future<void> _cargarSeries() async {
    setState(() => _cargando = true);
    try {
      final tecnico = await LogisticaService().fetchStockTecnico(
        widget.rutTecnico,
        nombreDisplay: widget.nombreTecnico,
      );
      final items = _filtrarDisponibles(
          tecnico?.seriadosPorCategoria(widget.tipoMaterial) ?? []);
      setState(() {
        _seriesDisponibles = items;
        _mostrandoLista    = true;
        _cargando          = false;
      });
    } catch (_) {
      setState(() {
        _seriesDisponibles = [];
        _mostrandoLista    = true;
        _cargando          = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(children: [
        const SizedBox(height: 12),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 12),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: Text(
                _mostrandoLista
                    ? 'Mi saldo · ${widget.tipoMaterial}'
                    : 'Escanear código de barra',
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            if (widget.soloCamara)
              TextButton.icon(
                onPressed: _cargando
                    ? null
                    : () {
                        if (_mostrandoLista) {
                          setState(() => _mostrandoLista = false);
                        } else {
                          _cargarSeries();
                        }
                      },
                icon: Icon(
                  _mostrandoLista
                      ? Icons.qr_code_scanner
                      : Icons.list_alt_outlined,
                  size: 16,
                  color: _accent,
                ),
                label: Text(
                  _mostrandoLista ? 'Cámara' : 'Ver mis series',
                  style: const TextStyle(color: _accent, fontSize: 12),
                ),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
              ),
          ]),
        ),

        const SizedBox(height: 8),

        // ── Cuerpo: cámara o lista ────────────────────────────
        Expanded(
          child: _cargando
              ? const Center(
                  child: CircularProgressIndicator(color: _accent))
              : _mostrandoLista
                  ? _buildLista()
                  : _buildCamara(),
        ),

        // ── Botón cancelar ────────────────────────────────────
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar',
              style: TextStyle(color: _textDim)),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _buildCamara() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            const stripH  = 64.0;
            final stripTop = (h - stripH) / 2;
            final scanWindow = Rect.fromLTWH(0, stripTop, w, stripH);

            return Stack(
              children: [
                // ── Cámara con zona de detección restringida ─────
                MobileScanner(
                  controller: _ctrl,
                  scanWindow: scanWindow,
                  onDetect: (capture) {
                    if (_scanned) return;
                    final raw = capture.barcodes.firstOrNull?.rawValue;
                    if (raw != null && raw.isNotEmpty) {
                      _scanned = true;
                      Navigator.pop(context, raw);
                    }
                  },
                ),

                // ── Overlay oscuro fuera de la franja ────────────
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ScanOverlayPainter(scanWindow: scanWindow),
                  ),
                ),

                // ── Línea roja animada (efecto láser) ────────────
                AnimatedBuilder(
                  animation: _lineAnim,
                  builder: (_, __) {
                    final lineY = stripTop + _lineAnim.value * stripH;
                    return Positioned(
                      top: lineY - 1.5,
                      left: 0, right: 0,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Colors.transparent,
                            Colors.red.withValues(alpha: 0.85),
                            Colors.red,
                            Colors.red.withValues(alpha: 0.85),
                            Colors.transparent,
                          ]),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.55),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // ── Instrucción bajo la franja ───────────────────
                Positioned(
                  top: stripTop + stripH + 14,
                  left: 0, right: 0,
                  child: Text(
                    'Alinea el código con la línea roja',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 8),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLista() {

    if (_seriesDisponibles.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.inventory_2_outlined, color: _textDim, size: 40),
          const SizedBox(height: 12),
          const Text('Sin series registradas para este material',
              style: TextStyle(color: _textDim, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(widget.tipoMaterial,
              style: const TextStyle(color: _accent, fontSize: 12)),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: _seriesDisponibles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final item = _seriesDisponibles[i];
        return InkWell(
          onTap: () => Navigator.pop(context, item),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: Row(children: [
              const Icon(Icons.memory_outlined, color: _accent, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.serie ?? '',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    Text(item.nombre,
                        style: const TextStyle(
                            color: _textDim, fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _textDim, size: 18),
            ]),
          ),
        );
      },
    );
  }
}

// ── Overlay para el scanner de códigos ───────────────────────
// Oscurece la zona fuera de [scanWindow] y dibuja esquinas rojas.

class _ScanOverlayPainter extends CustomPainter {
  final Rect scanWindow;

  const _ScanOverlayPainter({required this.scanWindow});

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()..color = const Color(0xBB000000);

    // Zona superior
    canvas.drawRect(
      Rect.fromLTRB(0, 0, size.width, scanWindow.top),
      shadow,
    );
    // Zona inferior
    canvas.drawRect(
      Rect.fromLTRB(0, scanWindow.bottom, size.width, size.height),
      shadow,
    );

    // Borde fino de la franja activa
    canvas.drawRect(
      scanWindow,
      Paint()
        ..color = Colors.red.withValues(alpha: 0.35)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );

    // Esquinas rojas (corner brackets)
    final corner = Paint()
      ..color = Colors.red
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const cl = 20.0; // longitud de cada trazo de esquina

    final l = scanWindow.left;
    final r = scanWindow.right;
    final t = scanWindow.top;
    final b = scanWindow.bottom;

    // Superior-izquierda
    canvas.drawLine(Offset(l, t + cl), Offset(l, t), corner);
    canvas.drawLine(Offset(l, t), Offset(l + cl, t), corner);
    // Superior-derecha
    canvas.drawLine(Offset(r - cl, t), Offset(r, t), corner);
    canvas.drawLine(Offset(r, t), Offset(r, t + cl), corner);
    // Inferior-izquierda
    canvas.drawLine(Offset(l, b - cl), Offset(l, b), corner);
    canvas.drawLine(Offset(l, b), Offset(l + cl, b), corner);
    // Inferior-derecha
    canvas.drawLine(Offset(r - cl, b), Offset(r, b), corner);
    canvas.drawLine(Offset(r, b), Offset(r, b - cl), corner);
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter old) =>
      old.scanWindow != scanWindow;
}
