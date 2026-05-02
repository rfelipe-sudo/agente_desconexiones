import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/constants/app_colors.dart';
import 'package:agente_desconexiones/screens/combustible_dia_detalle_screen.dart';
import 'package:agente_desconexiones/widgets/combustible_format.dart';
import 'package:agente_desconexiones/widgets/combustible_semana_tile.dart';
import 'package:agente_desconexiones/widgets/monedero_card.dart';
import 'package:agente_desconexiones/widgets/solicitar_recarga_sheet.dart';

/// Pantalla Combustible: monedero, resumen último día, solicitud, historial por semanas.
class CombustibleScreen extends StatefulWidget {
  const CombustibleScreen({super.key});

  @override
  State<CombustibleScreen> createState() => _CombustibleScreenState();
}

class _CombustibleScreenState extends State<CombustibleScreen> {
  String? _rut;
  Map<String, dynamic>? _rpcUltimoDia;
  Map<String, dynamic>? _monederoRow;
  double _precioLitroParametro = 1500;
  List<Map<String, dynamic>> _diasMes = [];
  bool _loading = true;
  String? _error;
  late DateTime _mesReferencia;

  /// Fecha del último día con datos (RPC `ultimo_dia_disponible`).
  String? _ultimaFechaYmd;

  /// Fila de `combustible_diario_tecnico` del último día (ida/vuelta trayecto, etc.).
  Map<String, dynamic>? _diaUltimoResumen;

  double _kmTrayectoFijo = 40;
  double _rendimientoKm = 13;

  bool _pendienteSolicitud = false;

  StreamSubscription<List<Map<String, dynamic>>>? _monederoSub;
  StreamSubscription<List<Map<String, dynamic>>>? _solicitudSub;

  final Set<String> _snackAtendidaIds = {};
  final Set<String> _snackRechazadaIds = {};

