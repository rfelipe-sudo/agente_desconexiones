// ============================================================================
// SERVICIO DE DATOS — MI EQUIPO (produccion, calidad, extensiones)
// ============================================================================

import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'produccion_service.dart';

String _nombreNomina(Map<String, dynamic> r) {
  final n =
      '${r['nombres'] ?? ''} ${r['paterno'] ?? ''} ${r['materno'] ?? ''}'.trim();
  return n.replaceAll(RegExp(r'\s+'), ' ');
}

class MiEquipoDataService {
  final _supabase = Supabase.instance.client;

  /// Usa ProduccionService.cuentaComoProduccion para consistencia
  static bool _cuentaComoProduccion(dynamic r) =>
      ProduccionService.cuentaComoProduccion(r);

  /// Expande RUTs con variantes (12345678-9, 12.345.678-9) para búsquedas en produccion
  static List<String> _rutsConVariantes(List<String> ruts) {
    final expandidos = <String>{};
    for (final r in ruts) {
      expandidos.addAll(ProduccionService.rutVariantes(r));
    }
    final lista = expandidos.where((x) => x.isNotEmpty).toList();
    return lista.isNotEmpty ? lista : List.from(ruts);
  }

  /// Evalúa si es_reiterado indica reiteración (acepta bool, int 1, "true", "SI")
  static bool _esReiterado(dynamic val) {
    if (val == null) return false;
    if (val == true || val == 1) return true;
    final s = val.toString().trim().toUpperCase();
    return s == 'TRUE' || s == 'SI' || s == 'YES' || s == '1';
  }

  /// Días hábiles transcurridos en el mes seleccionado.
  /// Si es mes actual: hasta hoy. Si es mes pasado: todos los días hábiles.
  static int diasHabilesTranscurridos(DateTime mesSeleccionado) {
    final hoy = DateTime.now();
    final esActual = mesSeleccionado.month == hoy.month &&
        mesSeleccionado.year == hoy.year;
    final ultimoDia = DateTime(mesSeleccionado.year, mesSeleccionado.month + 1, 0);
    final limite = esActual ? hoy.day : ultimoDia.day;
    int count = 0;
    for (int d = 1; d <= limite; d++) {
      if (DateTime(mesSeleccionado.year, mesSeleccionado.month, d)
          .weekday != DateTime.sunday) count++;
    }
    return math.max(count, 1);
  }

  /// Lista de meses disponibles (últimos 4: actual + 3 anteriores)
  static List<DateTime> mesesDisponibles() {
    final hoy = DateTime.now();
    return List.generate(4, (i) => DateTime(hoy.year, hoy.month - i, 1))
        .reversed
        .toList();
  }

  /// Obtener mapa rut -> nombre desde nomina_tecnicos (CREA)
  Future<Map<String, String>> obtenerNombresTecnicos(
      List<String> rutsEquipo) async {
    if (rutsEquipo.isEmpty) return {};
    try {
      final resp = await _supabase
          .from('nomina_tecnicos')
          .select('rut, nombres, paterno, materno')
          .inFilter('rut', rutsEquipo);

      final mapa = <String, String>{};
      for (final r in resp as List) {
        final m = Map<String, dynamic>.from(r as Map);
        final rut = m['rut'] as String? ?? '';
        final nombre = _nombreNomina(m);
        if (rut.isNotEmpty && nombre.isNotEmpty) {
          mapa[rut] = nombre;
        }
      }
      return mapa;
    } catch (e) {
      return {};
    }
  }

