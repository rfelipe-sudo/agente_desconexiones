import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:agente_desconexiones/constants/app_colors.dart';
import 'package:agente_desconexiones/models/solicitud_ayuda.dart';
import 'package:agente_desconexiones/services/ayuda_service.dart';
import 'package:agente_desconexiones/screens/ayuda_terreno_screen.dart';

/// Pantalla de tracking de solicitud de ayuda con mapa real
class AyudaTrackingScreen extends StatefulWidget {
  final SolicitudAyuda solicitud;

  const AyudaTrackingScreen({
    super.key,
    required this.solicitud,
  });

  @override
  State<AyudaTrackingScreen> createState() => _AyudaTrackingScreenState();
}

class _AyudaTrackingScreenState extends State<AyudaTrackingScreen> {
  GoogleMapController? _mapController;
  Position? _tecnicoPosition;
  bool _isLoadingLocation = true;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  List<Map<String, dynamic>> _supervisoresDisponibles = [];
  String? _supervisorAsignadoId;
  Timer? _pollingSupervisores;
  Timer? _pollingSupervisorAsignado; // Polling especÃ­fico para supervisor asignado
  double? _distanciaActual;
  int? _etaMinutos;
  
  // Iconos personalizados para marcadores
  BitmapDescriptor? _iconoTecnico;
  BitmapDescriptor? _iconoSupervisorAsignado;
  BitmapDescriptor? _iconoSupervisorOcupado;
  BitmapDescriptor? _iconoSupervisorDisponible;