  String? _bannerSolicitudExito;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _mesReferencia = DateTime(n.year, n.month, 1);
    print('[Combustible] CombustibleScreen initState');
    _cargarTodo();
  }

  @override
  void dispose() {
    _monederoSub?.cancel();
    _solicitudSub?.cancel();
    super.dispose();
  }

  static String _nombreMes(int mes) {
    const meses = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
    ];
    if (mes < 1 || mes > 12) return '';
    return meses[mes - 1];
  }

  DateTime? _parseFechaRow(dynamic f) {
    if (f == null) return null;
    if (f is DateTime) return DateTime(f.year, f.month, f.day);
    final s = f.toString().split('T').first;
    return DateTime.tryParse(s);
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _labelUltimoDiaRegistrado(String ymd) {
    try {
      final d = DateTime.parse(ymd);
      const meses = [
        '', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
        'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
      ];
      const dias = [
        'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo',
      ];
      return '${dias[d.weekday - 1]} ${d.day} ${meses[d.month]}';
    } catch (_) {
      return ymd;
    }
  }

  static List<Map<String, dynamic>> _coerceRowList(dynamic response) {
    if (response == null) return [];
    if (response is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final e in response) {
      if (e is Map<String, dynamic>) {
        out.add(Map<String, dynamic>.from(e));
      } else if (e is Map) {
        out.add(Map<String, dynamic>.from(e));
      }
    }
    return out;
  }

  static Map<String, dynamic>? _coerceRpcFirstRow(dynamic rpcRaw) {
    if (rpcRaw == null) return null;
    if (rpcRaw is List) {
      if (rpcRaw.isEmpty) return null;
      final f = rpcRaw.first;
      if (f is Map<String, dynamic>) return Map<String, dynamic>.from(f);
      if (f is Map) return Map<String, dynamic>.from(f);
      return null;
    }
    if (rpcRaw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(rpcRaw);
    }
    if (rpcRaw is Map) return Map<String, dynamic>.from(rpcRaw);
    return null;
  }

  String? _parseUltimoDia(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return _ymd(raw);
    final s = raw.toString();
    return s.split('T').first;
  }

  double _pickRpc(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return 0;
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) {
        return CombustibleFormat.toDouble(m[k]);
      }
    }
    return 0;
  }

  int _pickVisitasRpc(Map<String, dynamic>? m) {
    if (m == null) return 0;
    const keys = [
      'out_cant_visitas',
      'cant_ots',
      'cantidad_visitas',
      'visitas',
    ];
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) {
        return CombustibleFormat.toInt(m[k]);
      }
    }
    return 0;
  }

  /// Mapa para [MonederoCard] y solicitud: monedero + RPC (km restantes, etc.).
  Map<String, dynamic> _monederoDisplayMap() {
    final rpc = _rpcUltimoDia;
    final m = _monederoRow;

    var litros = 0.0;
    if (m != null) {
      litros = CombustibleFormat.toDouble(m['saldo_litros']);
    }
    if (litros == 0 && rpc != null) {
      litros = CombustibleFormat.toDouble(
        rpc['out_saldo_litros'] ?? rpc['saldo_litros'],
      );
    }

    var pesos = 0.0;
    if (m != null) {
      pesos = CombustibleFormat.toDouble(
        m['saldo_pesos'] ?? m['saldo_en_pesos'] ?? m['pesos_saldo'],
      );
    }
    if (pesos == 0 && rpc != null) {
      pesos = CombustibleFormat.toDouble(
        rpc['out_saldo_pesos'] ?? rpc['saldo_pesos'],
      );
    }

    var precio = CombustibleFormat.toDouble(rpc?['out_precio_litro']);
    if (precio == 0) precio = _precioLitroParametro;
    if (pesos == 0 && litros > 0 && precio > 0) {
      pesos = litros * precio;
    }

    double? kmRest;
    if (rpc != null &&
        (rpc['out_km_restantes'] != null || rpc['km_restantes'] != null)) {
      kmRest = CombustibleFormat.toDouble(
        rpc['out_km_restantes'] ?? rpc['km_restantes'],
      );
    }

    return <String, dynamic>{
      'out_saldo_litros': litros,
      'out_saldo_pesos': pesos,
      'out_precio_litro': precio,
      'out_km_restantes': kmRest,
    };
  }

  /// Evita SnackBars al conectar Realtime por solicitudes ya históricas.
  Future<void> _seedSolicitudSnackIds(String rut) async {
    print('[Combustible] _seedSolicitudSnackIds');
    try {
      final resp = await Supabase.instance.client
          .from('solicitudes_combustible')
          .select('id, estado')
          .eq('rut_tecnico', rut)
          .inFilter('estado', ['atendida', 'rechazada']);
      for (final m in _coerceRowList(resp)) {
        final id = m['id']?.toString() ?? '';
        final est = m['estado']?.toString() ?? '';
        if (id.isEmpty) continue;
        if (est == 'atendida') _snackAtendidaIds.add(id);
        if (est == 'rechazada') _snackRechazadaIds.add(id);
      }
    } catch (e, st) {
      print('[Combustible] _seedSolicitudSnackIds: $e\n$st');
    }
  }

  void _suscribirRealtime(String rut) {
    _monederoSub?.cancel();
    _solicitudSub?.cancel();

    print('[Combustible] Realtime monedero_combustible');
    _monederoSub = Supabase.instance.client
        .from('monedero_combustible')
        .stream(primaryKey: ['rut_tecnico'])
        .eq('rut_tecnico', rut)
        .listen((data) {
      if (data.isEmpty || !mounted) return;
      final row = data.first;
      setState(() {
        _monederoRow = Map<String, dynamic>.from(row);
      });
    });

    print('[Combustible] Realtime solicitudes_combustible');
    _solicitudSub = Supabase.instance.client
        .from('solicitudes_combustible')
        .stream(primaryKey: ['id'])
        .eq('rut_tecnico', rut)
        .listen((data) {
      if (!mounted) return;
      for (final s in data) {
        final id = s['id']?.toString() ?? '';
        final estado = s['estado']?.toString() ?? '';
        if (id.isEmpty) continue;
        if (estado == 'atendida' && !_snackAtendidaIds.contains(id)) {
          _snackAtendidaIds.add(id);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text('✅ Combustible cargado por el coordinador'),
            ),
          );
        } else if (estado == 'rechazada' &&
            !_snackRechazadaIds.contains(id)) {
          _snackRechazadaIds.add(id);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFFEF4444),
              content: Text(
                'Solicitud rechazada — contacta a tu coordinador',
              ),
            ),
          );
        }
      }
      setState(() {});
    });
  }

  Future<void> _cargarTodo() async {
    print('[Combustible] _cargarTodo inicio');
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final rut = prefs.getString('rut_tecnico');
      if (rut == null || rut.isEmpty) {
        print('[Combustible] sin rut_tecnico');
        if (!mounted) return;
        setState(() {
          _rut = null;
          _loading = false;
          _error = 'No hay RUT configurado. Revisa tu registro en la app.';
        });
        return;
      }

      await _loadParametros();

      final ultimaRaw = await Supabase.instance.client.rpc(
        'ultimo_dia_disponible',
        params: {'p_rut': rut},
      );
      print('[Combustible] ultimo_dia_disponible: $ultimaRaw');
      final ultimaFecha =
          _parseUltimoDia(ultimaRaw) ?? _ymd(DateTime.now());

      final results = await Future.wait([
        _fetchMonedero(rut),
        _fetchRpcUltimoDia(rut, ultimaFecha),
        _fetchHistorialMes(rut, DateTime.now()),
        _fetchPendienteSolicitud(rut),
        _fetchDiaDiarioResumen(rut, ultimaFecha),
      ]);

      final monedero = results[0] as Map<String, dynamic>?;
      final rpc = results[1] as Map<String, dynamic>?;
      final dias = results[2] as List<Map<String, dynamic>>;
      final pendiente = results[3] as bool;
      final diaResumen = results[4] as Map<String, dynamic>?;

      final now = DateTime.now();
      final mesRef = DateTime(now.year, now.month, 1);

      if (!mounted) return;
      setState(() {
        _rut = rut;
        _mesReferencia = mesRef;
        _ultimaFechaYmd = ultimaFecha;
        _monederoRow = monedero;
        _rpcUltimoDia = rpc;
        _diasMes = dias;
        _pendienteSolicitud = pendiente;
        _diaUltimoResumen = diaResumen;
        _loading = false;
      });

      await _seedSolicitudSnackIds(rut);
      _suscribirRealtime(rut);
      print('[Combustible] _cargarTodo OK');
    } catch (e, st) {
      print('[Combustible] ERROR _cargarTodo: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los datos: $e';
      });
    }
  }

  Future<void> _loadParametros() async {
    try {
      final param = await Supabase.instance.client
          .from('parametros_combustible')
          .select()
          .limit(1)
          .maybeSingle();
      print('[Combustible] parametros_combustible: $param');
      if (param != null) {
        final p = CombustibleFormat.toDouble(
          param['precio_litro'] ?? param['precio_litro_referencia'],
        );
        if (p > 0) _precioLitroParametro = p;
        final rk = CombustibleFormat.toDouble(param['rendimiento_km']);
        if (rk > 0) _rendimientoKm = rk;
        final kf = CombustibleFormat.toDouble(param['km_trayecto_fijo']);
        if (kf > 0) _kmTrayectoFijo = kf;
      }
    } catch (e) {
      print('[Combustible] parametros (opcional): $e');
    }
  }

  Future<Map<String, dynamic>?> _fetchMonedero(String rutTecnico) async {
    print('[Combustible] _fetchMonedero');
    try {
      final res = await Supabase.instance.client
          .from('monedero_combustible')
          .select()
          .eq('rut_tecnico', rutTecnico)
          .maybeSingle();
      print('[Combustible] monedero_combustible: $res');
      return res != null ? Map<String, dynamic>.from(res) : null;
    } catch (e, st) {
      print('[Combustible] ERROR _fetchMonedero: $e\n$st');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchDiaDiarioResumen(
    String rutTecnico,
    String fechaYmd,
  ) async {
    print('[Combustible] _fetchDiaDiarioResumen fecha=$fechaYmd');
    try {
      final res = await Supabase.instance.client
          .from('combustible_diario_tecnico')
          .select()
          .eq('rut_tecnico', rutTecnico)
          .eq('fecha', fechaYmd)
          .maybeSingle();
      print('[Combustible] combustible_diario_tecnico resumen: $res');
      return res != null ? Map<String, dynamic>.from(res) : null;
    } catch (e, st) {
      print('[Combustible] ERROR _fetchDiaDiarioResumen: $e\n$st');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchRpcUltimoDia(
    String rutTecnico,
    String fechaStr,
  ) async {
    print('[Combustible] _fetchRpcUltimoDia fecha=$fechaStr');
    try {
      final res = await Supabase.instance.client.rpc(
        'calcular_combustible_tecnico',
        params: {
          'p_rut': rutTecnico,
          'p_fecha': fechaStr,
        },
      );
      print('[Combustible] RPC calcular_combustible_tecnico: $res');
      return _coerceRpcFirstRow(res);
    } catch (e, st) {
      print('[Combustible] ERROR _fetchRpcUltimoDia: $e\n$st');
      return null;
    }
  }

  Future<bool> _fetchPendienteSolicitud(String rutTecnico) async {
    print('[Combustible] _fetchPendienteSolicitud');
    try {
      final p = await Supabase.instance.client
          .from('solicitudes_combustible')
          .select('id, estado')
          .eq('rut_tecnico', rutTecnico)
          .eq('estado', 'pendiente')
          .maybeSingle();
      print('[Combustible] solicitud pendiente: $p');
      return p != null;
    } catch (e, st) {
      print('[Combustible] ERROR _fetchPendienteSolicitud: $e\n$st');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchHistorialMes(
    String rutTecnico,
    DateTime mesRef,
  ) async {
    print('[Combustible] _fetchHistorialMes mes=$mesRef');
    final primer = DateTime(mesRef.year, mesRef.month, 1);
    final ultimo = DateTime(mesRef.year, mesRef.month + 1, 0);
    final desde = _ymd(primer);
    final hasta = _ymd(ultimo);

    print('[Combustible] historial rango $desde → $hasta');

    try {
      final diasResp = await Supabase.instance.client
          .from('combustible_diario_tecnico')
          .select()
          .eq('rut_tecnico', rutTecnico)
          .gte('fecha', desde)
          .lte('fecha', hasta)
          .order('fecha', ascending: false);

      final dias = _coerceRowList(diasResp);
      print('[Combustible] combustible_diario_tecnico: ${dias.length} filas');
      return dias;
    } catch (e, st) {
      print('[Combustible] ERROR _fetchHistorialMes: $e\n$st');
      return [];
    }
  }

  List<Widget> _buildSemanas(int anno, int mes) {
    final lastDay = DateTime(anno, mes + 1, 0).day;
    final weekIndices = <int>{};
    for (final row in _diasMes) {
      final d = _parseFechaRow(row['fecha']);
      if (d == null || d.year != anno || d.month != mes) continue;
      weekIndices.add(((d.day - 1) ~/ 7) + 1);
    }

    final sorted = weekIndices.toList()..sort();
    final rut = _rut ?? '';
    final tiles = <Widget>[];

    for (final w in sorted) {
      final diaInicio = (w - 1) * 7 + 1;
      final diaFin = math.min(w * 7, lastDay);
      final diasSemana = _diasMes.where((row) {
        final d = _parseFechaRow(row['fecha']);
        if (d == null || d.year != anno || d.month != mes) return false;
        return d.day >= diaInicio && d.day <= diaFin;
      }).toList()
        ..sort((a, b) {
          final da = _parseFechaRow(a['fecha']);
          final db = _parseFechaRow(b['fecha']);
          if (da == null || db == null) return 0;
          return da.compareTo(db);
        });

      if (diasSemana.isEmpty) continue;

      tiles.add(
        CombustibleSemanaTile(
          rutTecnico: rut,
          semanaIndex: w,
          anno: anno,
          mes: mes,
          diaInicio: diaInicio,
          diaFin: diaFin,
          diasOrdenados: diasSemana,
        ),
      );
    }
    return tiles;
  }

  void _abrirDetalleDia(CombustibleDetalleSeccion seccion) {
    final r = _rut;
    final f = _ultimaFechaYmd;
    if (r == null || f == null) return;
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CombustibleDiaDetalleScreen(
          rutTecnico: r,
          fechaYmd: f,
          scrollTo: seccion,
        ),
      ),
    );
  }

  Widget _buildResumenUltimoDia() {
    final rpc = _rpcUltimoDia;
    final ultima = _ultimaFechaYmd;

    if (rpc == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sin visitas registradas aún hoy',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'El monedero está disponible',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
          ],
        ),
      );
    }

    final visitas = _pickVisitasRpc(rpc);
    final kmOp = _pickRpc(rpc, [
      'out_km_operativo_hoy',
      'km_operativo',
      'out_km_operativo',
    ]);
    final litOp = _pickRpc(rpc, [
      'out_litros_operativo_hoy',
      'litros_operativo',
    ]);
    final pesosOp = _pickRpc(rpc, [
      'out_pesos_operativo_hoy',
      'costo_operativo',
    ]);

    final legs = TrayectoDiaLegs.fromRpcYDia(
      rpc: rpc,
      diaRow: _diaUltimoResumen,
      kmTrayectoFijo: _kmTrayectoFijo,
      precioLitro: _precioLitroParametro,
      rendimientoKm: _rendimientoKm,
    );

    final labelDia = ultima != null
        ? 'Último día registrado: ${_labelUltimoDiaRegistrado(ultima)}'
        : '';

    Widget tarjetaOperativo() {
      return Expanded(
        child: Material(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => _abrirDetalleDia(CombustibleDetalleSeccion.operativo),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '🛣️ Operativo',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[400],
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.open_in_new,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '(empresa paga)',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${CombustibleFormat.formatKm(kmOp)} km',
                    style: const TextStyle(
                      color: Color(0xFF22C55E),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${CombustibleFormat.formatLitros(litOp)} L',
                    style: TextStyle(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    CombustibleFormat.formatMoney(pesosOp),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF22C55E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$visitas visitas · último día',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF22C55E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toca para ver tramos entre OT',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget tarjetaTrayecto() {
      return Expanded(
        child: Material(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => _abrirDetalleDia(CombustibleDetalleSeccion.trayecto),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '🏠 Trayecto personal',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[400],
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.open_in_new,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '(tú pagas)',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${CombustibleFormat.formatKm(legs.kmTotal)} km',
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${CombustibleFormat.formatLitros(legs.litrosTotal)} L',
                    style: TextStyle(
                      color: const Color(0xFF9CA3AF).withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    CombustibleFormat.formatMoney(legs.costoTotal),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '🌅 ${CombustibleFormat.formatKm(legs.kmIda)} km · 1ª visita',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.3,
                      color: Colors.grey[500],
                    ),
                  ),
                  Text(
                    '🌙 ${CombustibleFormat.formatKm(legs.kmVuelta)} km · última OT → casa',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.3,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toca para detalle ida / vuelta',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (labelDia.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              labelDia,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[500],
              ),
            ),
          ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tarjetaOperativo(),
              const SizedBox(width: 8),
              tarjetaTrayecto(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bannerSolicitudWidget() {
    final t = _bannerSolicitudExito;
    if (t == null || t.isEmpty) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFF14532D),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => setState(() => _bannerSolicitudExito = null),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ),
              Icon(Icons.close, color: Colors.white.withValues(alpha: 0.8), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _botonSolicitarAdicional(BuildContext context) {
    final data = _monederoDisplayMap();
    final pesos = CombustibleFormat.toDouble(data['out_saldo_pesos']);
    final precio = CombustibleFormat.toDouble(data['out_precio_litro']);
    final kmRpc = data['out_km_restantes'];
    final km = kmRpc != null
        ? CombustibleFormat.toDouble(kmRpc)
        : (pesos > 0 ? pesos / (precio > 0 ? precio : 1500) * 13 : 0.0);

    if (_pendienteSolicitud) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.schedule, color: Colors.grey),
            label: const Text(
              '⏳ Solicitud enviada — pendiente de atención',
              style: TextStyle(color: Colors.grey),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Uso personal · No afecta tu saldo operativo',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          onPressed: _rut == null
              ? null
              : () async {
                  print('[Combustible] abrir sheet solicitud adicional');
                  final ok = await showSolicitarCombustibleAdicionalSheet(
                    context: context,
                    rutTecnico: _rut!,
                    saldoPesos: pesos,
                    kmRestantes: km,
                  );
                  if (ok == true && mounted) {
                    setState(() {
                      _pendienteSolicitud = true;
                      _bannerSolicitudExito =
                          '✅ Solicitud enviada al coordinador de flota\n'
                          'Saldo operativo: ${CombustibleFormat.formatMoney(pesos)} · '
                          '${km.toStringAsFixed(0)} km de recorrido disponibles';
                    });
                    await _cargarTodo();
                  }
                },
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('📋 Solicitar combustible adicional'),
        ),
        const SizedBox(height: 6),
        Text(
          'Uso personal · No afecta tu saldo operativo',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final refMes = _mesReferencia;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('⛽ Combustible'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
      ),
      body: RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        onRefresh: _cargarTodo,
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: const [_CombustibleShimmer()],
              )
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: Colors.red.shade300),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _cargarTodo,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      _bannerSolicitudWidget(),
                      if (_bannerSolicitudExito != null)
                        const SizedBox(height: 12),
                      MonederoCard(data: _monederoDisplayMap()),
                      const SizedBox(height: 16),
                      _buildResumenUltimoDia(),
                      const SizedBox(height: 20),
                      _botonSolicitarAdicional(context),
                      const SizedBox(height: 28),
                      Text(
                        'Historial — ${_nombreMes(refMes.month)} ${refMes.year}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_rut != null &&
                          _buildSemanas(refMes.year, refMes.month).isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Aún no hay movimientos registrados en este período.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
                        )
                      else
                        ..._buildSemanas(refMes.year, refMes.month),
                      const SizedBox(height: 32),
                    ],
                  ),
      ),
    );
  }
}

class _CombustibleShimmer extends StatelessWidget {
  const _CombustibleShimmer();

  @override
  Widget build(BuildContext context) {
    Widget bloque(double h) {
      return Container(
        height: h,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(14),
        ),
      )
          .animate(onPlay: (c) => c.repeat())
          .shimmer(
            duration: 1100.ms,
            color: Colors.white24,
          );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bloque(180),
        bloque(100),
        const SizedBox(height: 8),
        bloque(48),
        bloque(72),
      ],
    );
  }
}
