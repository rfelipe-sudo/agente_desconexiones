import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:agente_desconexiones/models/creavox_orden.dart';
import 'package:agente_desconexiones/models/creavox_tecnico.dart';
import 'package:agente_desconexiones/services/creavox_api_service.dart';
import 'package:agente_desconexiones/services/creavox_session_service.dart';
import 'ast_form_screen.dart';
import 'ast_login_screen.dart';

const _bg = Color(0xFF0A1628);
const _surface = Color(0xFF0D1B2A);
const _accent = Color(0xFF00D9FF);
const _border = Color(0xFF1E3A5F);
const _textDim = Color(0xFF8FA8C8);
const _green = Color(0xFF4CAF50);
const _orange = Color(0xFFF59E0B);
const _red = Color(0xFFEF4444);
const _primary = Color(0xFF2196F3);
const _distanciaMaxMetros = 300.0;

class AstWorkflowScreen extends StatefulWidget {
  const AstWorkflowScreen({super.key});

  @override
  State<AstWorkflowScreen> createState() => _AstWorkflowScreenState();
}

class _AstWorkflowScreenState extends State<AstWorkflowScreen> {
  final _session = CreavoxSessionService();
  final _api = CreavoxApiService();

  CreavoxTecnico? _tecnico;
  CreavoxOrden? _orden;
  Position? _posicion;
  double? _distanciaMetros;

  bool _loading = true;
  bool _tienePermisos = false;
  bool _estaEnRango = false;
  String? _error;

  Timer? _gpsTimer;
  StreamSubscription<Position>? _gpsSub;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    setState(() { _loading = true; _error = null; });
    try {
      await _session.inicializar();
      _tecnico = _session.getTecnico();

      if (_tecnico == null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AstLoginScreen()),
        );
        return;
      }

      _tienePermisos = await _pedirPermisos();
      await _cargarOrden();

      if (_tienePermisos && _orden != null) {
        await _actualizarGps();
        _iniciarGpsAutomatico();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error al cargar datos');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _pedirPermisos() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  Future<void> _cargarOrden() async {
    if (_tecnico == null) return;
    try {
      final orden = await _api.getOrdenActiva(_tecnico!.rutTecnico);
      setState(() => _orden = orden);
      if (orden != null) await _session.guardarOrden(orden);
    } catch (_) {}
  }

  Future<void> _actualizarGps() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() => _posicion = pos);
      if (_orden != null && _orden!.tieneCoordenadas) {
        final dist = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          _orden!.coordY,
          _orden!.coordX,
        );
        setState(() {
          _distanciaMetros = dist;
          _estaEnRango = dist <= _distanciaMaxMetros;
        });
      }
    } catch (_) {}
  }

  void _iniciarGpsAutomatico() {
    _gpsTimer?.cancel();
    _gpsTimer = Timer.periodic(const Duration(seconds: 10), (_) => _actualizarGps());
    _gpsSub?.cancel();
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() => _posicion = pos);
      if (_orden != null && _orden!.tieneCoordenadas) {
        final dist = Geolocator.distanceBetween(
          pos.latitude, pos.longitude,
          _orden!.coordY, _orden!.coordX,
        );
        setState(() {
          _distanciaMetros = dist;
          _estaEnRango = dist <= _distanciaMaxMetros;
        });
      }
    });
  }

  Future<void> _refrescar() async {
    await _actualizarGps();
    await _cargarOrden();
  }

  void _abrirAST() {
    if (!_estaEnRango) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Debes estar dentro de 300m para completar el AST'),
        backgroundColor: _orange,
      ));
      return;
    }
    if (_orden == null) return;

    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => AstFormScreen(orden: _orden!),
        ))
        .then((_) => _refrescar());
  }

  void _cerrarSesion() async {
    await _session.cerrarSesion();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AstLoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    _gpsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'AST — Análisis de Trabajo Seguro',
          style: TextStyle(color: Colors.white, fontSize: 15),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: _accent),
            onPressed: _loading ? null : _refrescar,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: _textDim),
            onPressed: _cerrarSesion,
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : RefreshIndicator(
              onRefresh: _refrescar,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) _buildError(),
                    _buildTecnicoCard(),
                    const SizedBox(height: 16),
                    if (_orden != null) ...[
                      _buildOrdenCard(),
                      const SizedBox(height: 16),
                      _buildUbicacionCard(),
                      const SizedBox(height: 24),
                      _buildBotonAST(),
                    ] else
                      _buildSinOrden(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _red.withOpacity(0.3)),
      ),
      child: Text(_error!, style: const TextStyle(color: _red)),
    );
  }

  Widget _buildTecnicoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: _primary.withOpacity(0.2),
            child: Text(
              (_tecnico?.nombreTecnico ?? 'T').substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: _primary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tecnico?.nombreTecnico ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'RUT: ${_tecnico?.rutTecnico ?? ''}',
                  style: const TextStyle(color: _textDim, fontSize: 13),
                ),
                Text(
                  'Supervisor: ${_tecnico?.nombreSupervisor ?? ''}',
                  style: const TextStyle(color: _textDim, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdenCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_rounded, color: _primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Orden Activa',
                style: TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
            ],
          ),
          const Divider(color: _border, height: 20),
          _fila('OT:', _orden!.ordenDeTrabajo),
          const SizedBox(height: 6),
          _fila('Cliente:', _orden!.nombreCompletoCliente),
          const SizedBox(height: 6),
          _fila('Dirección:', _orden!.direccion),
          const SizedBox(height: 6),
          _fila('Actividad:', _orden!.tipoActividad),
        ],
      ),
    );
  }

  Widget _buildUbicacionCard() {
    Color color;
    IconData icon;
    String titulo;
    String detalle;

    if (!_tienePermisos) {
      color = _red; icon = Icons.location_off;
      titulo = 'Sin permisos de ubicación';
      detalle = 'Habilita el GPS en ajustes';
    } else if (_posicion == null) {
      color = _orange; icon = Icons.gps_off;
      titulo = 'Obteniendo ubicación...';
      detalle = 'Espera un momento';
    } else if (_estaEnRango) {
      color = _green; icon = Icons.check_circle_rounded;
      titulo = 'Dentro del rango permitido';
      detalle = 'Distancia: ${_distanciaMetros!.toStringAsFixed(0)} m';
    } else {
      color = _red; icon = Icons.cancel_rounded;
      titulo = 'Fuera del rango';
      detalle =
          'Distancia: ${_distanciaMetros!.toStringAsFixed(0)} m (máx: 300m)';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 44, color: color),
          const SizedBox(height: 10),
          Text(
            titulo,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(detalle,
              style: const TextStyle(color: _textDim, fontSize: 13),
              textAlign: TextAlign.center),
          if (!_estaEnRango && _posicion != null) ...[
            const SizedBox(height: 8),
            const Text(
              'Acércate a la dirección del cliente para habilitar el AST',
              style: TextStyle(color: _orange, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBotonAST() {
    final habilitado = _estaEnRango && _orden != null;
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: habilitado ? _abrirAST : null,
        icon: const Icon(Icons.assignment_add, size: 26),
        label: const Text(
          'Completar Análisis de Trabajo Seguro',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _border,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildSinOrden() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: const Column(
        children: [
          Icon(Icons.assignment_late_rounded, size: 48, color: _orange),
          SizedBox(height: 16),
          Text(
            'No tienes órdenes asignadas',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            'Sin una orden activa no es posible completar el AST.',
            style: TextStyle(color: _textDim, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _fila(String label, String valor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: _textDim, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(valor,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
      ],
    );
  }
}
