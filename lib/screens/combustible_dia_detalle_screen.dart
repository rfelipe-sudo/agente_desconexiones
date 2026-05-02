import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_animate/flutter_animate.dart';

import 'package:agente_desconexiones/widgets/combustible_dia_detail.dart';
import 'package:agente_desconexiones/widgets/combustible_format.dart';

/// Detalle de un día: tramos operativos, trayecto y totalizador (pantalla completa).
class CombustibleDiaDetalleScreen extends StatefulWidget {
  const CombustibleDiaDetalleScreen({
    super.key,
    required this.rutTecnico,
    required this.fechaYmd,
    this.scrollTo,
  });

  final String rutTecnico;
  /// `YYYY-MM-DD`
  final String fechaYmd;

  /// Opcional: desplazar a operativo o trayecto al abrir (p. ej. desde resumen).
  final CombustibleDetalleSeccion? scrollTo;

  @override
  State<CombustibleDiaDetalleScreen> createState() =>
      _CombustibleDiaDetalleScreenState();
}

class _CombustibleDiaDetalleScreenState
    extends State<CombustibleDiaDetalleScreen> {
  Map<String, dynamic>? _diaRow;
  Map<String, dynamic>? _rpcDia;
  List<Map<String, dynamic>> _tramos = [];
  bool _loading = true;
  String? _error;

  double _precioLitro = 1500;
  double _rendimientoKm = 13;
  double _kmTrayectoFijo = 40;

  final GlobalKey _keyOperativo = GlobalKey();
  final GlobalKey _keyTrayecto = GlobalKey();
  bool _didScroll = false;
  int _scrollIntentos = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    print('[Combustible] DiaDetalle._cargar fecha=${widget.fechaYmd} rut=${widget.rutTecnico}');
    setState(() {
      _loading = true;
      _error = null;
      _didScroll = false;
      _scrollIntentos = 0;
    });
    try {
      final supabase = Supabase.instance.client;

      try {
        final param = await supabase
            .from('parametros_combustible')
            .select()
            .limit(1)
            .maybeSingle();
        if (param != null) {
          final p = CombustibleFormat.toDouble(param['precio_litro']);
          if (p > 0) _precioLitro = p;
          final r = CombustibleFormat.toDouble(param['rendimiento_km']);
          if (r > 0) _rendimientoKm = r;
          final k = CombustibleFormat.toDouble(param['km_trayecto_fijo']);
          if (k > 0) _kmTrayectoFijo = k;
        }
      } catch (e) {
        print('[Combustible] DiaDetalle parametros: $e');
      }

      dynamic rpcRaw;
      try {
        rpcRaw = await supabase.rpc(
          'calcular_combustible_tecnico',
          params: {
            'p_rut': widget.rutTecnico,
            'p_fecha': widget.fechaYmd,
          },
        );
      } catch (e) {
        print('[Combustible] DiaDetalle RPC: $e');
      }
      Map<String, dynamic>? rpcMap;
      if (rpcRaw is List && rpcRaw.isNotEmpty) {
        final f = rpcRaw.first;
        if (f is Map<String, dynamic>) {
          rpcMap = Map<String, dynamic>.from(f);
        } else if (f is Map) {
          rpcMap = Map<String, dynamic>.from(f);
        }
      } else if (rpcRaw is Map<String, dynamic>) {
        rpcMap = Map<String, dynamic>.from(rpcRaw);
      } else if (rpcRaw is Map) {
        rpcMap = Map<String, dynamic>.from(rpcRaw);
      }

      final dia = await supabase
          .from('combustible_diario_tecnico')
          .select()
          .eq('rut_tecnico', widget.rutTecnico)
          .eq('fecha', widget.fechaYmd)
          .maybeSingle();

      dynamic tramosResp;
      try {
        tramosResp = await supabase
            .from('combustible_tramos')
            .select()
            .eq('rut_tecnico', widget.rutTecnico)
            .eq('fecha', widget.fechaYmd)
            .order('created_at');
      } catch (e) {
        print('[Combustible] DiaDetalle tramos order created_at: $e');
        tramosResp = await supabase
            .from('combustible_tramos')
            .select()
            .eq('rut_tecnico', widget.rutTecnico)
            .eq('fecha', widget.fechaYmd)
            .order('fecha');
      }

      final list = <Map<String, dynamic>>[];
      if (tramosResp is List) {
        for (final e in tramosResp) {
          if (e is Map<String, dynamic>) {
            list.add(Map<String, dynamic>.from(e));
          } else if (e is Map) {
            list.add(Map<String, dynamic>.from(e));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _diaRow = dia != null ? Map<String, dynamic>.from(dia) : null;
        _rpcDia = rpcMap;
        _tramos = list;
        _loading = false;
      });
      print('[Combustible] DiaDetalle OK dia=${_diaRow != null} tramos=${list.length}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _intentarScrollSeccion();
      });
    } catch (e, st) {
      print('[Combustible] DiaDetalle ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _intentarScrollSeccion() {
    if (_didScroll || widget.scrollTo == null) return;
    if (_scrollIntentos > 12) return;
    _scrollIntentos++;
    final key = widget.scrollTo == CombustibleDetalleSeccion.operativo
        ? _keyOperativo
        : _keyTrayecto;
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOut,
        alignment: 0.15,
      );
      _didScroll = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _didScroll) return;
        _intentarScrollSeccion();
      });
    }
  }

  String _labelFecha() {
    try {
      final d = DateTime.parse(widget.fechaYmd);
      const meses = [
        '', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
        'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
      ];
      const dias = [
        'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo',
      ];
      return '${dias[d.weekday - 1]} ${d.day} ${meses[d.month]} ${d.year}';
    } catch (_) {
      return widget.fechaYmd;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: Text('⛽ ${_labelFecha()}'),
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        onRefresh: _cargar,
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: const [_DiaDetalleShimmer()],
              )
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _cargar,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      CombustibleDiaDetail(
                        fechaLabel: _labelFecha(),
                        diaRow: _diaRow,
                        tramos: _tramos,
                        rpcRow: _rpcDia,
                        kmTrayectoFijo: _kmTrayectoFijo,
                        precioLitro: _precioLitro,
                        rendimientoKm: _rendimientoKm,
                        keySeccionOperativo: _keyOperativo,
                        keySeccionTrayecto: _keyTrayecto,
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _DiaDetalleShimmer extends StatelessWidget {
  const _DiaDetalleShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(14),
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1100.ms, color: Colors.white24);
  }
}
