import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pantalla del bodeguero: lista de guías firmadas pendientes de confirmar.
class GuiasEntregaBodegueroScreen extends StatefulWidget {
  const GuiasEntregaBodegueroScreen({super.key});

  @override
  State<GuiasEntregaBodegueroScreen> createState() =>
      _GuiasEntregaBodegueroScreenState();
}

class _GuiasEntregaBodegueroScreenState
    extends State<GuiasEntregaBodegueroScreen> {
  final _db = Supabase.instance.client;

  String? _rutBodeguero;
  String? _nombreBodeguero;
  List<Map<String, dynamic>> _guias = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _rutBodeguero    = prefs.getString('rut_tecnico');
    _nombreBodeguero = prefs.getString('nombre_tecnico') ?? 'Bodeguero';
    await _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final rows = await _db
          .from('solicitudes_bodega')
          .select()
          .eq('estado', 'firmada')
          .order('fecha', ascending: false)
          .order('hora', ascending: false);
      setState(() => _guias = (rows as List).cast<Map<String, dynamic>>());
    } catch (_) {
    } finally {
      setState(() => _cargando = false);
    }
  }

  Future<void> _confirmar(Map<String, dynamic> guia) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF1E3A5F))),
        title: const Text('Confirmar recepción',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        content: Text(
          '¿Confirmar la guía de\n${guia['detalle_material'] ?? ''}?\n\nEntregador: ${guia['nombre_entregador'] ?? ''}\nSolicitante: ${guia['nombre_solicitante'] ?? ''}',
          style: const TextStyle(color: Color(0xFF8FA8C8), fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: Color(0xFF8FA8C8)))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E)),
              child: const Text('Confirmar',
                  style: TextStyle(color: Colors.black,
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final now = DateTime.now();

      await _db.from('solicitudes_bodega').update({
        'estado':          'confirmada_bodega',
        'rut_bodeguero':   _rutBodeguero,
        'nombre_bodeguero': _nombreBodeguero,
        'fecha_traspaso':  now.toIso8601String(),
      }).eq('id', guia['id'] as String);

      // Notificar a entregador y solicitante
      await _notificarTecnico(
        rut:  guia['rut_entregador'] as String? ?? '',
        desc: 'Guía confirmada por bodega: ${guia['detalle_material'] ?? ''}',
      );
      await _notificarTecnico(
        rut:  guia['rut_solicitante'] as String? ?? '',
        desc: 'Guía confirmada por bodega: ${guia['detalle_material'] ?? ''}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Guía confirmada. Notificaciones enviadas.'),
              backgroundColor: Color(0xFF22C55E)),
        );
      }

      await _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _notificarTecnico({
    required String rut,
    required String desc,
  }) async {
    if (rut.isEmpty) return;
    try {
      await _db.from('alertas_fcm').upsert({
        'rut_tecnico': rut,
        'activa':      true,
        'tipo':        'guia_confirmada',
        'descripcion': desc,
      }, onConflict: 'rut_tecnico');
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Guías de Entrega',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _guias.isEmpty
              ? _buildVacio()
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _guias.length,
                    itemBuilder: (_, i) => _buildGuiaCard(_guias[i]),
                  ),
                ),
    );
  }

  Widget _buildVacio() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline,
              color: const Color(0xFF22C55E).withValues(alpha: 0.5), size: 56),
          const SizedBox(height: 16),
          const Text('Sin guías pendientes',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Todas las guías firmadas han sido confirmadas.',
              style: TextStyle(color: Color(0xFF8FA8C8), fontSize: 13)),
        ]),
      );

  Widget _buildGuiaCard(Map<String, dynamic> guia) {
    final series =
        (guia['series'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final hora = (guia['hora'] as String? ?? '');
    final horaStr = hora.length >= 5 ? hora.substring(0, 5) : hora;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: const Color(0xFF00D9FF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6)),
            child: Text(
              guia['detalle_material'] as String? ?? '—',
              style: const TextStyle(
                  color: Color(0xFF00D9FF),
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            ),
          ),
          const Spacer(),
          Text(
            '${guia['fecha'] ?? ''}  $horaStr',
            style: const TextStyle(color: Color(0xFF8FA8C8), fontSize: 11),
          ),
        ]),
        const SizedBox(height: 10),
        _fila('Entregador', guia['nombre_entregador'] as String? ?? '—'),
        _fila('Solicitante', guia['nombre_solicitante'] as String? ?? '—'),
        _fila('Lugar', guia['lugar'] as String? ?? '—'),

        if (series.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: series
                  .map((s) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: const Color(0xFF22C55E)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: const Color(0xFF22C55E)
                                    .withValues(alpha: 0.3))),
                        child: Text(s,
                            style: const TextStyle(
                                color: Color(0xFF22C55E),
                                fontSize: 10)),
                      ))
                  .toList(),
            ),
          ),

        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _confirmar(guia),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Confirmar traspaso',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _fila(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(children: [
          SizedBox(
            width: 90,
            child: Text('$label:',
                style: const TextStyle(
                    color: Color(0xFF8FA8C8), fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white, fontSize: 12)),
          ),
        ]),
      );
}
