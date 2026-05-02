import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:agente_desconexiones/models/solicitud_ayuda.dart';
import 'package:agente_desconexiones/services/estado_supervisor_service.dart';
import 'package:agente_desconexiones/services/notification_service.dart';

/// Servicio de Ayuda en Terreno con Supabase Realtime.
/// Singleton — una sola instancia por toda la sesión de la app.
/// El canal GLOBAL del supervisor persiste sin importar qué pantalla esté abierta.
class AyudaService extends ChangeNotifier {
  // ── Singleton ────────────────────────────────────────────
  static final AyudaService _instance = AyudaService._internal();
  factory AyudaService() => _instance;
  AyudaService._internal();
  // ─────────────────────────────────────────────────────────

  final _supabase = Supabase.instance.client;
  final _player = AudioPlayer();

  SolicitudAyuda? _solicitudActual;
  List<SolicitudAyuda> _solicitudesSupervisor = [];
  RealtimeChannel? _canalTecnico;
  RealtimeChannel? _canalSupervisor;

  // Canal global: vive desde que el supervisor entra hasta que cierra la app.
  // No se destruye al cerrar SolicitudesAyudaScreen.
  RealtimeChannel? _canalGlobal;
  String? _rutSupervisorGlobal;

  // Rastreo de estado anterior para evitar disparar el diálogo
  // de respuesta cuando la actualización es solo de GPS (no de estado)
  EstadoSolicitud? _estadoAnteriorTecnico;

  SolicitudAyuda? get solicitudActual => _solicitudActual;
  List<SolicitudAyuda> get solicitudesSupervisor =>
      List.unmodifiable(_solicitudesSupervisor);
  // Compatibilidad con código existente
  List<SolicitudAyuda> get historial => [];

  // ─────────────────────────────────────────────────────────────
  // GPS
  // ─────────────────────────────────────────────────────────────

