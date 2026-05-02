import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agente_desconexiones/models/estado_supervisor.dart';
import 'package:agente_desconexiones/services/estado_supervisor_service.dart';
import 'package:agente_desconexiones/services/notification_service.dart' as notif_svc;

/// Pantalla/modal MI ACTIVIDAD para supervisores
class MiActividadScreen extends StatefulWidget {
  const MiActividadScreen({super.key});

  @override
  State<MiActividadScreen> createState() => _MiActividadScreenState();
}

class _MiActividadScreenState extends State<MiActividadScreen> {
  String? _rutSupervisor;
  String? _nombreSupervisor;
  bool _loading = false;
  String? _error;
  Timer? _countdownTimer;
  Timer? _timerTranscurrido;
  int _countdownSegundos = 600; // 10 min
  /// Técnicos precargados al entrar (evita delay al abrir formulario movimiento)
  List<Map<String, String>> _tecnicos = [];
  bool _tecnicosCargando = true;
  /// Feedback visual: actividad cuya card está en estado "cargando"
  ActividadSupervisor? _actividadCargando;

  static const _colorFondo = Color(0xFF0D1B2A);
  static const _colorCyan = Color(0xFF00E5FF);
  static const _colorVerde = Color(0xFF30D158);
  static const _colorNaranja = Color(0xFFFF9500);

  @override
  void initState() {
    super.initState();
    _cargarSesion();
    _cargarTecnicos();
  }

