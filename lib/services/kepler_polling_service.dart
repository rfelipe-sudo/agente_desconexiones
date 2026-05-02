import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import 'deteccion_caminata_service.dart';
import 'supabase_service.dart';
import 'alertas_cto_service.dart';

class KeplerPollingService {
  static final KeplerPollingService _instance = KeplerPollingService._internal();
  factory KeplerPollingService() => _instance;
  KeplerPollingService._internal();

  static const String _endpoint = 'https://kepler.sbip.cl/api/v1/toa/get_data_toa_other_enterprise';
  static const int _intervaloSegundos = 30;

  Timer? _timer;
  String? _rutTecnico;
  String? _otActualMonitoreando;
  final DeteccionCaminataService _deteccionService = DeteccionCaminataService();
  final SupabaseService _supabaseService = SupabaseService();
  final AlertasCTOService _alertasCTOService = AlertasCTOService();

  Future<void> iniciar() async {
    final prefs = await SharedPreferences.getInstance();
    _rutTecnico = prefs.getString('rut_tecnico');

    if (_rutTecnico == null || _rutTecnico!.isEmpty) {
      print('⚠️ [KeplerPolling] No hay RUT guardado - No se inicia polling');
      return;
    }

    print('✅ [KeplerPolling] Iniciando polling para RUT: $_rutTecnico');

    // Primera consulta inmediata
    await _consultarOrdenes();

    // Luego cada 30 segundos
    _timer = Timer.periodic(const Duration(seconds: _intervaloSegundos), (_) {
      _consultarOrdenes();
    });
  }

  void detener() {
    _timer?.cancel();
    _timer = null;
    print('🛑 [KeplerPolling] Polling detenido');
  }

  Future<void> _consultarOrdenes() async {
    try {
      final response = await http.get(
        Uri.parse(_endpoint),
        headers: AppConstants.keplerHeaders,
      );

      if (response.statusCode != 200) {
        print('❌ [KeplerPolling] Error HTTP: ${response.statusCode}');
        return;
      }

      final data = jsonDecode(response.body);
      // La API puede responder con un List directo o con un Map {data: [...]}.
      // Cada ítem debe ser Map; si viene List u otro tipo, [clave] usa índice int → error.
      final List<dynamic> raw = data is List
          ? data
          : (data is Map ? (data['data'] ?? []) : []);
      final ordenes = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is Map) {
          ordenes.add(Map<String, dynamic>.from(item));
        }
      }

      // Filtrar: Estado == "Iniciado" AND Rut_tecnico == mi_rut
      final ordenesIniciadas = ordenes.where((orden) {
        final estado = orden['Estado']?.toString() ?? '';
        final rutOrden = orden['Rut_tecnico']?.toString() ?? '';
        return estado == 'Iniciado' && rutOrden == _rutTecnico;
      }).toList();

      if (ordenesIniciadas.isEmpty) {
        // Si no hay órdenes iniciadas y había una monitoreando, finalizar
        if (_otActualMonitoreando != null) {
          print('🏁 [KeplerPolling] Orden $_otActualMonitoreando ya no está iniciada - Finalizando monitoreo');
          _deteccionService.finalizarTrabajo();
          _otActualMonitoreando = null;
        }
        return;
      }

      // Tomar la primera orden iniciada
      final ordenActiva = ordenesIniciadas.first;
      final ot = ordenActiva['Orden_de_Trabajo']?.toString() ?? '';

      // Si ya estamos monitoreando esta OT, no hacer nada
      if (_otActualMonitoreando == ot) return;

      // Nueva orden iniciada - Activar monitoreo
      print('🚀 [KeplerPolling] Nueva orden detectada: $ot - Activando monitoreo');

      final nombreTecnico = ordenActiva['Técnico']?.toString() ?? '';
      final direccion = ordenActiva['Dirección']?.toString() ?? '';
      final latTrabajo = (ordenActiva['Coord_Y'] as num?)?.toDouble();
      final lngTrabajo = (ordenActiva['Coord_X'] as num?)?.toDouble();

      _otActualMonitoreando = ot;

      // ═══════════════════════════════════════════════════════
      // ASOCIAR RUT ↔ NOMBRE (para alertas CTO)
      // ═══════════════════════════════════════════════════════
      if (_rutTecnico != null && nombreTecnico.isNotEmpty) {
        // Extraer nombre limpio (sin prefijo de empresa)
        String nombreLimpio = nombreTecnico;
        if (nombreTecnico.contains('_')) {
          final partes = nombreTecnico.split('_');
          nombreLimpio = partes.last; // Último segmento es el nombre
        }

        await _supabaseService.actualizarNombreTecnico(
          rut: _rutTecnico!,
          nombre: nombreLimpio,
          nombreFull: nombreTecnico,
        );

        // Notificar al servicio de alertas CTO
        _alertasCTOService.actualizarNombre(nombreLimpio);

        print('✅ [KeplerPolling] Asociado RUT $_rutTecnico con nombre: $nombreLimpio');
      }

      // Asegurarse de que el servicio esté corriendo antes de iniciar trabajo
      await _deteccionService.iniciarServicio();

      _deteccionService.iniciarTrabajo(
        ot: ot,
        tecnicoId: _rutTecnico ?? '',
        nombreTecnico: nombreTecnico,
        direccion: direccion,
        latTrabajo: latTrabajo,
        lngTrabajo: lngTrabajo,
      );
    } catch (e) {
      print('❌ [KeplerPolling] Error: $e');
    }
  }

  // Método para actualizar el RUT (cuando el técnico se registra)
  Future<void> actualizarRut(String rut) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rut_tecnico', rut);
    _rutTecnico = rut;
    print('✅ [KeplerPolling] RUT actualizado: $rut');

    // Reiniciar polling con nuevo RUT
    detener();
    await iniciar();
  }
}