  /// Obtener RUTs del equipo del supervisor
  Future<List<String>> obtenerRutsEquipo(String rutSupervisor) async {
    try {
      final resp = await _supabase
          .from('supervisor_tecnicos_crea')
          .select('rut_tecnico')
          .eq('rut_supervisor', rutSupervisor);
      return (resp as List)
          .map((e) => e['rut_tecnico'] as String? ?? '')
          .where((r) => r.isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Obtener códigos de técnicos desde produccion del día (para extensiones_tiempo)
  Future<List<String>> obtenerCodigosTecnicosEquipo(
      String rutSupervisor) async {
    try {
      final ruts = await obtenerRutsEquipo(rutSupervisor);
      if (ruts.isEmpty) return [];

      final hoy = DateTime.now();
      final dd = hoy.day.toString().padLeft(2, '0');
      final mm = hoy.month.toString().padLeft(2, '0');
      final yy = hoy.year.toString().substring(2);
      final fechaPunto = '$dd.$mm.$yy';
      final fechaBarra = '$dd/$mm/$yy';

      final rutsLista = _rutsConVariantes(ruts);
      final resp = await _supabase
          .from('produccion_crea')
          .select('codigo_tecnico')
          .inFilter('fecha_trabajo', [fechaPunto, fechaBarra])
          .inFilter('rut_tecnico', rutsLista);

      final codigos = <String>{};
      for (final r in resp as List) {
        final c = r['codigo_tecnico'] as String?;
        if (c != null && c.isNotEmpty) codigos.add(c);
      }
      return codigos.toList();
    } catch (e) {
      return [];
    }
  }

  /// Producción del mes — filtro por SUFIJO (ilike) para ambos formatos
  Future<Map<String, dynamic>> obtenerProduccionMes(
      List<String> rutsEquipo, DateTime mesSeleccionado) async {
    if (rutsEquipo.isEmpty) {
      return {
        'total_completadas': 0,
        'total_completadas_calidad': 0,
        'total_rgu': 0.0,
        'registros': <Map<String, dynamic>>[],
      };
    }
    try {
      final mm = mesSeleccionado.month.toString().padLeft(2, '0');
      final yy = mesSeleccionado.year.toString().substring(2);
      final yy4 = mesSeleccionado.year.toString();
      final sufPunto = '.$mm.$yy';
      final sufBarra = '/$mm/$yy';
      final sufPunto4 = '.$mm.$yy4';
      final sufBarra4 = '/$mm/$yy4';

      final rutsLista = _rutsConVariantes(rutsEquipo);
      final resp = await _supabase
          .from('produccion_crea')
          .select('rut_tecnico, tecnico, codigo_tecnico, orden_trabajo, estado, area_derivacion, rgu_total, es_px0, fecha_trabajo')
          .or('fecha_trabajo.ilike.%$sufPunto,fecha_trabajo.ilike.%$sufBarra,fecha_trabajo.ilike.%$sufPunto4,fecha_trabajo.ilike.%$sufBarra4')
          .inFilter('rut_tecnico', rutsLista);

      final lista = resp as List;
      int completadas = 0;
      int completadasCalidad = 0;
      double totalRgu = 0;
      for (final r in lista) {
        if (_cuentaComoProduccion(r)) {
          completadas++;
          if (!ProduccionService.esDerivacionRedes(r)) completadasCalidad++;
          totalRgu += ((r['rgu_total'] as num?) ?? 0).toDouble();
        }
      }

      return {
        'total_completadas': completadas,
        'total_completadas_calidad': completadasCalidad,
        'total_rgu': totalRgu,
        'registros': lista.cast<Map<String, dynamic>>(),
      };
    } catch (e) {
      return {
        'total_completadas': 0,
        'total_completadas_calidad': 0,
        'total_rgu': 0.0,
        'registros': <Map<String, dynamic>>[],
      };
    }
  }

  /// Producción del día (solo hoy — para activos, pendientes, PX0, quiebre)
  Future<Map<String, dynamic>> obtenerProduccionHoy(
      List<String> rutsEquipo) async {
    if (rutsEquipo.isEmpty) {
      return {
        'activos': 0,
        'tec_activos': 0,
        'pendientes_iniciar': 0,
        'px0': [],
        'quiebre': 0,
        'rgu_hoy': 0.0,
        'registros': <Map<String, dynamic>>[],
      };
    }
    try {
      final hoy = DateTime.now();
      final dd = hoy.day.toString().padLeft(2, '0');
      final mm = hoy.month.toString().padLeft(2, '0');
      final yy = hoy.year.toString().substring(2);
      final fechaPunto = '$dd.$mm.$yy';
      final fechaBarra = '$dd/$mm/$yy';

      final rutsLista = _rutsConVariantes(rutsEquipo);
      final resp = await _supabase
          .from('produccion_crea')
          .select('rut_tecnico, tecnico, codigo_tecnico, orden_trabajo, estado, area_derivacion, rgu_total, es_px0')
          .inFilter('fecha_trabajo', [fechaPunto, fechaBarra])
          .inFilter('rut_tecnico', rutsLista);

      final lista = (resp as List).cast<Map<String, dynamic>>();
      final activosRuts = <String>{};
      int pendientes = 0;
      final px0List = <Map<String, dynamic>>[];
      int quiebre = 0;
      double rguHoy = 0;

      for (final r in lista) {
        final rut = r['rut_tecnico'] as String? ?? '';
        final estado = r['estado'] as String? ?? '';
        final esPx0 = r['es_px0'] == true;
        final cuentaComoProd = _cuentaComoProduccion(r);

        if (cuentaComoProd || estado == 'Iniciado') {
          activosRuts.add(rut);
        }
        if (cuentaComoProd) {
          rguHoy += ((r['rgu_total'] as num?) ?? 0).toDouble();
        }

        if (estado == 'Iniciado') pendientes++;

        if (esPx0) {
          px0List.add({
            ...r,
            'tiene_trabajo_cargado': cuentaComoProd || estado == 'Iniciado',
          });
        }

        if (estado == 'No Realizada' && (r['area_derivacion']?.toString() ?? '').trim().toUpperCase() != 'GSA' && (r['area_derivacion']?.toString() ?? '').trim().toUpperCase() != 'REDES' ||
            estado == 'Cancelado' ||
            estado == 'Suspendido') {
          quiebre++;
        }
      }

      px0List.sort((a, b) {
        final aCargado = a['tiene_trabajo_cargado'] == true;
        final bCargado = b['tiene_trabajo_cargado'] == true;
        if (!aCargado && bCargado) return -1;
        if (aCargado && !bCargado) return 1;
        return 0;
      });

      return {
        'activos': activosRuts.length,
        'tec_activos': activosRuts.length,
        'pendientes_iniciar': pendientes,
        'px0': px0List,
        'quiebre': quiebre,
        'rgu_hoy': rguHoy,
        'registros': lista,
      };
    } catch (e) {
      return {
        'activos': 0,
        'tec_activos': 0,
        'pendientes_iniciar': 0,
        'px0': [],
        'quiebre': 0,
        'rgu_hoy': 0.0,
        'registros': <Map<String, dynamic>>[],
      };
    }
  }

  /// Calidad mes (reiteración) — total desde PRODUCCION; si 0, desde calidad_api_script
  /// Reiterados desde calidad_api_script
  Future<Map<String, dynamic>> obtenerCalidadMes(
      List<String> rutsEquipo, DateTime mesSeleccionado) async {
    if (rutsEquipo.isEmpty) {
      return {'reiterados': 0, 'total': 0, 'porcentaje': 0.0};
    }
    try {
      // Mes seleccionado = mes de trabajo; calidad_api_script guarda mes de remuneración (+1).
      final rem = DateTime(mesSeleccionado.year, mesSeleccionado.month + 1, 1);
      final periodoRem =
          '${rem.month.toString().padLeft(2, '0')}-${rem.year}';

      // Reiterados y total desde calidad_api_script
      final resp = await _supabase
          .from('calidad_api_script')
          .select('rut_o_bucket, es_reiterado')
          .eq('periodo', periodoRem)
          .inFilter('rut_o_bucket', rutsEquipo);

      final lista = resp as List;
      int reiterados = 0;
      for (final r in lista) {
        if (_esReiterado(r['es_reiterado'])) reiterados++;
      }
      final totalCalidad = lista.length;

      // Total: preferir produccion (denominador calidad = completadas sin REDES); si 0, usar calidad_api_script
      final prod = await obtenerProduccionMes(rutsEquipo, mesSeleccionado);
      final totalProdAll = prod['total_completadas'] as int? ?? 0;
      final totalProdCalidad = prod['total_completadas_calidad'] as int? ?? 0;
      final total = totalProdAll > 0 ? totalProdCalidad : totalCalidad;
      final porcentaje = total > 0 ? (reiterados / total) * 100 : 0.0;

      return {
        'reiterados': reiterados,
        'total': total,
        'porcentaje': porcentaje,
      };
    } catch (e) {
      return {'reiterados': 0, 'total': 0, 'porcentaje': 0.0};
    }
  }

  /// Extensiones de tiempo hoy
  Future<int> obtenerExtensionesHoy(List<String> codigosTecnicos) async {
    if (codigosTecnicos.isEmpty) return 0;
    try {
      final hoy = DateTime.now();
      final inicioDia = DateTime(hoy.year, hoy.month, hoy.day);

      final resp = await _supabase
          .from('extensiones_tiempo')
          .select('codigo_tecnico')
          .gte('hora_aplicada', inicioDia.toUtc().toIso8601String())
          .inFilter('codigo_tecnico', codigosTecnicos);

      return (resp as List).length;
    } catch (e) {
      return 0;
    }
  }

  /// Quiebre del mes (%) — desde registros de produccion
  Future<Map<String, dynamic>> obtenerQuiebreMes(
      List<String> rutsEquipo, DateTime mesSeleccionado) async {
    if (rutsEquipo.isEmpty) {
      return {'quiebre': 0, 'total': 0, 'porcentaje': 0.0};
    }
    try {
      final prod = await obtenerProduccionMes(rutsEquipo, mesSeleccionado);
      final registros = prod['registros'] as List<Map<String, dynamic>>;
      int quiebre = 0;
      for (final r in registros) {
        final estado = r['estado'] as String? ?? '';
        final areaDerivacion = r['area_derivacion']?.toString() ?? '';
        if (estado == 'No Realizada' && areaDerivacion.toUpperCase() != 'GSA' && areaDerivacion.toUpperCase() != 'REDES' ||
            estado == 'Cancelado' ||
            estado == 'Suspendido') quiebre++;
      }
      final total = registros.length;
      final porcentaje = total > 0 ? (quiebre / total) * 100 : 0.0;
      return {'quiebre': quiebre, 'total': total, 'porcentaje': porcentaje};
    } catch (e) {
      return {'quiebre': 0, 'total': 0, 'porcentaje': 0.0};
    }
  }

  /// Datos mes anterior para comparación
  Future<Map<String, dynamic>> obtenerDatosMesAnterior(
      List<String> rutsEquipo, DateTime mesSeleccionado) async {
    if (rutsEquipo.isEmpty) {
      return {
        'rgu_promedio': 0.0,
        'reiteracion': 0.0,
        'quiebre': 0.0,
        'ordenes_promedio': 0.0,
      };
    }
    try {
      final mesAnt = DateTime(mesSeleccionado.year, mesSeleccionado.month - 1);
      final mm = mesAnt.month.toString().padLeft(2, '0');
      final yy = mesAnt.year.toString().substring(2);
      final yy4 = mesAnt.year.toString();
      final sufPunto = '.$mm.$yy';
      final sufBarra = '/$mm/$yy';
      final sufPunto4 = '.$mm.$yy4';
      final sufBarra4 = '/$mm/$yy4';

      final rutsLista = _rutsConVariantes(rutsEquipo);
      final respProd = await _supabase
          .from('produccion_crea')
          .select('rut_tecnico, estado, area_derivacion, rgu_total')
          .or('fecha_trabajo.ilike.%$sufPunto,fecha_trabajo.ilike.%$sufBarra,fecha_trabajo.ilike.%$sufPunto4,fecha_trabajo.ilike.%$sufBarra4')
          .inFilter('rut_tecnico', rutsLista);

      final remAnt = DateTime(mesAnt.year, mesAnt.month + 1, 1);
      final periodoAntRem =
          '${remAnt.month.toString().padLeft(2, '0')}-${remAnt.year}';
      final respCalidad = await _supabase
          .from('calidad_api_script')
          .select('rut_o_bucket, es_reiterado')
          .eq('periodo', periodoAntRem)
          .inFilter('rut_o_bucket', rutsEquipo);

      final listaProd = respProd as List;
      int completadas = 0;
      int completadasCalidad = 0;
      double totalRgu = 0;
      int quiebre = 0;
      for (final r in listaProd) {
        final estado = r['estado'] as String? ?? '';
        final areaDerivacion = r['area_derivacion']?.toString() ?? '';
        if (_cuentaComoProduccion(r)) {
          completadas++;
          if (!ProduccionService.esDerivacionRedes(r)) completadasCalidad++;
          totalRgu += ((r['rgu_total'] as num?) ?? 0).toDouble();
        } else if (estado == 'No Realizada' && areaDerivacion.toUpperCase() != 'GSA' && areaDerivacion.toUpperCase() != 'REDES' ||
            estado == 'Cancelado' ||
            estado == 'Suspendido') {
          quiebre++;
        }
      }

      final listaCal = respCalidad as List;
      int reiterados = 0;
      for (final r in listaCal) {
        if (_esReiterado(r['es_reiterado'])) reiterados++;
      }
      // Denominador calidad: producción completada excl. derivación REDES
      final reiteracion =
          completadasCalidad > 0 ? (reiterados / completadasCalidad) * 100 : 0.0;
      final totalProd = listaProd.length;
      final quiebrePct = totalProd > 0 ? (quiebre / totalProd) * 100 : 0.0;

      final nTec = rutsEquipo.length;
      return {
        'rgu_promedio': nTec > 0 ? totalRgu / nTec : 0.0,
        'reiteracion': reiteracion,
        'quiebre': quiebrePct,
        'ordenes_promedio': nTec > 0 ? completadas / nTec : 0.0,
      };
    } catch (e) {
      return {
        'rgu_promedio': 0.0,
        'reiteracion': 0.0,
        'quiebre': 0.0,
        'ordenes_promedio': 0.0,
      };
    }
  }

  /// Técnicos con RGU del día (solo cuando mesSeleccionado es mes actual)
  Future<List<Map<String, dynamic>>> obtenerTecnicosConRguHoy(
      List<String> rutsEquipo) async {
    if (rutsEquipo.isEmpty) return [];
    try {
      final hoy = DateTime.now();
      final dd = hoy.day.toString().padLeft(2, '0');
      final mm = hoy.month.toString().padLeft(2, '0');
      final yy = hoy.year.toString().substring(2);
      final fechaPunto = '$dd.$mm.$yy';
      final fechaBarra = '$dd/$mm/$yy';

      final resp = await _supabase
          .from('produccion_crea')
          .select('rut_tecnico, tecnico, estado, area_derivacion, rgu_total')
          .inFilter('fecha_trabajo', [fechaPunto, fechaBarra])
          .inFilter('rut_tecnico', _rutsConVariantes(rutsEquipo));

      final mapa = <String, Map<String, dynamic>>{};
      for (final r in resp as List) {
        final rut = r['rut_tecnico'] as String? ?? '';
        final nombre = r['tecnico'] as String? ?? '';
        final rgu = ((r['rgu_total'] as num?) ?? 0).toDouble();

        if (!mapa.containsKey(rut)) {
          mapa[rut] = {
            'rut': rut,
            'nombre': nombre,
            'rgu_dia': 0.0,
            'completadas': 0,
            'total': 0,
            'activo': false,
          };
        }
        final m = mapa[rut]!;
        m['total'] = (m['total'] as int) + 1;
        if (_cuentaComoProduccion(r)) {
          m['completadas'] = (m['completadas'] as int) + 1;
          m['rgu_dia'] = (m['rgu_dia'] as double) + rgu;
        }
        m['activo'] = true;
      }

      for (final rut in rutsEquipo) {
        if (!mapa.containsKey(rut)) {
          mapa[rut] = {
            'rut': rut,
            'nombre': rut,
            'rgu_dia': 0.0,
            'completadas': 0,
            'total': 0,
            'activo': false,
          };
        }
      }

      return mapa.values.toList();
    } catch (e) {
      return [];
    }
  }
}
