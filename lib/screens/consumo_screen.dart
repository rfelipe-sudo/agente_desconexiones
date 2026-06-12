import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/consumo_reglas.dart';
import '../models/solicitud_material.dart';
import '../services/logistica_service.dart';
import '../services/recetas_consumo_service.dart';

// Mismos tokens visuales que solicitud de material.
const _bg = Color(0xFF0A1628);
const _surface = Color(0xFF0D1B2A);
const _accent = Color(0xFF00D9FF);
const _border = Color(0xFF1E3A5F);
const _textDim = Color(0xFF8FA8C8);
const _green = Color(0xFF22C55E);
const _orange = Color(0xFFF59E0B);

/// Lista de OTs pendientes de consumo → selección de materiales.
class ConsumoScreen extends StatefulWidget {
  const ConsumoScreen({super.key});

  @override
  State<ConsumoScreen> createState() => _ConsumoScreenState();
}

class _ConsumoScreenState extends State<ConsumoScreen> {
  final _service = RecetasConsumoService();
  final _logistica = LogisticaService();

  bool _cargando = true;
  String? _error;
  List<OrdenPendienteConsumo> _ordenes = [];
  List<Receta> _recetas = [];
  int? _idTrabajador;
  String? _rut;
  TecnicoStock? _stock;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final rut = prefs.getString('rut_tecnico');
      if (rut == null || rut.isEmpty) {
        throw Exception('No hay RUT de técnico en sesión');
      }

      final idTrab = await _service.resolverIdTrabajador(rut);
      if (idTrab == null) {
        throw Exception(
            'No se encontró tu ID en KRP. Contacta a soporte CREA.');
      }

      final nombre = prefs.getString('nombre_tecnico');

      final results = await Future.wait([
        _service.getOtsPendienteConsumo(rut: rut),
        _service.getRecetas(),
        _logistica.fetchStockTecnico(rut, nombreDisplay: nombre),
      ]);

