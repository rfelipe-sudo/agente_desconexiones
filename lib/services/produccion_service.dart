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
        (esEstadoNoRealizada(o) &&
            (a == 'GSA' || areaDerivacionEsRedes(o['area_derivacion'])));
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
      final diasHabiles = 22; // Valor aproximado temporal
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
          print('   - Ausencias: ${asistenciaData['ausencias']}');
          print('   - Vacaciones: ${asistenciaData['vacaciones']}');
          print('   - Días hábiles: ${asistenciaData['dias_habiles_mes']}');
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
          'diasAusentes': (asistenciaData?['ausencias'] as num?)?.toInt() ?? 0,
          'diasHabiles': (asistenciaData?['dias_habiles_mes'] as num?)?.toInt() ?? diasHabiles,
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

        if (estado == 'Completado') {
          completadas++;
            completadasDia++;
            final rgu = (orden['rgu_total'] as num?)?.toDouble() ?? 0;
            totalRGU += rgu;
            rguDia += rgu;
        } else if (estado == 'Cancelado') {
          canceladas++;
        } else if (estado == 'No Realizada') {
          noRealizadas++;
          }
        }

        if (completadasDia > 0) {
          diasConProduccion.add(fecha);
        } else {
          // Día PX-0: usa es_px0 si está disponible, sino lo infiere
          final esPx0 = ordenesDelDia.any((o) => o['es_px0'] == true)
              || ordenesDelDia.every((o) => o['estado']?.toString() != 'Completado');
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
        diasAusentesFinales = (asistenciaData['ausencias'] as num?)?.toInt() ?? 0;
        vacacionesFinales = (asistenciaData['vacaciones'] as num?)?.toInt() ?? 0;
        print('✅ [Produccion] Usando v_asistencia_tecnicos: dias_con_produccion=$diasTrabajados, ausencias=$diasAusentesFinales, vacaciones=$vacacionesFinales');
      } else {
        // Fallback: calcular desde produccion_creaciones
        diasTrabajados = diasConProduccion.length + diasPX0;
        vacacionesFinales = 0;
        diasAusentesFinales = (diasHabiles - diasTrabajados - feriadosFinales - vacacionesFinales).clamp(0, diasHabiles);
        print('⚠️ [Produccion] Sin asistencia en Supabase — calculando desde produccion_creaciones ($diasTrabajados días)');
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
          .eq('estado', 'Completado')
          .ilike('fecha_trabajo', '*/$mesPadded/$annoCorto');

      final ordenesCompletadas = response as List;

      // Agrupar por día (usar solo órdenes completadas)
      Map<String, Map<String, dynamic>> porDia = {};

      for (var orden in ordenesCompletadas) {
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
          .eq('estado', 'Completado')
          .inFilter('rut_tecnico', ruts)
          .inFilter('fecha_trabajo', fechas);
      final lista =
          (resp as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
      // Obtener TODAS las órdenes completadas usando paginación
      List<Map<String, dynamic>> todasOrdenes = [];
      int offset = 0;
      const int pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        final response = await _supabase
            .from('produccion_crea')
            .select('rut_tecnico, tecnico, rgu_total, fecha_trabajo, estado')
            .eq('estado', 'Completado')
            .range(offset, offset + pageSize - 1);

        final batch = List<Map<String, dynamic>>.from(response as List);
        todasOrdenes.addAll(batch);

        print('📦 [Ranking] Lote offset=$offset: ${batch.length} registros');

        hasMore = batch.length == pageSize;
        offset += pageSize;
      }

      print('📊 [Ranking] Total órdenes completadas obtenidas: ${todasOrdenes.length}');

      // Debug: mostrar ejemplos de fechas
      if (todasOrdenes.isNotEmpty) {
        final ejemplosFechas = todasOrdenes.take(5).map((o) => o['fecha_trabajo']).toList();
        print('🔍 [Ranking] Ejemplos de fechas: $ejemplosFechas');
      }

      // Filtrar por mes y año
      final ordenesMes = todasOrdenes.where((orden) {
        final fechaStr = orden['fecha_trabajo']?.toString() ?? '';
        final partes = fechaStr.split('/');

        if (partes.length != 3) {
          return false;
        }

        // Formato: D/M/YYYY o DD/MM/YYYY
        final mesOrden = int.tryParse(partes[1]) ?? 0;
        final annoOrden = int.tryParse(partes[2]) ?? 0;

        final coincide = mesOrden == mesConsulta && annoOrden == annoConsulta;
        return coincide;
      }).toList();

      print('✅ [Ranking] Órdenes filtradas mes $mesConsulta/$annoConsulta: ${ordenesMes.length}');

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

    // Buscar al técnico
    Map<String, dynamic>? tecnicoEncontrado;
    for (var t in ranking) {
      if (t['rut'] == rutTecnico) {
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
  // MÉTRICAS DE TIEMPO
  // ═══════════════════════════════════════════════════════════

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
      // Incluir órdenes Completadas, Suspendidas, Canceladas y No realizadas para el cálculo de inicio tardío
      final response = await _supabase
          .from('produccion_crea')
          .select('fecha_trabajo, hora_inicio, hora_fin, duracion_min, estado')
          .eq('rut_tecnico', rutTecnico)
          .inFilter('estado', ['Completado', 'Suspendido', 'Cancelado', 'No realizado']);

      final todasOrdenes = List<Map<String, dynamic>>.from(response as List);

      // Filtrar por mes y año
      final ordenesMes = todasOrdenes.where((orden) {
        final fechaStr = orden['fecha_trabajo']?.toString() ?? '';
        final partes = fechaStr.split('/');
        if (partes.length != 3) return false;

        final mesOrden = int.tryParse(partes[1]) ?? 0;
        final annoOrden = int.tryParse(partes[2]) ?? 0;

        return mesOrden == mesConsulta && annoOrden == annoConsulta;
      }).toList();

      if (ordenesMes.isEmpty) {
        return _metricasTiempoVacias();
      }

      // Agrupar por día
      Map<String, List<Map<String, dynamic>>> porDia = {};
      for (var orden in ordenesMes) {
        final fecha = orden['fecha_trabajo']?.toString() ?? '';
        porDia.putIfAbsent(fecha, () => []).add(orden);
      }

      int tiempoTrabajoTotal = 0;
      int tiempoTrayectoTotal = 0;
      int tiempoInicioTardioTotal = 0;
      int tiempoFinTempranoTotal = 0;
      int tiempoProductivoEsperado = 0;
      int diasTrabajados = porDia.length;
      int diasSemana = 0;
      int diasSabado = 0;
      List<Map<String, dynamic>> detalleInicioTardio = [];
      List<Map<String, dynamic>> detalleHorasExtras = [];
      int horasExtrasTotal = 0;
      // Para fallback de hora fin: guardar última hora_fin por fecha
      final Map<String, String> ultimaHoraFinPorDia = {};

      for (var entry in porDia.entries) {
        final fechaStr = entry.key;
        var ordenesDelDia = entry.value;

        // Parsear fecha para determinar día de la semana
        final partesFecha = fechaStr.split('/');
        DateTime? fecha;
        if (partesFecha.length == 3) {
          final dia = int.tryParse(partesFecha[0]) ?? 1;
          final mes = int.tryParse(partesFecha[1]) ?? 1;
          final anno = int.tryParse(partesFecha[2]) ?? 2025;
          fecha = DateTime(anno, mes, dia);
        }

        // Determinar parámetros según día de la semana
        final esSabado = fecha?.weekday == DateTime.saturday;
        final horaInicioJornada = esSabado ? 600 : 585;   // 10:00 o 9:45
        final horaFinJornada = esSabado ? 900 : 1125;     // 15:00 o 18:45
        final tiempoProductivoDia = esSabado ? 240 : 480; // 4h o 8h

        if (esSabado) {
          diasSabado++;
        } else {
          diasSemana++;
        }

        tiempoProductivoEsperado += tiempoProductivoDia;

        // Ordenar por hora de inicio
        ordenesDelDia.sort((a, b) {
          final horaA = _parseHoraAMinutos(a['hora_inicio']?.toString() ?? '00:00');
          final horaB = _parseHoraAMinutos(b['hora_inicio']?.toString() ?? '00:00');
          return horaA.compareTo(horaB);
        });

        // Sumar tiempo de trabajo del día
        int trabajoDia = 0;
        for (var orden in ordenesDelDia) {
          final duracion = (orden['duracion_min'] as num?)?.toInt() ?? 0;
          trabajoDia += duracion;
        }
        tiempoTrabajoTotal += trabajoDia;

        // Primera y última orden del día
        final primeraHora = _parseHoraAMinutos(ordenesDelDia.first['hora_inicio']?.toString() ?? '00:00');
        final ultimaHora = _parseHoraAMinutos(ordenesDelDia.last['hora_fin']?.toString() ?? '00:00');
        // Registrar hora fin de la última orden del día (string original si existe)
        final ultimaHoraStr = ordenesDelDia.last['hora_fin']?.toString() ?? '';
        ultimaHoraFinPorDia[fechaStr] = ultimaHoraStr;

        // Inicio tardío (si empieza después de la hora esperada pero antes de las 11:00)
        // No contar como atraso si pasa las 11:00 (660 minutos)
        if (primeraHora > horaInicioJornada && primeraHora < 660) {
          final retraso = primeraHora - horaInicioJornada;
          tiempoInicioTardioTotal += retraso;
          // Guardar detalle por día
          detalleInicioTardio.add({
            'fecha': fechaStr,
            'horaInicio': ordenesDelDia.first['hora_inicio']?.toString() ?? '00:00',
            'retraso': retraso,
            'esSabado': esSabado,
          });
        }

        // Fin temprano (si termina antes de la hora esperada)
        if (ultimaHora < horaFinJornada) {
          tiempoFinTempranoTotal += (horaFinJornada - ultimaHora);
        }

        // Tiempo en terreno del día
        final tiempoEnTerreno = ultimaHora - primeraHora;

        // Trayecto/Espera = Tiempo en terreno - Trabajo efectivo
        if (tiempoEnTerreno > trabajoDia) {
          tiempoTrayectoTotal += (tiempoEnTerreno - trabajoDia);
        }
      }

      // Horas extras (vista v_tiempos_tecnicos): minutos posteriores a 18:30 L-V o 15:00 Sáb
      // Horario: 9:45 a 18:30 (L-V) o 10:00 a 15:00 (Sáb)
      try {
        // Usamos select('*') para no fallar si cambian los nombres de columnas
        final extrasResponse = await _supabase
            .from('v_tiempos_tecnicos')
            .select('*')
            .eq('rut_tecnico', rutTecnico)
            .gt('horas_extras_min', 0)
            .order('fecha_trabajo', ascending: false);

        final extras = List<Map<String, dynamic>>.from(extrasResponse as List);

        // Candidatos de nombres de campos para hora fin
        const horaFinKeys = [
          'hora_fin',
          'hora_termino',
          'hora_fin_orden',
          'hora_fin_real',
        ];

        // Agrupar por semana
        Map<String, List<Map<String, dynamic>>> porSemana = {};

        for (final item in extras) {
          final fechaStr = item['fecha_trabajo']?.toString() ?? '';
          final partes = fechaStr.split('/');
          if (partes.length != 3) continue;

          final diaRegistro = int.tryParse(partes[0]) ?? 0;
          final mesRegistro = int.tryParse(partes[1]) ?? 0;
          final annoRegistro = int.tryParse(partes[2]) ?? 0;
          if (mesRegistro != mesConsulta || annoRegistro != annoConsulta) continue;

          final minutos = (item['horas_extras_min'] as num?)?.toInt() ?? 0;
          horasExtrasTotal += minutos;

          // Tomar horaFin de la vista; si no viene, usar fallback de la última orden completada del día
          String horaFin = _pickFirstNonEmpty(item, horaFinKeys);
          if (horaFin.isEmpty) {
            horaFin = ultimaHoraFinPorDia[fechaStr] ?? '';
          }

          // Determinar semana: del 1-7, 8-14, 15-21, 22-28, 29-31
          int semanaNum = 1;
          if (diaRegistro <= 7) {
            semanaNum = 1;
          } else if (diaRegistro <= 14) {
            semanaNum = 2;
          } else if (diaRegistro <= 21) {
            semanaNum = 3;
          } else if (diaRegistro <= 28) {
            semanaNum = 4;
          } else {
            semanaNum = 5;
          }

          final claveSemana = 'semana_$semanaNum';
          porSemana.putIfAbsent(claveSemana, () => []).add({
            'fecha': fechaStr,
            'horasExtrasMin': minutos,
            'esSabado': item['es_sabado'] as bool? ?? false,
            'horaFin': horaFin,
            'dia': diaRegistro,
            'mes': mesRegistro,
            'anno': annoRegistro,
          });
        }

        // Convertir agrupación por semana a lista de semanas
        for (final entry in porSemana.entries) {
          final diasSemana = entry.value;
          final totalSemana = diasSemana.fold<int>(0, (sum, d) => sum + (d['horasExtrasMin'] as int));
          
          // Ordenar días de la semana por fecha
          diasSemana.sort((a, b) => (a['dia'] as int).compareTo(b['dia'] as int));
          
          final primerDia = diasSemana.first;
          final mesSemana = primerDia['mes'] as int;
          final annoSemana = primerDia['anno'] as int;
          
          // Extraer número de semana de la clave (ej: "semana_1" -> 1)
          final semanaNum = int.tryParse(entry.key.split('_').last) ?? 1;
          
          // Calcular inicio y fin de semana
          final inicioSemana = semanaNum == 1 ? 1 : (semanaNum - 1) * 7 + 1;
          final finSemana = semanaNum == 5 
              ? DateTime(annoSemana, mesSemana + 1, 0).day // Último día del mes
              : semanaNum * 7;
          
          detalleHorasExtras.add({
            'tipo': 'semana',
            'inicioSemana': inicioSemana,
            'finSemana': finSemana,
            'mes': mesSemana,
            'anno': annoSemana,
            'totalMinutos': totalSemana,
            'dias': diasSemana,
          });
        }

        // Ordenar semanas por número descendente
        detalleHorasExtras.sort((a, b) {
          final semanaA = a['inicioSemana'] as int;
          final semanaB = b['inicioSemana'] as int;
          return semanaB.compareTo(semanaA);
        });
      } catch (e) {
        print('❌ [Tiempo] Error obteniendo horas extras: $e');
      }

      // Tiempo sin actividad = Inicio tardío + Fin temprano
      final tiempoSinActividad = tiempoInicioTardioTotal + tiempoFinTempranoTotal;

      // Promedios
      final tiempoPromedioOrden = ordenesMes.isNotEmpty
          ? (tiempoTrabajoTotal / ordenesMes.length).round()
          : 0;

      final ordenesPorDia = diasTrabajados > 0
          ? ordenesMes.length / diasTrabajados
          : 0.0;

      // Productividad = Trabajo efectivo / Tiempo productivo esperado
      final productividad = tiempoProductivoEsperado > 0
          ? (tiempoTrabajoTotal / tiempoProductivoEsperado) * 100
          : 0.0;

      // Promedio de inicio tardío por día
      final promedioInicioTardio = diasTrabajados > 0
          ? (tiempoInicioTardioTotal / diasTrabajados).round()
          : 0;

      print('⏱️ [Tiempo] Días L-V: $diasSemana, Sábados: $diasSabado');
      print('⏱️ [Tiempo] Trabajo: ${tiempoTrabajoTotal}min (${(tiempoTrabajoTotal/60).toStringAsFixed(1)}h)');
      print('⏱️ [Tiempo] Esperado: ${tiempoProductivoEsperado}min (${(tiempoProductivoEsperado/60).toStringAsFixed(1)}h)');
      print('⏱️ [Tiempo] Trayecto/Espera: ${tiempoTrayectoTotal}min');
      print('⏱️ [Tiempo] Inicio tardío: ${tiempoInicioTardioTotal}min, Fin temprano: ${tiempoFinTempranoTotal}min');
      print('⏱️ [Tiempo] Productividad: ${productividad.toStringAsFixed(1)}%');

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
  String _pickFirstNonEmpty(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty && s.toLowerCase() != 'null') {
        return s;
      }
    }
    return '';
  }

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
      //    Dashboard: produccion_crea estado=Completado & fecha_trabajo like.*/mesAnt/yearAnt
      final produccionResp = await _supabase
          .from('produccion_crea')
          .select('rut_tecnico, fecha_trabajo')
          .eq('rut_tecnico', rutTecnico)
          .eq('estado', 'Completado')
          .ilike('fecha_trabajo', '*/$mesAnt/$yearAnt');

      final totalCompletadas = (produccionResp as List).length;

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

  /// Obtener ranking de calidad para un período específico
  Future<Map<String, dynamic>> obtenerRankingCalidad(String periodo) async {
    try {
      print('🏆 [Calidad] Obteniendo ranking para período: $periodo');
      
      final response = await _supabase
          .from('v_calidad_tecnicos')
          .select()
          .eq('periodo', periodo)
          .order('porcentaje_reiteracion', ascending: true);

      final List<Map<String, dynamic>> tecnicos = List<Map<String, dynamic>>.from(response as List);
      
      // Asignar posiciones
      for (int i = 0; i < tecnicos.length; i++) {
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
      
      // Buscar al técnico
      Map<String, dynamic>? tecnicoEncontrado;
      for (var t in ranking) {
        if (t['rut_tecnico'] == rutTecnico) {
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

