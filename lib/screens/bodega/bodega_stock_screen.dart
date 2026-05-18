import 'package:flutter/material.dart';

import 'package:agente_desconexiones/models/solicitud_material.dart';
import 'package:agente_desconexiones/services/logistica_service.dart';
import 'package:agente_desconexiones/screens/supervisor/tecnico_stock_screen.dart';

class BodegaStockScreen extends StatefulWidget {
  const BodegaStockScreen({super.key});

  @override
  State<BodegaStockScreen> createState() => _BodegaStockScreenState();
}

class _BodegaStockScreenState extends State<BodegaStockScreen> {
  static const _bg      = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _border  = Color(0xFF1E3A5F);
  static const _accent  = Color(0xFF00D9FF);
  static const _green   = Color(0xFF22C55E);
  static const _orange  = Color(0xFFF59E0B);
  static const _red     = Color(0xFFEF4444);
  static const _textDim = Color(0xFF8FA8C8);

  List<TecnicoStock> _todos  = [];
  bool   _cargando = false;
  bool   _cargado  = false;
  String? _error;

  String _busquedaNombre   = '';
  String _busquedaMaterial = '';
  final _nombreCtrl   = TextEditingController();
  final _materialCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _materialCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final lista = await LogisticaService().fetchStock();
      if (mounted) {
        setState(() { _todos = lista; _cargando = false; _cargado = true; });
      }
    } catch (e) {
      if (mounted) setState(() { _cargando = false; _error = e.toString(); });
    }
  }

  void _setNombre(String q)   => setState(() => _busquedaNombre   = q.trim().toLowerCase());
  void _setMaterial(String q) => setState(() => _busquedaMaterial = q.trim().toLowerCase());

  List<TecnicoStock> get _lista {
    var result = _todos.toList();
    if (_busquedaNombre.isNotEmpty) {
      result = result
          .where((t) => t.nombre.toLowerCase().contains(_busquedaNombre))
          .toList();
    }
    if (_busquedaMaterial.isNotEmpty) {
      result.sort((a, b) =>
          _cantidadMaterial(b).compareTo(_cantidadMaterial(a)));
    }
    return result;
  }

  double _cantidadMaterial(TecnicoStock t) {
    if (_busquedaMaterial.isEmpty) return 0;
    double total = 0;
    for (final e in t.stock.entries) {
      if (e.key.toLowerCase().contains(_busquedaMaterial)) total += e.value;
    }
    return total;
  }

  double get _totalMaterial {
    if (_busquedaMaterial.isEmpty) return 0;
    return _todos.fold(0, (s, t) => s + _cantidadMaterial(t));
  }

  int get _tecnicosConStock =>
      _todos.where((t) => _cantidadMaterial(t) > 0).length;

  Color _badgeColor(double cantidad) {
    if (cantidad == 0) return _textDim;
    if (cantidad >= 5) return _green;
    if (cantidad >= 2) return _orange;
    return _red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text('Stock en Terreno',
            style: TextStyle(color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_cargado)
            IconButton(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh, color: _textDim),
              tooltip: 'Actualizar',
            ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(color: _accent, strokeWidth: 2),
                SizedBox(height: 12),
                Text('Consultando logística…',
                    style: TextStyle(color: _textDim, fontSize: 13)),
              ]),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline, color: _red, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _red, fontSize: 13)),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _cargar,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: _bg),
                      ),
                    ]),
                  ),
                )
              : Column(
                  children: [
                    // ── Buscador técnico ──────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                      child: _searchField(
                        ctrl: _nombreCtrl,
                        hint: 'Buscar técnico…',
                        icon: Icons.person_search_outlined,
                        value: _busquedaNombre,
                        onChanged: _setNombre,
                        onClear: () { _nombreCtrl.clear(); _setNombre(''); },
                      ),
                    ),
                    // ── Buscador material ─────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: _searchField(
                        ctrl: _materialCtrl,
                        hint: 'Buscar material…',
                        icon: Icons.cable_outlined,
                        value: _busquedaMaterial,
                        onChanged: _setMaterial,
                        onClear: () { _materialCtrl.clear(); _setMaterial(''); },
                        accentColor: _busquedaMaterial.isNotEmpty,
                      ),
                    ),

                    // ── Banner total material ─────────────────────
                    if (_busquedaMaterial.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: _buildTotalBanner(),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                        child: Text(
                          _busquedaNombre.isNotEmpty
                              ? '${_lista.length} técnico(s) encontrado(s)'
                              : '${_todos.length} técnicos con stock relevante',
                          style: const TextStyle(color: _textDim, fontSize: 11),
                        ),
                      ),

                    // ── Lista de técnicos ─────────────────────────
                    Expanded(
                      child: _lista.isEmpty
                          ? const Center(
                              child: Text('Sin resultados',
                                  style: TextStyle(color: _textDim, fontSize: 13)),
                            )
                          : RefreshIndicator(
                              color: _accent,
                              onRefresh: _cargar,
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                                itemCount: _lista.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1, color: _border),
                                itemBuilder: (_, i) =>
                                    _buildTecnicoTile(_lista[i]),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildTotalBanner() {
    final total    = _totalMaterial;
    final conStock = _tecnicosConStock;
    final totalStr = total == total.truncate()
        ? '${total.toInt()}'
        : total.toStringAsFixed(1);
    final color = _badgeColor(total);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Text(totalStr,
            style: TextStyle(color: color, fontSize: 28,
                fontWeight: FontWeight.bold, height: 1)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('unidades en el plantel',
                style: TextStyle(color: color, fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              conStock == 0
                  ? 'Ningún técnico tiene este material'
                  : '$conStock técnico${conStock == 1 ? '' : 's'} con stock · orden mayor → menor',
              style: const TextStyle(color: _textDim, fontSize: 11),
            ),
          ]),
        ),
        Icon(Icons.inventory_2_outlined,
            color: color.withValues(alpha: 0.6), size: 22),
      ]),
    );
  }

  Widget _buildTecnicoTile(TecnicoStock t) {
    final busqMat  = _busquedaMaterial.isNotEmpty;
    final cantidad = busqMat ? _cantidadMaterial(t) : 0.0;
    final sinStock = busqMat && cantidad == 0;
    final avatarClr = sinStock
        ? _textDim.withValues(alpha: 0.3)
        : _accent.withValues(alpha: 0.12);
    final letraClr = sinStock ? _textDim.withValues(alpha: 0.4) : _accent;

    return Container(
      color: _surface,
      child: InkWell(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => TecnicoStockScreen(tecnico: t))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: avatarClr, shape: BoxShape.circle),
              child: Center(
                child: Text(
                  t.nombre.isNotEmpty ? t.nombre[0].toUpperCase() : '?',
                  style: TextStyle(color: letraClr,
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.nombre,
                    style: TextStyle(
                        color: sinStock
                            ? _textDim.withValues(alpha: 0.5)
                            : Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                Text(
                  busqMat ? _busquedaMaterial : '${t.stock.length} tipo(s) en stock',
                  style: const TextStyle(color: _textDim, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            const SizedBox(width: 8),
            if (busqMat) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _badgeColor(cantidad).withValues(alpha: sinStock ? 0.06 : 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  cantidad == cantidad.truncate()
                      ? '${cantidad.toInt()}'
                      : cantidad.toStringAsFixed(1),
                  style: TextStyle(
                    color: _badgeColor(cantidad),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ] else
              const Icon(Icons.chevron_right, color: _textDim, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _searchField({
    required TextEditingController ctrl,
    required String hint,
    required IconData icon,
    required String value,
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
    bool accentColor = false,
  }) {
    final color = accentColor ? _accent : _textDim;
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _textDim, fontSize: 13),
        prefixIcon: Icon(icon, color: color, size: 18),
        suffixIcon: value.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.close, color: _textDim, size: 16),
                onPressed: onClear,
              )
            : null,
        filled: true,
        fillColor: _surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: accentColor ? _accent.withValues(alpha: 0.5) : _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _accent),
        ),
      ),
      onChanged: onChanged,
    );
  }
}