      if (!mounted) return;
      final ordenes = results[0] as List<OrdenPendienteConsumo>;
      setState(() {
        _rut = rut;
        _idTrabajador = idTrab;
        _ordenes = ordenes;
        _recetas = results[1] as List<Receta>;
        _stock = results[2] as TecnicoStock?;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  void _abrirOrden(OrdenPendienteConsumo orden) {
    if (_idTrabajador == null || _rut == null) return;

    final materiales =
        _service.materialesParaReceta(_recetas, orden.idReceta);
    final nombreReceta =
        _service.nombreReceta(_recetas, orden.idReceta) ?? 'Receta';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConsumoOrdenScreen(
          orden: orden,
          materiales: materiales,
          nombreReceta: nombreReceta,
          rut: _rut!,
          idTrabajador: _idTrabajador!,
          service: _service,
          stockInicial: _stock,
          onConsumoOk: _cargar,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Consumo de Materiales'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: _accent, strokeWidth: 2))
          : _error != null
              ? _buildError()
              : _buildListaOrdenes(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: _orange, size: 48),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: FilledButton.styleFrom(backgroundColor: _accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListaOrdenes() {
    if (_ordenes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline,
                  color: _green.withValues(alpha: 0.8), size: 56),
              const SizedBox(height: 16),
              const Text(
                'Sin órdenes pendientes',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'No tienes OTs pendientes de consumo de material.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textDim, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _accent,
      backgroundColor: _surface,
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _ordenes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildCardOrden(_ordenes[i]),
      ),
    );
  }

  Widget _buildCardOrden(OrdenPendienteConsumo orden) {
    final recetaNombre =
        _service.nombreReceta(_recetas, orden.idReceta) ?? 'Receta ${orden.idReceta}';

    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _abrirOrden(orden),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _orange.withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      'PENDIENTE',
                      style: TextStyle(
                          color: _orange,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: _textDim),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                orden.codigoExterno,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                orden.tipoActividad,
                style: const TextStyle(color: _accent, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                recetaNombre,
                style: const TextStyle(color: _textDim, fontSize: 12),
              ),
              if (orden.nombreCliente.isNotEmpty &&
                  orden.nombreCliente != 'NaN') ...[
                const SizedBox(height: 6),
                Text(
                  orden.nombreCliente,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
              if (orden.direccionCliente.isNotEmpty &&
                  orden.direccionCliente != 'NaN') ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_outlined,
                        color: _textDim, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${orden.direccionCliente}${orden.comunaCliente.isNotEmpty && orden.comunaCliente != 'NaN' ? ', ${orden.comunaCliente}' : ''}',
                        style: const TextStyle(color: _textDim, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Detalle: selección de materiales (estilo ayuda de material) ──────────────

class ConsumoOrdenScreen extends StatefulWidget {
  final OrdenPendienteConsumo orden;
  final List<RecetaMaterial> materiales;
  final String nombreReceta;
  final String rut;
  final int idTrabajador;
  final RecetasConsumoService service;
  final TecnicoStock? stockInicial;
  final VoidCallback onConsumoOk;

  const ConsumoOrdenScreen({
    super.key,
    required this.orden,
    required this.materiales,
    required this.nombreReceta,
    required this.rut,
    required this.idTrabajador,
    required this.service,
    this.stockInicial,
    required this.onConsumoOk,
  });

  @override
  State<ConsumoOrdenScreen> createState() => _ConsumoOrdenScreenState();
}

class _ConsumoOrdenScreenState extends State<ConsumoOrdenScreen> {
  final _logistica = LogisticaService();

  TecnicoStock? _stock;
  bool _cargandoStock = true;
  String? _errorStock;
  final Map<int, int> _cantidadesPorMaterial = {};
  final List<ItemStock> _seriesSeleccionadas = [];
  bool _enviando = false;

  late final Set<String> _categoriasReceta;
  late final bool _recetaTieneSeriados;

  @override
  void initState() {
    super.initState();
    _categoriasReceta = _calcularCategoriasReceta();
    _recetaTieneSeriados = widget.materiales.any((m) => m.esSeriado);
    _cargarStock();
  }

  Set<String> _calcularCategoriasReceta() {
    final cats = <String>{};
    for (final m in widget.materiales) {
      final cat = m.categoriaConsumo();
      if (cat != null) cats.add(cat);
    }
    return cats;
  }

  int _saldoCategoria(String categoria, {bool seriado = false}) {
    final stock = _stock;
    if (stock == null) return 0;

    if (!seriado) {
      return _itemsNoSeriados(categoria)
          .fold<int>(0, (sum, i) => sum + i.cantidad.toInt());
    }

    final desdeMapa = stock.stock[categoria]?.toInt() ?? 0;
    if (desdeMapa > 0) return desdeMapa;

    var total = 0.0;
    for (final i in stock.items) {
      if (i.categoria != categoria) continue;
      if (i.esSeriado) total += 1;
    }
    return total.toInt();
  }

  /// IDs de la receta de esta OT que corresponden a [categoria].
  Set<int> _idsRecetaParaCategoria(String categoria, {bool seriado = false}) {
    final ids = <int>{};
    for (final m in widget.materiales) {
      if (m.esSeriado != seriado) continue;
      if (m.categoriaConsumo() == categoria) ids.add(m.id);
    }
    return ids;
  }

  List<ItemStock> _filtrarPorReceta(
    String categoria,
    List<ItemStock> items, {
    required bool seriado,
  }) {
    final idsReceta = _idsRecetaParaCategoria(categoria, seriado: seriado);
    if (idsReceta.isEmpty) return items;
    final filtrados =
        items.where((i) => idsReceta.contains(i.idMaterial)).toList();
    return filtrados.isNotEmpty ? filtrados : items;
  }

  Future<void> _cargarStock() async {
    setState(() {
      _cargandoStock = true;
      _errorStock = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final nombre = prefs.getString('nombre_tecnico');
      final stock = widget.stockInicial ??
          await _logistica.fetchStockTecnico(
            widget.rut,
            nombreDisplay: nombre,
          );
      if (!mounted) return;
      if (stock == null) {
        setState(() {
          _errorStock =
              'No se encontró tu saldo en logística. Verifica tu RUT en nómina.';
          _cargandoStock = false;
        });
        return;
      }
      setState(() {
        _stock = stock;
        _cargandoStock = false;
        _prefillMinimosObligatorios();
        _consolidarCantidadesNoSeriadas();
      });
      debugPrint(
        '[Consumo] saldo ${stock.items.length} ítems, '
        'categorías receta: $_categoriasReceta, '
        'seriados receta: $_recetaTieneSeriados',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorStock = 'No se pudo cargar tu saldo';
        _cargandoStock = false;
      });
    }
  }

  bool _mostrarCategoria(MaterialItem m) {
    if (m.esSeriado) {
      if (_saldoCategoria(m.nombre, seriado: true) > 0) return true;
      if (_categoriasReceta.contains(m.nombre)) return true;
      final regla = consumoReglaPara(m.nombre, widget.orden.tipoActividad);
      return regla?.maximo != null && regla!.maximo! > 0;
    }

    if (_saldoCategoria(m.nombre) > 0) return true;
    if (_categoriasReceta.contains(m.nombre)) return true;
    final regla = consumoReglaPara(m.nombre, widget.orden.tipoActividad);
    return regla?.minimo != null && regla!.minimo! > 0;
  }

  List<MaterialItem> get _noSeriadosVisibles =>
      kMateriales.where((m) => !m.esSeriado && _mostrarCategoria(m)).toList();

  List<MaterialItem> get _seriadosVisibles =>
      kMateriales.where((m) => m.esSeriado && _mostrarCategoria(m)).toList();

  List<ItemStock> _itemsNoSeriados(String categoria) {
    final stock = _stock;
    if (stock == null) return const [];
    final items = stock.items
        .where((i) => !i.esSeriado && i.categoria == categoria)
        .toList();
    return _filtrarPorReceta(categoria, items, seriado: false);
  }

  /// Ítem no seriado con mayor saldo → único código a rebajar por categoría.
  ItemStock? _itemSaldoParaCategoria(String categoria) {
    final items = _itemsNoSeriados(categoria);
    if (items.isEmpty) return null;
    items.sort((a, b) => b.cantidad.compareTo(a.cantidad));
    return items.first;
  }

  void _consolidarCantidadesNoSeriadas() {
    for (final m in _noSeriadosVisibles) {
      final principal = _itemSaldoParaCategoria(m.nombre);
      if (principal == null) continue;
      var total = 0;
      for (final item in _itemsNoSeriados(m.nombre)) {
        total += _cantidadesPorMaterial[item.idMaterial] ?? 0;
        if (item.idMaterial != principal.idMaterial) {
          _cantidadesPorMaterial.remove(item.idMaterial);
        }
      }
      if (total > 0) {
        _cantidadesPorMaterial[principal.idMaterial] = total;
      }
    }
  }

  List<ItemStock> _itemsSeriados(String categoria) {
    final stock = _stock;
    if (stock == null) return const [];
    final usadas = _seriesSeleccionadas.map((s) => s.serie).toSet();
    final items = stock.items
        .where((i) =>
            i.esSeriado &&
            i.categoria == categoria &&
            !usadas.contains(i.serie))
        .toList();
    return _filtrarPorReceta(categoria, items, seriado: true);
  }

  int _totalCategoria(String categoria) {
    final stock = _stock;
    if (stock == null) return 0;
    var total = 0;
    for (final item in stock.items) {
      if (!item.esSeriado && item.categoria == categoria) {
        total += _cantidadesPorMaterial[item.idMaterial] ?? 0;
      }
    }
    return total;
  }

  int get _totalOnt => _seriesSeleccionadas
      .where((s) => kConsumoCategoriasOnt.contains(s.categoria))
      .length;

  int get _totalDeco => _seriesSeleccionadas
      .where((s) => kConsumoCategoriasDeco.contains(s.categoria))
      .length;

  int get _totalExtensor => _seriesSeleccionadas
      .where((s) => s.categoria == kConsumoCategoriaExtensor)
      .length;

  int get _totalDrop {
    var total = 0;
    for (final cat in kConsumoCategoriasDrop) {
      total += _totalCategoria(cat);
    }
    return total;
  }

  String? get _dropSeleccionado {
    for (final cat in kConsumoCategoriasDrop) {
      if (_totalCategoria(cat) > 0) return cat;
    }
    return null;
  }

  String? get _marcaDecoBloqueada {
    for (final s in _seriesSeleccionadas) {
      if (kConsumoCategoriasDeco.contains(s.categoria)) return s.categoria;
    }
    return null;
  }

  bool _categoriaSeriadaDeshabilitada(String categoria) {
    if (kConsumoCategoriasOnt.contains(categoria)) {
      if (_totalOnt >= kConsumoMaxOnt) {
        return !_seriesSeleccionadas.any((s) => s.categoria == categoria);
      }
      if (_totalOnt > 0) {
        return !_seriesSeleccionadas.any((s) => s.categoria == categoria);
      }
    }
    if (kConsumoCategoriasDeco.contains(categoria)) {
      final bloqueada = _marcaDecoBloqueada;
      if (bloqueada != null && bloqueada != categoria) return true;
      if (_totalDeco >= kConsumoMaxDeco &&
          !_seriesSeleccionadas.any((s) => s.categoria == categoria)) {
        return true;
      }
    }
    if (categoria == kConsumoCategoriaExtensor &&
        _totalExtensor >= kConsumoMaxExtensor &&
        !_seriesSeleccionadas.any((s) => s.categoria == categoria)) {
      return true;
    }
    return false;
  }

  void _prefillMinimosObligatorios() {
    if (!consumoExigirMinimos(widget.orden.tipoActividad)) return;
    for (final m in _noSeriadosVisibles) {
      final min = consumoMinimo(m.nombre, widget.orden.tipoActividad);
      if (min == null || min <= 0) continue;
      if (_totalCategoria(m.nombre) >= min) continue;
      final item = _itemSaldoParaCategoria(m.nombre);
      if (item == null) continue;
      final maxItem = item.cantidad.toInt();
      _cantidadesPorMaterial[item.idMaterial] =
          min.clamp(0, maxItem > 0 ? maxItem : min);
    }
  }

  Future<void> _mostrarAlertaMaximo(int maximo, String categoria) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _border),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: _orange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Límite de consumo',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          'ACTIVIDAD SOLO PERMITE CONSUMIR UN MAXIMO DE $maximo ${categoria.toUpperCase()}',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('ACEPTAR'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarAlertaSoloUnDrop(String dropActual) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _border),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: _orange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Límite de consumo',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          'ACTIVIDAD SOLO PERMITE CONSUMIR UN DROP. '
          'YA SELECCIONASTE ${dropActual.toUpperCase()}',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('ACEPTAR'),
          ),
        ],
      ),
    );
  }

  int _maxSeriado(String categoria) {
    if (kConsumoCategoriasOnt.contains(categoria)) return kConsumoMaxOnt;
    if (kConsumoCategoriasDeco.contains(categoria)) return kConsumoMaxDeco;
    return kConsumoMaxExtensor;
  }

  Future<void> _ajustarCantidad(String categoria, int delta) async {
    final item = _itemSaldoParaCategoria(categoria);
    if (item == null) return;

    final actual = _cantidadesPorMaterial[item.idMaterial] ?? 0;
    final maxCat = consumoMaximo(categoria, widget.orden.tipoActividad);
    final totalCat = _totalCategoria(categoria);
    final maxItem = item.cantidad.toInt();

    if (delta > 0 && kConsumoCategoriasDrop.contains(categoria)) {
      final dropActual = _dropSeleccionado;
      if (dropActual != null &&
          dropActual != categoria &&
          _totalDrop >= kConsumoMaxDropTotal) {
        await _mostrarAlertaSoloUnDrop(dropActual);
        return;
      }
    }

    if (delta > 0 && maxCat != null && totalCat >= maxCat) {
      await _mostrarAlertaMaximo(maxCat, categoria);
      return;
    }

    var nuevo = actual + delta;
    if (nuevo < 0) nuevo = 0;
    if (nuevo > maxItem) nuevo = maxItem;
    if (maxCat != null && nuevo > maxCat) {
      await _mostrarAlertaMaximo(maxCat, categoria);
      nuevo = maxCat;
    }

    setState(() {
      for (final other in _itemsNoSeriados(categoria)) {
        if (other.idMaterial != item.idMaterial) {
          _cantidadesPorMaterial.remove(other.idMaterial);
        }
      }
      if (nuevo == 0) {
        _cantidadesPorMaterial.remove(item.idMaterial);
      } else {
        _cantidadesPorMaterial[item.idMaterial] = nuevo;
      }
    });
  }

  void _agregarSerie(ItemStock? item) {
    if (item == null || item.serie == null) return;
    setState(() => _seriesSeleccionadas.add(item));
  }

  void _quitarSerie(ItemStock item) {
    setState(() => _seriesSeleccionadas.remove(item));
  }

  Future<void> _enviar() async {
    final noSeriados = <List<dynamic>>[];
    for (final entry in _cantidadesPorMaterial.entries) {
      if (entry.value > 0) noSeriados.add([entry.key, entry.value]);
    }
    final seriados = _seriesSeleccionadas
        .map((s) => [s.idMaterial, s.serie!] as List<dynamic>)
        .toList();

    if (noSeriados.isEmpty && seriados.isEmpty) {
      await _mostrarBloqueoConsumo(
        'Sin materiales seleccionados',
        'Indica cantidades en los materiales no seriados o selecciona '
        'series de tu saldo antes de registrar.',
      );
      return;
    }

    final totales = <String, int>{};
    for (final m in _noSeriadosVisibles) {
      final t = _totalCategoria(m.nombre);
      if (t > 0) totales[m.nombre] = t;
    }

    final err = validarConsumoCantidades(
      tipoActividad: widget.orden.tipoActividad,
      totalPorCategoria: totales,
      totalOnt: _totalOnt,
      totalDeco: _totalDeco,
      marcaDecoSeleccionada: _marcaDecoBloqueada,
      totalExtensor: _totalExtensor,
    );
    if (err != null) {
      await _mostrarBloqueoConsumo(
        'No cumple las reglas de consumo',
        err,
      );
      return;
    }

    final idTrabajador = widget.orden.idTrabajador > 0
        ? widget.orden.idTrabajador
        : widget.idTrabajador;

    setState(() => _enviando = true);

    ConsumoResult result;
    try {
      result = await widget.service.submitConsumo(
        ordenDeTrabajo: widget.orden.codigoExterno,
        idTrabajador: idTrabajador,
        noSeriados: noSeriados,
        seriados: seriados,
      );
    } catch (e) {
      result = ConsumoResult(exito: false, mensaje: e.toString());
    }

    if (!mounted) return;
    setState(() => _enviando = false);

    if (result.exito) {
      widget.onConsumoOk();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _border),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: _green),
              SizedBox(width: 8),
              Text('Consumo registrado',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: Text(
            'OT ${widget.orden.codigoExterno}\n'
            'Material descontado correctamente.',
            style: const TextStyle(color: _textDim),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(backgroundColor: _green),
              child: const Text('ACEPTAR'),
            ),
          ],
        ),
      );
    } else {
      await _mostrarBloqueoConsumo(
        'No se pudo registrar el consumo',
        '${result.mensaje}\n\n'
        'OT: ${widget.orden.codigoExterno}\n'
        'Técnico KRP: $idTrabajador\n'
        'Ítems no seriados: ${noSeriados.length} · '
        'Seriados: ${seriados.length}',
      );
    }
  }

  Future<void> _mostrarBloqueoConsumo(String titulo, String detalle) async {
    debugPrint('[Consumo] bloqueado — $titulo: $detalle');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _border),
        ),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: _orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            detalle,
            style: const TextStyle(color: _textDim, fontSize: 13),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('ENTENDIDO'),
          ),
        ],
      ),
    );
  }

  String _hintRegla(String categoria) {
    final min = consumoMinimo(categoria, widget.orden.tipoActividad);
    final max = consumoMaximo(categoria, widget.orden.tipoActividad);
    if (min != null && max != null) return 'Mín $min · Máx $max';
    if (min != null) return 'Mín $min';
    if (max != null) return 'Máx $max';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.orden.codigoExterno,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: _cargandoStock
          ? const Center(
              child: CircularProgressIndicator(color: _accent, strokeWidth: 2))
          : _errorStock != null
              ? _buildErrorStock()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    Expanded(child: _buildContenido()),
                  ],
                ),
    );
  }

  Widget _buildErrorStock() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined, color: _orange, size: 48),
            const SizedBox(height: 12),
            Text(_errorStock!,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _cargarStock,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: FilledButton.styleFrom(backgroundColor: _accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final exigirMin = consumoExigirMinimos(widget.orden.tipoActividad);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: _surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.orden.tipoActividad,
              style: const TextStyle(color: _accent, fontSize: 13)),
          const SizedBox(height: 4),
          Text(widget.nombreReceta,
              style: const TextStyle(color: _textDim, fontSize: 12)),
          if (exigirMin) ...[
            const SizedBox(height: 8),
            Text(
              'Los mínimos son obligatorios para esta actividad.',
              style: TextStyle(
                  color: _orange.withValues(alpha: 0.9), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContenido() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Column(
                children: [
                  if (_noSeriadosVisibles.isNotEmpty)
                    _grupoCategorias('No seriados', _noSeriadosVisibles),
                  if (_noSeriadosVisibles.isNotEmpty &&
                      _seriadosVisibles.isNotEmpty)
                    const Divider(height: 1, color: _border),
                  if (_seriadosVisibles.isNotEmpty)
                    _grupoCategorias('Seriados', _seriadosVisibles),
                  if (_noSeriadosVisibles.isEmpty &&
                      _seriadosVisibles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        widget.materiales.isEmpty
                            ? 'La receta de esta OT no trajo materiales desde KRP.'
                            : 'No hay materiales de la receta con saldo disponible.',
                        style: const TextStyle(color: _textDim, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildBotonEnviar(),
        ],
      ),
    );
  }

  Widget _grupoCategorias(String titulo, List<MaterialItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Text(
            titulo.toUpperCase(),
            style: const TextStyle(
              color: _textDim,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ),
        ...items.map(
          (m) => m.esSeriado ? _buildFilaSeriada(m) : _buildFilaNoSeriada(m),
        ),
      ],
    );
  }

  Widget _buildFilaNoSeriada(MaterialItem m) {
    final item = _itemSaldoParaCategoria(m.nombre);
    final saldo = _saldoCategoria(m.nombre);
    final hint = _hintRegla(m.nombre);
    final qty = item != null ? (_cantidadesPorMaterial[item.idMaterial] ?? 0) : 0;
    final enUso = qty > 0;

    if (item == null) {
      return _filaBase(
        m: m,
        enUso: enUso,
        hint: hint,
        saldo: saldo,
        trailing: const Text('—', style: TextStyle(color: _textDim, fontSize: 12)),
      );
    }

    return _filaBase(
      m: m,
      enUso: enUso,
      hint: hint,
      saldo: saldo,
      trailing: _stepperInline(m.nombre),
    );
  }

  Widget _buildFilaSeriada(MaterialItem m) {
    final deshabilitado = _categoriaSeriadaDeshabilitada(m.nombre);
    final saldo = _saldoCategoria(m.nombre, seriado: true);
    final hint = _hintRegla(m.nombre);
    final series =
        _seriesSeleccionadas.where((s) => s.categoria == m.nombre).toList();
    final disponibles = _itemsSeriados(m.nombre);
    final maxPermitido = _maxSeriado(m.nombre);
    final puedeAgregar = !deshabilitado &&
        series.length < maxPermitido &&
        disponibles.isNotEmpty;

    return Opacity(
      opacity: deshabilitado ? 0.4 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: series.isNotEmpty ? _accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.memory_outlined,
                color: series.isNotEmpty ? _accent : _textDim, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.nombre,
                    style: TextStyle(
                      color: series.isNotEmpty ? Colors.white : _textDim,
                      fontSize: 13,
                      fontWeight:
                          series.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (hint.isNotEmpty)
                    Text(hint,
                        style: const TextStyle(color: _textDim, fontSize: 10)),
                  Text(
                    saldo > 0 ? 'Saldo: $saldo' : 'Sin saldo',
                    style: TextStyle(
                      color: saldo > 0 ? _green : _orange,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ...series.map(
                    (s) => InputChip(
                      label: Text(
                        s.serie ?? '',
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: Colors.white,
                        ),
                      ),
                      deleteIconColor: _orange,
                      backgroundColor: const Color(0xFF0A1628),
                      side: BorderSide(color: _green.withValues(alpha: 0.4)),
                      onDeleted: () => _quitarSerie(s),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  if (puedeAgregar) _dropdownSerie(m.nombre, disponibles),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdownSerie(String categoria, List<ItemStock> disponibles) {
    return SizedBox(
      width: 118,
      height: 32,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ItemStock>(
          isExpanded: true,
          isDense: true,
          hint: const Text('Serie', style: TextStyle(color: _textDim, fontSize: 11)),
          dropdownColor: _surface,
          style: const TextStyle(color: Colors.white, fontSize: 10),
          items: disponibles
              .map((i) => DropdownMenuItem(
                    value: i,
                    child: Text(
                      i.serie ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ))
              .toList(),
          onChanged: deshabilitadoSerie(categoria)
              ? null
              : (v) => _agregarSerie(v),
        ),
      ),
    );
  }

  bool deshabilitadoSerie(String categoria) =>
      _categoriaSeriadaDeshabilitada(categoria);

  Widget _filaBase({
    required MaterialItem m,
    required bool enUso,
    required String hint,
    required int saldo,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: enUso ? _accent : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            m.esSeriado ? Icons.memory_outlined : Icons.cable_outlined,
            color: enUso ? _accent : _textDim,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.nombre,
                  style: TextStyle(
                    color: enUso ? Colors.white : _textDim,
                    fontSize: 13,
                    fontWeight: enUso ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (hint.isNotEmpty)
                  Text(hint,
                      style: const TextStyle(color: _textDim, fontSize: 10)),
                Text(
                  saldo > 0 ? 'Saldo: $saldo' : 'Sin saldo',
                  style: TextStyle(
                    color: saldo > 0 ? _green : _orange,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }

  Widget _stepperInline(String categoria) {
    final item = _itemSaldoParaCategoria(categoria);
    final qty = item != null ? (_cantidadesPorMaterial[item.idMaterial] ?? 0) : 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btnCantidad(Icons.remove, () => _ajustarCantidad(categoria, -1),
            pad: 8, iconSize: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '$qty',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        _btnCantidad(Icons.add, () => _ajustarCantidad(categoria, 1),
            pad: 8, iconSize: 18),
      ],
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _buildBotonEnviar() {
    return SafeArea(
      top: false,
      child: FilledButton.icon(
        onPressed: _enviando ? null : _enviar,
        icon: _enviando
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.send),
        label: Text(_enviando ? 'Registrando...' : 'REGISTRAR CONSUMO'),
        style: FilledButton.styleFrom(
          backgroundColor: _green,
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size(double.infinity, 52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _btnCantidad(IconData icon, VoidCallback onTap,
      {double pad = 8, double iconSize = 18}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _border),
        ),
        child: Icon(icon, color: _accent, size: iconSize),
      ),
    );
  }
}

