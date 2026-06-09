import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:agente_desconexiones/models/solicitud_ayuda.dart';
import 'package:agente_desconexiones/services/ayuda_alerta_estado.dart';
import 'package:agente_desconexiones/services/ayuda_service.dart';
import 'package:agente_desconexiones/services/estado_supervisor_service.dart';
import 'package:agente_desconexiones/screens/supervisor/supervisor_tracking_screen.dart';

class SolicitudesAyudaScreen extends StatefulWidget {
  const SolicitudesAyudaScreen({super.key});

  @override
  State<SolicitudesAyudaScreen> createState() =>
      _SolicitudesAyudaScreenState();
}

class _SolicitudesAyudaScreenState extends State<SolicitudesAyudaScreen> {
  final _ayudaService = AyudaService();

  List<SolicitudAyuda> _solicitudes = [];
  final List<SolicitudAyuda> _canceladasRecientes = [];
  final Map<String, EstadoSolicitud> _estadoAnteriorPorTicket = {};
  bool _cargando = false;
  String? _rutSupervisor;
  bool _nuevaAlerta = false;
  String? _mensajeCancelacion;
  String? _errorCarga;
  Timer? _timerOcultarCancelacion;

  // GPS propio del supervisor (para calcular distancia)
  double? _miLat;
  double? _miLng;

  // Timers
  Timer? _timerTarjetas;
  Timer? _timerGps; // actualiza GPS del supervisor cada 45s

  // Tickets que el supervisor ha aceptado (tracking GPS activo)
  final Set<String> _ticketsAceptadosTracking = {};

  // Tickets donde la llegada se auto-marcó por proximidad 100m
  final Set<String> _ticketsLlegadaAutoMarcada = {};

  // Nombre del supervisor para el GPS del lado técnico
  String? _nombreSupervisor;

  // Cache de direcciones por ticket (geocodificación inversa)
  final Map<String, String> _direccionesCache = {};

