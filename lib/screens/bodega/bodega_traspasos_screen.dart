import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/models/traspaso_bodega.dart';
import 'package:agente_desconexiones/screens/bodega/bodega_guia_screen.dart';
import 'package:agente_desconexiones/services/guia_pdf_service.dart';

class BodegaTraspassosScreen extends StatefulWidget {
  const BodegaTraspassosScreen({super.key});

  @override
  State<BodegaTraspassosScreen> createState() => _BodegaTraspassosScreenState();
}

class _BodegaTraspassosScreenState extends State<BodegaTraspassosScreen> {
  static const _bg      = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _border  = Color(0xFF1E3A5F);
  static const _accent  = Color(0xFF00D9FF);
  static const _green   = Color(0xFF22C55E);
  static const _orange  = Color(0xFFF59E0B);
  static const _textDim = Color(0xFF8FA8C8);

  final _db = Supabase.instance.client;

  List<TraspassoBodega> _traspasos = [];
  bool _cargando = true;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  String _rutBodega    = '';
  String _nombreBodega = '';

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();
    _suscribir();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _cargarDatosUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    final rut   = prefs.getString('rut_tecnico') ??
                  prefs.getString('user_rut') ?? '';
    final row   = await _db
        .from('nomina_bodega')
        .select('nombre')
        .eq('rut', rut)
        .maybeSingle();
    if (mounted) {
      setState(() {
        _rutBodega    = rut;
        _nombreBodega = row?['nombre'] as String? ?? rut;
      });
    }
  }

  void _suscribir() {
    _sub = _db
        .from('traspasos_bodega')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .listen((rows) {
      if (!mounted) return;
      setState(() {
        _traspasos = rows
            .map((r) => TraspassoBodega.fromMap(r as Map<String, dynamic>))
            .toList();
        _cargando = false;
      });
    });
  }

  Future<void> _aprobar(TraspassoBodega tr) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Aprobar transferencia en KRP',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          '¿Aprobar la transferencia de ${tr.tipoMaterial} de ${tr.nombreTecnicoB} a ${tr.nombreTecnicoA}?',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aprobar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final res = await _db.functions.invoke('aprobar-traspaso', body: {
        'traspaso_id':      tr.id,
        'aprobado_por':     _rutBodega,
        'nombre_aprobador': _nombreBodega,
      });
      final data  = res.data as Map<String, dynamic>?;
      final folio = data?['folio_kepler'] as String?;
      if (mounted) {
        // Optimistic update: marcar aprobado localmente sin esperar el stream
        setState(() {
          _traspasos = _traspasos.map((t) {
            if (t.id != tr.id) return t;
            return t.copyWith(
              estado:          'aprobado',
              nombreAprobador: _nombreBodega,
              aprobadoPor:     _rutBodega,
              aprobadoEn:      DateTime.now(),
              folioKepler:     folio,
            );
          }).toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: _green,
          content: Text(folio != null
              ? 'Aprobado ✓  Folio Kepler: $folio'
              : 'Aprobado ✓  Registrado en Kepler'),
        ));

        // Enviar PDF a Kepler de forma asíncrona (best-effort)
        if (folio != null && tr.solicitudMaterialId != null) {
          _enviarPdfKepler(tr, folio);
        }
        // Forzar recarga desde DB para asegurar estado correcto
        _recargar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('Error al aprobar: $e'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text('Solicitudes de Traspaso',
            style: TextStyle(color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _traspasos.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.inbox_outlined, color: _textDim, size: 52),
                    const SizedBox(height: 12),
                    Text('Sin solicitudes de traspaso',
                        style: TextStyle(color: _textDim, fontSize: 14)),
                  ]),
                )
              : _buildLista(),
    );
  }

  Widget _buildLista() {
    final pendientes  = _traspasos.where((t) => t.pendiente).toList();
    final krpOk       = _traspasos.where((t) => t.krpOk && !t.sapOk).toList();
    final sapOk       = _traspasos.where((t) => t.sapOk).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (pendientes.isNotEmpty) ...[
          _seccionHeader('Pendientes de aprobación', _orange),
          ...pendientes.map(_buildTraspasoCard),
          const SizedBox(height: 8),
        ],
        if (krpOk.isNotEmpty) ...[
          _seccionHeader('KRP realizado — SAP pendiente', _accent),
          ...krpOk.map(_buildTraspasoCard),
          const SizedBox(height: 8),
        ],
        if (sapOk.isNotEmpty) ...[
          _seccionHeader('Transferencia completa', _green),
          ...sapOk.map(_buildTraspasoCard),
        ],
      ],
    );
  }

  Future<void> _confirmarSap(TraspassoBodega tr) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Confirmar transferencia SAP',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          '¿Confirmar que la transferencia de ${tr.tipoMaterial} fue realizada en SAP?',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await _db.functions.invoke('confirmar-sap', body: {
        'traspaso_id':       tr.id,
        'confirmado_por':    _rutBodega,
        'nombre_confirmador': _nombreBodega,
      });
      if (mounted) {
        setState(() {
          _traspasos = _traspasos.map((t) {
            if (t.id != tr.id) return t;
            return t.copyWith(sapOk: true, sapConfirmadoEn: DateTime.now());
          }).toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: _green,
          content: Text('Transferencia SAP confirmada ✓'),
        ));
        // Forzar recarga desde DB para mover la card a la sección correcta
        _recargar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('Error al confirmar SAP: $e'),
        ));
      }
    }
  }

  Future<void> _recargar() async {
    try {
      final rows = await _db
          .from('traspasos_bodega')
          .select()
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _traspasos = (rows as List)
            .map((r) => TraspassoBodega.fromMap(r as Map<String, dynamic>))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _enviarPdfKepler(TraspassoBodega tr, String folio) async {
    try {
      final rows = await _db
          .from('solicitudes_bodega')
          .select()
          .eq('solicitud_id', tr.solicitudMaterialId!)
          .order('created_at', ascending: false)
          .limit(1);
      final list = rows as List;
      if (list.isEmpty) return;
      final guia = list.first as Map<String, dynamic>;

      final pdfBytes = await GuiaPdfService.generar(guia: guia, folio: folio);

      await _db.functions.invoke('enviar-pdf-kepler', body: {
        'pdf_base64':    base64Encode(pdfBytes),
        'folio':         folio,
        'rut_origen':    tr.rutTecnicoB,
        'rut_destino':   tr.rutTecnicoA,
        'tipo_material': tr.tipoMaterial,
        'traspaso_id':   tr.id,
      });
    } catch (e) {
      // Best-effort: el traspaso ya está aprobado, el PDF es secundario
      debugPrint('PDF Kepler error (no crítico): $e');
    }
  }

  Future<void> _verGuia(TraspassoBodega tr) async {
    final solicitudId = tr.solicitudMaterialId;
    if (solicitudId == null) return;
    try {
      final rows = await _db
          .from('solicitudes_bodega')
          .select()
          .eq('solicitud_id', solicitudId)
          .order('created_at', ascending: false)
          .limit(1);
      if (!mounted) return;
      final list = rows as List;
      if (list.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se encontró la guía asociada'),
          backgroundColor: Colors.orange,
        ));
        return;
      }
      final guia = list.first as Map<String, dynamic>;
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => BodegaGuiaScreen(
            guia: guia,
            folioKepler: tr.folioKepler,
          )));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al cargar guía: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Widget _seccionHeader(String titulo, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      Container(width: 4, height: 16,
          decoration: BoxDecoration(color: color,
              borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(titulo,
          style: TextStyle(color: color, fontSize: 13,
              fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _buildTraspasoCard(TraspassoBodega tr) {
    final fecha = '${tr.createdAt.day.toString().padLeft(2, '0')}/'
        '${tr.createdAt.month.toString().padLeft(2, '0')}/'
        '${tr.createdAt.year}  '
        '${tr.createdAt.hour.toString().padLeft(2, '0')}:'
        '${tr.createdAt.minute.toString().padLeft(2, '0')}';

    return Card(
      color: _surface,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: tr.pendiente ? _orange.withValues(alpha: 0.5) : _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
              tr.sapOk    ? Icons.verified_rounded
              : tr.krpOk  ? Icons.check_circle_outline
                          : Icons.hourglass_top_rounded,
              color: tr.sapOk   ? _green
                   : tr.krpOk  ? _accent
                               : _orange,
              size: 18,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(tr.tipoMaterial,
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            Text(fecha, style: TextStyle(color: _textDim, fontSize: 11)),
          ]),
          const SizedBox(height: 10),
          _fila('Origen (entregador)', '${tr.nombreTecnicoB} · ${tr.rutTecnicoB}'),
          _fila('Destino (solicitante)', '${tr.nombreTecnicoA} · ${tr.rutTecnicoA}'),
          _fila('Cantidad', '${tr.cantidad}'),
          if (tr.series.isNotEmpty) _fila('Series', tr.series.join(', ')),
          if (tr.folioKepler != null) _fila('Folio Kepler', tr.folioKepler!),
          if (!tr.pendiente && tr.nombreAprobador != null)
            _fila('Aprobado por', tr.nombreAprobador!),
          // Botón Ver guía (solo aprobados que tienen solicitud vinculada)
          if (!tr.pendiente && tr.solicitudMaterialId != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: const BorderSide(color: _accent),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.article_outlined, size: 16),
                label: const Text('Ver guía firmada',
                    style: TextStyle(fontSize: 13)),
                onPressed: () => _verGuia(tr),
              ),
            ),
          ],
          if (tr.pendiente) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Aprobar transferencia en KRP',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () => _aprobar(tr),
              ),
            ),
          ],
          if (tr.krpOk && !tr.sapOk) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: const Color(0xFF0A0F1E),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.sync_alt_rounded, size: 18),
                label: const Text('TRANSFERENCIA OK EN SAP',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: () => _confirmarSap(tr),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _fila(String label, String valor) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
          width: 140,
          child: Text(label,
              style: TextStyle(color: _textDim, fontSize: 12))),
      Expanded(
          child: Text(valor,
              style: const TextStyle(color: Colors.white, fontSize: 12))),
    ]),
  );
}
