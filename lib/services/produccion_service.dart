import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';
import '../models/metrica_produccion.dart';
import '../models/equipo_reversa.dart';
import '../models/calidad_tecnico.dart';
import '../utils/feriados_chile.dart';
import 'krp_marcas_service.dart';

class ProduccionService {
  static final ProduccionService _instance = ProduccionService._internal();
  factory ProduccionService() => _instance;
  ProduccionService._internal();

  static const String _endpointSabana = 'https://kepler.sbip.cl/api/v1/toa/get_sabana_metro';
  static const double _rendimientoKmPorLitro = 10.0;
  static const int _precioCombustiblePorLitro = 1200; // Pesos chilenos
  static const int _jornadaMinutos = 540; // 9 horas de jornada

  // Técnicos que conservan el turno antiguo 9:45-18:45 (L-V) / 10:00-15:00 (S)
  static const Set<String> _rutsTurnoAntiguo = {
    '18117649-0', '17024384-6',
  };

  // Técnicos con turno rotativo: L/J/S 9:45-17:15  |  M/X/V 9:45-18:15
  static const Set<String> _rutsTurnoRotativo = {
    '19548078-8', '19162849-7', '19878777-9',
  };

  final _supabase = Supabase.instance.client;
  final _marcasService = KrpMarcasService();

  // ── Estáticos usados por MiEquipoDataService (misma lógica que TrazaBox) ──

  static bool esEstadoNoRealizada(dynamic orden) {
    if (orden is! Map) return false;
    final e = (orden['estado']?.toString() ?? '').trim().toUpperCase();
    return e == 'NO REALIZADA' || e == 'NO REALIZADO' || e == 'NO REALIZADOS';
  }

  static bool areaDerivacionEsRedes(dynamic raw) {
    final a = (raw?.toString() ?? '').trim().toUpperCase();
    if (a.isEmpty) return false;
    return a == 'REDES' || a.contains('REDES');
  }

  static bool cuentaComoProduccion(dynamic orden) {
    if (orden is! Map) return false;
    final o = orden as Map<String, dynamic>;
    final e = (o['estado']?.toString() ?? '').trim().toUpperCase();
    final a = (o['area_derivacion']?.toString() ?? '').trim().toUpperCase();
    return e == 'COMPLETADO' ||
        (esEstadoNoRealizada(o) && a == 'GSA');
  }

  static bool esDerivacionRedes(dynamic orden) {
    if (orden is! Map) return false;
    final o = orden as Map<String, dynamic>;
    return areaDerivacionEsRedes(o['area_derivacion']);
  }

