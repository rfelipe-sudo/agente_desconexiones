import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/models/solicitud_material.dart';
import 'package:agente_desconexiones/services/logistica_service.dart';
import 'package:agente_desconexiones/screens/supervisor/tecnico_stock_screen.dart';

class SolicitudesMaterialSupervisorScreen extends StatefulWidget {
  const SolicitudesMaterialSupervisorScreen({super.key});

  @override
  State<SolicitudesMaterialSupervisorScreen> createState() =>
      _SolicitudesMaterialSupervisorScreenState();
}

class _SolicitudesMaterialSupervisorScreenState
    extends State<SolicitudesMaterialSupervisorScreen>
    with SingleTickerProviderStateMixin {
  // ── Colores ────────────────────────────────────────────────────
  static const _bg      = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _border  = Color(0xFF1E3A5F);
  static const _accent  = Color(0xFF00D9FF);
  static const _green   = Color(0xFF22C55E);
  static const _orange  = Color(0xFFF59E0B);
  static const _red     = Color(0xFFEF4444);
  static const _textDim = Color(0xFF8FA8C8);

  // ── Tabs ───────────────────────────────────────────────────────
  late TabController _tabCtrl;

  // ── Datos ──────────────────────────────────────────────────────
  List<SolicitudMaterial> _activas    = [];
  List<SolicitudMaterial> _historial  = [];
  bool _cargando = true;

  // Timer para refrescar el indicador de tiempo sin atención
  Timer? _clockTimer;

  StreamSubscription<List<Map<String, dynamic>>>? _subActivas;

  final _db = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _suscribir();
    _cargarHistorial();
    // Refresca el reloj cada 15 s para actualizar el tiempo transcurrido
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _clockTimer?.cancel();
    _subActivas?.cancel();
    super.dispose();
  }

  // ── Realtime ───────────────────────────────────────────────────

  void _suscribir() {
    _subActivas = _db
        .from('solicitudes_material')
        .stream(primaryKey: ['id'])
        .inFilter('estado', ['pendiente', 'aceptada', 'en_guia'])
        .listen((rows) {
      if (!mounted) return;
      final lista = rows
          .map((r) => SolicitudMaterial.fromMap(r as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() {
        _activas  = lista;
        _cargando = false;
      });
    });
  }

  Future<void> _cargarHistorial() async {
    final rows = await _db
        .from('solicitudes_material')
        .select()
        .inFilter('estado', ['completada', 'cancelada'])
        .order('created_at', ascending: false)
        .limit(40);

    if (!mounted) return;
    setState(() {
      _historial = rows
          .map((r) => SolicitudMaterial.fromMap(r as Map<String, dynamic>))
          .toList();
    });
  }

  // ── Helpers ────────────────────────────────────────────────────

  /// Solicitudes pendientes sin atención pasados 5 minutos
  List<SolicitudMaterial> get _vencidas => _activas.where((s) {
        if (s.estado != 'pendiente') return false;
        return DateTime.now().difference(s.createdAt).inMinutes >= 5;
      }).toList();

  int get _badgeCount => _vencidas.length;

  String _tiempoTranscurrido(DateTime fecha) {
    final diff = DateTime.now().difference(fecha);
    if (diff.inSeconds < 60) return 'hace ${diff.inSeconds}s';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    return 'hace ${diff.inHours} h';
  }

  String _labelEstado(String estado) => switch (estado) {
        'pendiente' => 'Sin atender',
        'aceptada'  => 'En camino',
        'en_guia'   => 'Firmando guía',
        'completada' => 'Completada',
        'cancelada' => 'Cancelada',
        _ => estado,
      };

  Color _colorEstado(String estado) => switch (estado) {
        'pendiente'  => _orange,
        'aceptada'   => _accent,
        'en_guia'    => _green,
        'completada' => _green,
        'cancelada'  => _textDim,
        _ => _textDim,
      };

  // ── Guía ───────────────────────────────────────────────────────

  Future<void> _verGuia(String guiaId) async {
    try {
      final row = await _db
          .from('solicitudes_bodega')
          .select()
          .eq('id', guiaId)
          .single();

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: _surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _GuiaBottomSheet(guia: row as Map<String, dynamic>),
      );
    } catch (e) {
      _snack('No se pudo cargar la guía: $e');
    }
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
        title: const Text('Solicitudes de Material',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          if (_badgeCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_badgeCount sin atender',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: _accent,
          labelColor: _accent,
          unselectedLabelColor: _textDim,
          tabs: const [
            Tab(text: 'Activas'),
            Tab(text: 'Historial'),
            Tab(text: 'Stock'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildActivas(),
          _buildHistorial(),
          _buildStock(),
        ],
      ),
    );
  }

  // ── Tab: Activas ───────────────────────────────────────────────

  Widget _buildActivas() {
    if (_cargando) {
      return const Center(
        child: CircularProgressIndicator(color: _accent),
      );
    }

    if (_activas.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.inventory_2_outlined, color: _textDim, size: 48),
          const SizedBox(height: 16),
          const Text('Sin solicitudes activas',
              style: TextStyle(color: _textDim, fontSize: 14)),
        ]),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // ── Banner de alerta si hay pendientes > 5 min ──
        if (_vencidas.isNotEmpty)
          _buildBannerAlerta(),

        // ── Agrupadas por estado ──
        ..._buildGrupos(),

      ],
    );
  }

  Widget _buildBannerAlerta() {
    final n = _vencidas.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _red.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: _red, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            n == 1
                ? '1 solicitud lleva más de 5 min sin atención'
                : '$n solicitudes llevan más de 5 min sin atención',
            style: const TextStyle(
                color: _red, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ]),
    );
  }

  List<Widget> _buildGrupos() {
    final pendientes  = _activas.where((s) => s.estado == 'pendiente').toList();
    final aceptadas   = _activas.where((s) => s.estado == 'aceptada').toList();
    final enGuia      = _activas.where((s) => s.estado == 'en_guia').toList();

    return [
      if (pendientes.isNotEmpty) ...[
        _seccion('SIN ATENDER', _orange),
        ...pendientes.map(_buildCard),
        const SizedBox(height: 10),
      ],
      if (aceptadas.isNotEmpty) ...[
        _seccion('EN CAMINO', _accent),
        ...aceptadas.map(_buildCard),
        const SizedBox(height: 10),
      ],
      if (enGuia.isNotEmpty) ...[
        _seccion('FIRMANDO GUÍA', _green),
        ...enGuia.map(_buildCard),
      ],
    ];
  }

  Widget _buildCard(SolicitudMaterial sol) {
    final vencida = sol.estado == 'pendiente' &&
        DateTime.now().difference(sol.createdAt).inMinutes >= 5;
    final borderColor = vencida ? _red : _colorEstado(sol.estado);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Cabecera ────────────────────────────────────
        Row(children: [
          // Chip de estado
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: borderColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _labelEstado(sol.estado),
              style: TextStyle(
                  color: borderColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          // Material
          Expanded(
            child: Text(
              '${sol.cantidad}× ${sol.tipoMaterial}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ),
          // Tiempo
          Text(
            _tiempoTranscurrido(sol.createdAt),
            style: TextStyle(
                color: vencida ? _red : _textDim, fontSize: 11),
          ),
          if (vencida) ...[
            const SizedBox(width: 4),
            const Icon(Icons.alarm, color: _red, size: 14),
          ],
        ]),

        const SizedBox(height: 10),
        const Divider(height: 1, color: _border),
        const SizedBox(height: 10),

        // ── Solicitante ─────────────────────────────────
        _persona(
          icono: Icons.person_outline,
          label: 'Solicita',
          nombre: sol.nombreSolicitante,
          rut: sol.rutSolicitante,
          color: _orange,
        ),

        // ── Entregador ──────────────────────────────────
        if (sol.nombreEntregador != null) ...[
          const SizedBox(height: 6),
          _persona(
            icono: Icons.directions_walk,
            label: 'Entrega',
            nombre: sol.nombreEntregador!,
            rut: sol.rutEntregador ?? '',
            color: _accent,
          ),
        ] else ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.person_search_outlined,
                color: _textDim, size: 14),
            const SizedBox(width: 6),
            Text(
              vencida
                  ? 'Sin técnico asignado — más de 5 min'
                  : 'Esperando técnico cercano…',
              style: TextStyle(
                  color: vencida ? _red : _textDim, fontSize: 12),
            ),
          ]),
        ],

        // ── Botón ver guía ──────────────────────────────
        if (sol.guiaId != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _verGuia(sol.guiaId!),
              icon: const Icon(Icons.description_outlined, size: 15),
              label: const Text('Ver guía de traspaso',
                  style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _green,
                side: BorderSide(color: _green.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _persona({
    required IconData icono,
    required String label,
    required String nombre,
    required String rut,
    required Color color,
  }) =>
      Row(children: [
        Icon(icono, color: color, size: 14),
        const SizedBox(width: 6),
        Text('$label: ',
            style:
                const TextStyle(color: _textDim, fontSize: 12)),
        Expanded(
          child: Text(
            '$nombre  ·  $rut',
            style: const TextStyle(
                color: Colors.white, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]);

  // ── Tab: Stock ─────────────────────────────────────────────────

  Widget _buildStock() {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(14),
      child: _StockMaterialesWidget(),
    );
  }

  // ── Tab: Historial ─────────────────────────────────────────────

  Widget _buildHistorial() {
    if (_historial.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.history, color: _textDim, size: 48),
          const SizedBox(height: 16),
          const Text('Sin historial',
              style: TextStyle(color: _textDim, fontSize: 14)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _cargarHistorial,
            child: const Text('Recargar'),
          ),
        ]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: _historial.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _buildHistorialItem(_historial[i]),
    );
  }

  Widget _buildHistorialItem(SolicitudMaterial sol) {
    final completada = sol.estado == 'completada';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Row(children: [
        Icon(
          completada
              ? Icons.check_circle_outline
              : Icons.cancel_outlined,
          color: completada ? _green : _textDim,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(
              '${sol.cantidad}× ${sol.tipoMaterial}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              sol.nombreSolicitante,
              style: const TextStyle(color: _textDim, fontSize: 11),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            _labelEstado(sol.estado),
            style: TextStyle(
                color: completada ? _green : _textDim,
                fontSize: 11,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            _tiempoTranscurrido(sol.createdAt),
            style: const TextStyle(color: _textDim, fontSize: 10),
          ),
        ]),
        if (sol.guiaId != null) ...[
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _verGuia(sol.guiaId!),
            icon: const Icon(Icons.description_outlined,
                color: _green, size: 18),
            tooltip: 'Ver guía',
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ],
      ]),
    );
  }

  // ── Helpers UI ─────────────────────────────────────────────────

  Widget _seccion(String titulo, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(titulo,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 0.8)),
        ]),
      );

}

