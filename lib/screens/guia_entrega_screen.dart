import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/config/constants.dart';
import 'package:agente_desconexiones/models/solicitud_material.dart';
import 'package:agente_desconexiones/screens/pin_entry_screen.dart';

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

  // Firma del entregador guardada para incluir en el PDF
  String? _firmaEntregadorB64;
  // Bytes del PDF generado — disponible en pantalla de confirmación
  Uint8List? _pdfBytes;

  // Series ingresadas por el entregador
  final List<String>      _series   = [];
  final TextEditingController _serieCtrl = TextEditingController();

  final _db = Supabase.instance.client;

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
  }

  @override
  void dispose() {
    _firmaCtrl.dispose();
    _serieCtrl.dispose();
    super.dispose();
  }

  // ── Series ───────────────────────────────────────────────────

  void _agregarSerie(String serie) {
    final s = serie.trim();
    if (s.isEmpty || _series.contains(s)) return;
    setState(() {
      _series.add(s);
      _serieCtrl.clear();
    });
  }

  void _eliminarSerie(String serie) =>
      setState(() => _series.remove(serie));

  Future<void> _escanearCodigo() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => const _BarcodeScannerSheet(),
    );
    if (result != null && result.isNotEmpty) _agregarSerie(result);
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

      final now = DateTime.now();
      final guia = await _db.from('solicitudes_bodega').insert({
        'solicitud_id':       sol.id,
        'rut_solicitante':    sol.rutSolicitante,
        'nombre_solicitante': sol.nombreSolicitante,
        'rut_entregador':     widget.rutPropio,
        'nombre_entregador':  widget.nombrePropio,
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

      await _db.from('solicitudes_material').update({
        'estado':   'en_guia',
        'guia_id':  guiaId,
        'series':   _series,
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
    setState(() => _guardando = true);
    try {
      final b64    = await _toBase64(_firmaCtrl);
      final guiaId = _guiaId ?? widget.solicitud.guiaId;

      await _db.from('solicitudes_bodega').update({
        'firma_solicitante': b64,
        'estado':            'firmada',
      }).eq('id', guiaId!);

      // Estado 'firmada': ambas firmas OK, falta confirmar PIN con Kepler.
      await _db.from('solicitudes_material').update({
        'estado': 'firmada',
      }).eq('id', widget.solicitud.id);

      // Generar PIN en Supabase y enviar por FCM al solicitante.
      await _db.functions.invoke('generar-pin', body: {
        'solicitud_id': widget.solicitud.id,
      });

      // Registro de combustible (fire-and-forget, no bloquea el PIN).
      unawaited(_insertarCombustible());

      // Generar PDF con ambas firmas
      if (_firmaEntregadorB64 != null) {
        try {
          _pdfBytes = await _generarPdf(
            firmaEntregadorB64:  _firmaEntregadorB64!,
            firmaSolicitanteB64: b64,
          );
        } catch (_) {
          // PDF no crítico — la guía igual queda firmada en Supabase
        }
      }

      setState(() => _guardando = false);

      if (!mounted) return;
      // Navegar a pantalla de ingreso de PIN (B ingresa el PIN que A recibió).
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PinEntryScreen(solicitud: widget.solicitud),
        ),
      );
    } catch (e) {
      setState(() => _guardando = false);
      _snack('Error: $e');
    }
  }

  // ── Insert combustible_materiales ─────────────────────────────

  Future<void> _insertarCombustible() async {
    final sol      = widget.solicitud;
    final modalidad = sol.modalidad;
    if (modalidad == null) return;

    final guiaId    = _guiaId ?? sol.guiaId;
    final meetLat   = widget.posicion?.latitude;
    final meetLng   = widget.posicion?.longitude;

    try {
      // Consulta en paralelo la última OT de entregador y solicitante
      final results = await Future.wait([
        _db
            .from('produccion_creaciones')
            .select('orden_trabajo, coord_x, coord_y')
            .eq('rut_tecnico', sol.rutEntregador ?? widget.rutPropio)
            .order('fecha_proceso', ascending: false)
            .limit(1),
        _db
            .from('produccion_creaciones')
            .select('orden_trabajo, coord_x, coord_y')
            .eq('rut_tecnico', sol.rutSolicitante)
            .order('fecha_proceso', ascending: false)
            .limit(1),
      ]);

      final rowE = (results[0] as List).isNotEmpty
          ? results[0][0] as Map<String, dynamic>
          : null;
      final rowS = (results[1] as List).isNotEmpty
          ? results[1][0] as Map<String, dynamic>
          : null;

      // coord_x = longitud, coord_y = latitud (convención geográfica)
      double? latE = double.tryParse(rowE?['coord_y']?.toString() ?? '');
      double? lngE = double.tryParse(rowE?['coord_x']?.toString() ?? '');
      double? latS = double.tryParse(rowS?['coord_y']?.toString() ?? '');
      double? lngS = double.tryParse(rowS?['coord_x']?.toString() ?? '');

      double? p1Lat, p1Lng, p4Lat, p4Lng;
      String? p1Ot, p4Ot;

      if (modalidad == 'yo_te_lo_llevo') {
        // Entregador parte de su OT → llega donde el solicitante → solicitante retorna a su OT
        p1Ot = rowE?['orden_trabajo'] as String?;
        p1Lat = latE; p1Lng = lngE;
        p4Ot = rowS?['orden_trabajo'] as String?;
        p4Lat = latS; p4Lng = lngS;
      } else {
        // Solicitante parte de su OT → va a buscar donde el entregador → retorna a su OT
        p1Ot = rowS?['orden_trabajo'] as String?;
        p1Lat = latS; p1Lng = lngS;
        p4Ot = p1Ot;
        p4Lat = latS; p4Lng = lngS;
      }

      await _db.from('combustible_materiales').insert({
        'solicitud_id':    sol.id,
        'guia_id':         guiaId,
        'modalidad':       modalidad,
        'rut_entregador':  sol.rutEntregador ?? widget.rutPropio,
        'rut_solicitante': sol.rutSolicitante,
        // P1: OT origen
        'p1_orden_trabajo': p1Ot,
        'p1_lat':           p1Lat,
        'p1_lng':           p1Lng,
        // P2: punto de entrega (GPS entregador al firmar)
        'p2_lat':           meetLat,
        'p2_lng':           meetLng,
        // P3: punto de recepción (coincide con el lugar de la guía)
        'p3_lat':           meetLat,
        'p3_lng':           meetLng,
        // P4: OT destino / retorno
        'p4_orden_trabajo': p4Ot,
        'p4_lat':           p4Lat,
        'p4_lng':           p4Lng,
      });

      debugPrint('[Combustible] registro insertado para solicitud ${sol.id}');
    } catch (e) {
      debugPrint('[Combustible] error: $e');
    }
  }

  // ── Generación de PDF ────────────────────────────────────────

  Future<Uint8List> _generarPdf({
    required String firmaEntregadorB64,
    required String firmaSolicitanteB64,
  }) async {
    final sol  = widget.solicitud;
    final now  = DateTime.now();
    final fecha = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final hora  = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final firmaE = pw.MemoryImage(base64Decode(firmaEntregadorB64));
    final firmaS = pw.MemoryImage(base64Decode(firmaSolicitanteB64));

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Título
            pw.Center(
              child: pw.Text(
                'GUÍA DE ENTREGA DE MATERIAL',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'CREABOX — Operaciones de fibra óptica',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey600),
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Divider(),
            pw.SizedBox(height: 10),

            // Fecha, hora, lugar
            pw.Row(children: [
              pw.Text('Fecha: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.Text(fecha, style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(width: 20),
              pw.Text('Hora: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.Text(hora, style: const pw.TextStyle(fontSize: 10)),
            ]),
            pw.SizedBox(height: 4),
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Lugar: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.Text(_lugarStr(), style: const pw.TextStyle(fontSize: 10)),
            ]),
            pw.SizedBox(height: 14),

            // Partes
            pw.Text('PARTES', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.blueGrey700)),
            pw.Divider(height: 8, thickness: 0.5),
            _pdfFila('Solicitante (recibe)', sol.nombreSolicitante),
            _pdfFila('RUT solicitante', sol.rutSolicitante),
            _pdfFila('Entregador (entrega)', sol.nombreEntregador ?? widget.nombrePropio),
            _pdfFila('RUT entregador', sol.rutEntregador ?? widget.rutPropio),
            pw.SizedBox(height: 14),

            // Material
            pw.Text('MATERIAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.blueGrey700)),
            pw.Divider(height: 8, thickness: 0.5),
            _pdfFila('Descripción', '${sol.cantidad}× ${sol.tipoMaterial}'),
            if (_series.isNotEmpty)
              _pdfFila('N° de serie(s)', _series.join(', ')),
            pw.SizedBox(height: 20),

            // Firmas lado a lado
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('Firma del entregador',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.SizedBox(height: 2),
                      pw.Text(sol.nombreEntregador ?? widget.nombrePropio,
                          style: const pw.TextStyle(fontSize: 9)),
                      pw.SizedBox(height: 6),
                      pw.Container(
                        width: 180,
                        height: 80,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.blueGrey300),
                        ),
                        child: pw.Image(firmaE, fit: pw.BoxFit.contain),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('Firma del solicitante',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.SizedBox(height: 2),
                      pw.Text(sol.nombreSolicitante,
                          style: const pw.TextStyle(fontSize: 9)),
                      pw.SizedBox(height: 6),
                      pw.Container(
                        width: 180,
                        height: 80,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.blueGrey300),
                        ),
                        child: pw.Image(firmaS, fit: pw.BoxFit.contain),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            pw.Spacer(),
            pw.Divider(),
            pw.Text(
              'Documento generado el $fecha a las $hora — CREABOX',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey400),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  pw.Widget _pdfFila(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 130,
              child: pw.Text('$label:',
                  style: pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey600)),
            ),
            pw.Expanded(
              child: pw.Text(value,
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
      );

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
                onPressed: _guardando
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

        // Escáner + campo manual
        Row(children: [
          Expanded(
            child: TextField(
              controller: _serieCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Número de serie',
                hintStyle:
                    TextStyle(color: _textDim.withValues(alpha: 0.5)),
                filled: true,
                fillColor: const Color(0xFF0A1628),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFF00D9FF)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                isDense: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              onSubmitted: _agregarSerie,
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => _agregarSerie(_serieCtrl.text),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _accent.withValues(alpha: 0.4))),
              child: const Icon(Icons.add, color: _accent, size: 20),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: _escanearCodigo,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _green.withValues(alpha: 0.4))),
              child: const Icon(Icons.qr_code_scanner,
                  color: _green, size: 20),
            ),
          ),
        ]),

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
  const _BarcodeScannerSheet();

  @override
  State<_BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<_BarcodeScannerSheet> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _scanned = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.55,
      child: Column(children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 12),
        const Text('Escanear código de barra',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        const SizedBox(height: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              controller: _ctrl,
              onDetect: (capture) {
                if (_scanned) return;
                final barcode = capture.barcodes.firstOrNull;
                final raw     = barcode?.rawValue;
                if (raw != null && raw.isNotEmpty) {
                  _scanned = true;
                  Navigator.pop(context, raw);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar',
              style: TextStyle(color: Colors.white54)),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}