  /// Verifica permisos y obtiene posición actual. Lanza excepción con mensaje
  /// amigable si GPS no está disponible o si el permiso es denegado.
  Future<Position> obtenerPosicion() async {
    bool servicioHabilitado = await Geolocator.isLocationServiceEnabled();
    if (!servicioHabilitado) {
      throw Exception(
          'El GPS está desactivado. Actívalo en Configuración para usar esta función.');
    }

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) {
        throw Exception(
            'Permiso de ubicación denegado. Actívalo en Configuración de la app.');
      }
    }
    if (permiso == LocationPermission.deniedForever) {
      throw Exception(
          'Permiso de ubicación denegado permanentemente. Ve a Configuración > Apps > TrazaBox > Permisos.');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TÉCNICO — Enviar solicitud
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> solicitarAyuda({
    required TipoAyuda tipo,
    required String rutTecnico,
    required String nombreTecnico,
  }) async {
    // 1. GPS obligatorio
    Position pos;
    try {
      pos = await obtenerPosicion();
    } catch (e) {
      return {'error': e.toString()};
    }

    // 2. Buscar supervisor más cercano para este técnico
    final supervisorData = await _encontrarSupervisorCercano(
      rutTecnico: rutTecnico,
      latTecnico: pos.latitude,
      lngTecnico: pos.longitude,
    );

    // 3. Insertar en Supabase
    try {
      final row = {
        'rut_tecnico': rutTecnico,
        'nombre_tecnico': nombreTecnico,
        'lat_tecnico': pos.latitude,
        'lng_tecnico': pos.longitude,
        'tipo': tipo.value,
        'estado': 'pendiente',
        if (supervisorData != null) ...{
          'rut_supervisor': supervisorData['rut'],
          'nombre_supervisor': supervisorData['nombre'],
          'distancia_km': supervisorData['distancia_km'],
        },
      };

      final resp = await _supabase
          .from('ayuda_terreno_crea')
          .insert(row)
          .select()
          .single();

      final solicitud = SolicitudAyuda.fromJson(resp);
      _solicitudActual = solicitud;
      notifyListeners();
      return {'ok': true, 'solicitud': solicitud};
    } catch (e) {
      debugPrint('❌ [AyudaService] Error al insertar solicitud: $e');
      return {'error': 'No se pudo enviar la solicitud. Intenta nuevamente.'};
    }
  }

  // ─────────────────────────────────────────────────────────────
  // TÉCNICO — Realtime: escuchar respuesta del supervisor
  // ─────────────────────────────────────────────────────────────

  void suscribirRespuestaTecnico({
    required String ticketId,
    required VoidCallback onSonido,
  }) {
    _canalTecnico?.unsubscribe();

    _canalTecnico = _supabase
        .channel('ayuda_tecnico_$ticketId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ayuda_terreno_crea',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ticket_id',
            value: ticketId,
          ),
          callback: (payload) {
            final data = payload.newRecord;
            final solicitudActualizada = SolicitudAyuda.fromJson(data);
            final estadoCambio =
                _estadoAnteriorTecnico != solicitudActualizada.estado;
            _estadoAnteriorTecnico = solicitudActualizada.estado;
            _solicitudActual = solicitudActualizada;
            notifyListeners();
            // Disparar alerta con sonido SOLO cuando la solicitud se cierra
            // (rechazada/cancelada). NO sonar cuando el supervisor acepta.
            if (estadoCambio) {
              if (solicitudActualizada.estaResuelta) {
                _reproducirSonido();
                NotificationService().alertaTecnicoRespuesta(
                  supervisorNombre:
                      solicitudActualizada.supervisorNombre ?? 'Supervisor',
                  estado: solicitudActualizada.estado.value,
                  minutosExtra: solicitudActualizada.tiempoExtraMinutos,
                );
                onSonido();
              }
            }
          },
        )
        .subscribe();

    debugPrint(
        '📡 [AyudaService] Suscrito a respuestas del ticket $ticketId');
  }

  void cancelarSuscripcionTecnico() {
    _canalTecnico?.unsubscribe();
    _canalTecnico = null;
    _estadoAnteriorTecnico = null;
    debugPrint('📡 [AyudaService] Suscripción técnico cancelada');
  }

  /// Actualiza lat/lng del supervisor en la fila de `ayuda_terreno`
  /// para que el técnico pueda ver la posición en tiempo real.
  Future<void> actualizarGpsSolicitud(
      String ticketId, double lat, double lng) async {
    try {
      await _supabase.from('ayuda_terreno_crea').update({
        'lat_supervisor': lat,
        'lng_supervisor': lng,
      }).eq('ticket_id', ticketId);
    } catch (e) {
      debugPrint('⚠️ [AyudaService] GPS solicitud no actualizado: $e');
    }
  }

  /// Expone la reproducción de sonido para uso externo (ej: alerta de carga).
  /// Usa just_audio + vibración. No muestra notificación del sistema
  /// para no duplicar cuando ya hay cards pendientes en pantalla.
  Future<void> reproducirAlerta() => _reproducirSonido();

  /// Recupera un ticket activo desde Supabase por su ticket_id
  Future<SolicitudAyuda?> obtenerSolicitudPorTicket(String ticketId) async {
    try {
      final resp = await _supabase
          .from('ayuda_terreno_crea')
          .select()
          .eq('ticket_id', ticketId)
          .maybeSingle();
      if (resp == null) return null;
      return SolicitudAyuda.fromJson(resp);
    } catch (e) {
      debugPrint('❌ [AyudaService] Error recuperando ticket $ticketId: $e');
      return null;
    }
  }

  /// Guarda el ticket_id activo en SharedPreferences (persistencia entre sesiones)
  Future<void> persistirTicketActivo(String ticketId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ayuda_ticket_activo', ticketId);
    debugPrint('💾 [AyudaService] Ticket persistido: $ticketId');
  }

  /// Limpia el ticket persistido cuando la solicitud se resuelve
  Future<void> limpiarTicketPersistido() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ayuda_ticket_activo');
    debugPrint('🗑️ [AyudaService] Ticket persistido eliminado');
  }

  void limpiarSolicitudActual() {
    _solicitudActual = null;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────
  // SUPERVISOR — Obtener RUTs del equipo
  // ─────────────────────────────────────────────────────────────

  /// Devuelve los RUTs de los técnicos asignados a este supervisor
  Future<List<String>> obtenerRutsEquipo(String rutSupervisor) async {
    try {
      // Columnas reales: rut_supervisor, rut_tecnico
      final resp = await _supabase
          .from('supervisor_tecnicos_crea')
          .select('rut_tecnico')
          .eq('rut_supervisor', rutSupervisor);
      final lista = resp as List;
      debugPrint(
          '👥 [AyudaService] Equipo de $rutSupervisor: ${lista.length} técnicos');
      return lista.map((e) => e['rut_tecnico'] as String).toList();
    } catch (e) {
      debugPrint('❌ [AyudaService] Error obteniendo equipo: $e');
      return [];
    }
  }

  /// Marca una ayuda como completada (supervisor llegó y terminó)
  Future<bool> completarAyudaSupervisor(
      String ticketId, String rutSupervisor) async {
    try {
      await _supabase.from('ayuda_terreno_crea').update({
        'estado': 'completada',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('ticket_id', ticketId);

      await EstadoSupervisorService().limpiarEstadoAyuda(rutSupervisor);

      _solicitudesSupervisor = _solicitudesSupervisor.map((s) {
        if (s.ticketId == ticketId) {
          return s.copyWith(estado: EstadoSolicitud.completada);
        }
        return s;
      }).toList();
      notifyListeners();
      debugPrint('✅ [AyudaService] Ayuda $ticketId completada por supervisor');
      return true;
    } catch (e) {
      debugPrint('❌ [AyudaService] Error completando ayuda: $e');
      return false;
    }
  }

  /// Historial de ayudas completadas hoy por este supervisor
  Future<List<Map<String, dynamic>>> obtenerHistorialAtencionDia(
      String rutSupervisor) async {
    try {
      final hoy = DateTime.now();
      final inicioDia = DateTime(hoy.year, hoy.month, hoy.day);
      final resp = await _supabase
          .from('ayuda_terreno_crea')
          .select('ticket_id, nombre_tecnico, tipo, created_at, updated_at')
          .eq('rut_supervisor', rutSupervisor)
          .eq('estado', 'completada')
          .neq('tipo', 'movimiento_material')
          .gte('created_at', inicioDia.toUtc().toIso8601String())
          .order('updated_at', ascending: false);
      final lista = <Map<String, dynamic>>[];
      for (final r in resp as List) {
        final created = r['created_at'] != null
            ? DateTime.parse(r['created_at'] as String).toLocal()
            : null;
        final updated = r['updated_at'] != null
            ? DateTime.parse(r['updated_at'] as String).toLocal()
            : null;
        final tiempoMin = (created != null && updated != null)
            ? updated.difference(created).inMinutes
            : 0;
        final horaDesde = created != null
            ? '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}'
            : '—';
        final horaHasta = updated != null
            ? '${updated.hour.toString().padLeft(2, '0')}:${updated.minute.toString().padLeft(2, '0')}'
            : '—';
        lista.add({
          'nombre_tecnico': r['nombre_tecnico'] ?? 'Técnico',
          'tipo': r['tipo'] ?? 'ayuda',
          'tiempo_min': tiempoMin,
          'hora_desde': horaDesde,
          'hora_hasta': horaHasta,
        });
      }
      return lista;
    } catch (e) {
      debugPrint('❌ [AyudaService] Error historial: $e');
      return [];
    }
  }

  /// Lista de supervisores/ITOs para traspasar (excluye rutActual)
  Future<List<Map<String, String>>> obtenerSupervisoresParaTraspasar(
      String rutActual) async {
    try {
      final resp = await _supabase
          .from('supervisores_crea')
          .select('rut, nombre')
          .neq('rut', rutActual)
          .order('nombre');
      return (resp as List)
          .map((r) => {
                'rut': r['rut'] as String? ?? '',
                'nombre': r['nombre'] as String? ?? r['rut']?.toString() ?? '',
              })
          .where((m) => m['rut']!.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('❌ [AyudaService] Error supervisores: $e');
      return [];
    }
  }

  /// Traspasar ticket a otro supervisor/ITO
  Future<bool> traspasarTicket(
      String ticketId, String rutDestino, String nombreDestino) async {
    try {
      await _supabase.from('ayuda_terreno_crea').update({
        'rut_supervisor': rutDestino,
        'nombre_supervisor': nombreDestino,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('ticket_id', ticketId);
      _solicitudesSupervisor = _solicitudesSupervisor
          .where((s) => s.ticketId != ticketId)
          .toList();
      notifyListeners();
      debugPrint('✅ [AyudaService] Ticket $ticketId traspasado a $nombreDestino');
      return true;
    } catch (e) {
      debugPrint('❌ [AyudaService] Error traspasar: $e');
      return false;
    }
  }

  /// Cancela una solicitud activa (lado técnico)
  Future<bool> cancelarSolicitud(String ticketId) async {
    try {
      await _supabase
          .from('ayuda_terreno_crea')
          .update({'estado': 'cancelada'})
          .eq('ticket_id', ticketId);
      debugPrint('🗑️ [AyudaService] Solicitud $ticketId cancelada');
      return true;
    } catch (e) {
      debugPrint('❌ [AyudaService] Error cancelando solicitud: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // SUPERVISOR — Cargar solicitudes del equipo (por rut_tecnico)
  // ─────────────────────────────────────────────────────────────

  Future<void> cargarSolicitudesSupervisor(String rutSupervisor) async {
    try {
      // 1. Obtener RUTs del equipo
      final rutsEquipo = await obtenerRutsEquipo(rutSupervisor);

      List<dynamic> resp;

      if (rutsEquipo.isEmpty) {
        // Sin equipo asignado: mostrar solicitudes donde rut_supervisor coincide
        debugPrint(
            '⚠️ [AyudaService] Sin equipo en supervisor_tecnicos_crea, usando fallback');
        final hoy = DateTime.now().subtract(const Duration(hours: 24));
        resp = await _supabase
            .from('ayuda_terreno_crea')
            .select()
            .eq('rut_supervisor', rutSupervisor)
            .neq('tipo', 'movimiento_material')
            .gte('created_at', hoy.toIso8601String())
            .order('created_at', ascending: false);
      } else {
        // 2. Buscar solicitudes donde rut_tecnico esté en el equipo (últimas 24h)
        // Excluir movimiento_material (no son solicitudes de ayuda del técnico)
        final hoy = DateTime.now().subtract(const Duration(hours: 24));
        resp = await _supabase
            .from('ayuda_terreno_crea')
            .select()
            .inFilter('rut_tecnico', rutsEquipo)
            .neq('tipo', 'movimiento_material')
            .gte('created_at', hoy.toIso8601String())
            .order('created_at', ascending: false);
      }

      _solicitudesSupervisor =
          (resp).map((e) => SolicitudAyuda.fromJson(e as Map<String, dynamic>)).toList();
      debugPrint(
          '📋 [AyudaService] Solicitudes cargadas: ${_solicitudesSupervisor.length}');
      notifyListeners();
    } catch (e) {
      debugPrint(
          '❌ [AyudaService] Error cargando solicitudes supervisor: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // SUPERVISOR — Realtime: escuchar nuevas solicitudes del equipo
  // ─────────────────────────────────────────────────────────────

  void suscribirSolicitudesSupervisor({
    required String rutSupervisor,
    required VoidCallback onNuevaSolicitud,
  }) {
    _canalSupervisor?.unsubscribe();

    // Suscribir SIN filtro de columna — cualquier INSERT en la tabla
    // El callback filtra si el técnico pertenece al equipo del supervisor
    _canalSupervisor = _supabase
        .channel('ayuda_equipo_$rutSupervisor')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ayuda_terreno_crea',
          callback: (payload) async {
            final raw = payload.newRecord as Map<String, dynamic>;
            if (raw['tipo'] == 'movimiento_material') return;
            final nueva =
                SolicitudAyuda.fromJson(raw);
            debugPrint(
                '📡 [AyudaService] Nueva solicitud recibida de: ${nueva.rutTecnico}');

            // Verificar si el técnico pertenece al equipo de este supervisor
            final rutsEquipo = await obtenerRutsEquipo(rutSupervisor);
            final esMiEquipo = rutsEquipo.contains(nueva.rutTecnico) ||
                nueva.rutSupervisor == rutSupervisor;

            if (!esMiEquipo && nueva.rutSupervisor != rutSupervisor) {
              debugPrint(
                  '📡 [AyudaService] Solicitud ignorada — técnico no pertenece al equipo');
              return;
            }

            // Agregar a la lista local si no está ya
            final yaExiste = _solicitudesSupervisor
                .any((s) => s.ticketId == nueva.ticketId);
            if (!yaExiste) {
              _solicitudesSupervisor = [nueva, ..._solicitudesSupervisor];
              notifyListeners();
              // NO reproducir sonido aquí: el canal GLOBAL ya lo hace
              // para evitar doble alerta cuando la pantalla está abierta.
              onNuevaSolicitud();
            }
          },
        )
        .subscribe();

    debugPrint(
        '📡 [AyudaService] Supervisor $rutSupervisor suscrito a solicitudes del equipo');
  }

  void cancelarSuscripcionSupervisor() {
    _canalSupervisor?.unsubscribe();
    _canalSupervisor = null;
    debugPrint('📡 [AyudaService] Suscripción supervisor (pantalla) cancelada');
  }

  // ─────────────────────────────────────────────────────────────
  // SUPERVISOR — Canal GLOBAL persistente (vive toda la sesión)
  // Dispara sonido + notificación del sistema sin importar qué
  // pantalla esté abierta. Llamar desde HomeScreen al iniciar.
  // ─────────────────────────────────────────────────────────────

  Future<void> iniciarMonitoreoGlobalSupervisor(String rutSupervisor) async {
    // Si ya está corriendo para el mismo RUT, no duplicar
    if (_rutSupervisorGlobal == rutSupervisor && _canalGlobal != null) {
      debugPrint(
          '📡 [AyudaService] Canal global ya activo para $rutSupervisor');
      return;
    }

    _canalGlobal?.unsubscribe();
    _rutSupervisorGlobal = rutSupervisor;

    // Pre-cargar equipo; se refrescará si viene vacío en el callback
    final List<String> rutsEquipo = await obtenerRutsEquipo(rutSupervisor);
    debugPrint(
        '🔔 [AyudaService] Iniciando monitoreo GLOBAL supervisor $rutSupervisor '
        '(${rutsEquipo.length} técnicos en equipo)');

    _canalGlobal = _supabase
        .channel('global_ayuda_$rutSupervisor')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ayuda_terreno_crea',
          callback: (payload) async {
            final raw = payload.newRecord as Map<String, dynamic>;
            if (raw['tipo'] == 'movimiento_material') return;
            final nueva = SolicitudAyuda.fromJson(raw);
            debugPrint(
                '🔔 [AyudaService][GLOBAL] INSERT: tecnico=${nueva.rutTecnico}'
                ' supAsignado=${nueva.rutSupervisor} equipo=$rutsEquipo');

            // Verificar si pertenece al equipo de este supervisor.
            // Si el equipo está vacío (carga fallida) re-intentar obtenerlo.
            List<String> equipo = rutsEquipo;
            if (equipo.isEmpty) {
              equipo = await obtenerRutsEquipo(rutSupervisor);
              if (equipo.isNotEmpty) rutsEquipo.addAll(equipo);
            }

            // Es "mi equipo" si:
            //  1. El técnico aparece en la lista de mi equipo
            //  2. La solicitud fue asignada a este supervisor
            //  3. La solicitud no tiene supervisor asignado aún
            //     (puede ser para mí — no descartar sin datos)
            final esMiEquipo = equipo.contains(nueva.rutTecnico) ||
                nueva.rutSupervisor == rutSupervisor ||
                (equipo.isEmpty && nueva.rutSupervisor == null);

            debugPrint('🔔 [AyudaService][GLOBAL] esMiEquipo=$esMiEquipo');

            if (!esMiEquipo) return;

            // Agregar a la lista interna si no está
            final yaExiste = _solicitudesSupervisor
                .any((s) => s.ticketId == nueva.ticketId);
            if (!yaExiste) {
              _solicitudesSupervisor = [nueva, ..._solicitudesSupervisor];
              notifyListeners();
            }

            // Vibración SIEMPRE (funciona aunque el dispositivo esté en silencio)
            NotificationService().vibrarParaAlerta();
            // Notificación PRIMERO (sonido del sistema, funciona aunque
            // la app esté en otra pantalla o minimizada)
            await NotificationService().alertaSupervisorNuevaSolicitud(
              tecnicoNombre: nueva.tecnicoNombre,
              tipoAyuda: nueva.tipo.displayName,
            );
            // Sonido in-app como refuerzo (cuando la app está en primer plano)
            await _reproducirSonido();
          },
        )
        .subscribe();

    debugPrint('📡 [AyudaService] Canal global supervisor activo');
  }

  /// Detener monitoreo global (llamar solo en logout)
  void detenerMonitoreoGlobal() {
    _canalGlobal?.unsubscribe();
    _canalGlobal = null;
    _rutSupervisorGlobal = null;
    debugPrint('📡 [AyudaService] Canal global supervisor detenido');
  }

  // ─────────────────────────────────────────────────────────────
  // SUPERVISOR — Responder solicitud
  // ─────────────────────────────────────────────────────────────

  Future<bool> responderSolicitud({
    required String ticketId,
    required EstadoSolicitud estado,
    int? tiempoExtraMinutos,
    String? mensaje,
    double? latSupervisor,
    double? lngSupervisor,
    String? nombreSupervisor,
    String? rutSupervisor,
    String? rutTecnico,
    String? nombreTecnico,
    String? tipoAyuda,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _supabase.from('ayuda_terreno_crea').update({
        'estado': estado.value,
        if (tiempoExtraMinutos != null)
          'tiempo_extra_minutos': tiempoExtraMinutos,
        if (mensaje != null) 'respuesta_mensaje': mensaje,
        if (latSupervisor != null) 'lat_supervisor': latSupervisor,
        if (lngSupervisor != null) 'lng_supervisor': lngSupervisor,
        if (nombreSupervisor != null) 'nombre_supervisor': nombreSupervisor,
        if (rutSupervisor != null) 'rut_supervisor': rutSupervisor,
        'updated_at': now,
      }).eq('ticket_id', ticketId);

      // Actualizar estado_supervisor al aceptar o rechazar
      if (rutSupervisor != null && rutSupervisor.isNotEmpty) {
        final esAceptacion = estado == EstadoSolicitud.aceptada ||
            estado == EstadoSolicitud.aceptadaConTiempo;
        if (esAceptacion &&
            latSupervisor != null &&
            lngSupervisor != null &&
            rutTecnico != null &&
            nombreTecnico != null &&
            tipoAyuda != null) {
          await EstadoSupervisorService().iniciarAyudaEnCamino(
            rutSupervisor: rutSupervisor,
            nombreSupervisor: nombreSupervisor ?? 'Supervisor',
            ticketId: ticketId,
            rutTecnico: rutTecnico,
            nombreTecnico: nombreTecnico,
            tipoAyuda: tipoAyuda,
            lat: latSupervisor,
            lng: lngSupervisor,
          );
        } else if (!esAceptacion) {
          await EstadoSupervisorService().limpiarEstadoAyuda(rutSupervisor);
        }
      }

      // Actualizar lista local
      _solicitudesSupervisor = _solicitudesSupervisor.map((s) {
        if (s.ticketId == ticketId) {
          return s.copyWith(
            estado: estado,
            tiempoExtraMinutos: tiempoExtraMinutos,
            respuestaMensaje: mensaje,
          );
        }
        return s;
      }).toList();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ [AyudaService] Error al responder solicitud: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // SUPERVISOR — Actualizar ubicación propia
  // ─────────────────────────────────────────────────────────────

  Future<void> actualizarUbicacionSupervisor(String rutSupervisor) async {
    try {
      final pos = await obtenerPosicion();
      await _supabase.from('supervisores_crea').update({
        'lat_ultima': pos.latitude,
        'lng_ultima': pos.longitude,
        'ultima_ubicacion_at': DateTime.now().toIso8601String(),
      }).eq('rut', rutSupervisor);
      debugPrint('📍 [AyudaService] Ubicación supervisor actualizada');
    } catch (e) {
      debugPrint(
          '⚠️ [AyudaService] No se pudo actualizar ubicación supervisor: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Interno — Encontrar supervisor más cercano
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _encontrarSupervisorCercano({
    required String rutTecnico,
    required double latTecnico,
    required double lngTecnico,
  }) async {
    try {
      // 1. Obtener supervisores asignados a este técnico
      // Columnas reales: rut_supervisor, rut_tecnico
      final relaciones = await _supabase
          .from('supervisor_tecnicos_crea')
          .select('rut_supervisor')
          .eq('rut_tecnico', rutTecnico);

      if (relaciones == null || (relaciones as List).isEmpty) {
        debugPrint(
            '⚠️ [AyudaService] Sin supervisor asignado para $rutTecnico');
        return null;
      }

      final rutsSuper =
          (relaciones as List).map((e) => e['rut_supervisor'] as String).toList();

      // 2. Obtener ubicaciones de esos supervisores
      final supervisores = await _supabase
          .from('supervisores_crea')
          .select('rut, nombre, lat_ultima, lng_ultima')
          .inFilter('rut', rutsSuper);

      if (supervisores == null || (supervisores as List).isEmpty) {
        return null;
      }

      // 3. Calcular distancia y elegir el más cercano que tenga GPS
      Map<String, dynamic>? cercano;
      double distanciaMenor = double.infinity;

      for (final s in supervisores as List) {
        final lat = (s['lat_ultima'] as num?)?.toDouble();
        final lng = (s['lng_ultima'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        final dist = _calcularDistanciaKm(latTecnico, lngTecnico, lat, lng);
        if (dist < distanciaMenor) {
          distanciaMenor = dist;
          cercano = {
            'rut': s['rut'],
            'nombre': s['nombre'],
            'distancia_km': double.parse(dist.toStringAsFixed(2)),
          };
        }
      }

      // Si ninguno tiene GPS, asignar al primero de la lista
      if (cercano == null && (supervisores as List).isNotEmpty) {
        final primero = (supervisores as List).first;
        cercano = {
          'rut': primero['rut'],
          'nombre': primero['nombre'],
          'distancia_km': null,
        };
      }

      debugPrint(
          '📍 [AyudaService] Supervisor más cercano: ${cercano?['nombre']} (${cercano?['distancia_km']} km)');
      return cercano;
    } catch (e) {
      debugPrint('⚠️ [AyudaService] Error buscando supervisor cercano: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Fórmula Haversine para distancia en km
  // ─────────────────────────────────────────────────────────────

  double _calcularDistanciaKm(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _toRad(double deg) => deg * pi / 180;

  // ─────────────────────────────────────────────────────────────
  // Audio
  // ─────────────────────────────────────────────────────────────

  Future<void> _reproducirSonido() async {
    // Intentar reproducir via just_audio (app en primer plano)
    try {
      if (_player.playing) await _player.stop();
      await _player.setAsset('assets/sounds/alerta_supervisor.mp3');
      await _player.play();
      debugPrint('🔊 [AyudaService] Sonido reproducido via just_audio');
    } catch (e) {
      debugPrint('⚠️ [AyudaService] just_audio falló: $e — usando notificación sistema');
    }
  }

  /// Refresca la solicitud actual desde Supabase (tracking / mapa).
  Future<void> consultarEstado() async {
    final cur = _solicitudActual;
    if (cur == null) return;
    try {
      final row = await _supabase
          .from('ayuda_terreno_crea')
          .select()
          .eq('ticket_id', cur.ticketId)
          .maybeSingle();
      if (row == null) return;
      _solicitudActual =
          SolicitudAyuda.fromJson(Map<String, dynamic>.from(row));
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ [AyudaService] consultarEstado: $e');
    }
  }

  /// Supervisores cercanos para el mapa (placeholder; la UI de TrazaBox puede ampliarlo).
  Future<List<Map<String, dynamic>>> obtenerSupervisoresDisponibles({
    required double latitud,
    required double longitud,
  }) async {
    return [];
  }

  /// El singleton NUNCA se dispone; cancelar solo los canales Realtime
  /// de la pantalla activa (técnico y supervisor local).
  /// El AudioPlayer y el canal global permanecen vivos toda la sesión.
  void cancelarCanalesLocales() {
    _canalTecnico?.unsubscribe();
    _canalTecnico = null;
    _canalSupervisor?.unsubscribe();
    _canalSupervisor = null;
  }

  @override
  void dispose() {
    // No llamar super.dispose() ni _player.dispose() en el singleton.
    // Solo limpiar canales locales.
    cancelarCanalesLocales();
  }
}