// ─────────────────────────────────────────────────────────────
// Widget de stock de materiales por técnico
// ─────────────────────────────────────────────────────────────

class _StockMaterialesWidget extends StatefulWidget {
  const _StockMaterialesWidget();

  @override
  State<_StockMaterialesWidget> createState() => _StockMaterialesWidgetState();
}

class _StockMaterialesWidgetState extends State<_StockMaterialesWidget> {
  static const _surface  = Color(0xFF0D1B2A);
  static const _border   = Color(0xFF1E3A5F);
  static const _accent   = Color(0xFF00D9FF);
  static const _textDim  = Color(0xFF8FA8C8);
  static const _green    = Color(0xFF22C55E);
  static const _orange   = Color(0xFFF59E0B);
  static const _red      = Color(0xFFEF4444);

  List<TecnicoStock> _todos   = [];
  bool   _cargando = false;
  bool   _cargado  = false;
  String? _error;

  String _busquedaNombre   = '';
  String _busquedaMaterial = '';
  final _nombreCtrl   = TextEditingController();
  final _materialCtrl = TextEditingController();

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
      setState(() {
        _todos    = lista;
        _cargando = false;
        _cargado  = true;
      });
    } catch (e) {
      setState(() { _cargando = false; _error = e.toString(); });
    }
  }

  void _setNombre(String q)   => setState(() => _busquedaNombre   = q.trim().toLowerCase());
  void _setMaterial(String q) => setState(() => _busquedaMaterial = q.trim().toLowerCase());

  // Lista resultante: filtra por nombre y, si hay búsqueda de material,
  // incluye TODOS los técnicos ordenados de mayor a menor cantidad.
  List<TecnicoStock> get _lista {
    var result = _todos.toList();

    if (_busquedaNombre.isNotEmpty) {
      result = result
          .where((t) => t.nombre.toLowerCase().contains(_busquedaNombre))
          .toList();
    }

    if (_busquedaMaterial.isNotEmpty) {
      // Ordena de mayor a menor; incluye técnicos con 0
      result.sort((a, b) =>
          _cantidadMaterial(b).compareTo(_cantidadMaterial(a)));
    }

    return result;
  }

  // Suma de todas las categorías que coincidan con la búsqueda de material
  double _cantidadMaterial(TecnicoStock t) {
    if (_busquedaMaterial.isEmpty) return 0;
    double total = 0;
    for (final e in t.stock.entries) {
      if (e.key.toLowerCase().contains(_busquedaMaterial)) total += e.value;
    }
    return total;
  }

  // Total del material buscado sumado sobre TODOS los técnicos cargados
  double get _totalMaterial {
    if (_busquedaMaterial.isEmpty) return 0;
    double total = 0;
    for (final t in _todos) {
      total += _cantidadMaterial(t);
    }
    return total;
  }

  // Técnicos del plantel completo que tienen al menos 1 unidad del material
  int get _tecnicosConStock =>
      _todos.where((t) => _cantidadMaterial(t) > 0).length;

  Color _badgeColor(double cantidad) {
    if (cantidad == 0) return _textDim;
    if (cantidad >= 5) return _green;
    if (cantidad >= 2) return _orange;
    return _red;
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
        // Número grande
        Text(
          totalStr,
          style: TextStyle(
            color:      color,
            fontSize:   28,
            fontWeight: FontWeight.bold,
            height:     1,
          ),
        ),
        const SizedBox(width: 10),
        // Etiquetas
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'unidades en el plantel',
                style: TextStyle(color: color, fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                conStock == 0
                    ? 'Ningún técnico tiene este material'
                    : '$conStock técnico${conStock == 1 ? '' : 's'} con stock · orden mayor → menor',
                style: const TextStyle(color: _textDim, fontSize: 11),
              ),
            ],
          ),
        ),
        // Icono
        Icon(Icons.inventory_2_outlined, color: color.withValues(alpha: 0.6), size: 22),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Encabezado ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(children: [
            const Icon(Icons.warehouse_outlined, color: _accent, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('STOCK POR TÉCNICO',
                  style: TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5)),
            ),
            if (!_cargado && !_cargando)
              TextButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.download_outlined, size: 14),
                label: const Text('Cargar', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: _accent),
              ),
            if (_cargado)
              IconButton(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh, size: 16, color: _textDim),
                tooltip: 'Actualizar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ]),
        ),

        // ── Estado: cargando / error / vacío / sin tocar ─────
        if (_cargando)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(color: _accent, strokeWidth: 2),
                SizedBox(height: 10),
                Text('Consultando logística…',
                    style: TextStyle(color: _textDim, fontSize: 12)),
              ]),
            ),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(children: [
              const Icon(Icons.error_outline, color: _red, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: const TextStyle(color: _red, fontSize: 11)),
              ),
              TextButton(
                onPressed: _cargar,
                child: const Text('Reintentar',
                    style: TextStyle(fontSize: 11)),
              ),
            ]),
          )
        else if (!_cargado)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(children: [
              const Icon(Icons.touch_app, color: _textDim, size: 14),
              const SizedBox(width: 8),
              const Text('Presiona "Cargar" para ver el stock del equipo',
                  style: TextStyle(color: _textDim, fontSize: 12)),
            ]),
          )
        else ...[
          // ── Buscador por técnico ─────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _searchField(
              ctrl: _nombreCtrl,
              hint: 'Buscar técnico…',
              icon: Icons.person_search_outlined,
              value: _busquedaNombre,
              onChanged: _setNombre,
              onClear: () { _nombreCtrl.clear(); _setNombre(''); },
            ),
          ),

          // ── Buscador por material ────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
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

          // ── Banner total (solo cuando hay búsqueda de material) ─
          if (_busquedaMaterial.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
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

          if (_lista.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Text('Sin resultados',
                  style: TextStyle(color: _textDim, fontSize: 12)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _lista.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: _border),
              itemBuilder: (_, i) => _buildTecnicoTile(_lista[i]),
            ),

          const SizedBox(height: 4),
        ],
      ]),
    );
  }

  Widget _buildTecnicoTile(TecnicoStock t) {
    final busqMat   = _busquedaMaterial.isNotEmpty;
    final cantidad  = busqMat ? _cantidadMaterial(t) : 0.0;
    final sinStock  = busqMat && cantidad == 0;
    final avatarClr = sinStock
        ? _textDim.withValues(alpha: 0.3)
        : _accent.withValues(alpha: 0.12);
    final letraClr  = sinStock ? _textDim.withValues(alpha: 0.4) : _accent;

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TecnicoStockScreen(tecnico: t)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          // Avatar inicial
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: avatarClr, shape: BoxShape.circle),
            child: Center(
              child: Text(
                t.nombre.isNotEmpty ? t.nombre[0].toUpperCase() : '?',
                style: TextStyle(
                    color: letraClr,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Nombre + subtítulo
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
          // Badge de cantidad (solo en búsqueda de material) o chevron
          if (busqMat)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _badgeColor(cantidad).withValues(
                    alpha: sinStock ? 0.06 : 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                cantidad == cantidad.truncate()
                    ? '${cantidad.toInt()}'
                    : cantidad.toStringAsFixed(1),
                style: TextStyle(
                  color: _badgeColor(cantidad),
                  fontWeight:
                      sinStock ? FontWeight.normal : FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            )
          else
            const Icon(Icons.chevron_right, color: _textDim, size: 20),
        ]),
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
  }) =>
      TextField(
        controller: ctrl,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _textDim, fontSize: 13),
          prefixIcon: Icon(icon,
              color: accentColor ? _accent : _textDim, size: 18),
          suffixIcon: value.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: _textDim, size: 16),
                  onPressed: onClear,
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                  color: accentColor
                      ? _accent.withValues(alpha: 0.5)
                      : _border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _accent)),
          filled: true,
          fillColor: const Color(0xFF0A1628),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// Bottom sheet: detalle de guía de traspaso