  @override
  void initState() {
    super.initState();
    
    // Crear iconos personalizados
    _crearIconosPersonalizados();
    
    // Obtener ubicaciÃ³n del tÃ©cnico de forma segura
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _obtenerUbicacionTecnico();
      }
    });
    
    // Cargar supervisores despuÃ©s de un pequeÃ±o delay para asegurar que el contexto estÃ© listo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          _cargarSupervisoresDisponibles();
          
          // Recargar supervisores cada 10 segundos
          _pollingSupervisores = Timer.periodic(const Duration(seconds: 10), (_) {
            if (mounted) {
              _cargarSupervisoresDisponibles();
            }
          });
          
          // Iniciar polling de supervisor asignado si existe
          _iniciarPollingSupervisorAsignado();
        } catch (e) {
          debugPrint('âŒ Error en initState de ayuda_tracking: $e');
        }
      }
    });
  }

  /// Crear iconos personalizados modernos para los marcadores
  Future<void> _crearIconosPersonalizados() async {
    try {
      // Icono del tÃ©cnico (azul con cÃ­rculo)
      _iconoTecnico = await _crearIconoMarcador(
        color: const Color(0xFF2196F3),
        icono: Icons.person,
        tamano: 80,
      );
      
      // Icono supervisor asignado (verde con pulso)
      _iconoSupervisorAsignado = await _crearIconoMarcador(
        color: const Color(0xFF4CAF50),
        icono: Icons.support_agent,
        tamano: 90,
      );
      
      // Icono supervisor ocupado (rojo)
      _iconoSupervisorOcupado = await _crearIconoMarcador(
        color: const Color(0xFFF44336),
        icono: Icons.person_off,
        tamano: 70,
      );
      
      // Icono supervisor disponible (gris claro)
      _iconoSupervisorDisponible = await _crearIconoMarcador(
        color: const Color(0xFF9E9E9E),
        icono: Icons.person_outline,
        tamano: 70,
      );
    } catch (e) {
      debugPrint('âŒ Error creando iconos personalizados: $e');
      // Usar iconos por defecto si falla
    }
  }

  /// Crear un icono personalizado para marcador
  Future<BitmapDescriptor> _crearIconoMarcador({
    required Color color,
    required IconData icono,
    required double tamano,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(tamano, tamano);
    
    // Sombra
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2 + 2),
      size.width / 2 - 4,
      shadowPaint,
    );
    
    // CÃ­rculo principal con gradiente radial
    final gradient = ui.Gradient.radial(
      Offset(size.width / 2, size.height / 2),
      size.width / 2 - 6,
      [
        color,
        color.withOpacity(0.8),
      ],
    );
    
    final gradientPaint = Paint()
      ..shader = gradient
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2 - 6,
      gradientPaint,
    );
    
    // Borde blanco grueso
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2 - 6,
      borderPaint,
    );
    
    // CÃ­rculo interno blanco como indicador
    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      tamano * 0.12,
      iconPaint,
    );
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  /// Inicia polling para actualizar ubicaciÃ³n del supervisor asignado cada 3 segundos
  void _iniciarPollingSupervisorAsignado() {
    if (!mounted) return;
    
    try {
      final ayudaService = Provider.of<AyudaService>(context, listen: false);
      final solicitud = ayudaService.solicitudActual ?? widget.solicitud;
      
      if (solicitud.rutSupervisor != null) {
        _supervisorAsignadoId = solicitud.rutSupervisor;
        
        // Polling cada 3 segundos para actualizar ubicaciÃ³n del supervisor
        _pollingSupervisorAsignado = Timer.periodic(const Duration(seconds: 3), (_) {
          if (mounted) {
            _actualizarUbicacionSupervisor();
          }
        });
      }
    } catch (e) {
      debugPrint('âŒ Error iniciando polling supervisor: $e');
    }
  }

  /// Actualiza la ubicaciÃ³n del supervisor asignado y recalcula ETA
  Future<void> _actualizarUbicacionSupervisor() async {
    if (!mounted) return;
    
    try {
      final ayudaService = Provider.of<AyudaService>(context, listen: false);
      final solicitud = ayudaService.solicitudActual ?? widget.solicitud;
      
      // Si no hay supervisor asignado, detener polling
      if (solicitud.rutSupervisor == null) {
        _pollingSupervisorAsignado?.cancel();
        _pollingSupervisorAsignado = null;
        return;
      }
      
      // Consultar estado actualizado (incluye nueva ubicaciÃ³n del supervisor)
      await ayudaService.consultarEstado();
      
      final solicitudActualizada = ayudaService.solicitudActual ?? solicitud;
      
      if (mounted && _tecnicoPosition != null) {
        // Calcular distancia y ETA si tenemos ambas ubicaciones
        if (solicitudActualizada.latSupervisor != null &&
            solicitudActualizada.lngSupervisor != null) {
          // Calcular distancia
          final distancia = Geolocator.distanceBetween(
            _tecnicoPosition!.latitude,
            _tecnicoPosition!.longitude,
            solicitudActualizada.latSupervisor!,
            solicitudActualizada.lngSupervisor!,
          ) / 1000; // Convertir a km
          
          // Calcular ETA (asumiendo velocidad promedio de 50 km/h en ciudad)
          // O usar el ETA del servidor si estÃ¡ disponible
          final eta = solicitudActualizada.tiempoExtraMinutos ?? 
              (distancia / 50 * 60).round(); // km / (km/h) * 60 = minutos
          
          setState(() {
            _distanciaActual = distancia;
            _etaMinutos = eta;
          });
          
          // Actualizar mapa con nueva posiciÃ³n
          _actualizarMapa();
        }
      }
    } catch (e) {
      debugPrint('âŒ Error actualizando ubicaciÃ³n supervisor: $e');
    }
  }

  Future<void> _obtenerUbicacionTecnico() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _tecnicoPosition = position;
        _isLoadingLocation = false;
      });
      _actualizarMapa();
    } catch (e) {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  Future<void> _cargarSupervisoresDisponibles() async {
    if (!mounted) return;
    
    try {
      final solicitud = Provider.of<AyudaService>(context, listen: false)
          .solicitudActual ?? widget.solicitud;
      
      final ayudaService = Provider.of<AyudaService>(context, listen: false);
      final supervisores = await ayudaService.obtenerSupervisoresDisponibles(
        latitud: solicitud.latTecnico,
        longitud: solicitud.lngTecnico,
      );
      
      if (mounted) {
        setState(() {
          _supervisoresDisponibles = supervisores;
          // Guardar ID del supervisor asignado si existe
          _supervisorAsignadoId = solicitud.rutSupervisor;
        });
        _actualizarMapa();
      }
    } catch (e) {
      debugPrint('âŒ Error cargando supervisores: $e');
      // Continuar sin supervisores si hay error
      if (mounted) {
        setState(() {
          _supervisoresDisponibles = [];
        });
      }
    }
  }

  void _actualizarMapa() {
    final solicitud = Provider.of<AyudaService>(context, listen: false)
        .solicitudActual ?? widget.solicitud;

    _markers.clear();
    _polylines.clear();

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // MARCADOR DEL TÃ‰CNICO (MODERNO)
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    if (_tecnicoPosition != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('tecnico'),
          position: LatLng(
            _tecnicoPosition!.latitude,
            _tecnicoPosition!.longitude,
          ),
          icon: _iconoTecnico ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(
            title: 'ðŸ“ TÃº',
            snippet: 'Tu ubicaciÃ³n actual',
          ),
          anchor: const Offset(0.5, 0.5),
        ),
      );
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // AGREGAR TODOS LOS SUPERVISORES/ITOs AL MAPA
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    for (final supervisor in _supervisoresDisponibles) {
      final supervisorId = supervisor['id'] as String;
      final nombre = supervisor['nombre'] as String;
      final lat = supervisor['latitud'] as double;
      final lng = supervisor['longitud'] as double;
      final estaAtendiendo = supervisor['esta_atendiendo'] as bool;
      final tipo = supervisor['tipo'] as String;
      final esAsignado = supervisorId == _supervisorAsignadoId;

      // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
      // MARCADORES DE SUPERVISORES (MODERNOS)
      // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
      BitmapDescriptor icono;
      String estado;
      String emoji;
      
      if (esAsignado) {
        // VERDE: Supervisor/ITO asignado a esta solicitud
        icono = _iconoSupervisorAsignado ?? 
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
        estado = 'Asignado a tu solicitud';
        emoji = 'âœ…';
      } else if (estaAtendiendo) {
        // ROJO: Atendiendo otra solicitud
        icono = _iconoSupervisorOcupado ?? 
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
        estado = 'Atendiendo otra solicitud';
        emoji = 'ðŸ”´';
      } else {
        // GRIS: Disponible
        icono = _iconoSupervisorDisponible ?? 
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
        estado = 'Disponible';
        emoji = 'âšª';
      }

      _markers.add(
        Marker(
          markerId: MarkerId('supervisor_$supervisorId'),
          position: LatLng(lat, lng),
          icon: icono,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(
            title: '$emoji $nombre',
            snippet: '$tipo - $estado',
          ),
        ),
      );
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // AGREGAR RUTA Y MARCADOR DEL SUPERVISOR ASIGNADO
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    if (solicitud.latSupervisor != null &&
        solicitud.lngSupervisor != null) {
      // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
      // MARCADOR DEL SUPERVISOR ASIGNADO (MODERNO CON PULSO)
      // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
      _markers.add(
        Marker(
          markerId: const MarkerId('supervisor_asignado'),
          position: LatLng(
            solicitud.latSupervisor!,
            solicitud.lngSupervisor!,
          ),
          icon: _iconoSupervisorAsignado ?? 
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(
            title: 'âœ… ${solicitud.supervisorNombre ?? 'Supervisor'}',
            snippet: solicitud.estado == EstadoSolicitud.aceptada
                ? 'En camino hacia ti'
                : 'Asignado a tu solicitud',
          ),
        ),
      );
      
      // Agregar ruta si tenemos ubicaciÃ³n del tÃ©cnico
      if (_tecnicoPosition != null) {
        _obtenerRuta(
          LatLng(_tecnicoPosition!.latitude, _tecnicoPosition!.longitude),
          LatLng(
            solicitud.latSupervisor!,
            solicitud.lngSupervisor!,
          ),
        );
      }
    }

    setState(() {});

    // Ajustar cÃ¡mara para mostrar todos los marcadores
    if (_markers.isNotEmpty && _mapController != null) {
      _ajustarCamara();
    }
  }

  Future<void> _obtenerRuta(LatLng origen, LatLng destino) async {
    if (!mounted) return;
    
    try {
      // Limpiar ruta anterior
      _polylines.removeWhere((p) => p.polylineId == const PolylineId('ruta'));
      
      // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
      // OBTENER RUTA REAL USANDO GOOGLE DIRECTIONS API
      // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
      const apiKey = 'AIzaSyCqWYl4MzfnLi6okjCJozltYT6ssnHdXvY';
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=${origen.latitude},${origen.longitude}&'
        'destination=${destino.latitude},${destino.longitude}&'
        'key=$apiKey&'
        'language=es&'
        'units=metric',
      );
      
      try {
        final response = await http.get(url).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('Timeout al obtener ruta');
          },
        );
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          
          if (data['status'] == 'OK' && 
              data['routes'] != null && 
              (data['routes'] as List).isNotEmpty) {
            final route = data['routes'][0];
            final overviewPolyline = route['overview_polyline'] as Map<String, dynamic>;
            final encodedPoints = overviewPolyline['points'] as String;
            
            // Decodificar polyline
            final points = _decodePolyline(encodedPoints);
            
            if (points.isNotEmpty && mounted) {
              _polylines.add(
                Polyline(
                  polylineId: const PolylineId('ruta'),
                  points: points,
                  color: const Color(0xFF4CAF50), // Verde para la ruta
                  width: 7,
                  patterns: [PatternItem.dash(50), PatternItem.gap(20)],
                  geodesic: true,
                  jointType: JointType.round,
                  endCap: Cap.roundCap,
                  startCap: Cap.roundCap,
                ),
              );
              
              // Obtener duraciÃ³n y distancia de la ruta
              final legs = route['legs'] as List<dynamic>?;
              if (legs != null && legs.isNotEmpty) {
                final leg = legs[0];
                final duration = leg['duration'] as Map<String, dynamic>?;
                final distance = leg['distance'] as Map<String, dynamic>?;
                
                if (duration != null && distance != null && mounted) {
                  final durationValue = duration['value'] as int?; // en segundos
                  final distanceValue = distance['value'] as int?; // en metros
                  
                  if (durationValue != null && distanceValue != null) {
                    setState(() {
                      _etaMinutos = (durationValue / 60).round();
                      _distanciaActual = distanceValue / 1000; // convertir a km
                    });
                  }
                }
              }
              
              debugPrint('âœ… Ruta obtenida: ${points.length} puntos');
            } else {
              throw Exception('No se pudieron decodificar los puntos de la ruta');
            }
          } else {
            debugPrint('âš ï¸ No se encontrÃ³ ruta: ${data['status']}');
            throw Exception('No se encontrÃ³ ruta: ${data['status']}');
          }
        } else {
          throw Exception('Error HTTP: ${response.statusCode}');
        }
      } on TimeoutException {
        debugPrint('âš ï¸ Timeout obteniendo ruta, usando lÃ­nea recta');
        throw TimeoutException('Timeout');
      } catch (e) {
        debugPrint('âš ï¸ Error obteniendo ruta real: $e');
        throw e;
      }
    } catch (e) {
      // Fallback: usar lÃ­nea recta si falla la API (mejorada visualmente)
      debugPrint('âš ï¸ Usando lÃ­nea recta como fallback: $e');
      if (mounted) {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('ruta'),
            points: [origen, destino],
            color: const Color(0xFF4CAF50),
            width: 6,
            patterns: [PatternItem.dash(40), PatternItem.gap(15)],
            geodesic: true,
            jointType: JointType.round,
            endCap: Cap.roundCap,
            startCap: Cap.roundCap,
          ),
        );
        setState(() {});
      }
    }
    
    if (mounted) {
      // Centrar cÃ¡mara en la ruta si hay supervisor asignado
      if (_mapController != null && _markers.length >= 2) {
        _ajustarCamara();
      }
    }
  }

  /// Decodifica un polyline codificado de Google Maps
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  void _ajustarCamara() {
    if (_mapController == null || _markers.isEmpty) return;

    // Si hay supervisor asignado, centrar en tÃ©cnico y supervisor
    // Si no, mostrar todos los marcadores
    final solicitud = Provider.of<AyudaService>(context, listen: false)
        .solicitudActual ?? widget.solicitud;
    
    if (solicitud.latSupervisor != null && 
        solicitud.lngSupervisor != null &&
        _tecnicoPosition != null) {
      // Centrar en tÃ©cnico y supervisor asignado
      final supervisorPos = LatLng(
        solicitud.latSupervisor!,
        solicitud.lngSupervisor!,
      );
      final tecnicoPos = LatLng(
        _tecnicoPosition!.latitude,
        _tecnicoPosition!.longitude,
      );
      
      double minLat = tecnicoPos.latitude < supervisorPos.latitude 
          ? tecnicoPos.latitude 
          : supervisorPos.latitude;
      double maxLat = tecnicoPos.latitude > supervisorPos.latitude 
          ? tecnicoPos.latitude 
          : supervisorPos.latitude;
      double minLng = tecnicoPos.longitude < supervisorPos.longitude 
          ? tecnicoPos.longitude 
          : supervisorPos.longitude;
      double maxLng = tecnicoPos.longitude > supervisorPos.longitude 
          ? tecnicoPos.longitude 
          : supervisorPos.longitude;
      
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - 0.005, minLng - 0.005),
            northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
          ),
          100.0, // padding en pÃ­xeles
        ),
      );
    } else {
      // Mostrar todos los marcadores
      double minLat = double.infinity;
      double maxLat = -double.infinity;
      double minLng = double.infinity;
      double maxLng = -double.infinity;

      for (var marker in _markers) {
        minLat = minLat < marker.position.latitude ? minLat : marker.position.latitude;
        maxLat = maxLat > marker.position.latitude ? maxLat : marker.position.latitude;
        minLng = minLng < marker.position.longitude ? minLng : marker.position.longitude;
        maxLng = maxLng > marker.position.longitude ? maxLng : marker.position.longitude;
      }

      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - 0.01, minLng - 0.01),
            northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
          ),
          100.0, // padding en pÃ­xeles
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<AyudaService>(
        builder: (context, ayudaService, _) {
          final solicitud = ayudaService.solicitudActual ?? widget.solicitud;

          // Actualizar supervisor asignado si cambiÃ³ y recargar supervisores
          if (solicitud.rutSupervisor != _supervisorAsignadoId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              setState(() {
                _supervisorAsignadoId = solicitud.rutSupervisor;
              });
              _cargarSupervisoresDisponibles();
              
              // Iniciar polling de supervisor si se asignÃ³ uno
              if (solicitud.rutSupervisor != null) {
                _iniciarPollingSupervisorAsignado();
              } else {
                // Detener polling si se cancelÃ³ la asignaciÃ³n
                _pollingSupervisorAsignado?.cancel();
                _pollingSupervisorAsignado = null;
              }
            });
          }
          
          // Actualizar mapa cuando cambie la solicitud
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _actualizarMapa();
          });

          return Stack(
            children: [
              // Mapa de fondo (pantalla completa)
              _buildMapaView(solicitud),
              
              // Barra superior estilo Uber
              SafeArea(
                child: Column(
                  children: [
                    _buildTopBar(context, solicitud),
                    const SizedBox(height: 16),
                    // Barra de bÃºsqueda estilo Uber
                    _buildSearchBar(solicitud),
                  ],
                ),
              ),
              
              // Tarjeta inferior con informaciÃ³n del supervisor
              if (solicitud.supervisorNombre != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildSupervisorCard(solicitud),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Barra superior estilo Uber
  Widget _buildTopBar(BuildContext context, SolicitudAyuda solicitud) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // BotÃ³n de cerrar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => _cancelarSolicitud(context),
            ),
          ),
          const Spacer(),
          // Estado de la solicitud
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _getEstadoColor(solicitud.estado).withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Text(
              _getEstadoTexto(solicitud.estado),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Barra de bÃºsqueda estilo Uber
  Widget _buildSearchBar(SolicitudAyuda solicitud) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              solicitud.supervisorNombre != null
                  ? 'Supervisor asignado: ${solicitud.supervisorNombre}'
                  : 'Buscando supervisor cercano...',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          if (solicitud.supervisorNombre != null)
            const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 24),
        ],
      ),
    );
  }

  Color _getEstadoColor(EstadoSolicitud estado) {
    switch (estado) {
      case EstadoSolicitud.pendiente:
        return Colors.orange;
      case EstadoSolicitud.aceptada:
        return Colors.purple;
      case EstadoSolicitud.aceptadaConTiempo:
        return Colors.green;
      case EstadoSolicitud.rechazada:
      case EstadoSolicitud.cancelada:
        return Colors.red;
      case EstadoSolicitud.completada:
        return Colors.green;
    }
  }

  String _getEstadoTexto(EstadoSolicitud estado) {
    switch (estado) {
      case EstadoSolicitud.pendiente:
        return 'Buscando...';
      case EstadoSolicitud.aceptada:
        return 'En camino';
      case EstadoSolicitud.aceptadaConTiempo:
        return 'Con demora';
      case EstadoSolicitud.rechazada:
        return 'Rechazada';
      case EstadoSolicitud.cancelada:
        return 'Cancelada';
      case EstadoSolicitud.completada:
        return 'Completada';
    }
  }

  Widget _buildEstadoCard(SolicitudAyuda solicitud) {
    Color estadoColor;
    IconData estadoIcon;
    String estadoTexto;

    switch (solicitud.estado) {
      case EstadoSolicitud.pendiente:
        estadoColor = Colors.orange;
        estadoIcon = Icons.access_time;
        estadoTexto = 'Buscando supervisor cercano...';
        break;
      case EstadoSolicitud.aceptada:
        estadoColor = Colors.purple;
        estadoIcon = Icons.directions_car;
        estadoTexto = 'Supervisor en camino';
        break;
      case EstadoSolicitud.aceptadaConTiempo:
        estadoColor = Colors.green;
        estadoIcon = Icons.near_me;
        estadoTexto = 'Supervisor con demora';
        break;
      case EstadoSolicitud.rechazada:
        estadoColor = Colors.red;
        estadoIcon = Icons.cancel;
        estadoTexto = 'Solicitud rechazada';
        break;
      case EstadoSolicitud.completada:
        estadoColor = Colors.green;
        estadoIcon = Icons.check_circle;
        estadoTexto = 'Ayuda completada';
        break;
      case EstadoSolicitud.cancelada:
        estadoColor = Colors.red;
        estadoIcon = Icons.cancel;
        estadoTexto = 'Solicitud cancelada';
        break;
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: estadoColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(estadoIcon, color: estadoColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  estadoTexto,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (solicitud.respuestaMensaje != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    solicitud.respuestaMensaje!,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.1);
  }

  Widget _buildMapaView(SolicitudAyuda solicitud) {
    if (_isLoadingLocation) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    // Centro inicial (tÃ©cnico o supervisor si estÃ¡ asignado)
    LatLng centro = _tecnicoPosition != null
        ? LatLng(_tecnicoPosition!.latitude, _tecnicoPosition!.longitude)
        : LatLng(solicitud.latTecnico, solicitud.lngTecnico);

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: centro,
        zoom: 15,
        tilt: 0.0, // Sin inclinaciÃ³n para estilo Uber
        bearing: 0.0,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
        // Aplicar estilo personalizado al mapa
        _aplicarEstiloMapa(controller);
        // PequeÃ±o delay para asegurar que el mapa estÃ© completamente inicializado
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _actualizarMapa();
          }
        });
      },
      markers: _markers,
      polylines: _polylines,
      myLocationEnabled: true,
      myLocationButtonEnabled: false, // Ocultar botÃ³n de ubicaciÃ³n (estilo Uber)
      mapType: MapType.normal,
      zoomControlsEnabled: false,
      compassEnabled: false, // Ocultar brÃºjula (estilo Uber)
      mapToolbarEnabled: false,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: false, // Sin inclinaciÃ³n (estilo Uber)
      zoomGesturesEnabled: true,
      scrollGesturesEnabled: true,
      // Estilo personalizado estilo Uber
      style: _estiloMapaUber,
    );
  }

  Widget _buildSupervisorCard(SolicitudAyuda solicitud) {
    // Usar distancia y ETA actualizados si estÃ¡n disponibles
    final distancia = _distanciaActual ?? solicitud.distanciaKm;
    final eta = _etaMinutos ?? solicitud.tiempoExtraMinutos;
    
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, -5),
            ),
          ],
        ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header con nombre del supervisor
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.support_agent,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Supervisor asignado',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      solicitud.supervisorNombre ?? 'Supervisor',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (distancia != null || eta != null) ...[
            const SizedBox(height: 20),
            // InformaciÃ³n de distancia y tiempo estilo Uber
            Row(
              children: [
                if (distancia != null) ...[
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.straighten,
                      value: '${distancia.toStringAsFixed(1)} km',
                      label: 'Distancia',
                    ),
                  ),
                ],
                if (eta != null) ...[
                  if (distancia != null)
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey[300],
                    ),
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.access_time,
                      value: '$eta min',
                      label: 'Tiempo estimado',
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  /// Widget para mostrar informaciÃ³n (distancia/tiempo) estilo Uber
  Widget _buildInfoItem({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.black87, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Future<void> _cancelarSolicitud(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Cancelar Solicitud'),
        content: const Text('Â¿EstÃ¡s seguro de cancelar esta solicitud de ayuda?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('SÃ­, Cancelar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      final ayudaService = Provider.of<AyudaService>(context, listen: false);
      final ticketId = ayudaService.solicitudActual?.ticketId ??
          widget.solicitud.ticketId;
      final cancelado = await ayudaService.cancelarSolicitud(ticketId);

      if (context.mounted) {
        if (cancelado) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const AyudaTerrenoScreen(),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al cancelar solicitud'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Aplicar estilo personalizado al mapa
  void _aplicarEstiloMapa(GoogleMapController controller) {
    controller.setMapStyle(_estiloMapaUber);
  }

  /// Estilo personalizado del mapa estilo Uber (limpio y minimalista)
  static const String _estiloMapaUber = '''
  [
    {
      "featureType": "all",
      "elementType": "geometry",
      "stylers": [
        {
          "color": "#f5f5f5"
        }
      ]
    },
    {
      "featureType": "water",
      "elementType": "geometry",
      "stylers": [
        {
          "color": "#e9e9e9"
        }
      ]
    },
    {
      "featureType": "road",
      "elementType": "geometry",
      "stylers": [
        {
          "color": "#ffffff"
        }
      ]
    },
    {
      "featureType": "road.highway",
      "elementType": "geometry",
      "stylers": [
        {
          "color": "#dadada"
        }
      ]
    },
    {
      "featureType": "road.arterial",
      "elementType": "geometry",
      "stylers": [
        {
          "color": "#fafafa"
        }
      ]
    },
    {
      "featureType": "road.local",
      "elementType": "geometry",
      "stylers": [
        {
          "color": "#ffffff"
        }
      ]
    },
    {
      "featureType": "landscape",
      "elementType": "geometry",
      "stylers": [
        {
          "color": "#f5f5f5"
        }
      ]
    },
    {
      "featureType": "poi",
      "elementType": "labels",
      "stylers": [
        {
          "visibility": "off"
        }
      ]
    },
    {
      "featureType": "poi",
      "elementType": "geometry",
      "stylers": [
        {
          "visibility": "off"
        }
      ]
    },
    {
      "featureType": "transit",
      "elementType": "geometry",
      "stylers": [
        {
          "visibility": "off"
        }
      ]
    }
  ]
  ''';

  @override
  void dispose() {
    _pollingSupervisores?.cancel();
    _pollingSupervisorAsignado?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
}

