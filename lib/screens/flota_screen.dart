import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/flota_service.dart';
import '../services/tag_service.dart';
import '../models/paso_tag.dart';

/// Pantalla de detalle de Flota
/// Muestra TAG y combustible con el detalle mensual
class FlotaScreen extends StatefulWidget {
  const FlotaScreen({super.key});

  @override
  State<FlotaScreen> createState() => _FlotaScreenState();
}

class _FlotaScreenState extends State<FlotaScreen>
    with SingleTickerProviderStateMixin {
  final FlotaService _flotaService = FlotaService();
  final TagService _tagService = TagService();

  late TabController _tabController;

  Map<String, dynamic>? _datosActual;
  Map<String, dynamic>? _datosCerrado;
  List<PasoTag> _pasosTag = [];

  bool _cargando = true;
  bool _enviandoSolicitud = false;
  bool _solicitudEnviada = false;
  String? _nombreTecnico;
  String? _rutTecnico;

  late int _mesActual;
  late int _annoActual;
  late int _mesCerrado;
  late int _annoCerrado;

  static const _meses = [
    '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _inicializar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _inicializar() async {
    final prefs = await SharedPreferences.getInstance();
    _rutTecnico = prefs.getString('rut_tecnico');
    _nombreTecnico = prefs.getString('nombre_tecnico') ?? 'Técnico';

    final now = DateTime.now();
    _mesActual = now.month;
    _annoActual = now.year;
    _mesCerrado = now.month == 1 ? 12 : now.month - 1;
    _annoCerrado = now.month == 1 ? now.year - 1 : now.year;

    await _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    if (_rutTecnico == null) {
      setState(() => _cargando = false);
      return;
    }

    setState(() => _cargando = true);

    try {
      final results = await Future.wait([
        _flotaService.obtenerDatosFlota(
          _rutTecnico!,
          mes: _mesActual,
          anno: _annoActual,
        ),
        _flotaService.obtenerDatosFlota(
          _rutTecnico!,
          mes: _mesCerrado,
          anno: _annoCerrado,
        ),
        _tagService.getPasosDelMes(),
      ]);

      // Verificar solicitud pendiente
      final mesStr =
          '$_annoActual-${_mesActual.toString().padLeft(2, '0')}';
      final tieneSolicitud = await _flotaService.tieneSolicitudPendiente(
        _rutTecnico!,
        mesStr,
      );

      setState(() {
        _datosActual = results[0] as Map<String, dynamic>;
        _datosCerrado = results[1] as Map<String, dynamic>;
        _pasosTag = results[2] as List<PasoTag>;
        _solicitudEnviada = tieneSolicitud;
        _cargando = false;
      });
    } catch (e) {
      print('❌ [FlotaScreen] Error: $e');
      setState(() => _cargando = false);
    }
  }

  Future<void> _enviarSolicitud(Map<String, dynamic> combustible) async {
    if (_rutTecnico == null) return;

    final litrosOperac =
        (combustible['litros_operac'] as num?)?.toDouble() ?? 0.0;

    // Verificar umbral
    if (FlotaService.tieneCombustibleSuficiente(litrosOperac)) {
      _mostrarDialogoAunTieneCombustible(litrosOperac);
      return;
    }

    setState(() => _enviandoSolicitud = true);

    final mesStr =
        '$_annoActual-${_mesActual.toString().padLeft(2, '0')}';

    final exito = await _flotaService.solicitarCombustible(
      rutTecnico: _rutTecnico!,
      nombreTecnico: _nombreTecnico ?? 'Técnico',
      litrosOperac: litrosOperac,
      litrosTrayecto:
          (combustible['litros_trayecto'] as num?)?.toDouble() ?? 0.0,
      kmOperac: (combustible['km_operac'] as num?)?.toDouble() ?? 0.0,
      kmTrayecto: (combustible['km_trayecto'] as num?)?.toDouble() ?? 0.0,
      mes: mesStr,
    );

    setState(() {
      _enviandoSolicitud = false;
      if (exito) _solicitudEnviada = true;
    });

    if (!mounted) return;
    _mostrarSnackbar(
      exito
          ? '✅ Solicitud enviada al supervisor'
          : '❌ Error al enviar la solicitud',
      exito ? Colors.green : Colors.red,
    );
  }

  void _mostrarDialogoAunTieneCombustible(double litros) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Text('⛽', style: TextStyle(fontSize: 24)),
            SizedBox(width: 8),
            Text('Combustible disponible'),
          ],
        ),
        content: Text(
          'Aún tienes ${litros.toStringAsFixed(1)} litros de combustible operacional '
          '(por encima de los ${FlotaService.umbralCombustibleOperac.toStringAsFixed(0)} L de umbral).\n\n'
          '¿Deseas solicitar de todas formas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(ctx);
              _enviarSolicitudForzada();
            },
            child: const Text('Solicitar igual'),
          ),
        ],
      ),
    );
  }

  Future<void> _enviarSolicitudForzada() async {
    if (_datosActual == null || _rutTecnico == null) return;
    final combustible =
        _datosActual!['combustible'] as Map<String, dynamic>;
    final mesStr =
        '$_annoActual-${_mesActual.toString().padLeft(2, '0')}';

    setState(() => _enviandoSolicitud = true);

    final exito = await _flotaService.solicitarCombustible(
      rutTecnico: _rutTecnico!,
      nombreTecnico: _nombreTecnico ?? 'Técnico',
      litrosOperac:
          (combustible['litros_operac'] as num?)?.toDouble() ?? 0.0,
      litrosTrayecto:
          (combustible['litros_trayecto'] as num?)?.toDouble() ?? 0.0,
      kmOperac: (combustible['km_operac'] as num?)?.toDouble() ?? 0.0,
      kmTrayecto:
          (combustible['km_trayecto'] as num?)?.toDouble() ?? 0.0,
      mes: mesStr,
    );

    setState(() {
      _enviandoSolicitud = false;
      if (exito) _solicitudEnviada = true;
    });

    if (!mounted) return;
    _mostrarSnackbar(
      exito ? '✅ Solicitud enviada' : '❌ Error al enviar',
      exito ? Colors.green : Colors.red,
    );
  }

  void _mostrarSnackbar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flota'),
        backgroundColor: const Color(0xFF1e3a5f),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(
              text:
                  '${_meses[_mesActual]} $_annoActual',
              icon: const Icon(Icons.calendar_today, size: 16),
            ),
            Tab(
              text: '${_meses[_mesCerrado]} $_annoCerrado',
              icon: const Icon(Icons.lock, size: 16),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargarDatos,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTabContenido(
                  _datosActual,
                  esCerrado: false,
                ),
                _buildTabContenido(
                  _datosCerrado,
                  esCerrado: true,
                ),
              ],
            ),
    );
  }

  Widget _buildTabContenido(
    Map<String, dynamic>? datos, {
    required bool esCerrado,
  }) {
    if (datos == null) {
      return const Center(child: Text('Sin datos disponibles'));
    }

    final tag = datos['tag'] as Map<String, dynamic>;
    final comb = datos['combustible'] as Map<String, dynamic>;

    return RefreshIndicator(
      onRefresh: _cargarDatos,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── TAG ──────────────────────────────────────
            _buildSeccionTag(tag, esCerrado: esCerrado),
            const SizedBox(height: 16),

            // ── COMBUSTIBLE ───────────────────────────────
            _buildSeccionCombustible(comb, esCerrado: esCerrado),

            if (!esCerrado) ...[
              const SizedBox(height: 16),
              _buildBotonSolicitud(comb),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Sección TAG
  // ─────────────────────────────────────────────────────────

  Widget _buildSeccionTag(
    Map<String, dynamic> tag, {
    required bool esCerrado,
  }) {
    final total = (tag['total'] as num?)?.toInt() ?? 0;
    final pasos = (tag['pasos'] as num?)?.toInt() ?? 0;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.toll, color: Colors.indigo, size: 24),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Gasto TAG',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatItem(
                  label: 'Total cobrado',
                  value: '\$${FlotaService.formatearPesos(total.toDouble())}',
                  color: Colors.indigo,
                  large: true,
                ),
                _buildStatItem(
                  label: 'Pórticos',
                  value: '$pasos',
                  color: Colors.grey[700]!,
                ),
              ],
            ),
            if (!esCerrado && _pasosTag.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Últimos pórticos registrados:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 6),
              ..._pasosTag.take(3).map(
                    (p) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.circle,
                              size: 8, color: Colors.indigo),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              p.porticoNombre,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '\$${FlotaService.formatearPesos(p.tarifaCobrada.toDouble())}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Sección Combustible
  // ─────────────────────────────────────────────────────────

  Widget _buildSeccionCombustible(
    Map<String, dynamic> comb, {
    required bool esCerrado,
  }) {
    final kmOperac = (comb['km_operac'] as num?)?.toDouble() ?? 0.0;
    final kmTrayecto = (comb['km_trayecto'] as num?)?.toDouble() ?? 0.0;
    final litrosOperac = (comb['litros_operac'] as num?)?.toDouble() ?? 0.0;
    final litrosTrayecto =
        (comb['litros_trayecto'] as num?)?.toDouble() ?? 0.0;
    final litrosTotal = (comb['litros_total'] as num?)?.toDouble() ?? 0.0;
    final costoOperac = (comb['costo_operac'] as num?)?.toDouble() ?? 0.0;
    final costoTrayecto =
        (comb['costo_trayecto'] as num?)?.toDouble() ?? 0.0;
    final costoTotal = (comb['costo_total'] as num?)?.toDouble() ?? 0.0;
    final diasTrabajados = (comb['dias_trabajados'] as num?)?.toInt() ?? 0;
    final minViaje = (comb['minutos_viaje'] as num?)?.toDouble() ?? 0.0;

    final tieneSuficiente =
        FlotaService.tieneCombustibleSuficiente(litrosOperac);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1e3a5f).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_gas_station,
                      color: Color(0xFF1e3a5f), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Combustible',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '\$${FlotaService.formatearPesos(FlotaService.precioPorLitro)}/L',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),

            const Divider(height: 24),

            // Operacional
            _buildFilaCombustible(
              icono: '🔧',
              label: 'Operacional',
              sublabel:
                  '${kmOperac.toStringAsFixed(1)} km · ${(minViaje / 60).toStringAsFixed(1)} h viaje',
              litros: litrosOperac,
              costo: costoOperac,
              color: const Color(0xFF1e3a5f),
            ),

            const SizedBox(height: 12),

            // Trayecto
            _buildFilaCombustible(
              icono: '🏠',
              label: 'Trayecto',
              sublabel:
                  '${kmTrayecto.toStringAsFixed(1)} km · $diasTrabajados días',
              litros: litrosTrayecto,
              costo: costoTrayecto,
              color: Colors.teal,
            ),

            const Divider(height: 24),

            // Total
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total combustible',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      '${litrosTotal.toStringAsFixed(1)} litros',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Text(
                  '\$${FlotaService.formatearPesos(costoTotal)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1e3a5f),
                  ),
                ),
              ],
            ),

            // Parámetros informativos
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildParamInfo('Rendimiento',
                      '${FlotaService.rendimientoKmLitro.toStringAsFixed(0)} km/L'),
                  _buildParamInfo('Velocidad prom.',
                      '${FlotaService.velocidadPromedioKmh.toStringAsFixed(0)} km/h'),
                  _buildParamInfo('Km trayecto/día',
                      '${FlotaService.kmTrayectoDiario.toStringAsFixed(0)} km'),
                ],
              ),
            ),

            // Alerta si tiene suficiente combustible operacional
            if (!esCerrado && tieneSuficiente) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green[300]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tienes ${litrosOperac.toStringAsFixed(1)} L de combustible operacional disponible',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilaCombustible({
    required String icono,
    required String label,
    required String sublabel,
    required double litros,
    required double costo,
    required Color color,
  }) {
    return Row(
      children: [
        Text(icono, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                sublabel,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${litros.toStringAsFixed(1)} L',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              '\$${FlotaService.formatearPesos(costo)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildParamInfo(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // Botón de solicitud de combustible
  // ─────────────────────────────────────────────────────────

  Widget _buildBotonSolicitud(Map<String, dynamic> comb) {
    if (_solicitudEnviada) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue[300]!),
        ),
        child: const Row(
          children: [
            Icon(Icons.send, color: Colors.blue),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Solicitud de combustible enviada al supervisor',
                style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF1e3a5f),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed:
            _enviandoSolicitud ? null : () => _enviarSolicitud(comb),
        icon: _enviandoSolicitud
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.local_gas_station),
        label: Text(
          _enviandoSolicitud ? 'Enviando...' : 'Solicitar Combustible',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Helpers de UI
  // ─────────────────────────────────────────────────────────

  Widget _buildStatItem({
    required String label,
    required String value,
    required Color color,
    bool large = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: large ? 22 : 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