// ─────────────────────────────────────────────────────────────

class _GuiaBottomSheet extends StatelessWidget {
  const _GuiaBottomSheet({required this.guia});
  final Map<String, dynamic> guia;

  static const _surface = Color(0xFF0D1B2A);
  static const _border  = Color(0xFF1E3A5F);
  static const _accent  = Color(0xFF00D9FF);
  static const _textDim = Color(0xFF8FA8C8);
  static const _green   = Color(0xFF22C55E);

  @override
  Widget build(BuildContext context) {
    final series = (guia['series'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),

            // Título
            Row(children: [
              const Icon(Icons.description_outlined,
                  color: _accent, size: 18),
              const SizedBox(width: 8),
              const Text('GUÍA DE TRASPASO',
                  style: TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 0.5)),
            ]),
            const Divider(height: 20, color: _border),

            _campo('Fecha', '${guia['fecha'] ?? '-'}'),
            _campo('Hora', '${guia['hora'] ?? '-'}'),
            _campo('Lugar', '${guia['lugar'] ?? '-'}'),
            const Divider(height: 16, color: _border),
            _campo('Solicitante', '${guia['nombre_solicitante'] ?? '-'}'),
            _campo('RUT sol.', '${guia['rut_solicitante'] ?? '-'}'),
            _campo('Entregador', '${guia['nombre_entregador'] ?? '-'}'),
            _campo('RUT ent.', '${guia['rut_entregador'] ?? '-'}'),
            const Divider(height: 16, color: _border),
            _campo('Material', '${guia['detalle_material'] ?? '-'}'),
            _campo('Cantidad', '${guia['cantidad'] ?? '-'}'),
            if (series.isNotEmpty)
              _campo('Series', series.join('\n')),
            const Divider(height: 16, color: _border),

            // Estado de firmas
            _firmaIndicador(
              'Firma entregador',
              guia['firma_entregador'] != null,
            ),
            const SizedBox(height: 6),
            _firmaIndicador(
              'Firma solicitante',
              guia['firma_solicitante'] != null,
            ),

            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Cerrar',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text('$label:',
                  style:
                      const TextStyle(color: _textDim, fontSize: 12)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );

  Widget _firmaIndicador(String label, bool tiene) => Row(children: [
        Icon(
          tiene ? Icons.check_circle : Icons.radio_button_unchecked,
          color: tiene ? _green : _textDim,
          size: 16,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
              color: tiene ? Colors.white : _textDim, fontSize: 12),
        ),
      ]);
}