  static List<String> rutVariantes(String rut) {
    final s = rut.toString().trim();
    if (s.isEmpty) return [];
    final sinPuntos = s.replaceAll('.', '');
    final partes = sinPuntos.split('-');
    if (partes.length < 2) return [s];
    final run = partes[0];
    final dv = partes.sublist(1).join('-');
    final conGuion = '$run-$dv';
    String conPuntos = conGuion;
    if (run.length > 3) {
      final chars = run.split('');
      final grupos = <String>[];
      for (var i = chars.length; i > 0; i -= 3) {
        final start = (i - 3).clamp(0, chars.length);
        grupos.insert(0, chars.sublist(start, i).join());
      }
      conPuntos = '${grupos.join('.')}-$dv';
    }
    final variantes = <String>{s, conGuion, conPuntos};
    if (partes.length >= 2) {
      final sinGuion = '$run${partes.sublist(1).join()}';
      if (sinGuion.isNotEmpty) variantes.add(sinGuion);
    }
    return variantes.where((v) => v.isNotEmpty).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // OBTENER Y PROCESAR SABANA
  // ═══════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> obtenerSabana() async {
    try {
      final response = await http.get(
        Uri.parse(_endpointSabana),
        headers: AppConstants.keplerHeaders,
      );
      
      if (response.statusCode != 200) {
        print('❌ [Produccion] Error HTTP: ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['data'] ?? []);
    } catch (e) {
      print('❌ [Produccion] Error obteniendo sabana: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> obtenerOrdenesTecnico(String tecnicoNombre, {DateTime? fecha}) async {
    final sabana = await obtenerSabana();
    
    final fechaFiltro = fecha ?? DateTime.now();
    final fechaStr = '${fechaFiltro.day.toString().padLeft(2, '0')}/${fechaFiltro.month.toString().padLeft(2, '0')}/${fechaFiltro.year.toString().substring(2)}';
    
    return sabana.where((orden) {
      final tecnico = orden['Técnico']?.toString() ?? '';
      final fechaOrden = orden['Fecha']?.toString() ?? '';
      
      final coincideTecnico = tecnico.toLowerCase().contains(tecnicoNombre.toLowerCase());
      final coincideFecha = fechaOrden == fechaStr;
      
      return coincideTecnico && coincideFecha;
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // CALCULAR MÉTRICAS DEL DÍA
  // ═══════════════════════════════════════════════════════════

  Future<MetricaProduccion?> calcularMetricasDia(String tecnicoRut, String tecnicoNombre, {DateTime? fecha}) async {
    try {
      final ordenes = await obtenerOrdenesTecnico(tecnicoNombre, fecha: fecha);
      
      if (ordenes.isEmpty) {
        print('⚠️ [Produccion] Sin órdenes para $tecnicoNombre');
        return null;
      }

      // Ordenar por hora de inicio
      ordenes.sort((a, b) {
        final inicioA = _parseHora(a['Inicio']?.toString() ?? '00:00');
        final inicioB = _parseHora(b['Inicio']?.toString() ?? '00:00');
        return inicioA.compareTo(inicioB);
      });

      // Calcular tiempos
      int tiempoTrabajo = 0;
      int tiempoTrayecto = 0;
      Map<int, int> ordenesPorHora = {};
      Map<String, int> ordenesPorZona = {};

      for (int i = 0; i < ordenes.length; i++) {
        final orden = ordenes[i];
        final inicio = _parseHora(orden['Inicio']?.toString() ?? '00:00');
        final fin = _parseHora(orden['Fin']?.toString() ?? '00:00');
        
        // Tiempo de trabajo en esta orden
        final duracion = fin - inicio;
        if (duracion > 0) tiempoTrabajo += duracion;

        // Hora pico
        final hora = inicio ~/ 60;
        ordenesPorHora[hora] = (ordenesPorHora[hora] ?? 0) + 1;

        // Zona
        final zona = orden['Zona de trabajo']?.toString() ?? 'Sin zona';
        ordenesPorZona[zona] = (ordenesPorZona[zona] ?? 0) + 1;

        // Tiempo de trayecto (desde fin anterior hasta inicio actual)
        if (i > 0) {
          final finAnterior = _parseHora(ordenes[i - 1]['Fin']?.toString() ?? '00:00');
          final trayecto = inicio - finAnterior;
          if (trayecto > 0 && trayecto < 120) { // Máximo 2 horas de trayecto
            tiempoTrayecto += trayecto;
          }
        }
      }

      // Calcular km recorridos
      double kmTotal = 0;
      for (int i = 1; i < ordenes.length; i++) {
        final lat1 = (ordenes[i - 1]['Coord Y'] as num?)?.toDouble() ?? 0;
        final lon1 = (ordenes[i - 1]['Coord X'] as num?)?.toDouble() ?? 0;
        final lat2 = (ordenes[i]['Coord Y'] as num?)?.toDouble() ?? 0;
        final lon2 = (ordenes[i]['Coord X'] as num?)?.toDouble() ?? 0;
        
        if (lat1 != 0 && lon1 != 0 && lat2 != 0 && lon2 != 0) {
          kmTotal += _calcularDistanciaKm(lat1, lon1, lat2, lon2);
        }
      }

      // Contar estados
      int completadas = 0;
      int quiebres = 0;
      int altas = 0;
      int bajas = 0;
      int reparaciones = 0;

      for (final orden in ordenes) {
        final estado = orden['Estado']?.toString() ?? '';
        final tipo = orden['Tipo de Actividad']?.toString() ?? '';
        final codigoCierre = orden['Código de Cierre']?.toString() ?? '';

        if (estado == 'Completado') {
          completadas++;
          
          if (tipo.toLowerCase().contains('alta')) altas++;
          else if (tipo.toLowerCase().contains('baja')) bajas++;
          else if (tipo.toLowerCase().contains('reparaci')) reparaciones++;
        }

        // Detectar quiebres
        if (_esQuiebre(codigoCierre)) {
          quiebres++;
        }
      }

      // Hora pico
      String? horaPico;
      int maxOrdenes = 0;
      ordenesPorHora.forEach((hora, cantidad) {
        if (cantidad > maxOrdenes) {
          maxOrdenes = cantidad;
          horaPico = '${hora.toString().padLeft(2, '0')}:00';
        }
      });

      // Zona más eficiente
      String? zonaMasEficiente;
      int maxZona = 0;
      ordenesPorZona.forEach((zona, cantidad) {
        if (cantidad > maxZona) {
          maxZona = cantidad;
          zonaMasEficiente = zona;
        }
      });

      // Calcular porcentajes
      final porcentajeProductividad = ordenes.isNotEmpty 
          ? (completadas / ordenes.length) * 100 
          : 0.0;
      final porcentajeQuiebre = ordenes.isNotEmpty 
          ? (quiebres / ordenes.length) * 100 
          : 0.0;
      final productividadVsQuiebre = porcentajeQuiebre > 0 
          ? porcentajeProductividad / porcentajeQuiebre 
          : porcentajeProductividad;

      // Costos
      final combustibleLitros = kmTotal / _rendimientoKmPorLitro;
      final costoCombustible = (combustibleLitros * _precioCombustiblePorLitro).round();

      // Tiempo de ocio
      final tiempoOcio = _jornadaMinutos - tiempoTrabajo - tiempoTrayecto;

      final metrica = MetricaProduccion(
        tecnicoRut: tecnicoRut,
        tecnicoNombre: tecnicoNombre,
        fecha: fecha ?? DateTime.now(),
        tiempoTrabajoMin: tiempoTrabajo,
        tiempoTrayectoMin: tiempoTrayecto,
        tiempoOcioMin: tiempoOcio > 0 ? tiempoOcio : 0,
        tiempoPromedioOrdenMin: completadas > 0 ? tiempoTrabajo ~/ completadas : 0,
        kmRecorridos: kmTotal,
        combustibleLitros: combustibleLitros,
        costoCombustible: costoCombustible,
        ordenesAsignadas: ordenes.length,
        ordenesCompletadas: completadas,
        quiebres: quiebres,
        porcentajeProductividad: porcentajeProductividad,
        porcentajeQuiebre: porcentajeQuiebre,
        productividadVsQuiebre: productividadVsQuiebre,
        altasCompletadas: altas,
        bajasCompletadas: bajas,
        reparacionesCompletadas: reparaciones,
        horaPico: horaPico,
        zonaMasEficiente: zonaMasEficiente,
      );

      // Guardar en Supabase
      await _guardarMetrica(metrica);

      print('✅ [Produccion] Métricas calculadas: ${completadas}/${ordenes.length} órdenes');
      return metrica;

    } catch (e) {
      print('❌ [Produccion] Error calculando métricas: $e');
      return null;
    }
  }

  bool _esQuiebre(String codigoCierre) {
    final quiebres = [
      'sin moradores',
      'cliente ausente',
      'reagenda',
      'no permite',
      'rechaza',
      'cancelada',
      'suspendida',
      'no acceso',
      'dirección errónea',
    ];
    
    final codigoLower = codigoCierre.toLowerCase();
    return quiebres.any((q) => codigoLower.contains(q));
  }

  // ═══════════════════════════════════════════════════════════
  // EXTRAER EQUIPOS EN REVERSA
  // ═══════════════════════════════════════════════════════════

  Future<List<EquipoReversa>> extraerEquiposReversa(String tecnicoRut, String tecnicoNombre, {DateTime? fecha}) async {
    try {
      final ordenes = await obtenerOrdenesTecnico(tecnicoNombre, fecha: fecha);
      final equipos = <EquipoReversa>[];

      for (final orden in ordenes) {
        final tipo = orden['Tipo de Actividad']?.toString() ?? '';
        
        // Solo procesar bajas
        if (!tipo.toLowerCase().contains('baja')) continue;

        final items = orden['Items Orden']?.toString() ?? '';
        final pasos = orden['Pasos']?.toString() ?? '';
        
        // Extraer seriales de los pasos (más confiable)
        final serialesMatch = RegExp(r'Numero de serie\s*:\s*([A-Z0-9]+)', caseSensitive: false)
            .allMatches(pasos);
        
        for (final match in serialesMatch) {
          final serial = match.group(1) ?? '';
          if (serial.isEmpty) continue;

          // Determinar tipo de equipo
          String tipoEquipo = 'Equipo';
          if (pasos.contains('MTA')) tipoEquipo = 'MTA/Router';
          else if (pasos.contains('D-Box')) tipoEquipo = 'D-Box';
          else if (pasos.contains('Extensor')) tipoEquipo = 'Extensor WiFi';
          else if (pasos.contains('CM')) tipoEquipo = 'Cable Modem';

          final equipo = EquipoReversa(
            tecnicoRut: tecnicoRut,
            tecnicoNombre: tecnicoNombre,
            serial: serial,
            tipoEquipo: tipoEquipo,
            ot: orden['Orden de Trabajo']?.toString() ?? '',
            cliente: orden['Cliente']?.toString(),
            direccion: orden['Dirección']?.toString(),
            fechaDesinstalacion: fecha ?? DateTime.now(),
            estado: 'pendiente',
          );

          equipos.add(equipo);
        }
      }

      // Guardar en Supabase
      for (final equipo in equipos) {
        await _guardarEquipoReversa(equipo);
      }

      print('✅ [Reversa] ${equipos.length} equipos extraídos');
      return equipos;

    } catch (e) {
      print('❌ [Reversa] Error extrayendo equipos: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SUPABASE OPERATIONS
  // ═══════════════════════════════════════════════════════════

  Future<void> _guardarMetrica(MetricaProduccion metrica) async {
    try {
      await _supabase.from('metricas_produccion').upsert(
        metrica.toJson(),
        onConflict: 'tecnico_rut,fecha',
      );
    } catch (e) {
      print('❌ [Produccion] Error guardando métrica: $e');
    }
  }

  Future<void> _guardarEquipoReversa(EquipoReversa equipo) async {
    try {
      await _supabase.from('equipos_reversa').upsert(
        equipo.toJson(),
        onConflict: 'serial,ot',
      );
    } catch (e) {
      print('❌ [Reversa] Error guardando equipo: $e');
    }
  }

  Future<List<EquipoReversa>> obtenerEquiposPendientes(String tecnicoRut) async {
    try {
      final response = await _supabase
          .from('equipos_reversa')
          .select()
          .eq('tecnico_rut', tecnicoRut)
          .eq('estado', 'pendiente')
          .order('fecha_desinstalacion', ascending: false);

      return (response as List)
          .map((json) => EquipoReversa.fromJson(json))
          .toList();
    } catch (e) {
      print('❌ [Reversa] Error obteniendo equipos: $e');
      return [];
    }
  }

  Future<void> marcarEquipoEntregado(String equipoId, String bodegaRecibe) async {
    try {
      await _supabase.from('equipos_reversa').update({
        'estado': 'entregado',
        'fecha_entrega': DateTime.now().toIso8601String().split('T')[0],
        'bodega_recibe': bodegaRecibe,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', equipoId);
      
      print('✅ [Reversa] Equipo marcado como entregado');
    } catch (e) {
      print('❌ [Reversa] Error marcando entregado: $e');
    }
  }

  Future<MetricaProduccion?> obtenerMetricaHoy(String tecnicoRut) async {
    try {
      final hoy = DateTime.now().toIso8601String().split('T')[0];
      
      final response = await _supabase
          .from('metricas_produccion')
          .select()
          .eq('tecnico_rut', tecnicoRut)
          .eq('fecha', hoy)
          .maybeSingle();

      if (response != null) {
        return MetricaProduccion.fromJson(response);
      }
      return null;
    } catch (e) {
      print('❌ [Produccion] Error obteniendo métrica: $e');
      return null;
    }
  }

  Future<List<MetricaProduccion>> obtenerMetricasMes(String tecnicoRut, String mesAnno) async {
    try {
      final response = await _supabase
          .from('metricas_produccion')
          .select()
          .eq('tecnico_rut', tecnicoRut)
          .gte('fecha', '$mesAnno-01')
          .lte('fecha', '$mesAnno-31')
          .order('fecha', ascending: false);

      return (response as List)
          .map((json) => MetricaProduccion.fromJson(json))
          .toList();
    } catch (e) {
      print('❌ [Produccion] Error obteniendo métricas del mes: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // UTILIDADES
  // ═══════════════════════════════════════════════════════════

  int _parseHora(String hora) {
    try {
      final partes = hora.split(':');
      final h = int.parse(partes[0]);
      final m = partes.length > 1 ? int.parse(partes[1]) : 0;
      return h * 60 + m;
    } catch (e) {
      return 0;
    }
  }

  double _calcularDistanciaKm(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // Km
  }

  // ═══════════════════════════════════════════════════════════
  // PROCESAR HISTORIAL COMPLETO
  // ═══════════════════════════════════════════════════════════

  Future<List<MetricaProduccion>> procesarHistorial({
    required String tecnicoRut,
    required String tecnicoNombre,
    required DateTime fechaInicio,
    DateTime? fechaFin,
  }) async {
    final fin = fechaFin ?? DateTime.now();
    final metricas = <MetricaProduccion>[];
    
    print('🔍 [DEBUG] Iniciando procesarHistorial');
    print('🔍 [DEBUG] tecnicoNombre buscado: "$tecnicoNombre"');
    print('🔍 [DEBUG] tecnicoRut: "$tecnicoRut"');
    print('🔍 [DEBUG] Rango: ${fechaInicio.day}/${fechaInicio.month} al ${fin.day}/${fin.month}');
    
    // Obtener toda la sabana una sola vez
    final sabanaCompleta = await obtenerSabana();
    
    print('📋 [DEBUG] Total registros en sabana: ${sabanaCompleta.length}');
    
    if (sabanaCompleta.isEmpty) {
      print('❌ [DEBUG] Sabana vacía!');
      return [];
    }
    
    // DEBUG: Mostrar técnicos CREA únicos en la sabana
    final tecnicosCrea = sabanaCompleta
        .map((o) => o['Técnico']?.toString() ?? '')
        .where((t) => t.contains('_CREA_'))
        .toSet();
    print('👷 [DEBUG] Técnicos CREA en sabana: ${tecnicosCrea.length}');
    for (final t in tecnicosCrea) {
      print('   - "$t"');
    }
    
    // DEBUG: Mostrar fechas únicas
    final fechasUnicas = sabanaCompleta
        .map((o) => o['Fecha']?.toString() ?? 'Sin fecha')
        .toSet();
    print('📅 [DEBUG] Fechas en sabana:');
    for (final f in fechasUnicas) {
      print('   - "$f"');
    }
    
    // Filtrar por técnico (debe contener _CREA_ y el nombre)
    final ordenesDelTecnico = sabanaCompleta.where((orden) {
      final tecnico = orden['Técnico']?.toString() ?? '';
      
      // Solo técnicos CREA
      if (!tecnico.contains('_CREA_')) return false;
      
      // Y que coincida con el nombre buscado
      return tecnico.toLowerCase().contains(tecnicoNombre.toLowerCase());
    }).toList();
    
    print('🎯 [DEBUG] Órdenes que coinciden con "$tecnicoNombre": ${ordenesDelTecnico.length}');
    
    if (ordenesDelTecnico.isEmpty) {
      print('❌ [DEBUG] No se encontraron órdenes para el técnico');
      print('💡 [DEBUG] Verifica que el nombre configurado coincida parcialmente con alguno de los técnicos listados arriba');
      return [];
    }
    
    // Agrupar por fecha
    final Map<String, List<Map<String, dynamic>>> ordenesPorFecha = {};
    for (final orden in ordenesDelTecnico) {
      final fecha = orden['Fecha']?.toString() ?? '';
      ordenesPorFecha.putIfAbsent(fecha, () => []).add(orden);
    }
    
    print('📊 [DEBUG] Órdenes por fecha:');
    ordenesPorFecha.forEach((fecha, ordenes) {
      print('   - $fecha: ${ordenes.length} órdenes');
    });
    
    // Procesar cada fecha
    for (final entry in ordenesPorFecha.entries) {
      final fechaStr = entry.key;
      final ordenesDelDia = entry.value;
      
      // Parsear fecha DD/MM/YY
      final partes = fechaStr.split('/');
      if (partes.length != 3) continue;
      
      final dia = int.tryParse(partes[0]) ?? 0;
      final mes = int.tryParse(partes[1]) ?? 0;
      final anno = 2000 + (int.tryParse(partes[2]) ?? 25);
      
      final fechaParsed = DateTime(anno, mes, dia);
      
      print('⚙️ [DEBUG] Procesando $fechaStr (${ordenesDelDia.length} órdenes)');
      
      // Calcular métricas
      final metrica = await _calcularMetricasDeOrdenes(
        tecnicoRut: tecnicoRut,
        tecnicoNombre: tecnicoNombre,
        fecha: fechaParsed,
        ordenes: ordenesDelDia,
      );
      
      if (metrica != null) {
        metricas.add(metrica);
        print('✅ [DEBUG] Métrica guardada para $fechaStr');
        
        // Extraer equipos
        await _extraerEquiposDeOrdenes(
          tecnicoRut: tecnicoRut,
          tecnicoNombre: tecnicoNombre,
          fecha: fechaParsed,
          ordenes: ordenesDelDia,
        );
      }
    }
    
    print('🏁 [DEBUG] Historial procesado: ${metricas.length} días con métricas');
    return metricas;
  }

  // Método interno para calcular métricas de una lista de órdenes
  Future<MetricaProduccion?> _calcularMetricasDeOrdenes({
    required String tecnicoRut,
    required String tecnicoNombre,
    required DateTime fecha,
    required List<Map<String, dynamic>> ordenes,
  }) async {
    try {
      if (ordenes.isEmpty) return null;

      // Ordenar por hora de inicio
      ordenes.sort((a, b) {
        final inicioA = _parseHora(a['Inicio']?.toString() ?? '00:00');
        final inicioB = _parseHora(b['Inicio']?.toString() ?? '00:00');
        return inicioA.compareTo(inicioB);
      });

      // Calcular tiempos
      int tiempoTrabajo = 0;
      int tiempoTrayecto = 0;
      Map<int, int> ordenesPorHora = {};
      Map<String, int> ordenesPorZona = {};

      for (int i = 0; i < ordenes.length; i++) {
        final orden = ordenes[i];
        final inicio = _parseHora(orden['Inicio']?.toString() ?? '00:00');
        final fin = _parseHora(orden['Fin']?.toString() ?? '00:00');
        
        final duracion = fin - inicio;
        if (duracion > 0) tiempoTrabajo += duracion;

        final hora = inicio ~/ 60;
        ordenesPorHora[hora] = (ordenesPorHora[hora] ?? 0) + 1;

        final zona = orden['Zona de trabajo']?.toString() ?? 'Sin zona';
        ordenesPorZona[zona] = (ordenesPorZona[zona] ?? 0) + 1;

        if (i > 0) {
          final finAnterior = _parseHora(ordenes[i - 1]['Fin']?.toString() ?? '00:00');
          final trayecto = inicio - finAnterior;
          if (trayecto > 0 && trayecto < 120) {
            tiempoTrayecto += trayecto;
          }
        }
      }

      // Calcular km recorridos
      double kmTotal = 0;
      for (int i = 1; i < ordenes.length; i++) {
        final lat1 = (ordenes[i - 1]['Coord Y'] as num?)?.toDouble() ?? 0;
        final lon1 = (ordenes[i - 1]['Coord X'] as num?)?.toDouble() ?? 0;
        final lat2 = (ordenes[i]['Coord Y'] as num?)?.toDouble() ?? 0;
        final lon2 = (ordenes[i]['Coord X'] as num?)?.toDouble() ?? 0;
        
        if (lat1 != 0 && lon1 != 0 && lat2 != 0 && lon2 != 0) {
          kmTotal += _calcularDistanciaKm(lat1, lon1, lat2, lon2);
        }
      }

      // Contar estados
      int completadas = 0;
      int quiebres = 0;
      int altas = 0;
      int bajas = 0;
      int reparaciones = 0;

      for (final orden in ordenes) {
        final estado = orden['Estado']?.toString() ?? '';
        final tipo = orden['Tipo de Actividad']?.toString() ?? '';
        final codigoCierre = orden['Código de Cierre']?.toString() ?? '';

        if (estado == 'Completado') {
          completadas++;
          
          if (tipo.toLowerCase().contains('alta')) altas++;
          else if (tipo.toLowerCase().contains('baja')) bajas++;
          else if (tipo.toLowerCase().contains('reparaci')) reparaciones++;
        }

        if (_esQuiebre(codigoCierre)) {
          quiebres++;
        }
      }

      // Hora pico
      String? horaPico;
      int maxOrdenes = 0;
      ordenesPorHora.forEach((hora, cantidad) {
        if (cantidad > maxOrdenes) {
          maxOrdenes = cantidad;
          horaPico = '${hora.toString().padLeft(2, '0')}:00';
        }
      });

      // Zona más eficiente
      String? zonaMasEficiente;
      int maxZona = 0;
      ordenesPorZona.forEach((zona, cantidad) {
        if (cantidad > maxZona) {
          maxZona = cantidad;
          zonaMasEficiente = zona;
        }
      });

      // Calcular porcentajes
      final porcentajeProductividad = ordenes.isNotEmpty 
          ? (completadas / ordenes.length) * 100 
          : 0.0;
      final porcentajeQuiebre = ordenes.isNotEmpty 
          ? (quiebres / ordenes.length) * 100 
          : 0.0;
      final productividadVsQuiebre = porcentajeQuiebre > 0 
          ? porcentajeProductividad / porcentajeQuiebre 
          : porcentajeProductividad;

      // Costos
      final combustibleLitros = kmTotal / _rendimientoKmPorLitro;
      final costoCombustible = (combustibleLitros * _precioCombustiblePorLitro).round();

      // Tiempo de ocio
      final tiempoOcio = _jornadaMinutos - tiempoTrabajo - tiempoTrayecto;

      final metrica = MetricaProduccion(
        tecnicoRut: tecnicoRut,
        tecnicoNombre: tecnicoNombre,
        fecha: fecha,
        tiempoTrabajoMin: tiempoTrabajo,
        tiempoTrayectoMin: tiempoTrayecto,
        tiempoOcioMin: tiempoOcio > 0 ? tiempoOcio : 0,
        tiempoPromedioOrdenMin: completadas > 0 ? tiempoTrabajo ~/ completadas : 0,
        kmRecorridos: kmTotal,
        combustibleLitros: combustibleLitros,
        costoCombustible: costoCombustible,
        ordenesAsignadas: ordenes.length,
        ordenesCompletadas: completadas,
        quiebres: quiebres,
        porcentajeProductividad: porcentajeProductividad,
        porcentajeQuiebre: porcentajeQuiebre,
        productividadVsQuiebre: productividadVsQuiebre,
        altasCompletadas: altas,
        bajasCompletadas: bajas,
        reparacionesCompletadas: reparaciones,
        horaPico: horaPico,
        zonaMasEficiente: zonaMasEficiente,
      );

      // Guardar en Supabase
      await _guardarMetrica(metrica);

      return metrica;

    } catch (e) {
      print('❌ [Produccion] Error calculando métricas: $e');
      return null;
    }
  }

  // Método interno para extraer equipos de una lista de órdenes
  Future<void> _extraerEquiposDeOrdenes({
    required String tecnicoRut,
    required String tecnicoNombre,
    required DateTime fecha,
    required List<Map<String, dynamic>> ordenes,
  }) async {
    try {
      for (final orden in ordenes) {
        final tipo = orden['Tipo de Actividad']?.toString() ?? '';
        
        if (!tipo.toLowerCase().contains('baja')) continue;

        final pasos = orden['Pasos']?.toString() ?? '';
        
        final serialesMatch = RegExp(r'Numero de serie\s*:\s*([A-Z0-9]+)', caseSensitive: false)
            .allMatches(pasos);
        
        for (final match in serialesMatch) {
          final serial = match.group(1) ?? '';
          if (serial.isEmpty) continue;

          String tipoEquipo = 'Equipo';
          if (pasos.contains('MTA')) tipoEquipo = 'MTA/Router';
          else if (pasos.contains('D-Box')) tipoEquipo = 'D-Box';
          else if (pasos.contains('Extensor')) tipoEquipo = 'Extensor WiFi';
          else if (pasos.contains('CM')) tipoEquipo = 'Cable Modem';

          final equipo = EquipoReversa(
            tecnicoRut: tecnicoRut,
            tecnicoNombre: tecnicoNombre,
            serial: serial,
            tipoEquipo: tipoEquipo,
            ot: orden['Orden de Trabajo']?.toString() ?? '',
            cliente: orden['Cliente']?.toString(),
            direccion: orden['Dirección']?.toString(),
            fechaDesinstalacion: fecha,
            estado: 'pendiente',
          );

          await _guardarEquipoReversa(equipo);
        }
      }
    } catch (e) {
      print('❌ [Reversa] Error extrayendo equipos: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // CONSULTA RGU DESDE SUPABASE (produccion_crea)
  // ═══════════════════════════════════════════════════════════

  bool _esMesEnCurso(int mes, int anno) {
    final now = DateTime.now();
    return mes == now.month && anno == now.year;
  }

  /// Días laborables L-S ya transcurridos en el mes (hasta hoy si es el mes actual).
  int _diasLaborablesTranscurridos(int mes, int anno) {
    final now = DateTime.now();
    final ultimoDiaMes = DateTime(anno, mes + 1, 0).day;
    final diaLimite = _esMesEnCurso(mes, anno) ? now.day : ultimoDiaMes;
    var count = 0;
    for (var dia = 1; dia <= diaLimite; dia++) {
      if (DateTime(anno, mes, dia).weekday != DateTime.sunday) count++;
    }
    return count;
  }

  /// Resuelve ausencias evitando contar días futuros del mes en curso.
  ///
  /// `v_asistencia_tecnicos.ausencias` resta contra `dias_habiles_mes` (mes completo),
  /// por eso un técnico con 5/5 días de producción puede mostrar 17 ausencias.
  int _resolverDiasAusentes({
    required Map<String, dynamic>? asistenciaData,
    required int mes,
    required int anno,
    int diasTrabajadosFallback = 0,
  }) {
    if (asistenciaData == null) {
      if (!_esMesEnCurso(mes, anno)) return 0;
      final efectivos = _diasLaborablesTranscurridos(mes, anno);
      return (efectivos - diasTrabajadosFallback).clamp(0, efectivos);
    }

    final ausenciasView = (asistenciaData['ausencias'] as num?)?.toInt() ?? 0;
    if (!_esMesEnCurso(mes, anno)) return ausenciasView;

    final vacaciones = (asistenciaData['vacaciones'] as num?)?.toInt() ?? 0;
    final licencias = (asistenciaData['licencias'] as num?)?.toInt() ?? 0;
    final diasExcluidos = (asistenciaData['dias_excluidos'] as num?)?.toInt() ?? 0;
    final diasEfectivos = (asistenciaData['dias_efectivos'] as num?)?.toInt() ??
        _diasLaborablesTranscurridos(mes, anno);
    final diasProduccion =
        (asistenciaData['dias_con_produccion'] as num?)?.toInt() ?? 0;
    final sinProduccion =
        (asistenciaData['sin_produccion'] as num?)?.toInt() ?? 0;
    final diasPresentes = (asistenciaData['dias_presentes'] as num?)?.toInt();
    final diasCubiertos = diasPresentes ?? (diasProduccion + sinProduccion);

    final ausentesCalculados =
        diasEfectivos - diasCubiertos - vacaciones - licencias - diasExcluidos;

    print(
      '📊 [Produccion] Ausencias mes en curso: efectivos=$diasEfectivos, '
      'cubiertos=$diasCubiertos, view=$ausenciasView, '
      'calc=${ausentesCalculados.clamp(0, diasEfectivos)}',
    );

    return ausentesCalculados.clamp(0, diasEfectivos);
  }

  /// Obtener resumen del mes con datos de RGU desde Supabase
  Future<Map<String, dynamic>> obtenerResumenMesRGU(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    final now = DateTime.now();
    final mesConsulta = mes ?? now.month;
    final annoConsulta = anno ?? now.year;

    try {
      // Calcular días hábiles del mes (L-S - feriados)
      // TEMPORALMENTE COMENTADO - FeriadosChile
      // final diasHabiles = FeriadosChile.calcularDiasHabilesMes(mesConsulta, annoConsulta);
      // final feriadosEnMes = FeriadosChile.contarFeriadosHabilesEnMes(mesConsulta, annoConsulta);
      var diasHabiles = 22; // Valor aproximado temporal; se ajusta más abajo
      final feriadosEnMes = 0; // Temporal

      // Obtener asistencia desde v_asistencia_tecnicos (mismo origen que el dashboard)
      Map<String, dynamic>? asistenciaData;
      try {
        final periodoAsist = '$annoConsulta-${mesConsulta.toString().padLeft(2, '0')}';
        final asistenciaResp = await _supabase
            .from('v_asistencia_tecnicos')
            .select('rut,periodo,dias_habiles_mes,dias_efectivos,dias_con_produccion,dias_presentes,dias_no_marca,vacaciones,licencias,ausencias,sin_produccion,dias_excluidos')
            .eq('rut', rutTecnico)
            .eq('periodo', periodoAsist)
            .maybeSingle();
        asistenciaData = asistenciaResp != null ? Map<String, dynamic>.from(asistenciaResp) : null;
        if (asistenciaData != null) {
          print('📊 [Produccion] Asistencia v_asistencia_tecnicos (periodo: $periodoAsist):');
          print('   - Días con producción: ${asistenciaData['dias_con_produccion']}');
          print('   - Días efectivos: ${asistenciaData['dias_efectivos']}');
          print('   - Ausencias (view): ${asistenciaData['ausencias']}');
          print('   - Vacaciones: ${asistenciaData['vacaciones']}');
          print('   - Días hábiles mes: ${asistenciaData['dias_habiles_mes']}');
        } else {
          print('⚠️ [Produccion] Sin datos en v_asistencia_tecnicos para $periodoAsist');
        }
      } catch (e) {
        print('⚠️ [Produccion] Error obteniendo asistencia: $e');
        asistenciaData = null;
      }

      // produccion_creaciones usa DD/MM/YY (año 2 dígitos, mes con cero)
      final mesPadded  = mesConsulta.toString().padLeft(2, '0');
      final annoCorto  = (annoConsulta % 100).toString().padLeft(2, '0');
      final response = await _supabase
          .from('produccion_creaciones')
          .select()
          .eq('rut_tecnico', rutTecnico)
          .ilike('fecha_trabajo', '*/$mesPadded/$annoCorto');

      final ordenesMes = response as List;

      if (ordenesMes.isEmpty) {
        return {
          'totalRGU': 0.0,
          'promedioRGU': 0.0,
          'ordenesCompletadas': 0,
          'ordenesAsignadas': 0,
          'ordenesCanceladas': 0,
          'ordenesNoRealizadas': 0,
          'diasTrabajados': (asistenciaData?['dias_con_produccion'] as num?)?.toInt() ?? 0,
          'diasPX0': 0,
          'diasPX0List': <Map<String, dynamic>>[],
          'diasAusentes': _resolverDiasAusentes(
            asistenciaData: asistenciaData,
            mes: mesConsulta,
            anno: annoConsulta,
            diasTrabajadosFallback:
                (asistenciaData?['dias_con_produccion'] as num?)?.toInt() ?? 0,
          ),
          'diasHabiles': _esMesEnCurso(mesConsulta, annoConsulta)
              ? ((asistenciaData?['dias_efectivos'] as num?)?.toInt() ??
                  _diasLaborablesTranscurridos(mesConsulta, annoConsulta))
              : ((asistenciaData?['dias_habiles_mes'] as num?)?.toInt() ??
                  diasHabiles),
          'feriados': feriadosEnMes,
          'vacaciones': (asistenciaData?['vacaciones'] as num?)?.toInt() ?? 0,
          'efectividad': 0.0,
          'porcentajeQuiebre': 0.0,
        };
      }

      // Agrupar órdenes por fecha para análisis detallado
      Map<String, List<dynamic>> ordenesPorFecha = {};
      for (var orden in ordenesMes) {
        final fecha = orden['fecha_trabajo']?.toString() ?? '';
        if (fecha.isNotEmpty) {
          ordenesPorFecha.putIfAbsent(fecha, () => []);
          ordenesPorFecha[fecha]!.add(orden);
        }
      }

      // Analizar cada día
      int completadas = 0;
      int canceladas = 0;
      int noRealizadas = 0;
      double totalRGU = 0;
      Set<String> diasConProduccion = {};
      List<Map<String, dynamic>> diasPX0List = [];

      for (var entry in ordenesPorFecha.entries) {
        final fecha = entry.key;
        final ordenesDelDia = entry.value;

        int completadasDia = 0;
        double rguDia = 0;

        for (var orden in ordenesDelDia) {
          final estado = orden['estado']?.toString() ?? '';

          if (cuentaComoProduccion(orden)) {
            completadas++;
            completadasDia++;
            final rgu = (orden['rgu_total'] as num?)?.toDouble() ?? 0;
            totalRGU += rgu;
            rguDia += rgu;
          } else if (estado == 'Cancelado') {
            canceladas++;
          } else if (esEstadoNoRealizada(orden)) {
            noRealizadas++;
          }
        }

        if (completadasDia > 0) {
          diasConProduccion.add(fecha);
        } else {
          // Día PX-0: usa es_px0 si está disponible, sino lo infiere
          final esPx0 = ordenesDelDia.any((o) => o['es_px0'] == true)
              || !ordenesDelDia.any((o) => cuentaComoProduccion(o));
          if (esPx0) {
            diasPX0List.add({
              'fecha': fecha,
              'ordenes': ordenesDelDia.length,
            });
          }
        }
      }

      final totalAsignadas = completadas + canceladas + noRealizadas;
      final diasPX0 = diasPX0List.length;
      
      // Días trabajados y asistencia desde v_asistencia_tecnicos (mismo origen que el dashboard)
      int diasTrabajados;
      int diasAusentesFinales;
      int feriadosFinales;
      int vacacionesFinales;

      feriadosFinales = feriadosEnMes;

      if (asistenciaData != null) {
        // v_asistencia_tecnicos tiene datos — fuente de verdad igual que el dashboard
        diasTrabajados = (asistenciaData['dias_con_produccion'] as num?)?.toInt()
            ?? diasConProduccion.length;
        vacacionesFinales = (asistenciaData['vacaciones'] as num?)?.toInt() ?? 0;
        diasAusentesFinales = _resolverDiasAusentes(
          asistenciaData: asistenciaData,
          mes: mesConsulta,
          anno: annoConsulta,
          diasTrabajadosFallback: diasTrabajados + diasPX0,
        );
        print(
          '✅ [Produccion] Usando v_asistencia_tecnicos: dias_con_produccion=$diasTrabajados, '
          'ausencias=$diasAusentesFinales, vacaciones=$vacacionesFinales',
        );
      } else {
        // Fallback: calcular desde produccion_creaciones
        diasTrabajados = diasConProduccion.length + diasPX0;
        vacacionesFinales = 0;
        diasAusentesFinales = _resolverDiasAusentes(
          asistenciaData: null,
          mes: mesConsulta,
          anno: annoConsulta,
          diasTrabajadosFallback: diasTrabajados,
        );
        print('⚠️ [Produccion] Sin asistencia en Supabase — calculando desde produccion_creaciones ($diasTrabajados días)');
      }

      if (_esMesEnCurso(mesConsulta, annoConsulta)) {
        diasHabiles = (asistenciaData?['dias_efectivos'] as num?)?.toInt() ??
            _diasLaborablesTranscurridos(mesConsulta, annoConsulta);
      } else if (asistenciaData != null) {
        diasHabiles =
            (asistenciaData['dias_habiles_mes'] as num?)?.toInt() ?? diasHabiles;
      }

      // Divisor para promedio = días trabajados (ya incluye PX-0)
      final divisor = diasTrabajados > 0 ? diasTrabajados : 1;
      final promedioRGU = totalRGU / divisor;

      final efectividad = totalAsignadas > 0
          ? (completadas / totalAsignadas) * 100
          : 0.0;

      final porcentajeQuiebre = totalAsignadas > 0
          ? ((canceladas + noRealizadas) / totalAsignadas) * 100
          : 0.0;

      print('📊 [Produccion] Resumen final mes: $mesConsulta/$annoConsulta');
      print('   - Días hábiles (L-S - feriados): $diasHabiles');
      print('   - Feriados: $feriadosFinales');
      print('   - Días trabajados: $diasTrabajados');
      print('   - Días con producción: ${diasConProduccion.length}');
      print('   - Días PX-0: $diasPX0');
      print('   - Días ausentes: $diasAusentesFinales');
      print('   - Vacaciones: $vacacionesFinales');
      print('   - Divisor para RGU/día: $divisor');
      print('   - Promedio RGU: ${promedioRGU.toStringAsFixed(2)}');

      return {
        'totalRGU': totalRGU,
        'promedioRGU': promedioRGU,
        'ordenesCompletadas': completadas,
        'ordenesAsignadas': totalAsignadas,
        'ordenesCanceladas': canceladas,
        'ordenesNoRealizadas': noRealizadas,
        'diasTrabajados': diasTrabajados,
        'diasPX0': diasPX0,
        'diasPX0List': diasPX0List, // Lista con fechas de días PX-0
        'diasAusentes': diasAusentesFinales,
        'diasHabiles': diasHabiles,
        'feriados': feriadosFinales,
        'vacaciones': vacacionesFinales,
        'efectividad': efectividad,
        'porcentajeQuiebre': porcentajeQuiebre,
      };
    } catch (e) {
      print('❌ [Produccion] Error obteniendo resumen RGU: $e');
      return {
        'totalRGU': 0.0,
        'promedioRGU': 0.0,
        'ordenesCompletadas': 0,
        'ordenesAsignadas': 0,
        'ordenesCanceladas': 0,
        'ordenesNoRealizadas': 0,
        'diasTrabajados': 0,
        'diasPX0': 0,
        'diasPX0List': <Map<String, dynamic>>[],
        'diasAusentes': 0,
        'diasHabiles': 0,
        'feriados': 0,
        'vacaciones': 0,
        'efectividad': 0.0,
        'porcentajeQuiebre': 0.0,
      };
    }
  }

  /// Obtener detalle por día con RGU
  Future<List<Map<String, dynamic>>> obtenerDetallePorDiaRGU(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    final now = DateTime.now();
    final mesConsulta = mes ?? now.month;
    final annoConsulta = anno ?? now.year;

    try {
      // produccion_creaciones usa DD/MM/YY (año 2 dígitos, mes con cero)
      final mesPadded = mesConsulta.toString().padLeft(2, '0');
      final annoCorto = (annoConsulta % 100).toString().padLeft(2, '0');
      final response = await _supabase
          .from('produccion_creaciones')
          .select()
          .eq('rut_tecnico', rutTecnico)
          .ilike('fecha_trabajo', '*/$mesPadded/$annoCorto');

      final ordenesCompletadas = response as List;

      // Agrupar por día (solo órdenes que cuentan como producción)
      Map<String, Map<String, dynamic>> porDia = {};

      for (var orden in ordenesCompletadas) {
        if (!cuentaComoProduccion(orden)) continue;
        final fecha = orden['fecha_trabajo']?.toString() ?? '';
        if (fecha.isEmpty) continue;

        if (!porDia.containsKey(fecha)) {
          porDia[fecha] = {
            'fecha': fecha,
            'ordenesCompletadas': 0,
            'rguTotal': 0.0,
            'ordenes': <Map<String, dynamic>>[], // Lista de órdenes individuales
          };
        }

        porDia[fecha]!['ordenesCompletadas'] = (porDia[fecha]!['ordenesCompletadas'] as int) + 1;
        porDia[fecha]!['rguTotal'] = (porDia[fecha]!['rguTotal'] as double) +
            ((orden['rgu_total'] as num?)?.toDouble() ?? 0);

        // Agregar detalle de la orden
        (porDia[fecha]!['ordenes'] as List<Map<String, dynamic>>).add({
          'orden_trabajo': orden['orden_trabajo'],
          'tipo_orden': orden['tipo_orden'],
          'rgu_base': (orden['rgu_base'] as num?)?.toDouble() ?? 0,
          'rgu_adicional': (orden['rgu_adicional'] as num?)?.toDouble() ?? 0,
          'rgu_total': (orden['rgu_total'] as num?)?.toDouble() ?? 0,
          'cant_dbox': orden['cant_dbox'] ?? 0,
          'cant_extensores': orden['cant_extensores'] ?? 0,
          'hora_inicio': orden['hora_inicio'],
          'hora_fin': orden['hora_fin'],
          'fecha_trabajo': orden['fecha_trabajo'],
        });
      }

      // Convertir a lista y ordenar por fecha (más reciente primero)
      final lista = porDia.values.toList();
      lista.sort((a, b) {
        // Parsear fechas DD/MM/YY o D/M/YYYY
        DateTime? _parseFecha(String s) {
          final p = s.split('/');
          if (p.length != 3) return null;
          final d = int.tryParse(p[0]) ?? 0;
          final m = int.tryParse(p[1]) ?? 0;
          var y  = int.tryParse(p[2]) ?? 0;
          if (y < 100) y += 2000;
          return DateTime(y, m, d);
        }
        final fechaA = _parseFecha(a['fecha'] as String);
        final fechaB = _parseFecha(b['fecha'] as String);
        if (fechaA != null && fechaB != null) {
          return fechaB.compareTo(fechaA); // Más reciente primero
        }
        return 0;
      });

      return lista;
    } catch (e) {
      print('❌ [Produccion] Error obteniendo detalle por día RGU: $e');
      return [];
    }
  }

  /// Formatos de fecha que pueden existir en [produccion_crea.fecha_trabajo].
  static List<String> variantesFechaConsulta(String fechaTrabajo) {
    final s = fechaTrabajo.trim();
    if (s.isEmpty) return [];
    final out = <String>{s};
    final partes = s.split(RegExp(r'[\/\.]'));
    if (partes.length == 3) {
      final d = partes[0].padLeft(2, '0');
      final m = partes[1].padLeft(2, '0');
      var y = partes[2];
      if (y.length == 2) {
        out.add('$d/$m/$y');
        out.add('$d.$m.$y');
      }
      if (y.length == 4) {
        final yy = y.substring(2);
        out.add('$d/$m/$yy');
        out.add('$d.$m.$yy');
      }
    }
    return out.toList();
  }

  /// Fila completa de [produccion_crea] para una OT concreta.
  Future<Map<String, dynamic>?> obtenerOrdenProduccionCrea({
    required String rutTecnico,
    required String ordenTrabajo,
    required String fechaTrabajo,
  }) async {
    try {
      final fechas = variantesFechaConsulta(fechaTrabajo);
      final ruts = ProduccionService.rutVariantes(rutTecnico);
      if (fechas.isEmpty || ruts.isEmpty) return null;
      final row = await _supabase
          .from('produccion_crea')
          .select()
          .eq('orden_trabajo', ordenTrabajo)
          .inFilter('rut_tecnico', ruts)
          .inFilter('fecha_trabajo', fechas)
          .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (e) {
      print('⚠️ [Produccion] obtenerOrdenProduccionCrea: $e');
      return null;
    }
  }

  /// Órdenes completadas de un día (p. ej. vista supervisor).
  Future<List<Map<String, dynamic>>> listarOrdenesCompletadasDia({
    required String rutTecnico,
    required String fechaTrabajo,
  }) async {
    try {
      final fechas = variantesFechaConsulta(fechaTrabajo);
      final ruts = ProduccionService.rutVariantes(rutTecnico);
      if (fechas.isEmpty || ruts.isEmpty) return [];
      final resp = await _supabase
          .from('produccion_crea')
          .select()
          .inFilter('rut_tecnico', ruts)
          .inFilter('fecha_trabajo', fechas);
      final lista = (resp as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((o) => cuentaComoProduccion(o))
          .toList();
      lista.sort((a, b) => (a['hora_inicio'] ?? '')
          .toString()
          .compareTo((b['hora_inicio'] ?? '').toString()));
      return lista;
    } catch (e) {
      print('⚠️ [Produccion] listarOrdenesCompletadasDia: $e');
      return [];
    }
  }

  // Obtener resumen del mes (método antiguo - mantener para compatibilidad)
  Future<Map<String, dynamic>> obtenerResumenMes(String tecnicoRut, {DateTime? mes}) async {
    final fecha = mes ?? DateTime.now();
    final inicioMes = DateTime(fecha.year, fecha.month, 1);
    final finMes = DateTime(fecha.year, fecha.month + 1, 0);
    
    try {
      final response = await _supabase
          .from('metricas_produccion')
          .select()
          .eq('tecnico_rut', tecnicoRut)
          .gte('fecha', inicioMes.toIso8601String().split('T')[0])
          .lte('fecha', finMes.toIso8601String().split('T')[0]);

      final metricas = (response as List).map((json) => MetricaProduccion.fromJson(json)).toList();

      if (metricas.isEmpty) {
        return {
          'diasTrabajados': 0,
          'ordenesTotales': 0,
          'ordenesCompletadas': 0,
          'quiebresTotales': 0,
          'kmTotales': 0.0,
          'tiempoTrabajoTotal': 0,
          'tiempoTrayectoTotal': 0,
          'combustibleTotal': 0.0,
          'costoTotal': 0,
          'promedioOrdenesDia': 0.0,
          'porcentajeProductividad': 0.0,
          'porcentajeQuiebre': 0.0,
        };
      }

      int ordenesTotales = 0;
      int ordenesCompletadas = 0;
      int quiebresTotales = 0;
      double kmTotales = 0;
      int tiempoTrabajoTotal = 0;
      int tiempoTrayectoTotal = 0;
      double combustibleTotal = 0;
      int costoTotal = 0;

      for (final m in metricas) {
        ordenesTotales += m.ordenesAsignadas;
        ordenesCompletadas += m.ordenesCompletadas;
        quiebresTotales += m.quiebres;
        kmTotales += m.kmRecorridos;
        tiempoTrabajoTotal += m.tiempoTrabajoMin;
        tiempoTrayectoTotal += m.tiempoTrayectoMin;
        combustibleTotal += m.combustibleLitros;
        costoTotal += m.costoCombustible;
      }

      return {
        'diasTrabajados': metricas.length,
        'ordenesTotales': ordenesTotales,
        'ordenesCompletadas': ordenesCompletadas,
        'quiebresTotales': quiebresTotales,
        'kmTotales': kmTotales,
        'tiempoTrabajoTotal': tiempoTrabajoTotal,
        'tiempoTrayectoTotal': tiempoTrayectoTotal,
        'combustibleTotal': combustibleTotal,
        'costoTotal': costoTotal,
        'promedioOrdenesDia': metricas.isNotEmpty ? ordenesCompletadas / metricas.length : 0.0,
        'porcentajeProductividad': ordenesTotales > 0 ? (ordenesCompletadas / ordenesTotales) * 100 : 0.0,
        'porcentajeQuiebre': ordenesTotales > 0 ? (quiebresTotales / ordenesTotales) * 100 : 0.0,
        'metricas': metricas,
      };
    } catch (e) {
      print('❌ [Produccion] Error obteniendo resumen: $e');
      return {};
    }
  }

  // ═══════════════════════════════════════════════════════════
  // RANKING DE PRODUCCIÓN
  // ═══════════════════════════════════════════════════════════

  /// Obtener ranking de técnicos por RGU del mes
  Future<Map<String, dynamic>> obtenerRankingMes({
    int? mes,
    int? anno,
  }) async {
    final now = DateTime.now();
    final mesConsulta = mes ?? now.month;
    final annoConsulta = anno ?? now.year;

    print('🔍 [Ranking] Consultando mes: $mesConsulta, año: $annoConsulta');

    try {
      final todasOrdenes = await _cargarOrdenesProduccionCreacionesMes(
        mes: mesConsulta,
        anno: annoConsulta,
      );

      print('📊 [Ranking] Total órdenes mes (produccion_creaciones): ${todasOrdenes.length}');

      final ordenesMes = todasOrdenes.where(cuentaComoProduccion).toList();

      print('✅ [Ranking] Órdenes con producción mes $mesConsulta/$annoConsulta: ${ordenesMes.length}');

      if (ordenesMes.isEmpty) {
        print('⚠️ [Ranking] No hay órdenes para el mes seleccionado');
        return {
          'ranking': <Map<String, dynamic>>[],
          'totalTecnicos': 0,
        };
      }

      // Agrupar por técnico y sumar RGU
      Map<String, Map<String, dynamic>> porTecnico = {};

      for (var orden in ordenesMes) {
        final rut = orden['rut_tecnico']?.toString() ?? '';
        final nombre = orden['tecnico']?.toString() ?? '';
        final rgu = (orden['rgu_total'] as num?)?.toDouble() ?? 0;
        final fecha = orden['fecha_trabajo']?.toString() ?? '';

        if (rut.isEmpty) continue;

        if (!porTecnico.containsKey(rut)) {
          porTecnico[rut] = {
            'rut': rut,
            'nombre': nombre,
            'rguTotal': 0.0,
            'ordenes': 0,
            'diasTrabajados': <String>{}, // Set para días únicos
          };
        }

        porTecnico[rut]!['rguTotal'] = (porTecnico[rut]!['rguTotal'] as double) + rgu;
        porTecnico[rut]!['ordenes'] = (porTecnico[rut]!['ordenes'] as int) + 1;
        if (fecha.isNotEmpty) {
          (porTecnico[rut]!['diasTrabajados'] as Set<String>).add(fecha);
        }
      }

      // Calcular promedio RGU por técnico
      for (var tecnico in porTecnico.values) {
        final diasTrabajados = (tecnico['diasTrabajados'] as Set<String>).length;
        final rguTotal = tecnico['rguTotal'] as double;
        final promedioRGU = diasTrabajados > 0 ? rguTotal / diasTrabajados : 0.0;
        tecnico['promedioRGU'] = promedioRGU;
        tecnico['diasTrabajados'] = diasTrabajados;
      }

      print('👥 [Ranking] Técnicos únicos encontrados: ${porTecnico.length}');

      // Convertir a lista y ordenar por RGU descendente
      final ranking = porTecnico.values.toList();
      ranking.sort((a, b) => (b['rguTotal'] as double).compareTo(a['rguTotal'] as double));

      // Asignar posiciones
      for (int i = 0; i < ranking.length; i++) {
        ranking[i]['posicion'] = i + 1;
      }

      // Debug: mostrar top 5
      print('🏆 [Ranking] Top 5:');
      for (var i = 0; i < (ranking.length < 5 ? ranking.length : 5); i++) {
        print('   #${ranking[i]['posicion']} ${ranking[i]['nombre']} - ${(ranking[i]['rguTotal'] as double).toStringAsFixed(1)} RGU');
      }

      return {
        'ranking': ranking,
        'totalTecnicos': ranking.length,
      };
    } catch (e, stack) {
      print('❌ [Ranking] Error: $e');
      print('❌ [Ranking] Stack: $stack');
      return {
        'ranking': <Map<String, dynamic>>[],
        'totalTecnicos': 0,
      };
    }
  }

  /// Obtener posición específica de un técnico en el ranking
  Future<Map<String, dynamic>> obtenerPosicionTecnico(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    print('🎯 [Posicion] Buscando RUT: $rutTecnico');

    final rankingData = await obtenerRankingMes(mes: mes, anno: anno);
    final ranking = List<Map<String, dynamic>>.from(rankingData['ranking'] as List);

    print('🎯 [Posicion] Ranking tiene ${ranking.length} técnicos');

    // Buscar al técnico (normalizar variantes de RUT)
    Map<String, dynamic>? tecnicoEncontrado;
    for (var t in ranking) {
      if (_rutsCoinciden(t['rut']?.toString() ?? '', rutTecnico)) {
        tecnicoEncontrado = t;
        break;
      }
    }

    print('🎯 [Posicion] Técnico encontrado: $tecnicoEncontrado');

    // Devolver TODOS los técnicos, no solo top 10
    // Nombre del campo sigue siendo 'top10' para no romper compatibilidad
    final todosLosTecnicos = ranking.toList();

    if (tecnicoEncontrado == null) {
      return {
        'posicion': 0,
        'totalTecnicos': ranking.length,
        'rguTotal': 0.0,
        'promedioRGU': 0.0,
        'ordenes': 0,
        'top10': todosLosTecnicos, // Todos los técnicos, no solo top 10
      };
    }

    return {
      'posicion': tecnicoEncontrado['posicion'],
      'totalTecnicos': ranking.length,
      'rguTotal': tecnicoEncontrado['rguTotal'],
      'promedioRGU': tecnicoEncontrado['promedioRGU'] ?? 0.0,
      'ordenes': tecnicoEncontrado['ordenes'],
      'nombre': tecnicoEncontrado['nombre'],
      'top10': todosLosTecnicos, // Todos los técnicos, no solo top 10
    };
  }

  // ═══════════════════════════════════════════════════════════
  // RANKING DE PRODUCTIVIDAD
  // ═══════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> obtenerRankingProductividad({
    int? mes,
    int? anno,
  }) async {
    final now = DateTime.now();
    final mesConsulta = mes ?? now.month;
    final annoConsulta = anno ?? now.year;

    try {
      final ordenesMes = (await _cargarOrdenesProduccionCreacionesMes(
        mes: mesConsulta,
        anno: annoConsulta,
      ))
          .where(_ordenCuentaParaMetricasTiempo)
          .toList();

      if (ordenesMes.isEmpty) {
        return {'ranking': <Map<String, dynamic>>[], 'totalTecnicos': 0};
      }

      final porTecnico = <String, Map<String, List<Map<String, dynamic>>>>{};
      final nombres = <String, String>{};

      for (final orden in ordenesMes) {
        final rut = orden['rut_tecnico']?.toString() ?? '';
        if (rut.isEmpty) continue;
        nombres[rut] = orden['tecnico']?.toString() ?? nombres[rut] ?? '';
        final fecha = orden['fecha_trabajo']?.toString() ?? '';
        porTecnico.putIfAbsent(rut, () => {});
        porTecnico[rut]!.putIfAbsent(fecha, () => []).add(orden);
      }

      final ranking = <Map<String, dynamic>>[];
      for (final entry in porTecnico.entries) {
        final metricas = _calcularMetricasTiempoDesdePorDia(
          rutTecnico: entry.key,
          porDia: entry.value,
          mesConsulta: mesConsulta,
          annoConsulta: annoConsulta,
        );
        ranking.add({
          'rut': entry.key,
          'nombre': nombres[entry.key] ?? '',
          'productividad': (metricas['productividad'] as num?)?.toDouble() ?? 0.0,
          'diasTrabajados': metricas['diasTrabajados'] ?? 0,
        });
      }

      ranking.sort((a, b) =>
          (b['productividad'] as double).compareTo(a['productividad'] as double));
      for (var i = 0; i < ranking.length; i++) {
        ranking[i]['posicion'] = i + 1;
      }

      return {'ranking': ranking, 'totalTecnicos': ranking.length};
    } catch (e) {
      print('❌ [Ranking Productividad] Error: $e');
      return {'ranking': <Map<String, dynamic>>[], 'totalTecnicos': 0};
    }
  }

  Future<Map<String, dynamic>> obtenerPosicionProductividad(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    final data = await obtenerRankingProductividad(mes: mes, anno: anno);
    final ranking = List<Map<String, dynamic>>.from(data['ranking'] as List);

    Map<String, dynamic>? encontrado;
    for (final t in ranking) {
      if (_rutsCoinciden(t['rut']?.toString() ?? '', rutTecnico)) {
        encontrado = t;
        break;
      }
    }

    if (encontrado == null) {
      return {
        'posicion': 0,
        'totalTecnicos': ranking.length,
        'productividad': 0.0,
        'diasTrabajados': 0,
        'top10': ranking,
      };
    }

    return {
      'posicion': encontrado['posicion'],
      'totalTecnicos': ranking.length,
      'productividad': encontrado['productividad'],
      'diasTrabajados': encontrado['diasTrabajados'],
      'nombre': encontrado['nombre'],
      'top10': ranking,
    };
  }

  // ═══════════════════════════════════════════════════════════
  // MÉTRICAS DE TIEMPO
  // ═══════════════════════════════════════════════════════════

  static const int _minutosBodegaExtra = 60; // 08:45 → 09:45

  String _filtroFechaMesIlike(int mes, int anno) {
    final mesPadded = mes.toString().padLeft(2, '0');
    final annoCorto = (anno % 100).toString().padLeft(2, '0');
    return '*/$mesPadded/$annoCorto';
  }

  String _normalizarRutKey(String rut) =>
      rut.replaceAll(RegExp(r'[.\-\s]'), '').toUpperCase();

  static bool rutsCoinciden(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    final keysA = rutVariantes(a).map(_normalizarRutKeyStatic).toSet();
    final keysB = rutVariantes(b).map(_normalizarRutKeyStatic).toSet();
    return keysA.intersection(keysB).isNotEmpty;
  }

  static String _normalizarRutKeyStatic(String rut) =>
      rut.replaceAll(RegExp(r'[.\-\s]'), '').toUpperCase();

  bool _rutsCoinciden(String a, String b) => rutsCoinciden(a, b);

  bool _ordenCuentaParaMetricasTiempo(Map<String, dynamic> orden) {
    final hora = orden['hora_inicio']?.toString().trim() ?? '';
    if (hora.isEmpty || hora == '00:00') return false;
    final estado = (orden['estado']?.toString() ?? '').trim();
    return estado.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> _cargarOrdenesProduccionCreacionesMes({
    required int mes,
    required int anno,
    String? rutTecnico,
  }) async {
    final filtro = _filtroFechaMesIlike(mes, anno);
    final campos =
        'rut_tecnico,tecnico,rgu_total,fecha_trabajo,estado,area_derivacion,hora_inicio,hora_fin,duracion_min';
    final todas = <Map<String, dynamic>>[];
    var offset = 0;
    const pageSize = 1000;
    var hasMore = true;

    while (hasMore) {
      var query = _supabase
          .from('produccion_creaciones')
          .select(campos)
          .ilike('fecha_trabajo', filtro);

      if (rutTecnico != null && rutTecnico.isNotEmpty) {
        query = query.inFilter('rut_tecnico', rutVariantes(rutTecnico));
      }

      final response = await query.range(offset, offset + pageSize - 1);
      final batch = (response as List)
          .map((o) => Map<String, dynamic>.from(o as Map))
          .toList();
      todas.addAll(batch);
      hasMore = batch.length == pageSize;
      offset += pageSize;
    }

    return todas
        .where((o) =>
            _fechaCoincideMesConsulta(o['fecha_trabajo']?.toString() ?? '', mes, anno))
        .toList();
  }

  int _duracionMinOrden(Map<String, dynamic> orden) {
    final dur = (orden['duracion_min'] as num?)?.toInt() ?? 0;
    if (dur > 0) return dur;
    final ini = _parseHoraAMinutos(orden['hora_inicio']?.toString() ?? '00:00');
    final fin = _parseHoraAMinutos(orden['hora_fin']?.toString() ?? '00:00');
    return fin > ini ? fin - ini : 0;
  }

  bool _aplicaJornadaJunio2026(int mes, int anno) =>
      anno > 2026 || (anno == 2026 && mes >= 6);

  int _parseAnnoFechaTrabajo(String annoStr) {
    final n = int.tryParse(annoStr) ?? 0;
    if (n >= 100) return n;
    return n >= 50 ? 1900 + n : 2000 + n;
  }

  bool _fechaCoincideMesConsulta(String fechaStr, int mes, int anno) {
    final partes = fechaStr.split('/');
    if (partes.length != 3) return false;
    final mesOrden = int.tryParse(partes[1]) ?? 0;
    final annoOrden = _parseAnnoFechaTrabajo(partes[2]);
    return mesOrden == mes && annoOrden == anno;
  }

  DateTime? _parseFechaTrabajo(String fechaStr) =>
      _parseFechaTrabajoPartes(fechaStr.split('/'));

  DateTime? _parseFechaTrabajoPartes(List<String> partes) {
    if (partes.length != 3) return null;
    final dia = int.tryParse(partes[0]) ?? 1;
    final mes = int.tryParse(partes[1]) ?? 1;
    final anno = _parseAnnoFechaTrabajo(partes[2]);
    return DateTime(anno, mes, dia);
  }

  int _semanaIsoDelAnio(DateTime fecha) {
    final jueves = fecha.add(Duration(days: DateTime.thursday - fecha.weekday));
    final primerJueves = DateTime(jueves.year, 1, 4);
    return 1 + jueves.difference(primerJueves).inDays ~/ 7;
  }

  ({int inicio, int fin, int productivoMin}) _horarioJornada({
    required String rutTecnico,
    required DateTime? fecha,
    required int mesConsulta,
    required int annoConsulta,
  }) {
    final esSabado = fecha?.weekday == DateTime.saturday;

    if (_aplicaJornadaJunio2026(mesConsulta, annoConsulta) &&
        fecha != null &&
        fecha.weekday != DateTime.sunday) {
      return (inicio: 585, fin: 1065, productivoMin: 480); // L-S 9:45–17:45
    }

    if (_rutsTurnoRotativo.contains(rutTecnico)) {
      final wd = fecha?.weekday ?? DateTime.monday;
      final fin = (esSabado || wd == DateTime.monday || wd == DateTime.thursday)
          ? 1035
          : 1095;
      return (inicio: 585, fin: fin, productivoMin: esSabado ? 240 : 480);
    }

    final fin = esSabado
        ? 900
        : (_rutsTurnoAntiguo.contains(rutTecnico) ? 1125 : 1065);
    final inicio = esSabado ? 600 : 585;
    return (inicio: inicio, fin: fin, productivoMin: esSabado ? 240 : 480);
  }

  Map<String, dynamic> _calcularMetricasTiempoDesdePorDia({
    required String rutTecnico,
    required Map<String, List<Map<String, dynamic>>> porDia,
    required int mesConsulta,
    required int annoConsulta,
  }) {
    if (porDia.isEmpty) return _metricasTiempoVacias();

    int tiempoTrabajoTotal = 0;
    int tiempoTrayectoTotal = 0;
    int tiempoInicioTardioTotal = 0;
    int tiempoFinTempranoTotal = 0;
    int tiempoProductivoEsperado = 0;
    final diasTrabajados = porDia.length;
    int diasSemana = 0;
    int diasSabado = 0;
    final detalleInicioTardio = <Map<String, dynamic>>[];
    final detalleHorasExtras = <Map<String, dynamic>>[];
    int horasExtrasTotal = 0;
    final overtimePorSemana = <String, List<Map<String, dynamic>>>{};
    final semanasConTrabajo = <int>{};

    for (final entry in porDia.entries) {
      final fechaStr = entry.key;
      var ordenesDelDia = entry.value;
      final partesFecha = fechaStr.split('/');
      final fecha = _parseFechaTrabajoPartes(partesFecha);
      if (fecha == null) continue;

      final jornada = _horarioJornada(
        rutTecnico: rutTecnico,
        fecha: fecha,
        mesConsulta: mesConsulta,
        annoConsulta: annoConsulta,
      );
      final horaInicioJornada = jornada.inicio;
      final horaFinJornada = jornada.fin;
      final esSabado = fecha.weekday == DateTime.saturday;

      if (esSabado) {
        diasSabado++;
      } else {
        diasSemana++;
      }

      tiempoProductivoEsperado += jornada.productivoMin;
      semanasConTrabajo.add(_semanaIsoDelAnio(fecha));

      ordenesDelDia.sort((a, b) {
        final horaA = _parseHoraAMinutos(a['hora_inicio']?.toString() ?? '00:00');
        final horaB = _parseHoraAMinutos(b['hora_inicio']?.toString() ?? '00:00');
        return horaA.compareTo(horaB);
      });

      var trabajoDia = 0;
      for (final orden in ordenesDelDia) {
        trabajoDia += _duracionMinOrden(orden);
      }
      tiempoTrabajoTotal += trabajoDia;

      final primeraHora =
          _parseHoraAMinutos(ordenesDelDia.first['hora_inicio']?.toString() ?? '00:00');
      final ultimaHora =
          _parseHoraAMinutos(ordenesDelDia.last['hora_fin']?.toString() ?? '00:00');
      final ultimaHoraStr = ordenesDelDia.last['hora_fin']?.toString() ?? '';

      if (primeraHora > horaInicioJornada && primeraHora < 660) {
        final retraso = primeraHora - horaInicioJornada;
        tiempoInicioTardioTotal += retraso;
        detalleInicioTardio.add({
          'fecha': fechaStr,
          'horaInicio': ordenesDelDia.first['hora_inicio']?.toString() ?? '00:00',
          'retraso': retraso,
          'esSabado': esSabado,
        });
      }

      if (ultimaHora < horaFinJornada) {
        tiempoFinTempranoTotal += (horaFinJornada - ultimaHora);
      }

      // Extra desde 17:46 (fin jornada 17:45 = minuto 1065)
      if (ultimaHora > horaFinJornada) {
        final extrasMin = ultimaHora - horaFinJornada;
        horasExtrasTotal += extrasMin;
        final diaNum = int.tryParse(partesFecha[0]) ?? 0;
        var semNum = 1;
        if (diaNum > 28) {
          semNum = 5;
        } else if (diaNum > 21) {
          semNum = 4;
        } else if (diaNum > 14) {
          semNum = 3;
        } else if (diaNum > 7) {
          semNum = 2;
        }
        overtimePorSemana.putIfAbsent('semana_$semNum', () => []).add({
          'fecha': fechaStr,
          'horasExtrasMin': extrasMin,
          'esSabado': esSabado,
          'horaFin': ultimaHoraStr,
          'dia': diaNum,
          'mes': int.tryParse(partesFecha[1]) ?? 0,
          'anno': _parseAnnoFechaTrabajo(partesFecha[2]),
        });
      }

      final tiempoEnTerreno = ultimaHora - primeraHora;
      if (tiempoEnTerreno > trabajoDia) {
        tiempoTrayectoTotal += (tiempoEnTerreno - trabajoDia);
      }
    }

    for (final entry in overtimePorSemana.entries) {
      final diasEntry = entry.value;
      final totalSemana =
          diasEntry.fold<int>(0, (s, d) => s + (d['horasExtrasMin'] as int));
      diasEntry.sort((a, b) => (a['dia'] as int).compareTo(b['dia'] as int));
      final primerDia = diasEntry.first;
      final mesSemana = primerDia['mes'] as int;
      final annoSemana = primerDia['anno'] as int;
      final semNum = int.tryParse(entry.key.split('_').last) ?? 1;
      final inicioSemana = semNum == 1 ? 1 : (semNum - 1) * 7 + 1;
      final finSemana = semNum == 5
          ? DateTime(annoSemana, mesSemana + 1, 0).day
          : semNum * 7;
      detalleHorasExtras.add({
        'tipo': 'semana',
        'inicioSemana': inicioSemana,
        'finSemana': finSemana,
        'mes': mesSemana,
        'anno': annoSemana,
        'totalMinutos': totalSemana,
        'dias': diasEntry,
      });
    }

    if (_aplicaJornadaJunio2026(mesConsulta, annoConsulta)) {
      for (final semanaAnio in semanasConTrabajo) {
        horasExtrasTotal += _minutosBodegaExtra;
        detalleHorasExtras.add({
          'tipo': 'bodega',
          'semanaAnio': semanaAnio,
          'anno': annoConsulta,
          'totalMinutos': _minutosBodegaExtra,
          'horario': '08:45 – 09:45',
          'label': 'Hora extra bodega semana $semanaAnio del año',
        });
      }
    }

    detalleHorasExtras.sort((a, b) {
      final ta = a['tipo']?.toString() ?? '';
      final tb = b['tipo']?.toString() ?? '';
      if (ta != tb) return ta == 'bodega' ? -1 : 1;
      if (ta == 'bodega') {
        return (b['semanaAnio'] as int? ?? 0).compareTo(a['semanaAnio'] as int? ?? 0);
      }
      return (b['inicioSemana'] as int? ?? 0).compareTo(a['inicioSemana'] as int? ?? 0);
    });

    final tiempoSinActividad = tiempoInicioTardioTotal + tiempoFinTempranoTotal;
    final totalOrdenes =
        porDia.values.fold<int>(0, (s, list) => s + list.length);
    final tiempoPromedioOrden =
        totalOrdenes > 0 ? (tiempoTrabajoTotal / totalOrdenes).round() : 0;
    final ordenesPorDia = diasTrabajados > 0 ? totalOrdenes / diasTrabajados : 0.0;
    final productividad = tiempoProductivoEsperado > 0
        ? (tiempoTrabajoTotal / tiempoProductivoEsperado) * 100
        : 0.0;
    final promedioInicioTardio =
        diasTrabajados > 0 ? (tiempoInicioTardioTotal / diasTrabajados).round() : 0;

    return {
      'tiempoTrabajoTotal': tiempoTrabajoTotal,
      'tiempoTrayectoTotal': tiempoTrayectoTotal,
      'tiempoInicioTardio': tiempoInicioTardioTotal,
      'tiempoFinTemprano': tiempoFinTempranoTotal,
      'tiempoSinActividad': tiempoSinActividad,
      'tiempoPromedioOrden': tiempoPromedioOrden,
      'promedioInicioTardio': promedioInicioTardio,
      'productividad': productividad,
      'diasTrabajados': diasTrabajados,
      'diasSemana': diasSemana,
      'diasSabado': diasSabado,
      'ordenesPorDia': ordenesPorDia,
      'tiempoProductivoEsperado': tiempoProductivoEsperado,
      'detalleInicioTardio': detalleInicioTardio,
      'horasExtrasTotal': horasExtrasTotal,
      'detalleHorasExtras': detalleHorasExtras,
    };
  }

  /// Obtener métricas de tiempo del técnico en el mes
  Future<Map<String, dynamic>> obtenerMetricasTiempo(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    final now = DateTime.now();
    final mesConsulta = mes ?? now.month;
    final annoConsulta = anno ?? now.year;

    try {
      final ordenesMes = (await _cargarOrdenesProduccionCreacionesMes(
        mes: mesConsulta,
        anno: annoConsulta,
        rutTecnico: rutTecnico,
      ))
          .where(_ordenCuentaParaMetricasTiempo)
          .toList();

      if (ordenesMes.isEmpty) return _metricasTiempoVacias();

      final porDia = <String, List<Map<String, dynamic>>>{};
      for (final orden in ordenesMes) {
        final fecha = orden['fecha_trabajo']?.toString() ?? '';
        porDia.putIfAbsent(fecha, () => []).add(orden);
      }

      final resultado = _calcularMetricasTiempoDesdePorDia(
        rutTecnico: rutTecnico,
        porDia: porDia,
        mesConsulta: mesConsulta,
        annoConsulta: annoConsulta,
      );

      print('⏱️ [Tiempo] Días L-V: ${resultado['diasSemana']}, Sábados: ${resultado['diasSabado']}');
      print(
        '⏱️ [Tiempo] Productividad: '
        '${(resultado['productividad'] as num).toStringAsFixed(1)}% · '
        'Extras: ${resultado['horasExtrasTotal']} min',
      );

      return resultado;
    } catch (e) {
      print('❌ [Produccion] Error obteniendo métricas de tiempo: $e');
      return _metricasTiempoVacias();
    }
  }

  Map<String, dynamic> _metricasTiempoVacias() {
    return {
      'tiempoTrabajoTotal': 0,
      'tiempoTrayectoTotal': 0,
      'tiempoInicioTardio': 0,
      'tiempoFinTemprano': 0,
      'tiempoSinActividad': 0,
      'tiempoPromedioOrden': 0,
      'promedioInicioTardio': 0,
      'productividad': 0.0,
      'diasTrabajados': 0,
      'diasSemana': 0,
      'diasSabado': 0,
      'ordenesPorDia': 0.0,
      'tiempoProductivoEsperado': 0,
      'detalleInicioTardio': <Map<String, dynamic>>[],
      'horasExtrasTotal': 0,
      'detalleHorasExtras': <Map<String, dynamic>>[],
    };
  }

  /// Devuelve el primer valor no vacío de las llaves candidatas
  /// Parsear hora "HH:MM" a minutos desde medianoche
  int _parseHoraAMinutos(String hora) {
    try {
      final partes = hora.split(':');
      if (partes.length >= 2) {
        final h = int.parse(partes[0]);
        final m = int.parse(partes[1]);
        return h * 60 + m;
      }
    } catch (e) {
      // Ignorar errores de parseo
    }
    return 0;
  }

  /// Formatear minutos a string "Xh Xm"
  static String formatearMinutos(int minutos) {
    if (minutos <= 0) return '0m';
    final horas = minutos ~/ 60;
    final mins = minutos % 60;
    if (horas > 0 && mins > 0) return '${horas}h ${mins}m';
    if (horas > 0) return '${horas}h';
    return '${mins}m';
  }

  // ═══════════════════════════════════════════════════════════
  // MÉTRICAS DE CALIDAD
  // ═══════════════════════════════════════════════════════════

  /// Obtener métricas de calidad del técnico desde v_calidad_tecnicos
  /// Retorna un mapa compatible con el formato anterior para mantener compatibilidad
  Future<Map<String, dynamic>> obtenerCalidadMes(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    try {
      // Consultar vista v_calidad_tecnicos
      final response = await _supabase
          .from('v_calidad_tecnicos')
          .select()
          .eq('rut_tecnico', rutTecnico)
          .maybeSingle();

      if (response == null) {
        // Técnico sin reiterados
        return {
          'reiteracion': 0.0,
          'completadas': 0,
          'reiterados': 0,
          'totalReiterados': 0,
          'promedioDias': 0.0,
          'calidadTecnico': null,
          'ordenesReiteradas': <Map<String, dynamic>>[],
          'ordenesCompletadas': <Map<String, dynamic>>[],
          'periodo': '',
        };
      }

      final calidadTecnico = CalidadTecnico.fromJson(response);
      
      // Calcular porcentaje de reiteración (mantener compatibilidad)
      // Nota: La vista ya calcula total_reiterados, pero necesitamos completadas
      // para el porcentaje. Por ahora usamos total_reiterados como base.
      final reiteracion = calidadTecnico.totalReiterados > 0
          ? (calidadTecnico.totalReiterados / (calidadTecnico.totalReiterados + 50)) * 100
          : 0.0; // Aproximación, ya que no tenemos completadas en la vista

      print('📊 [Calidad] Total reiterados: ${calidadTecnico.totalReiterados}');
      print('📊 [Calidad] Promedio días: ${calidadTecnico.promedioDias}');
      print('📊 [Calidad] Reiteración: ${reiteracion.toStringAsFixed(1)}%');

      return {
        'reiteracion': reiteracion,
        'completadas': calidadTecnico.totalReiterados + 50, // Aproximación
        'reiterados': calidadTecnico.totalReiterados,
        'totalReiterados': calidadTecnico.totalReiterados,
        'promedioDias': calidadTecnico.promedioDias,
        'calidadTecnico': calidadTecnico,
        'ordenesReiteradas': <Map<String, dynamic>>[],
        'ordenesCompletadas': <Map<String, dynamic>>[],
        'periodo': '',
      };
    } catch (e, stackTrace) {
      print('❌ [Calidad] Error: $e');
      print('❌ [Calidad] StackTrace: $stackTrace');
        return {
          'reiteracion': 0.0,
          'completadas': 0,
          'reiterados': 0,
        'totalReiterados': 0,
        'promedioDias': 0.0,
        'calidadTecnico': null,
          'ordenesReiteradas': <Map<String, dynamic>>[],
          'ordenesCompletadas': <Map<String, dynamic>>[],
        'periodo': '',
      };
    }
  }

  /// Obtener detalle de reiterados desde calidad_crea
  Future<List<DetalleReiterado>> obtenerDetalleReiterados(String rutTecnico) async {
    try {
      print('📋 [Detalle] Consultando calidad_crea para RUT=$rutTecnico');
      
      // Obtener TODOS los reiterados sin límite
      final response = await _supabase
          .from('calidad_crea')
          .select('*')
          .eq('rut_tecnico_original', rutTecnico)
          .order('fecha_original', ascending: false);

      final lista = List<Map<String, dynamic>>.from(response as List);
      print('📋 [Detalle] ✅ ${lista.length} reiterados encontrados en total');
      
      return lista.map((item) => DetalleReiterado.fromJson(item)).toList();
    } catch (e) {
      print('❌ [Calidad] Error obteniendo detalle reiterados: $e');
      return [];
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════════
  /// MÉTODOS PARA CALIDAD (garantía al último día del mes de pago; medición 1…último día del mes anterior)
  /// ═══════════════════════════════════════════════════════════════════════════
  
  /// Obtener período CERRADO de Calidad (garantía ya venció)
  /// Ejemplo: Hoy 3 ENE → CERRADO = DIC (garantía terminó el 31 dic)
  /// Ejemplo: Hoy 25 ENE → CERRADO = ENE (garantía terminó el 31 ene)
  /// BONO CERRADO: siempre el mes anterior al actual.
  /// Hoy 7 ABR → BONO MARZO = "2026-03" (trabajo feb 1-28, garantía vencida el 31-mar)
  String getPeriodoCerrado() {
    final mes = DateTime(DateTime.now().year, DateTime.now().month - 1, 1);
    return '${mes.year}-${mes.month.toString().padLeft(2, '0')}';
  }

  /// BONO ACTUAL (en medición): siempre el mes en curso.
  /// Hoy 7 ABR → BONO ABRIL = "2026-04" (trabajo mar 1-31, garantía vence 30-abr)
  String getPeriodoActual() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  /// BONO ANTERIOR (histórico, dos meses atrás).
  String getPeriodoAnterior() {
    final mes = DateTime(DateTime.now().year, DateTime.now().month - 2, 1);
    return '${mes.year}-${mes.month.toString().padLeft(2, '0')}';
  }

  /// BONO SIGUIENTE (también en medición): mes siguiente al actual.
  /// Hoy 7 ABR → BONO MAYO = "2026-05" (trabajo abr 1-30, garantía vence 31-may)
  String getPeriodoSiguiente() {
    final mes = DateTime(DateTime.now().year, DateTime.now().month + 1, 1);
    return '${mes.year}-${mes.month.toString().padLeft(2, '0')}';
  }

  /// Misma regla que el card **Producción** en Tu Mes (columna izquierda):
  /// mes de **pago** = mes calendario actual; datos = mes de medición anterior.
  /// Ej. hoy en abril → `2026-04` (Bono abril, medición marzo).
  String getPeriodoMesPagoProduccionCerrado() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  /// Misma regla que el card **Producción** en Tu Mes (columna derecha, en curso):
  /// mes de **pago** = mes siguiente; datos = mes calendario actual.
  /// Ej. hoy en abril → `2026-05` (Bono mayo, medición abril).
  String getPeriodoMesPagoProduccionEnCurso() {
    final mes = DateTime(DateTime.now().year, DateTime.now().month + 1, 1);
    return '${mes.year}-${mes.month.toString().padLeft(2, '0')}';
  }

  /// Gráfico detalle calidad: tres meses de **pago** (anterior, actual, siguiente).
  /// `label` = nombre corto del mes de pago (Ene…Dic). Misma regla que Tu Mes / producción.
  List<Map<String, String>> getPeriodosGraficoCalidadMenosUnoCerradoEnCurso() {
    final now = DateTime.now();
    final pMenos1 = DateTime(now.year, now.month - 1, 1);
    final pCerrado = DateTime(now.year, now.month, 1);
    final pEnCurso = DateTime(now.year, now.month + 1, 1);
    const mesesCortos = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
    ];
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}';
    String etiquetaMes(DateTime d) =>
        mesesCortos[d.month - 1];
    return [
      {'periodo': fmt(pMenos1), 'label': etiquetaMes(pMenos1)},
      {'periodo': fmt(pCerrado), 'label': etiquetaMes(pCerrado)},
      {'periodo': fmt(pEnCurso), 'label': etiquetaMes(pEnCurso)},
    ];
  }

  /// Obtener calidad del técnico para los dos períodos mostrados en Tu Mes.
  /// Los meses de pago coinciden con [getPeriodoMesPagoProduccionCerrado] / [getPeriodoMesPagoProduccionEnCurso]
  /// (misma lógica que el resumen RGU de Producción).
  Future<Map<String, dynamic>> obtenerCalidadPeriodos(String rutTecnico) async {
    try {
      final now = DateTime.now();
      final periodoEnCurso  = getPeriodoMesPagoProduccionEnCurso();
      final periodoCerrado  = getPeriodoMesPagoProduccionCerrado();
      final pPagado         = DateTime(now.year, now.month - 1, 1);
      final periodoPagado   = '${pPagado.year}-${pPagado.month.toString().padLeft(2, '0')}';

      print('📊 [Calidad] ══════════════════════════════════════════');
      print('📊 [Calidad] RUT: $rutTecnico');
      print('📊 [Calidad] PAGADO   (pago=mes ant.): $periodoPagado → ${periodoAFormatoCalidad(periodoPagado)}');
      print('📊 [Calidad] CERRADO  (pago=mes act.): $periodoCerrado → ${periodoAFormatoCalidad(periodoCerrado)}');
      print('📊 [Calidad] EN CURSO (pago=mes sig.): $periodoEnCurso → ${periodoAFormatoCalidad(periodoEnCurso)}');
      print('📊 [Calidad] Consultando calidad_api_crea en paralelo...');

      final resultados = await Future.wait([
        obtenerCalidadPorPeriodo(rutTecnico, periodoPagado),
        obtenerCalidadPorPeriodo(rutTecnico, periodoCerrado),
        obtenerCalidadPorPeriodo(rutTecnico, periodoEnCurso),
      ]);

      final pagado  = resultados[0];
      final cerrado = resultados[1];
      final enCurso = resultados[2];

      print('📊 [Calidad] Resultados:');
      print('   - Pagado  ($periodoPagado): ${pagado  != null ? "✅ ${pagado['total_reiterados']} reit. / ${pagado['total_completadas']} comp. = ${pagado['porcentaje_reiteracion']}%"  : "❌ sin datos"}');
      print('   - Cerrado ($periodoCerrado): ${cerrado != null ? "✅ ${cerrado['total_reiterados']} reit. / ${cerrado['total_completadas']} comp. = ${cerrado['porcentaje_reiteracion']}%" : "❌ sin datos"}');
      print('   - En curso ($periodoEnCurso): ${enCurso != null ? "✅ ${enCurso['total_reiterados']} reit. / ${enCurso['total_completadas']} comp. = ${enCurso['porcentaje_reiteracion']}%"  : "❌ sin datos"}');
      print('📊 [Calidad] ══════════════════════════════════════════');

      return {
        'pagado':           pagado,
        'cerrado':          cerrado,
        'actual':           enCurso,
        'anterior':         enCurso,
        'periodo_pagado':   periodoPagado,
        'periodo_cerrado':  periodoCerrado,
        'periodo_actual':   periodoEnCurso,
        'periodo_anterior': periodoEnCurso,
      };
    } catch (e) {
      print('❌ [Calidad] Error obteniendo calidad por períodos: $e');
      final now = DateTime.now();
      final pPagado = DateTime(now.year, now.month - 1, 1);
      return {
        'pagado':           null,
        'cerrado':          null,
        'actual':           null,
        'anterior':         null,
        'periodo_pagado':   '${pPagado.year}-${pPagado.month.toString().padLeft(2, '0')}',
        'periodo_cerrado':  getPeriodoMesPagoProduccionCerrado(),
        'periodo_actual':   getPeriodoMesPagoProduccionEnCurso(),
        'periodo_anterior': getPeriodoMesPagoProduccionEnCurso(),
      };
    }
  }

  /// Obtener color según porcentaje de reiterados
  Color getColorCalidad(double porcentaje) {
    if (porcentaje <= 4.0) return Colors.green;      // Excelente (≤ 4%)
    if (porcentaje <= 5.7) return Colors.orange;      // Regular (4.1% - 5.7%)
    return Colors.red;                                 // Necesita mejorar (> 5.8%)
  }

  /// Obtener calidad del técnico para un período específico
  /// Usa calidad_api_crea (mismo origen que el dashboard)
  /// [periodo] formato YYYY-MM (mes de pago)
  /// [periodoCalidadOverride] permite forzar el período de consulta en calidad_api_crea (MM-YYYY).
  /// Si no se provee, se usa el período mismo (lógica para CERRADO: "03-2026" para marzo).
  /// Para ACTUAL/SIGUIENTE se pasa el período del mes cerrado para medir los mismos trabajos.
  Future<Map<String, dynamic>?> obtenerCalidadPorPeriodo(
    String rutTecnico,
    String periodo, {
    String? periodoCalidadOverride,
  }) async {
    try {
      final partes = periodo.split('-');
      if (partes.length != 2) return null;

      // periodoCalidad: cuál período consultar en calidad_api_crea (formato MM-YYYY)
      // - Para CERRADO: usa el mismo período (ej. "03-2026" para bono marzo)
      // - Para ACTUAL/SIGUIENTE: se pasa override = período cerrado (ej. "03-2026")
      final periodoCalidad = periodoCalidadOverride ?? periodoAFormatoCalidad(periodo);

      // mesPago / annoPago: mes/año de PAGO (de periodoCalidad, formato MM-YYYY)
      // mesAnt  / yearAnt:  mes/año de MEDICIÓN = mesPago - 1 (igual que el dashboard)
      // Ejemplo: periodoCalidad="03-2026" → mesPago=3, mesAnt=2 (febrero 2026)
      final partesCalidad = periodoCalidad.split('-');
      final mesPago = int.parse(partesCalidad[0]);
      final annoPago = int.parse(partesCalidad[1]);

      // Mes de medición usando DateTime para manejar cruce de año (ene→dic del año ant)
      final fechaMedicion = DateTime(annoPago, mesPago - 1, 1);
      final mesAnt = fechaMedicion.month;
      final yearAnt = fechaMedicion.year;

      print('📊 [Calidad] Display: ${periodoAFormatoCalidad(periodo)} | calidad_api_crea.periodo=$periodoCalidad | Medición: $mesAnt/$yearAnt');

      // 1. Reiterados: igual que el dashboard — carga TODO el período sin filtrar por RUT,
      //    luego filtra en cliente por rut_o_bucket.
      //    Esto evita perder registros cuando rut_o_bucket tiene un formato ligeramente
      //    distinto al del técnico (con/sin dígito verificador, diferente guion, etc.)
      //    Dashboard: rawReiterados = queryAll('calidad_api_crea',
      //               `es_reiterado=eq.true&periodo=eq.${periodoCalidadStr}`)
      //               reiteradosPorRut[r.rut_o_bucket]++
      // Paginación igual que el dashboard (queryAll con limit 1000 + offset)
      // Seleccionamos también los campos de detalle (orden original, causa, fechas)
      // para no tener que hacer otra consulta desde la pantalla de detalle.
      final todosReiteradosPeriodo = <dynamic>[];
      int offset = 0;
      const pageSize = 1000;
      while (true) {
        final page = (await _supabase
            .from('calidad_api_crea')
            .select(
              'rut_o_bucket, orden_de_trabajo, reiterada_por_ot, '
              'reiterada_por_fecha, fecha, tipo_de_actividad, '
              'reiterada_por_tipo_actividad, tipo_red_producto',
            )
            .eq('es_reiterado', true)
            .eq('periodo', periodoCalidad)
            .range(offset, offset + pageSize - 1)) as List;
        todosReiteradosPeriodo.addAll(page);
        if (page.length < pageSize) break;
        offset += pageSize;
      }

      // Filtro cliente: coincidencia exacta de rut_o_bucket (igual que dashboard)
      final listaReiterados = todosReiteradosPeriodo
          .where((r) => r['rut_o_bucket']?.toString() == rutTecnico)
          .toList();

      final totalReiterados = listaReiterados.length;

      // ── Diagnóstico ──────────────────────────────────────────────────────────
      // Muestra cuántos registros hay en el período y qué RUTs tienen más de 0
      // para detectar diferencias de formato (con guion, sin guion, etc.)
      final rutCounts = <String, int>{};
      for (final r in todosReiteradosPeriodo) {
        final rut = r['rut_o_bucket']?.toString() ?? 'null';
        rutCounts[rut] = (rutCounts[rut] ?? 0) + 1;
      }
      // Buscar el RUT del técnico con variaciones de formato
      final rutSinGuion = rutTecnico.replaceAll('-', '');
      final posibles = rutCounts.entries
          .where((e) => e.key.replaceAll('-', '').startsWith(rutSinGuion.substring(0, rutSinGuion.length > 7 ? 7 : rutSinGuion.length)))
          .toList();
      print('📊 [Calidad] Total período $periodoCalidad: ${todosReiteradosPeriodo.length} | Exacto RUT "$rutTecnico": $totalReiterados | Posibles: ${posibles.map((e) => "${e.key}=${e.value}").join(", ")}');
      // ─────────────────────────────────────────────────────────────────────────

      // Extraer números de orden para mostrar el detalle exacto
      final ordenesReiteradas = listaReiterados
          .map((r) => r['orden_de_trabajo']?.toString() ?? '')
          .where((o) => o.isNotEmpty)
          .toList();

      // 2. Denominador: completadas del mes de MEDICIÓN (mesAnt / yearAnt)
      //    Usa produccion_creaciones (igual que pantalla Producción): mes con cero, año 2 dígitos.
      //    Se traen todas las órdenes del mes y se filtra con cuentaComoProduccion para incluir
      //    también las "No Realizada" derivadas a GSA.
      final mesMedPadded = mesAnt.toString().padLeft(2, '0');
      final annoMedCorto = (yearAnt % 100).toString().padLeft(2, '0');
      final produccionResp = await _supabase
          .from('produccion_creaciones')
          .select('rut_tecnico, fecha_trabajo, estado, area_derivacion')
          .eq('rut_tecnico', rutTecnico)
          .ilike('fecha_trabajo', '*/$mesMedPadded/$annoMedCorto');

      final totalCompletadas = (produccionResp as List)
          .where((o) => cuentaComoProduccion(o))
          .length;

      // 3. Porcentaje (redondeado a 2 dec, igual que el dashboard)
      final porcentaje = totalCompletadas > 0
          ? (totalReiterados / totalCompletadas * 100 * 100).roundToDouble() / 100.0
          : 0.0;

      print('📊 [Calidad] $totalReiterados reiterados / $totalCompletadas completadas (${mesAnt}/${yearAnt}) = $porcentaje%');

      return {
        'total_reiterados': totalReiterados,
        'total_completadas': totalCompletadas,
        'porcentaje_reiteracion': porcentaje,
        'periodo': periodo,
        'rut_tecnico': rutTecnico,
        'ordenes_reiteradas': ordenesReiteradas,
        'mes_base': mesPago,
        'anno_base': annoPago,
        'mes_medicion': mesAnt,
        'anno_medicion': yearAnt,
        // Detalle completo de calidad_api_crea para la pantalla de detalle.
        // Incluye orden_original (reiterada_por_ot) y causa (tipo_de_actividad).
        'detalle_calidad_api': listaReiterados,
      };
    } catch (e) {
      print('❌ [Calidad] Error obteniendo calidad por período: $e');
      return null;
    }
  }

  /// Obtiene el detalle de órdenes reiteradas por sus números de orden exactos.
  /// [ordenes] son los valores de calidad_api_crea.orden_de_trabajo (= orden REITERADA).
  /// En calidad_crea ese campo se llama 'orden_reiterada', no 'orden_original'.
  Future<List<DetalleReiterado>> obtenerDetalleReiteradosPorOrdenes(
    String rutTecnico,
    List<String> ordenes,
  ) async {
    try {
      if (ordenes.isEmpty) return [];

      print('📋 [Detalle] Consultando calidad_crea.orden_reiterada IN $ordenes');

      final response = await _supabase
          .from('calidad_crea')
          .select('*')
          .eq('rut_tecnico_original', rutTecnico)
          .inFilter('orden_reiterada', ordenes)
          .order('fecha_original', ascending: false);

      final lista = List<Map<String, dynamic>>.from(response as List);
      print('📋 [Detalle] ✅ ${lista.length} registros encontrados en calidad_crea');
      return lista.map((item) => DetalleReiterado.fromJson(item)).toList();
    } catch (e) {
      print('❌ [Detalle] Error obteniendo detalle por órdenes: $e');
      return [];
    }
  }

  /// Fallback: busca el detalle de reiterados por rango de fechas del mes de trabajo.
  /// Se usa cuando el cruce por orden_reiterada no devuelve resultados.
  /// [mesTrabajo] y [annoTrabajo] = mes/año en que se hizo el trabajo original.
  /// BONO MARZO (pago=3/2026) → mesTrabajo=2, annoTrabajo=2026 (febrero)
  Future<List<DetalleReiterado>> obtenerDetalleReiteradosPorMesTrabajo(
    String rutTecnico,
    int mesTrabajo,
    int annoTrabajo,
  ) async {
    try {
      final inicio = DateTime(annoTrabajo, mesTrabajo, 1);
      final fin = DateTime(annoTrabajo, mesTrabajo + 1, 0); // último día del mes
      final inicioStr =
          '${inicio.year}-${inicio.month.toString().padLeft(2, '0')}-01';
      final finStr =
          '${fin.year}-${fin.month.toString().padLeft(2, '0')}-${fin.day.toString().padLeft(2, '0')}';

      print(
          '📋 [Detalle] Fallback fecha_original BETWEEN $inicioStr AND $finStr');

      final response = await _supabase
          .from('calidad_crea')
          .select('*')
          .eq('rut_tecnico_original', rutTecnico)
          .gte('fecha_original', inicioStr)
          .lte('fecha_original', finStr)
          .order('fecha_original', ascending: false);

      final lista = List<Map<String, dynamic>>.from(response as List);
      print('📋 [Detalle] Fallback: ${lista.length} registros encontrados');
      return lista.map((item) => DetalleReiterado.fromJson(item)).toList();
    } catch (e) {
      print('❌ [Detalle] Error fallback por fecha: $e');
      return [];
    }
  }

  /// Obtiene detalle de reiterados como List<Map> para calidad_detalle_screen.
  /// Usa v_calidad_detalle filtrada por número de orden (la misma vista que funciona).
  /// [ordenes] = calidad_api_crea.orden_de_trabajo (= orden REITERADA en la vista).
  Future<List<Map<String, dynamic>>> obtenerDetalleMapa(
    String rutTecnico,
    List<String> ordenes,
  ) async {
    if (ordenes.isEmpty) return [];

    print('📋 [DetalleMapa] Buscando ${ordenes.length} órdenes en v_calidad_detalle: $ordenes');

    // Buscar en v_calidad_detalle filtrando por orden_reiterada O orden_original.
    // Los valores de calidad_api_crea.orden_de_trabajo corresponden a la orden
    // reiterada en la vista.
    final ordenesJoin = ordenes.join(',');
    try {
      final response = await _supabase
          .from('v_calidad_detalle')
          .select('*')
          .eq('rut_tecnico_original', rutTecnico)
          .or('orden_reiterada.in.($ordenesJoin),orden_original.in.($ordenesJoin)');

      final lista = List<Map<String, dynamic>>.from(response as List);
      print('📋 [DetalleMapa] v_calidad_detalle encontró: ${lista.length}/${ordenes.length}');

      // Determinar qué órdenes siguen faltando para el fallback
      final ordenesEncontradas = <String>{};
      for (final d in lista) {
        final orig = d['orden_original']?.toString() ?? '';
        final reit = d['orden_reiterada']?.toString() ?? '';
        if (orig.isNotEmpty) ordenesEncontradas.add(orig);
        if (reit.isNotEmpty) ordenesEncontradas.add(reit);
      }
      final ordenesFaltantes = ordenes
          .where((o) => o.isNotEmpty && !ordenesEncontradas.contains(o))
          .toList();

      if (ordenesFaltantes.isNotEmpty) {
        print('📋 [DetalleMapa] ${ordenesFaltantes.length} sin dato → produccion_crea');
        final desdeProduccion = await obtenerDetalleDesdeProduccion(rutTecnico, ordenesFaltantes);
        lista.addAll(desdeProduccion.map((d) => <String, dynamic>{
          'orden_original': d.ordenOriginal,
          'fecha_original': d.fechaOriginal,
          'tipo_actividad': d.tipoActividad,
          'orden_reiterada': d.ordenReiterada,
          'fecha_reiterada': d.fechaReiterada,
          'dias_reiterado': d.diasReiterado,
          'cliente': d.cliente,
          'direccion': d.direccion,
          'descripcion_reiterado': d.causa,
          'codigo_cierre_reiterado': d.codigoCierre,
        }));
      }

      print('📋 [DetalleMapa] Total final: ${lista.length}/${ordenes.length}');
      return lista;
    } catch (e) {
      print('❌ [DetalleMapa] Error: $e');
      // Si falla la vista, ir directamente a produccion_crea
      final desdeProduccion = await obtenerDetalleDesdeProduccion(rutTecnico, ordenes);
      return desdeProduccion.map((d) => <String, dynamic>{
        'orden_original': d.ordenOriginal,
        'fecha_original': d.fechaOriginal,
        'tipo_actividad': d.tipoActividad,
        'orden_reiterada': d.ordenReiterada,
        'fecha_reiterada': d.fechaReiterada,
        'dias_reiterado': d.diasReiterado,
        'cliente': d.cliente,
        'direccion': d.direccion,
        'descripcion_reiterado': d.causa,
        'codigo_cierre_reiterado': d.codigoCierre,
      }).toList();
    }
  }

  /// Fallback final: construye DetalleReiterado desde produccion_crea.
  /// Se usa cuando calidad_crea no tiene datos para el período (ej. datos nuevos de BONO ABR).
  /// Retorna el trabajo reiterado con su fecha e información básica.
  Future<List<DetalleReiterado>> obtenerDetalleDesdeProduccion(
    String rutTecnico,
    List<String> ordenes,
  ) async {
    try {
      if (ordenes.isEmpty) return [];

      print('📋 [Detalle-Prod] Buscando ${ordenes.length} órdenes en produccion_crea');

      // En produccion_crea el campo se llama 'orden_trabajo' (sin 'de')
      final response = await _supabase
          .from('produccion_crea')
          .select('*')
          .eq('rut_tecnico', rutTecnico)
          .inFilter('orden_trabajo', ordenes);

      final lista = List<Map<String, dynamic>>.from(response as List);
      print('📋 [Detalle-Prod] ✅ ${lista.length} órdenes encontradas en produccion_crea');

      return lista.map((item) {
        final orden = item['orden_trabajo']?.toString() ?? '';
        final fecha = item['fecha_trabajo']?.toString() ?? '';
        final tipo = item['tipo_actividad']?.toString() ?? '';
        final cliente = item['nombre_cliente']?.toString() ??
            item['cliente']?.toString() ??
            '';
        final direccion = item['direccion']?.toString() ?? '';
        return DetalleReiterado(
          ordenOriginal: orden,
          fechaOriginal: fecha,
          tipoActividad: tipo,
          ordenReiterada: '', // No disponible desde produccion_crea
          fechaReiterada: '',
          diasReiterado: 0,
          cliente: cliente,
          direccion: direccion,
          causa: 'Orden reiterada registrada en período de medición',
          codigoCierre: '',
        );
      }).toList();
    } catch (e) {
      print('❌ [Detalle-Prod] Error: $e');
      return [];
    }
  }

  /// Obtener período desde mes y año
  String getPeriodoDesdeMesAnno(int mes, int anno) {
    return '$anno-${mes.toString().padLeft(2, '0')}';
  }

  /// Convertir período YYYY-MM → MM-YYYY (formato calidad_api_crea)
  /// Público para que calidad_screen pueda usarlo para el override.
  String periodoAFormatoCalidad(String periodo) {
    final partes = periodo.split('-');
    if (partes.length == 2) {
      return '${partes[1].padLeft(2, '0')}-${partes[0]}'; // MM-YYYY
    }
    return periodo;
  }

  /// Obtener nombre del mes desde período
  String getNombreMes(String periodo) {
    try {
      final partes = periodo.split('-');
      if (partes.length == 2) {
        final mes = int.parse(partes[1]);
        const meses = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
        if (mes >= 1 && mes <= 12) {
          return meses[mes];
        }
      }
    } catch (e) {
      print('⚠️ [Calidad] Error obteniendo nombre del mes: $e');
    }
    return '';
  }

  /// Obtener detalle de reiterados desde v_calidad_detalle
  /// Solo trae reiterados que CUENTAN para calidad (dentro de 30 días de garantía)
  /// Filtra por fecha de instalación (fecha_original) dentro del período de trabajo
  Future<List<Map<String, dynamic>>> obtenerDetalleReiteradosPorPeriodo(
    String rutTecnico,
    String periodo,
  ) async {
    try {
      print('📋 [Detalle] Consultando v_calidad_detalle para RUT=$rutTecnico, periodo=$periodo');
      
      // Rango de fechas de instalación = mes de medición completo (día 1 al último día)
      final fechas = _calcularRangoFechasTrabajo(periodo);
      final fechaInicio = fechas['inicio']!;
      final fechaFin = fechas['fin']!;
      
      print('📋 [Detalle] Rango de instalaciones: $fechaInicio → $fechaFin');
      
      // 1. Primero, ver TODOS los reiterados del técnico sin filtros
      print('📋 [Debug] Consultando TODOS los reiterados del técnico...');
      final responseTodos = await _supabase
          .from('v_calidad_detalle')
          .select()
          .eq('rut_tecnico_original', rutTecnico)
          .order('fecha_original', ascending: false);
      
      final todosList = List<Map<String, dynamic>>.from(responseTodos as List);
      print('📋 [Debug] Total reiterados en v_calidad_detalle: ${todosList.length}');
      
      // 2. Ver cuántos están en el rango de fechas (sin filtrar por cuenta_para_calidad)
      final enRango = todosList.where((item) {
        final fechaOrig = item['fecha_original']?.toString() ?? '';
        return fechaOrig.compareTo(fechaInicio) >= 0 && fechaOrig.compareTo(fechaFin) <= 0;
      }).toList();
      print('📋 [Debug] Reiterados en rango de fechas: ${enRango.length}');
      
      // 3. Ver cuántos cuentan para calidad
      final cuentan = enRango.where((item) => 
        item['cuenta_para_calidad']?.toString() == 'SÍ'
      ).toList();
      print('📋 [Debug] De esos, cuentan para calidad: ${cuentan.length}');
      
      // 4. Mostrar algunos ejemplos de los que NO cuentan
      final noCuentan = enRango.where((item) => 
        item['cuenta_para_calidad']?.toString() != 'SÍ'
      ).toList();
      if (noCuentan.isNotEmpty) {
        print('⚠️ [Debug] ${noCuentan.length} reiterados NO cuentan para calidad:');
        for (var i = 0; i < noCuentan.length && i < 3; i++) {
          print('   - Orden: ${noCuentan[i]['orden_original']}, '
                'Fecha orig: ${noCuentan[i]['fecha_original']}, '
                'Fecha reit: ${noCuentan[i]['fecha_reiterada']}, '
                'Cuenta: ${noCuentan[i]['cuenta_para_calidad']}');
        }
      }
      
      // 5. Consulta final (CON el filtro cuenta_para_calidad)
      final response = await _supabase
          .from('v_calidad_detalle')
          .select()
          .eq('rut_tecnico_original', rutTecnico)
          .eq('cuenta_para_calidad', 'SÍ')  // Solo los que cuentan (30 días de garantía)
          .gte('fecha_original', fechaInicio)  // Desde el 1.º día del mes de medición
          .lte('fecha_original', fechaFin)     // Hasta el último día del mes de medición
          .order('fecha_original', ascending: false);

      final lista = List<Map<String, dynamic>>.from(response as List);
      print('📋 [Detalle] ✅ ${lista.length} reiterados FINALES que cuentan para calidad');
      
      return lista;
    } catch (e) {
      print('❌ [Calidad] Error obteniendo detalle de reiterados: $e');
      return [];
    }
  }

  /// Rango de fechas de TRABAJO (medición): del 1 al último día del mes anterior al mes de pago.
  Map<String, String> _calcularRangoFechasTrabajo(String periodo) {
    try {
      final partes = periodo.split('-');
      if (partes.length == 2) {
        final int anno = int.parse(partes[0]);
        final int mes = int.parse(partes[1]);

        // Mes de trabajo = mes de pago - 1 (ciclo 1 al último del mes)
        // BONO MARZO (mes=3, anno=2026) → trabajo FEBRERO → "2026-02-01" a "2026-02-28"
        // BONO ABRIL  (mes=4, anno=2026) → trabajo MARZO   → "2026-03-01" a "2026-03-31"
        final mesTrabajo = DateTime(anno, mes - 1, 1);
        final ultimoDia = DateTime(mesTrabajo.year, mesTrabajo.month + 1, 0).day;

        final fechaInicio =
            '${mesTrabajo.year}-${mesTrabajo.month.toString().padLeft(2, '0')}-01';
        final fechaFin =
            '${mesTrabajo.year}-${mesTrabajo.month.toString().padLeft(2, '0')}-${ultimoDia.toString().padLeft(2, '0')}';

        print('📋 [RangoFechas] Período $periodo → trabajo $fechaInicio → $fechaFin');

        return {
          'inicio': fechaInicio,
          'fin': fechaFin,
        };
      }
    } catch (e) {
      print('⚠️ Error calculando rango de fechas: $e');
    }
    
        return {
      'inicio': '2000-01-01',
      'fin': '2099-12-31',
    };
  }

  /// Calcular el siguiente mes para el filtro de rango
  String _calcularSiguienteMes(String periodo) {
    try {
      final partes = periodo.split('-');
      if (partes.length == 2) {
        int anno = int.parse(partes[0]);
        int mes = int.parse(partes[1]);
        
        mes += 1;
        if (mes > 12) {
          mes = 1;
          anno += 1;
        }
        
        return '$anno-${mes.toString().padLeft(2, '0')}-01';
      }
    } catch (e) {
      print('⚠️ Error calculando siguiente mes: $e');
    }
    return '2099-12-31'; // Fecha lejana como fallback
  }

  /// Formatear fecha desde formato "2025-11-20" a "20/11/2025"
  String formatearFecha(String? fecha) {
    if (fecha == null || fecha.isEmpty) return '';
    try {
      final partes = fecha.split('-');
      if (partes.length == 3) {
        return '${partes[2]}/${partes[1]}/${partes[0]}';
      }
    } catch (e) {
      print('⚠️ [Calidad] Error formateando fecha: $e');
    }
    return fecha;
  }

  /// Ranking de calidad para un período de pago (YYYY-MM).
  /// Misma lógica que [obtenerCalidadPorPeriodo]: reiterados en calidad_api_crea
  /// y completadas en produccion_creaciones del mes de medición (mes pago − 1).
  Future<Map<String, dynamic>> obtenerRankingCalidad(String periodo) async {
    try {
      print('🏆 [Calidad] Obteniendo ranking para período: $periodo');

      final partes = periodo.split('-');
      if (partes.length != 2) {
        return {'ranking': [], 'totalTecnicos': 0};
      }

      final periodoCalidad = periodoAFormatoCalidad(periodo);
      final partesCalidad = periodoCalidad.split('-');
      final mesPago = int.parse(partesCalidad[0]);
      final annoPago = int.parse(partesCalidad[1]);
      final fechaMedicion = DateTime(annoPago, mesPago - 1, 1);
      final mesAnt = fechaMedicion.month;
      final yearAnt = fechaMedicion.year;
      final filtroMes = _filtroFechaMesIlike(mesAnt, yearAnt);

      print(
        '🏆 [Calidad] Ranking: calidad_api_crea=$periodoCalidad, '
        'medición=$mesAnt/$yearAnt ($filtroMes)',
      );

      final reiteradosPorKey = <String, int>{};
      final rutDisplayPorKey = <String, String>{};
      var offset = 0;
      const pageSize = 1000;
      while (true) {
        final page = (await _supabase
                .from('calidad_api_crea')
                .select('rut_o_bucket')
                .eq('es_reiterado', true)
                .eq('periodo', periodoCalidad)
                .range(offset, offset + pageSize - 1))
            as List;
        for (final r in page) {
          final rut = r['rut_o_bucket']?.toString() ?? '';
          if (rut.isEmpty) continue;
          final key = _normalizarRutKey(rut);
          reiteradosPorKey[key] = (reiteradosPorKey[key] ?? 0) + 1;
          rutDisplayPorKey.putIfAbsent(key, () => rut);
        }
        if (page.length < pageSize) break;
        offset += pageSize;
      }

      final completadasPorKey = <String, int>{};
      final nombresPorKey = <String, String>{};
      offset = 0;
      while (true) {
        final page = (await _supabase
                .from('produccion_creaciones')
                .select('rut_tecnico, tecnico, estado, area_derivacion')
                .ilike('fecha_trabajo', filtroMes)
                .range(offset, offset + pageSize - 1))
            as List;
        for (final o in page) {
          if (!cuentaComoProduccion(o)) continue;
          final rut = o['rut_tecnico']?.toString() ?? '';
          if (rut.isEmpty) continue;
          final key = _normalizarRutKey(rut);
          completadasPorKey[key] = (completadasPorKey[key] ?? 0) + 1;
          final nombre = o['tecnico']?.toString() ?? '';
          if (nombre.isNotEmpty) nombresPorKey[key] = nombre;
          rutDisplayPorKey[key] = rut;
        }
        if (page.length < pageSize) break;
        offset += pageSize;
      }

      final tecnicos = <Map<String, dynamic>>[];
      for (final key in completadasPorKey.keys) {
        final completadas = completadasPorKey[key] ?? 0;
        if (completadas <= 0) continue;
        final reiterados = reiteradosPorKey[key] ?? 0;
        final porcentaje = (reiterados / completadas * 100 * 100).roundToDouble() /
            100.0;
        tecnicos.add({
          'rut_tecnico': rutDisplayPorKey[key] ?? key,
          'tecnico': nombresPorKey[key] ?? '',
          'total_reiterados': reiterados,
          'total_completadas': completadas,
          'porcentaje_reiteracion': porcentaje,
          'promedio_dias': 0.0,
          'periodo': periodo,
        });
      }

      tecnicos.sort((a, b) {
        final pa = (a['porcentaje_reiteracion'] as num).toDouble();
        final pb = (b['porcentaje_reiteracion'] as num).toDouble();
        final cmp = pa.compareTo(pb);
        if (cmp != 0) return cmp;
        final ra = (a['total_reiterados'] as num).toInt();
        final rb = (b['total_reiterados'] as num).toInt();
        return ra.compareTo(rb);
      });

      for (var i = 0; i < tecnicos.length; i++) {
        tecnicos[i]['posicion'] = i + 1;
      }

      print('🏆 [Calidad] Ranking tiene ${tecnicos.length} técnicos');

      return {
        'ranking': tecnicos,
        'totalTecnicos': tecnicos.length,
      };
    } catch (e) {
      print('❌ [Calidad] Error obteniendo ranking: $e');
      return {
        'ranking': [],
        'totalTecnicos': 0,
      };
    }
  }

  /// Obtener posición del técnico en ranking de calidad
  Future<Map<String, dynamic>> obtenerPosicionCalidad(
    String rutTecnico,
    String periodo,
  ) async {
    try {
      print('🎯 [Calidad] Buscando posición para RUT: $rutTecnico en período: $periodo');
      
      final rankingData = await obtenerRankingCalidad(periodo);
      final ranking = List<Map<String, dynamic>>.from(rankingData['ranking'] as List);
      
      // Buscar al técnico (RUT puede venir con distinto formato)
      Map<String, dynamic>? tecnicoEncontrado;
      for (var t in ranking) {
        if (rutsCoinciden(t['rut_tecnico']?.toString() ?? '', rutTecnico)) {
          tecnicoEncontrado = t;
          break;
        }
      }
      
      // Retornar TODOS los técnicos, no solo top 10
      final todosLosTecnicos = ranking;
      
      if (tecnicoEncontrado == null) {
        return {
          'posicion': 0,
          'totalTecnicos': ranking.length,
          'porcentajeReiterados': 0.0,
          'totalReiterados': 0,
          'totalCompletadas': 0,
          'promedioDias': 0.0,
          'top10': todosLosTecnicos,
        };
      }
      
      return {
        'posicion': tecnicoEncontrado['posicion'],
        'totalTecnicos': ranking.length,
        'porcentajeReiterados': (tecnicoEncontrado['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0,
        'totalReiterados': (tecnicoEncontrado['total_reiterados'] as num?)?.toInt() ?? 0,
        'totalCompletadas': (tecnicoEncontrado['total_completadas'] as num?)?.toInt() ?? 0,
        'promedioDias': (tecnicoEncontrado['promedio_dias'] as num?)?.toDouble() ?? 0.0,
        'nombre': tecnicoEncontrado['tecnico'],
        'top10': todosLosTecnicos,
      };
    } catch (e) {
      print('❌ [Calidad] Error obteniendo posición: $e');
      return {
        'posicion': 0,
        'totalTecnicos': 0,
        'porcentajeReiterados': 0.0,
        'totalReiterados': 0,
        'totalCompletadas': 0,
        'promedioDias': 0.0,
        'top10': [],
      };
    }
  }
}