  static const _colorFondo = Color(0xFF0D1B2A);
  static const _colorCyan = Color(0xFF00E5FF);
  static const _colorRojo = Color(0xFFFF3B30);
  static const _colorNaranja = Color(0xFFFF9500);
  static const _colorVerde = Color(0xFF30D158);
  static const _colorAmbar = Color(0xFFFFD60A);

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _timerTarjetas?.cancel();
    _timerGps?.cancel();
    _timerOcultarCancelacion?.cancel();
    _ayudaService.removeListener(_onAyudaActualizada);
    _ayudaService.setOnSolicitudCancelada(null);
    _ayudaService.cancelarSuscripcionSupervisor();
    super.dispose();
  }

  Future<void> _iniciar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _rutSupervisor = await AyudaService.resolverRutSupervisorSesion();
      _nombreSupervisor = prefs.getString('nombre_supervisor') ??
          prefs.getString('user_nombre') ?? '';

      debugPrint(
          '👤 [SolicitudesAyuda] Supervisor RUT: $_rutSupervisor');

      if (_rutSupervisor == null || _rutSupervisor!.isEmpty) {
        if (mounted) {
          setState(() {
            _errorCarga = 'No se pudo obtener el RUT del supervisor.';
            _cargando = false;
          });
        }
        return;
      }

      // GPS inmediato y timer periódico cada 10s
      _obtenerGpsPropio();
      _timerGps = Timer.periodic(const Duration(seconds: 10), (_) {
        _actualizarGpsYTracking();
      });

      // Timer para refrescar tiempo transcurrido en tarjetas cada 30s
      _timerTarjetas = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });

      await _cargarSolicitudes();
      await _ayudaService.iniciarMonitoreoGlobalSupervisor(_rutSupervisor!);

      // Suscribir a Realtime para nuevas solicitudes
      if (mounted) {
        _ayudaService.addListener(_onAyudaActualizada);
        _ayudaService.setOnSolicitudCancelada(_registrarCancelacion);
        _ayudaService.suscribirSolicitudesSupervisor(
          rutSupervisor: _rutSupervisor!,
          onNuevaSolicitud: () {
            if (mounted) {
              HapticFeedback.heavyImpact();
              setState(() {
                _nuevaAlerta = true;
                _solicitudes = _ayudaService.solicitudesSupervisor;
                _sincronizarEstadosAnteriores(_solicitudes);
              });
              _mostrarBannerNuevaSolicitud();
              Future.delayed(
                const Duration(seconds: 3),
                () => mounted ? setState(() => _nuevaAlerta = false) : null,
              );
            }
          },
        );
      }
    } catch (e) {
      debugPrint('❌ [SolicitudesAyuda] Error en _iniciar: $e');
      if (mounted) {
        setState(() {
          _errorCarga = 'Error al cargar solicitudes: $e';
          _cargando = false;
        });
      }
    }
  }

  Future<void> _obtenerGpsPropio() async {
    // 1. Carga instantánea desde BD como fallback (evita "Calculando distancia...")
    if (_miLat == null && _rutSupervisor != null && _rutSupervisor!.isNotEmpty) {
      final ultima =
          await _ayudaService.obtenerUltimaUbicacionSupervisor(_rutSupervisor!);
      if (ultima != null && mounted && _miLat == null) {
        setState(() {
          _miLat = ultima['lat'];
          _miLng = ultima['lng'];
        });
      }
    }

    // 2. GPS real del dispositivo (más preciso, puede tardar hasta 15s)
    try {
      final pos = await _ayudaService.obtenerPosicion();
      if (mounted) {
        setState(() {
          _miLat = pos.latitude;
          _miLng = pos.longitude;
        });
      }
      _ayudaService
          .actualizarUbicacionSupervisor(_rutSupervisor!)
          .catchError((_) {});
    } catch (e) {
      debugPrint('⚠️ [SolicitudesAyuda] GPS propio no disponible: $e');
    }
  }

  /// Actualiza GPS y propaga ubicación a tickets aceptados activos
  /// Auto-marca llegada cuando supervisor está a ≤100m del técnico
  Future<void> _actualizarGpsYTracking() async {
    try {
      final pos = await _ayudaService.obtenerPosicion();
      if (mounted) {
        setState(() {
          _miLat = pos.latitude;
          _miLng = pos.longitude;
        });
      }
      // Propagar ubicación a todas las solicitudes aceptadas en tracking
      for (final tid in _ticketsAceptadosTracking) {
        _ayudaService.actualizarGpsSolicitud(tid, pos.latitude, pos.longitude);
      }
      _ayudaService
          .actualizarUbicacionSupervisor(_rutSupervisor!)
          .catchError((_) {});

      // Auto-marcar llegada cuando supervisor está a ≤100m del técnico
      if (_rutSupervisor != null && _rutSupervisor!.isNotEmpty) {
        for (final s in _solicitudes) {
          if (!s.supervisorEnCamino) continue;
          if (_ticketsLlegadaAutoMarcada.contains(s.ticketId)) continue;
          final distMetros = Geolocator.distanceBetween(
            pos.latitude, pos.longitude,
            s.latTecnico, s.lngTecnico,
          );
          if (distMetros <= 100) {
            _ticketsLlegadaAutoMarcada.add(s.ticketId);
            await EstadoSupervisorService().marcarLlegadaAyuda(
              rutSupervisor: _rutSupervisor!,
              ticketId: s.ticketId,
              nombreTecnico: s.tecnicoNombre ?? 'Técnico',
            );
            if (mounted) {
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Llegada detectada automáticamente (100m)'),
                backgroundColor: Color(0xFF30D158),
              ));
            }
            break;
          }
        }
      }
    } catch (_) {}
  }

  /// Obtiene la dirección del técnico (geocodificación inversa). Usa cache.
  Future<String?> _obtenerDireccionTecnico(SolicitudAyuda s) async {
    if (_direccionesCache.containsKey(s.ticketId)) {
      return _direccionesCache[s.ticketId];
    }
    try {
      final placemarks = await placemarkFromCoordinates(
        s.latTecnico,
        s.lngTecnico,
      ).timeout(const Duration(seconds: 5));
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final partes = <String>[];
        if (p.street != null && p.street!.isNotEmpty) partes.add(p.street!);
        if (p.subLocality != null && p.subLocality!.isNotEmpty) {
          partes.add(p.subLocality!);
        } else if (p.locality != null && p.locality!.isNotEmpty) {
          partes.add(p.locality!);
        }
        if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) {
          partes.add(p.administrativeArea!);
        }
        final dir = partes.isNotEmpty
            ? partes.join(', ')
            : '${s.latTecnico.toStringAsFixed(4)}, ${s.lngTecnico.toStringAsFixed(4)}';
        _direccionesCache[s.ticketId] = dir;
        if (mounted) setState(() {});
        return dir;
      }
    } catch (e) {
      debugPrint('⚠️ [SolicitudesAyuda] Geocoding: $e');
    }
    final fallback = '${s.latTecnico.toStringAsFixed(5)}, ${s.lngTecnico.toStringAsFixed(5)}';
    _direccionesCache[s.ticketId] = fallback;
    return fallback;
  }

  double? _distanciaATecnico(SolicitudAyuda s) {
    if (_miLat == null || _miLng == null) return null;
    const r = 6371.0;
    final dLat = (s.latTecnico - _miLat!) * math.pi / 180;
    final dLon = (s.lngTecnico - _miLng!) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_miLat! * math.pi / 180) *
            math.cos(s.latTecnico * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  String _tiempoTranscurrido(DateTime desde) {
    final diff = DateTime.now().difference(desde);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  Future<void> _cargarSolicitudes() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _errorCarga = null;
    });

    try {
      // Solo silenciar solicitudes que ya existían antes de abrir la pantalla.
      final umbralCarga = DateTime.now();
      await _ayudaService
          .cargarSolicitudesSupervisor(_rutSupervisor!)
          .timeout(const Duration(seconds: 15));

      if (mounted) {
        final lista = _ayudaService.solicitudesSupervisor;
        setState(() {
          _solicitudes = lista;
          _cargando = false;
        });
        _sincronizarEstadosAnteriores(lista);
        final pendientesPrevias = lista.where((s) =>
            s.estado == EstadoSolicitud.pendiente &&
            !s.fechaCreacion.isAfter(umbralCarga));
        await _ayudaService.detenerAlerta();
        await AyudaAlertaEstado.markAllSeen(
          pendientesPrevias.map((s) => s.ticketId),
        );
        // Registrar tickets aceptados para tracking de GPS
        final estadoSvc = EstadoSupervisorService();
        for (final s in lista) {
          if (s.estado == EstadoSolicitud.aceptada ||
              s.estado == EstadoSolicitud.aceptadaConTiempo) {
            _ticketsAceptadosTracking.add(s.ticketId);
            if (estadoSvc.estadoActual?.actividad == 'ejecutando' &&
                estadoSvc.estadoActual?.ticketIdActivo == s.ticketId) {
              _ticketsLlegadaAutoMarcada.add(s.ticketId);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ [SolicitudesAyuda] Error cargando solicitudes: $e');
      if (mounted) {
        setState(() {
          _errorCarga = 'Error de conexión. Desliza para reintentar.';
          _cargando = false;
        });
      }
    }
  }

  void _sincronizarEstadosAnteriores(List<SolicitudAyuda> lista) {
    for (final s in lista) {
      _estadoAnteriorPorTicket[s.ticketId] = s.estado;
    }
  }

  void _onAyudaActualizada() {
    if (!mounted) return;
    final lista = _ayudaService.solicitudesSupervisor;
    for (final s in lista) {
      _estadoAnteriorPorTicket[s.ticketId] = s.estado;
    }
    setState(() => _solicitudes = lista);
  }

  void _registrarCancelacion(SolicitudAyuda s) {
    if (!mounted) return;
    final nombre = s.tecnicoNombre.trim().isNotEmpty
        ? s.tecnicoNombre
        : 'Técnico (${s.rutTecnico})';
    _ticketsAceptadosTracking.remove(s.ticketId);
    _ticketsLlegadaAutoMarcada.remove(s.ticketId);
    HapticFeedback.mediumImpact();
    setState(() {
      _solicitudes = _ayudaService.solicitudesSupervisor;
      _canceladasRecientes.removeWhere((c) => c.ticketId == s.ticketId);
      _canceladasRecientes.insert(0, s);
      if (_canceladasRecientes.length > 5) {
        _canceladasRecientes.removeRange(5, _canceladasRecientes.length);
      }
      _mensajeCancelacion =
          '$nombre canceló la solicitud de ${s.tipo.displayName}';
    });
    _mostrarBannerCancelacion(s);
    _timerOcultarCancelacion?.cancel();
    _timerOcultarCancelacion = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _mensajeCancelacion = null);
    });
  }

  void _mostrarBannerNuevaSolicitud() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: _colorNaranja,
      duration: const Duration(seconds: 4),
      content: const Row(
        children: [
          Icon(Icons.notifications_active, color: Colors.white),
          SizedBox(width: 10),
          Text(
            '¡Nueva solicitud de ayuda recibida!',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    ));
  }

  void _mostrarBannerCancelacion(SolicitudAyuda s) {
    final nombre = s.tecnicoNombre.trim().isNotEmpty
        ? s.tecnicoNombre
        : 'Técnico (${s.rutTecnico})';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: _colorRojo,
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(12),
      content: Row(
        children: [
          const Icon(Icons.cancel_outlined, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$nombre canceló la solicitud de ${s.tipo.displayName}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
          backgroundColor: _colorFondo, body: _buildCargando());
    }
    if (_errorCarga != null) {
      return Scaffold(
          backgroundColor: _colorFondo,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: _buildError());
    }
    return Scaffold(
      backgroundColor: _colorFondo,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: _buildContenidoPrincipal(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCargando() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF00E5FF)),
          const SizedBox(height: 16),
          const Text(
            'Cargando solicitudes...',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            _rutSupervisor != null && _rutSupervisor!.isNotEmpty
                ? 'RUT: $_rutSupervisor'
                : 'Obteniendo sesión...',
            style: const TextStyle(color: Colors.white24, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off, color: Color(0xFFFF3B30), size: 48),
                  const SizedBox(height: 16),
                  Text(
                    _errorCarga ?? 'Error desconocido',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _cargarSolicitudes,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline,
                    color: Color(0xFF30D158), size: 56),
                SizedBox(height: 16),
                Text('Sin solicitudes pendientes',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w500)),
                SizedBox(height: 8),
                Text('Desliza para actualizar',
                    style: TextStyle(
                        color: Colors.white38, fontSize: 13)),
              ],
            ),
          ),
        ),
      ],
    );
  }


  // ─── App bar moderna ───────────────────────────────────────
  Widget _buildAppBar() {
    final pendientes =
        _solicitudes.where((s) => s.estado == EstadoSolicitud.pendiente).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _colorFondo,
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.08), width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.08),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        _nuevaAlerta
                            ? Icons.notifications_active
                            : Icons.help_outline_rounded,
                        key: ValueKey(_nuevaAlerta),
                        color: _nuevaAlerta ? _colorNaranja : _colorCyan,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Solicitudes de ayuda',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_solicitudes.length} solicitud${_solicitudes.length != 1 ? 'es' : ''}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _cargarSolicitudes,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: pendientes > 0
                    ? _colorRojo.withOpacity(0.9)
                    : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: pendientes > 0
                  ? Center(
                      child: Text(
                        '$pendientes',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : const Icon(Icons.refresh_rounded, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Contenido principal (lista de solicitudes) ───────────
  Widget _buildContenidoPrincipal() {
    final pendientes =
        _solicitudes.where((s) => s.estado == EstadoSolicitud.pendiente).toList();
    final enCamino =
        _solicitudes.where((s) => s.supervisorEnCamino).toList();
    final vigentes = [...pendientes, ...enCamino];

    final canceladasVisibles = _canceladasRecientes
        .where((s) => s.estado == EstadoSolicitud.cancelada)
        .toList();

    return Column(
      children: [
        if (_mensajeCancelacion != null)
          _buildBannerCancelacionActiva(_mensajeCancelacion!),
        if (pendientes.isNotEmpty)
          _AlertaBanner(
            count: pendientes.length,
            onTap: _ayudaService.reproducirAlerta,
          ),
        Expanded(
          child: vigentes.isEmpty && canceladasVisibles.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _cargarSolicitudes,
                  color: _colorCyan,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      24 + MediaQuery.of(context).padding.bottom + 40,
                    ),
                    children: [
                      if (canceladasVisibles.isNotEmpty) ...[
                        _buildSeccionLabel(
                            'CANCELADAS (${canceladasVisibles.length})',
                            _colorRojo),
                        ...canceladasVisibles
                            .map((s) => _buildTarjetaCancelada(s)),
                        const SizedBox(height: 16),
                      ],
                      if (pendientes.isNotEmpty) ...[
                        _buildSeccionLabel(
                            'PENDIENTES (${pendientes.length})',
                            _colorNaranja),
                        ...pendientes.map((s) => _buildTarjeta(s)),
                        const SizedBox(height: 16),
                      ],
                      if (enCamino.isNotEmpty) ...[
                        _buildSeccionLabel(
                            'EN CAMINO (${enCamino.length})',
                            _colorVerde),
                        ...enCamino.map((s) => _buildTarjeta(s)),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildBannerCancelacionActiva(String mensaje) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: _colorRojo.withOpacity(0.92),
      child: Row(
        children: [
          const Icon(Icons.cancel_outlined, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTarjetaCancelada(SolicitudAyuda s) {
    final nombre = s.tecnicoNombre.trim().isNotEmpty
        ? s.tecnicoNombre
        : 'Técnico (${s.rutTecnico})';
    final hora = DateFormat('HH:mm').format(s.fechaCreacion.toLocal());
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1218),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _colorRojo.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _colorRojo.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cancel_outlined,
                color: _colorRojo, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ayuda cancelada por el técnico',
                  style: TextStyle(
                    color: _colorRojo.withOpacity(0.95),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$nombre · ${s.tipo.displayName}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Solicitud enviada a las $hora',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionLabel(String texto, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        texto,
        style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5),
      ),
    );
  }

  CameraPosition _calcCamaraMini(SolicitudAyuda s) {
    final tLat = s.latTecnico;
    final tLng = s.lngTecnico;
    if (_miLat == null || _miLng == null) {
      return CameraPosition(target: LatLng(tLat, tLng), zoom: 14);
    }
    final centerLat = (tLat + _miLat!) / 2;
    final centerLng = (tLng + _miLng!) / 2;
    final maxDiff = math.max((tLat - _miLat!).abs(), (tLng - _miLng!).abs());
    final zoom = maxDiff < 0.005 ? 15.0
        : maxDiff < 0.02 ? 13.0
        : maxDiff < 0.05 ? 12.0
        : maxDiff < 0.1  ? 11.0
        : maxDiff < 0.3  ? 10.0
        : maxDiff < 1.0  ? 9.0
        : 7.0;
    return CameraPosition(target: LatLng(centerLat, centerLng), zoom: zoom);
  }

  Set<Marker> _marcadoresMini(SolicitudAyuda s) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('tecnico'),
        position: LatLng(s.latTecnico, s.lngTecnico),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
    };
    if (_miLat != null && _miLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('supervisor'),
        position: LatLng(_miLat!, _miLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    }
    return markers;
  }

  Widget _buildMiniMapa(SolicitudAyuda s, double? distanciaMia) {
    return GestureDetector(
      onTap: () {
        if (s.supervisorEnCamino) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => SupervisorTrackingScreen(solicitud: s, ticketId: s.ticketId),
          ));
        } else {
          _preguntarAbrirEnMapa(s);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 160,
          child: Stack(
            children: [
              GoogleMap(
                key: ValueKey('minimap_${s.ticketId}'),
                liteModeEnabled: true,
                initialCameraPosition: _calcCamaraMini(s),
                markers: _marcadoresMini(s),
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
                scrollGesturesEnabled: false,
                zoomGesturesEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
              ),
              // Badge distancia + tiempo
              if (distanciaMia != null)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _colorCyan.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.navigation_rounded, color: _colorCyan, size: 13),
                        const SizedBox(width: 5),
                        Text(
                          '${distanciaMia.toStringAsFixed(1)} km  ·  ~${(distanciaMia / 40 * 60).ceil()} min',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              // Badge acción
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        s.supervisorEnCamino ? Icons.directions_car_rounded : Icons.open_in_full_rounded,
                        color: Colors.white70,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        s.supervisorEnCamino ? 'Seguimiento' : 'Ampliar',
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTarjeta(SolicitudAyuda s, {bool opaco = false}) {
    final colorEstado = _colorPorEstado(s.estado);
    final horaEnvio = DateFormat('HH:mm').format(s.fechaCreacion.toLocal());
    final tiempoTranscurrido = _tiempoTranscurrido(s.fechaCreacion.toLocal());
    final distanciaMia = _distanciaATecnico(s);
    final colorTipo = _colorPorTipo(s.tipo);
    final esPendiente = s.estado == EstadoSolicitud.pendiente;
    final nombreTecnico = s.tecnicoNombre.trim().isNotEmpty
        ? s.tecnicoNombre
        : 'Técnico (RUT: ${s.rutTecnico})';
    final direccion = _direccionesCache[s.ticketId];

    // Disparar geocodificación si no está en cache
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_direccionesCache.containsKey(s.ticketId)) {
        _obtenerDireccionTecnico(s);
      }
    });

    return AnimatedOpacity(
      opacity: opaco ? 0.6 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF151F2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: esPendiente
                ? _colorNaranja.withOpacity(0.4)
                : colorEstado.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Encabezado: tipo de ayuda + tiempo ───────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorTipo.withOpacity(0.15),
                      colorTipo.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorTipo.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_iconoPorTipo(s.tipo),
                          color: colorTipo, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s.tipo.displayName.toUpperCase(),
                        style: TextStyle(
                          color: colorTipo,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: esPendiente
                            ? _colorNaranja.withOpacity(0.2)
                            : Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule_rounded,
                              size: 14,
                              color: esPendiente ? _colorNaranja : Colors.white54),
                          const SizedBox(width: 4),
                          Text(
                            tiempoTranscurrido,
                            style: TextStyle(
                              color: esPendiente ? _colorNaranja : Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      horaEnvio,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Cuerpo: nombre técnico destacado + detalles ───
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nombre del técnico (destacado)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _colorCyan.withOpacity(0.3),
                                _colorCyan.withOpacity(0.1),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              nombreTecnico.isNotEmpty
                                  ? nombreTecnico[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: _colorCyan,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nombreTecnico,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'RUT: ${s.rutTecnico}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              if (direccion != null) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.location_on_rounded,
                                        size: 14,
                                        color: _colorCyan.withOpacity(0.9)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        direccion,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                          fontSize: 12,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else
                                const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _colorCyan,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: colorEstado.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: colorEstado.withOpacity(0.3)),
                          ),
                          child: Text(
                            s.estado.displayName.toUpperCase(),
                            style: TextStyle(
                              color: colorEstado,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Mini-mapa con ubicación del técnico y supervisor
                    _buildMiniMapa(s, distanciaMia),
                    const SizedBox(height: 8),
                    if (s.latTecnico != null && s.lngTecnico != null)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _preguntarAbrirEnMapa(s),
                          icon: const Icon(Icons.map_outlined, size: 16),
                          label: const Text('Abrir en Google Maps',
                              style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _colorCyan,
                            side: BorderSide(color: _colorCyan.withOpacity(0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),

                    // Botones de respuesta
                    if (esPendiente) ...[
                      const SizedBox(height: 16),
                      _buildBotonesRespuesta(s),
                    ],

                    // Botones cuando supervisor en camino: Llegué (si no marcado) + Completar
                    if (s.supervisorEnCamino) ...[
                      const SizedBox(height: 16),
                      Consumer<EstadoSupervisorService>(
                        builder: (context, estadoSvc, _) {
                          final yaLlego = estadoSvc.estadoActual?.actividad == 'ejecutando' &&
                              estadoSvc.estadoActual?.ticketIdActivo == s.ticketId;
                          return Row(
                            children: [
                              if (!yaLlego) ...[
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _marcarLlegada(s),
                                    icon: const Icon(Icons.location_on, size: 18),
                                    label: const Text('Llegué'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _colorCyan,
                                      side: BorderSide(color: _colorCyan.withOpacity(0.5)),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _completarAyuda(s),
                                  icon: const Icon(Icons.check_circle, size: 18),
                                  label: const Text('Completar'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _colorVerde,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],

                    // Respuesta enviada
                    if (s.respuestaMensaje != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _colorVerde.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _colorVerde.withOpacity(0.2)),
                        ),
                        child: Text(
                          '"${s.respuestaMensaje}"',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                    if (s.tiempoExtraMinutos != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded,
                              color: _colorNaranja, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Demora extra: ${s.tiempoExtraMinutos} min',
                            style: TextStyle(
                              color: _colorNaranja,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBotonesRespuesta(SolicitudAyuda s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Fila 1: Aceptar | Con demora
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _responder(s, EstadoSolicitud.aceptada),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Aceptar', style: TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _colorVerde,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _mostrarDialogoConTiempo(s),
                icon: const Icon(Icons.schedule, size: 18),
                label: const Text('Con demora', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _colorNaranja,
                  side: BorderSide(color: _colorNaranja.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Fila 2: Rechazar | Traspasar
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _responder(s, EstadoSolicitud.rechazada),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Rechazar', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _colorRojo,
                  side: BorderSide(color: _colorRojo.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _mostrarDialogoTraspasar(s),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Traspasar', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _colorCyan,
                  side: BorderSide(color: _colorCyan.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _mostrarDialogoTraspasar(SolicitudAyuda s) async {
    if (_rutSupervisor == null || _rutSupervisor!.isEmpty) return;
    final supervisores =
        await _ayudaService.obtenerSupervisoresParaTraspasar(_rutSupervisor!);
    if (!mounted) return;
    if (supervisores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No hay otros supervisores/ITOs disponibles'),
        backgroundColor: _colorNaranja,
      ));
      return;
    }
    final seleccionado = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: const Color(0xFF1A2C3D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.6;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Traspasar a',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(
                height: maxH,
                child: ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).padding.bottom + 16,
                  ),
                  itemCount: supervisores.length,
                  itemBuilder: (_, i) {
                    final sup = supervisores[i];
                    final esIto = sup['tipo'] == 'ITO';
                    return ListTile(
                      leading: Icon(
                        esIto ? Icons.engineering : Icons.supervisor_account,
                        color: esIto
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF00E5FF),
                      ),
                      title: Text(
                        sup['nombre'] ?? sup['rut'] ?? '',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${sup['tipo'] ?? 'Supervisor'} · ${sup['rut'] ?? ''}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                      onTap: () => Navigator.pop(ctx, sup),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (seleccionado == null || !mounted) return;
    final ok = await _ayudaService.traspasarTicket(
      s.ticketId,
      seleccionado['rut']!,
      seleccionado['nombre'] ?? seleccionado['rut']!,
    );
    if (mounted) {
      if (ok) {
        _solicitudes = _ayudaService.solicitudesSupervisor;
        _ticketsAceptadosTracking.remove(s.ticketId);
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Solicitud traspasada a ${seleccionado['nombre'] ?? ''}'),
          backgroundColor: _colorVerde,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error al traspasar. Intenta nuevamente.'),
          backgroundColor: _colorRojo,
        ));
      }
    }
  }

  Future<void> _marcarLlegada(SolicitudAyuda s) async {
    if (_rutSupervisor == null || _rutSupervisor!.isEmpty) return;
    try {
      _ticketsLlegadaAutoMarcada.add(s.ticketId);
      await EstadoSupervisorService().marcarLlegadaAyuda(
        rutSupervisor: _rutSupervisor!,
        ticketId: s.ticketId,
        nombreTecnico: s.tecnicoNombre ?? 'Técnico',
      );
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Marcado como llegada'),
          backgroundColor: _colorVerde,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: _colorRojo,
        ));
      }
    }
  }

  Future<void> _completarAyuda(SolicitudAyuda s) async {
    if (_rutSupervisor == null || _rutSupervisor!.isEmpty) return;
    final ok = await _ayudaService.completarAyudaSupervisor(
        s.ticketId, _rutSupervisor!);
    if (mounted) {
      if (ok) {
        _ticketsAceptadosTracking.remove(s.ticketId);
        _solicitudes = _ayudaService.solicitudesSupervisor;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ayuda completada'),
          backgroundColor: _colorVerde,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error al completar. Intenta de nuevo.'),
          backgroundColor: _colorRojo,
        ));
      }
    }
  }

  Future<void> _responder(
      SolicitudAyuda s, EstadoSolicitud estado,
      {int? tiempoExtra, String? mensaje}) async {
    await _ayudaService.detenerAlerta();
    await AyudaAlertaEstado.markSeen(s.ticketId);

    final esAceptacion = estado == EstadoSolicitud.aceptada ||
        estado == EstadoSolicitud.aceptadaConTiempo;
    // Si acepta y no tenemos GPS, obtenerlo antes para que el técnico vea distancia/ETA
    if (esAceptacion && (_miLat == null || _miLng == null)) {
      await _obtenerGpsPropio();
    }
    final ok = await _ayudaService.responderSolicitud(
      ticketId: s.ticketId,
      estado: estado,
      tiempoExtraMinutos: tiempoExtra,
      mensaje: mensaje,
      latSupervisor: esAceptacion ? _miLat : null,
      lngSupervisor: esAceptacion ? _miLng : null,
      nombreSupervisor: esAceptacion ? _nombreSupervisor : null,
      rutSupervisor: _rutSupervisor,
      rutTecnico: s.rutTecnico,
      nombreTecnico: s.tecnicoNombre,
      tipoAyuda: s.tipo.value,
    );
    // Si aceptó, iniciar tracking de GPS para esta solicitud
    if (ok && esAceptacion) {
      _ticketsAceptadosTracking.add(s.ticketId);
      // Actualizar GPS inmediatamente para que el técnico vea distancia/ETA
      // (no esperar al ciclo de 45s)
      _actualizarGpsYTracking();
    }

    if (mounted) {
      if (ok) {
        // Actualizar lista y marcadores en un solo setState para evitar
        // double-rebuild que deja pantalla negra momentánea
        _solicitudes = _solicitudes.map((item) {
          if (item.ticketId == s.ticketId) {
            return item.copyWith(
              estado: estado,
              tiempoExtraMinutos: tiempoExtra,
              respuestaMensaje: mensaje,
            );
          }
          return item;
        }).toList();
        if (mounted) setState(() {});

        // Al aceptar → navegar directo al mapa de tracking
        if (esAceptacion && mounted) {
          final solicitudActualizada = s.copyWith(
            estado: estado,
            tiempoExtraMinutos: tiempoExtra,
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SupervisorTrackingScreen(
                solicitud: solicitudActualizada,
                ticketId: s.ticketId,
              ),
            ),
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Solicitud ${estado.displayName.toLowerCase()}'),
          backgroundColor: _colorVerde,
          duration: const Duration(seconds: 2),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error al responder. Intenta nuevamente.'),
          backgroundColor: Color(0xFFFF3B30),
        ));
      }
    }
  }

  Future<void> _preguntarAbrirEnMapa(SolicitudAyuda s) async {
    await _ayudaService.detenerAlerta();
    await AyudaAlertaEstado.markSeen(s.ticketId);

    final abrir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2C3D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.map, color: Color(0xFF00E5FF), size: 24),
            SizedBox(width: 10),
            Text('Abrir ubicación',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Text(
          '¿Abrir Google Maps con ruta hacia ${s.tecnicoNombre}?',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
            ),
            child: const Text('Sí, abrir'),
          ),
        ],
      ),
    );
    if (abrir != true || !mounted) return;
    // URL de direcciones: origen=supervisor, destino=técnico (modo conducción)
    // Si no tenemos GPS del supervisor, usa solo destino (Maps tomará ubicación actual)
    final dest = '${s.latTecnico},${s.lngTecnico}';
    final mapsDirUrl = Uri.parse(
      _miLat != null && _miLng != null
          ? 'https://www.google.com/maps/dir/?api=1'
            '&origin=${_miLat},${_miLng}'
            '&destination=$dest'
            '&travelmode=driving'
          : 'https://www.google.com/maps/dir/?api=1'
            '&destination=$dest'
            '&travelmode=driving',
    );
    final geoUri = Uri.parse('geo:$dest?q=$dest');
    try {
      if (await canLaunchUrl(mapsDirUrl)) {
        await launchUrl(mapsDirUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo abrir el mapa. Instala Google Maps.'),
          backgroundColor: Color(0xFFFF9500),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al abrir mapa: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _mostrarDialogoConTiempo(SolicitudAyuda s) async {
    int minutos = 15;
    String mensaje = '';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: const Color(0xFF1A2C3D),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Aceptar con demora',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('¿Cuántos minutos adicionales necesitas?',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              // Selector de tiempo
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () =>
                        setLocal(() => minutos = (minutos - 5).clamp(5, 120)),
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Color(0xFF00E5FF)),
                  ),
                  Text(
                    '$minutos min',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () =>
                        setLocal(() => minutos = (minutos + 5).clamp(5, 120)),
                    icon: const Icon(Icons.add_circle_outline,
                        color: Color(0xFF00E5FF)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => mensaje = v,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Mensaje opcional...',
                  hintStyle:
                      const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _colorNaranja,
                  foregroundColor: Colors.black),
              child: const Text('Confirmar',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await _responder(
        s,
        EstadoSolicitud.aceptadaConTiempo,
        tiempoExtra: minutos,
        mensaje: mensaje.isNotEmpty ? mensaje : null,
      );
    }
  }

  Color _colorPorEstado(EstadoSolicitud e) {
    return switch (e) {
      EstadoSolicitud.pendiente => _colorAmbar,
      EstadoSolicitud.aceptada => _colorVerde,
      EstadoSolicitud.rechazada => _colorRojo,
      EstadoSolicitud.aceptadaConTiempo => _colorNaranja,
      EstadoSolicitud.cancelada => Colors.white38,
      EstadoSolicitud.completada => _colorVerde,
    };
  }

  IconData _iconoPorTipo(TipoAyuda tipo) {
    return switch (tipo) {
      TipoAyuda.zonaRoja => Icons.warning_amber,
      TipoAyuda.crucePeligroso => Icons.traffic,
      TipoAyuda.ducto => Icons.block,
      TipoAyuda.fusion => Icons.cable,
      TipoAyuda.altura => Icons.height,
    };
  }

  Color _colorPorTipo(TipoAyuda tipo) {
    return switch (tipo) {
      TipoAyuda.zonaRoja       => _colorRojo,
      TipoAyuda.crucePeligroso => _colorNaranja,
      TipoAyuda.ducto          => _colorAmbar,
      TipoAyuda.fusion         => _colorCyan,
      TipoAyuda.altura         => _colorVerde,
    };
  }

}

// ─────────────────────────────────────────────────────────────
// Widget: Banner animado de alertas pendientes
// ─────────────────────────────────────────────────────────────

class _AlertaBanner extends StatefulWidget {
  final int count;
  final Future<void> Function() onTap;
  const _AlertaBanner({required this.count, required this.onTap});

  @override
  State<_AlertaBanner> createState() => _AlertaBannerState();
}

class _AlertaBannerState extends State<_AlertaBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => widget.onTap(),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Color.lerp(
              const Color(0xFFFF9500), const Color(0xFFFF6B00), _pulse.value),
          child: child,
        ),
        child: Row(
          children: [
            const Icon(Icons.notifications_active,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${widget.count} solicitud${widget.count > 1 ? 'es' : ''} '
                'pendiente${widget.count > 1 ? 's' : ''} de atención',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ),
            const Icon(Icons.volume_up, color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }
}