  Future<void> _cargarTecnicos() async {
    try {
      final tecnicos = await EstadoSupervisorService().obtenerTodosTecnicosParaMovimiento();
      if (mounted) {
        setState(() {
          _tecnicos = tecnicos;
          _tecnicosCargando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _tecnicos = [{'rut': 'BODEGA', 'nombre': 'BODEGA'}];
          _tecnicosCargando = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _timerTranscurrido?.cancel();
    super.dispose();
  }

  Future<void> _cargarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    _rutSupervisor = prefs.getString('rut_supervisor') ??
        prefs.getString('rut_tecnico') ??
        prefs.getString('user_rut');
    _nombreSupervisor = prefs.getString('nombre_supervisor') ??
        prefs.getString('user_nombre');
    if (_rutSupervisor == null || _rutSupervisor!.isEmpty) {
      setState(() => _error = 'No se encontró sesión de supervisor.');
      return;
    }
    final svc = EstadoSupervisorService();
    await svc.cargarEstado(_rutSupervisor!);
    await svc.verificarRecoveryActividad(_rutSupervisor!);
    svc.suscribirRealtime(_rutSupervisor!);
    svc.setOnCountdownNotificacion(_mostrarNotifCountdown);
    svc.setOnAutoCompletado(_mostrarNotifAutoCompletado);
    if (svc.estadoActual?.estaActivo ?? false) {
      _timerTranscurrido = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    setState(() {});
  }

  void _mostrarNotifCountdown() {
    notif_svc.NotificationService().mostrarNotificacion(
      titulo: '📍 Has llegado al destino',
      cuerpo: 'La actividad se completará en 10 minutos si no la cierras antes.',
    );
    _iniciarCountdownVisual();
  }

  void _mostrarNotifAutoCompletado() {
    notif_svc.NotificationService().mostrarNotificacion(
      titulo: '✅ Movimiento completado',
      cuerpo: 'Movimiento de material completado automáticamente',
    );
  }

  void _iniciarCountdownVisual() {
    _countdownTimer?.cancel();
    _countdownSegundos = 600;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_countdownSegundos > 0 && mounted) {
        setState(() => _countdownSegundos--);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: _colorFondo,
        title: const Text('MI ACTIVIDAD', style: TextStyle(letterSpacing: 2)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _error != null
          ? _buildError()
          : ListenableBuilder(
              listenable: EstadoSupervisorService(),
              builder: (_, __) {
                final svc = EstadoSupervisorService();
                final estado = svc.estadoActual;
                final activo = estado?.estaActivo ?? false;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildEstadoActual(estado, activo),
                      if (_countdownSegundos < 600 && _countdownSegundos > 0)
                        _buildCountdownBanner(),
                      const SizedBox(height: 24),
                      if (activo)
                        _buildCompletarBoton(svc)
                      else
                        ...ActividadSupervisor.values.map(
                            (a) => _buildActividadCard(a, svc)),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadoActual(EstadoSupervisor? estado, bool activo) {
    final actividadNombre = estado?.actividad == 'sin_actividad'
        ? 'Sin actividad'
        : _nombreActividad(estado?.actividad);
    final tiempoTranscurrido = estado?.actividadDesde != null
        ? _formatTiempo(DateTime.now().difference(estado!.actividadDesde!))
        : null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151F2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: activo ? _colorCyan.withOpacity(0.5) : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                activo ? Icons.pending_actions : Icons.check_circle_outline,
                color: activo ? _colorNaranja : _colorVerde,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      actividadNombre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (tiempoTranscurrido != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        tiempoTranscurrido,
                        style: TextStyle(
                          color: _colorCyan.withOpacity(0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (estado?.nombreTecnicoActivo != null) ...[
            const SizedBox(height: 8),
            Text(
              '→ ${estado!.nombreTecnicoActivo}',
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTiempo(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds % 60}s';
    }
    return '${d.inSeconds}s';
  }

  String _nombreActividad(String? valor) {
    return switch (valor) {
      'verificando_asistencia' => 'Verificando asistencia',
      'reunion_equipo' => 'Reunión de equipo',
      'movimiento_material' => 'Movimiento de materiales',
      'colacion' => 'Colación',
      'desvinculacion' => 'Desvinculación',
      'reunion_jefatura' => 'Reunión con jefatura',
      _ => valor ?? 'Sin actividad',
    };
  }

  Widget _buildCountdownBanner() {
    final min = _countdownSegundos ~/ 60;
    final seg = _countdownSegundos % 60;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _colorNaranja.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _colorNaranja),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer, color: _colorNaranja),
          const SizedBox(width: 12),
          Text(
            'Auto-completar en ${min.toString().padLeft(2, '0')}:${seg.toString().padLeft(2, '0')}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletarBoton(EstadoSupervisorService svc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ElevatedButton.icon(
        onPressed: _loading
            ? null
            : () async {
                setState(() => _loading = true);
                try {
                  await svc.completarActividad(_rutSupervisor!);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Actividad completada'), backgroundColor: _colorVerde),
                    );
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (mounted) {
                    setState(() => _loading = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
        icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_circle),
        label: Text(_loading ? 'Completando...' : 'COMPLETAR ACTIVIDAD'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _colorVerde,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildActividadCard(ActividadSupervisor act, EstadoSupervisorService svc) {
    final esMovimiento = act == ActividadSupervisor.movimientoMateriales;
    final estaCargando = _actividadCargando == act;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: estaCargando
          ? _colorCyan.withOpacity(0.15)
          : const Color(0xFF151F2E),
      child: InkWell(
        onTap: _loading ? null : () => _onTapActividad(svc, act, esMovimiento),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _colorCyan.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: estaCargando
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _colorCyan,
                        ),
                      )
                    : Icon(_iconoActividad(act), color: _colorCyan, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  act.displayName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton(
                onPressed: _loading
                    ? null
                    : () => _onTapActividad(svc, act, esMovimiento),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _colorCyan,
                  foregroundColor: Colors.black,
                ),
                child: const Text('INICIAR'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onTapActividad(
      EstadoSupervisorService svc, ActividadSupervisor act, bool esMovimiento) async {
    setState(() => _actividadCargando = act);
    if (esMovimiento) {
      // Técnicos ya precargados en initState; abrir formulario de inmediato
      await _mostrarFormularioMovimiento(svc);
    } else {
      await _iniciarActividadSimple(svc, act);
    }
    if (mounted) setState(() => _actividadCargando = null);
  }

  IconData _iconoActividad(ActividadSupervisor act) {
    return switch (act) {
      ActividadSupervisor.verificandoAsistencia => Icons.people_alt,
      ActividadSupervisor.reunionEquipo => Icons.groups,
      ActividadSupervisor.movimientoMateriales => Icons.local_shipping,
      ActividadSupervisor.colacion => Icons.restaurant,
      ActividadSupervisor.desvinculacion => Icons.person_off,
      ActividadSupervisor.reunionJefatura => Icons.business_center,
    };
  }

  Future<void> _iniciarActividadSimple(EstadoSupervisorService svc, ActividadSupervisor act) async {
    setState(() => _loading = true);
    try {
      await svc.iniciarActividad(
        rutSupervisor: _rutSupervisor!,
        nombreSupervisor: _nombreSupervisor ?? 'Supervisor',
        actividadValor: act.valorSupabase,
      );
      if (mounted) {
        setState(() => _loading = false);
        _timerTranscurrido?.cancel();
        _timerTranscurrido = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${act.displayName} iniciada'), backgroundColor: _colorVerde),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _mostrarFormularioMovimiento(EstadoSupervisorService svc) async {
    if (!mounted) return;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => _FormularioMovimientoMateriales(
          tecnicos: _tecnicos,
          tecnicosCargando: _tecnicosCargando,
          onIniciar: (data) => Navigator.pop(context, data),
          onCancelar: () => Navigator.pop(context),
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );

    if (result != null && mounted) {
      setState(() => _loading = true);
      try {
        await svc.iniciarMovimientoMateriales(
          rutSupervisor: _rutSupervisor!,
          nombreSupervisor: _nombreSupervisor ?? 'Supervisor',
          materialOrigen: result['origen'] as String,
          materialDestino: result['destino'] as String,
          latOrigen: result['lat_origen'] as double,
          lngOrigen: result['lng_origen'] as double,
          latDestino: result['lat_destino'] as double,
          lngDestino: result['lng_destino'] as double,
          materialDetalle: 'Material',
          materialCantidad: 1,
          rutDestino: result['rut_destino'] as String,
          nombreDestino: result['nombre_destino'] as String,
        );
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Movimiento de materiales iniciado'), backgroundColor: _colorVerde),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}

class _FormularioMovimientoMateriales extends StatefulWidget {
  final List<Map<String, String>> tecnicos;
  final bool tecnicosCargando;
  final void Function(Map<String, dynamic> data) onIniciar;
  final VoidCallback onCancelar;

  const _FormularioMovimientoMateriales({
    required this.tecnicos,
    this.tecnicosCargando = false,
    required this.onIniciar,
    required this.onCancelar,
  });

  @override
  State<_FormularioMovimientoMateriales> createState() =>
      _FormularioMovimientoMaterialesState();
}

class _FormularioMovimientoMaterialesState
    extends State<_FormularioMovimientoMateriales> {
  static const _colorFondo = Color(0xFF0D1B2A);

  String? _origenRut;
  String? _origenNombre;
  String? _destinoRut;
  String? _destinoNombre;
  double? _latOrigen;
  double? _lngOrigen;
  double? _latDestino;
  double? _lngDestino;
  String _filtroOrigen = '';
  String _filtroDestino = '';
  bool _guardando = false;

  List<Map<String, String>> get _tecnicosFiltradosOrigen =>
      widget.tecnicos.where((t) => (t['nombre'] ?? '').toLowerCase().contains(_filtroOrigen.toLowerCase())).toList();

  List<Map<String, String>> get _tecnicosFiltradosDestino =>
      widget.tecnicos.where((t) => (t['nombre'] ?? '').toLowerCase().contains(_filtroDestino.toLowerCase())).toList();

  Future<void> _capturarGpsOrigen() async {
    try {
      final pos = await EstadoSupervisorService().obtenerPosicion();
      setState(() {
        _latOrigen = pos.latitude;
        _lngOrigen = pos.longitude;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _capturarGpsDestino() async {
    try {
      final pos = await EstadoSupervisorService().obtenerPosicion();
      setState(() {
        _latDestino = pos.latitude;
        _lngDestino = pos.longitude;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _iniciar() async {
    if (_origenNombre == null || _destinoNombre == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona DESDE y HASTA'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (_latOrigen == null || _lngOrigen == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Captura GPS en DESDE'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (_latDestino == null || _lngDestino == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Captura GPS en HASTA'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _guardando = true);
    widget.onIniciar({
      'origen': _origenNombre!,
      'destino': _destinoNombre!,
      'lat_origen': _latOrigen!,
      'lng_origen': _lngOrigen!,
      'lat_destino': _latDestino!,
      'lng_destino': _lngDestino!,
      'rut_destino': _destinoRut ?? 'BODEGA',
      'nombre_destino': _destinoNombre!,
    });
  }

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 24, width: 200, color: Colors.white24),
          const SizedBox(height: 20),
          Container(height: 48, color: Colors.white12),
          const SizedBox(height: 12),
          ...List.generate(5, (_) => Container(height: 48, margin: const EdgeInsets.only(bottom: 8), color: Colors.white12)),
          const SizedBox(height: 20),
          Container(height: 48, color: Colors.white12),
          const SizedBox(height: 12),
          ...List.generate(5, (_) => Container(height: 48, margin: const EdgeInsets.only(bottom: 8), color: Colors.white12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tecnicosCargando) {
      return Scaffold(
        backgroundColor: _colorFondo,
        appBar: AppBar(
          backgroundColor: _colorFondo,
          title: const Text('Movimiento de materiales'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => widget.onCancelar(),
          ),
        ),
        body: _buildSkeleton(),
      );
    }
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: _colorFondo,
        title: const Text('Movimiento de materiales'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => widget.onCancelar(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Movimiento de materiales', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            const Text('DESDE', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              onChanged: (v) => setState(() => _filtroOrigen = v),
              decoration: InputDecoration(
                hintText: 'Buscar...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            ..._tecnicosFiltradosOrigen.take(5).map((t) => ListTile(
              title: Text(t['nombre'] ?? '', style: const TextStyle(color: Colors.white)),
              trailing: _origenRut == t['rut'] ? const Icon(Icons.check, color: Color(0xFF30D158)) : null,
              onTap: () async {
                setState(() {
                  _origenRut = t['rut'];
                  _origenNombre = t['nombre'];
                });
                await _capturarGpsOrigen();
              },
            )),
            if (_latOrigen != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('GPS: ${_latOrigen!.toStringAsFixed(5)}, ${_lngOrigen!.toStringAsFixed(5)}', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
              ),
            const SizedBox(height: 20),
            const Text('HASTA', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              onChanged: (v) => setState(() => _filtroDestino = v),
              decoration: InputDecoration(
                hintText: 'Buscar...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            ..._tecnicosFiltradosDestino.take(5).map((t) => ListTile(
              title: Text(t['nombre'] ?? '', style: const TextStyle(color: Colors.white)),
              trailing: _destinoRut == t['rut'] ? const Icon(Icons.check, color: Color(0xFF30D158)) : null,
              onTap: () async {
                setState(() {
                  _destinoRut = t['rut'];
                  _destinoNombre = t['nombre'];
                });
                await _capturarGpsDestino();
              },
            )),
            if (_latDestino != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('GPS: ${_latDestino!.toStringAsFixed(5)}, ${_lngDestino!.toStringAsFixed(5)}', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _guardando ? null : widget.onCancelar,
                    child: const Text('CANCELAR'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _guardando ? null : _iniciar,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black),
                    child: Text(_guardando ? '...' : 'INICIAR'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
