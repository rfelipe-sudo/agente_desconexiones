import 'dart:convert';

import 'package:agente_desconexiones/constants/app_constants.dart';
import 'package:agente_desconexiones/services/nyquist_service.dart';
import 'package:http/http.dart' as http;

/// Panel coordinación Nyquist (`datos_panel_coord`) para Mi Equipo.
///
/// Mapeo temporal: en Nyquist el equipo 2 sigue bajo Rafael Martínez;
/// en CREABOX el supervisor es Luis García → al consultar con el RUT de Luis
/// leemos el bucket de Rafael en Nyquist.
class NyquistPanelCoordService {
  NyquistPanelCoordService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _baseUrl = 'https://nyquist.sbip.cl/api/v1/datos_panel_coord';

  /// CREABOX — Luis García Benitez (supervisor equipo 2).
  static const String rutLuisGarcia = '25626541-9';
  static const String nombreLuisGarcia = 'LUIS GARCIA BENITEZ';

  /// Nyquist — aún figura como supervisor del equipo 2.
  static const String rutRafaelMartinez = '26601622-0';
  static const String nombreRafaelMartinez = 'RAFAEL ANGEL MARTINEZ CHACARE';

  /// RUT de sesión → RUT con el que Nyquist indexa al supervisor.
  static String rutNyquistParaSupervisor(String rutSupervisor) {
    final key = normalizeRutKey(rutSupervisor);
    if (key == normalizeRutKey(rutLuisGarcia)) return rutRafaelMartinez;
    return rutSupervisor;
  }

  /// Nombre mostrado en CREABOX (no el de Nyquist si hay mapeo).
  static String nombreDisplaySupervisor(String rutSupervisor) {
    if (normalizeRutKey(rutSupervisor) == normalizeRutKey(rutLuisGarcia)) {
      return nombreLuisGarcia;
    }
    return '';
  }

  Future<Map<String, dynamic>> fetchPanelRaw() async {
    final resp = await _client.get(
      Uri.parse(_baseUrl),
      headers: {
        'api-token': AppConstants.nyquistPanelCoordToken,
        'Accept': 'application/json',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Nyquist panel_coord HTTP ${resp.statusCode}: ${resp.body}',
      );
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// KPIs + técnicos del supervisor de sesión (con mapeo Rafael→Luis).
  Future<NyquistEquipoSupervisor> obtenerEquipoSupervisor(
    String rutSupervisor,
  ) async {
    final raw = await fetchPanelRaw();
    final rutNyquist = rutNyquistParaSupervisor(rutSupervisor);
    final nomNyquist = _nomDesdeSups(raw, rutNyquist);

    if (nomNyquist == null) {
      throw Exception(
        'Supervisor no encontrado en Nyquist (rut=$rutNyquist)',
      );
    }

    final supKpi = raw['sup_kpi'] as Map<String, dynamic>? ?? {};
    final supTec = raw['sup_tec'] as Map<String, dynamic>? ?? {};

    final kpi = Map<String, dynamic>.from(
      (supKpi[nomNyquist] as Map?)?.cast<String, dynamic>() ?? {},
    );
    final tecnicosRaw = supTec[nomNyquist] as List? ?? [];
    final tecnicos = tecnicosRaw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final displayNombre = nombreDisplaySupervisor(rutSupervisor);
    final sups = raw['sups'] as List? ?? [];
    final metaSup = sups
        .cast<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((s) => normalizeRutKey(s['rut']?.toString() ?? '') ==
            normalizeRutKey(rutNyquist))
        .firstOrNull;

    return NyquistEquipoSupervisor(
      rutSesion: rutSupervisor,
      nombreSesion: displayNombre.isNotEmpty
          ? displayNombre
          : (metaSup?['nom']?.toString() ?? nomNyquist),
      equipo: metaSup?['equipo']?.toString(),
      mapeadoDesdeRafael: normalizeRutKey(rutSupervisor) ==
          normalizeRutKey(rutLuisGarcia),
      nomNyquist: nomNyquist,
      dates: Map<String, dynamic>.from(
        (raw['dates'] as Map?)?.cast<String, dynamic>() ?? {},
      ),
      kpi: kpi,
      tecnicos: tecnicos,
    );
  }

  String? _nomDesdeSups(Map<String, dynamic> raw, String rut) {
    final sups = raw['sups'] as List? ?? [];
    final key = normalizeRutKey(rut);
    for (final item in sups) {
      final m = Map<String, dynamic>.from(item as Map);
      if (normalizeRutKey(m['rut']?.toString() ?? '') == key) {
        return m['nom']?.toString();
      }
    }
    return null;
  }

  static double asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static int entero(dynamic v) => asDouble(v).round();

  static int diasHabilesMesActual() {
    final hoy = DateTime.now();
    var count = 0;
    for (var d = 1; d <= hoy.day; d++) {
      if (DateTime(hoy.year, hoy.month, d).weekday != DateTime.sunday) {
        count++;
      }
    }
    return count > 0 ? count : 1;
  }

  /// Sin cierre hoy: flag Nyquist o actividad sin OT completada ni RGU.
  static bool esPx0Hoy(Map<String, dynamic> t) {
    if (t['ausente'] == true || t['permiso'] == true) return false;
    if (t['es_px0'] == true) return true;
    if (t['tiene_actividad_dia'] != true) return false;
    final completadas = entero(t['completadas']);
    final rgu = asDouble(t['rgu_dia']);
    final enEjecucion = entero(t['en_ejecucion']);
    return completadas == 0 && rgu <= 0 && enEjecucion > 0;
  }

  static String rutTecnico(Map<String, dynamic> t) =>
      (t['rut']?.toString() ?? '').trim().toUpperCase();

  static String nombreTecnico(Map<String, dynamic> t) =>
      (t['nombre']?.toString() ?? '').trim();
}

class NyquistEquipoSupervisor {
  final String rutSesion;
  final String nombreSesion;
  final String? equipo;
  final bool mapeadoDesdeRafael;
  final String nomNyquist;
  final Map<String, dynamic> dates;
  final Map<String, dynamic> kpi;
  final List<Map<String, dynamic>> tecnicos;

  const NyquistEquipoSupervisor({
    required this.rutSesion,
    required this.nombreSesion,
    this.equipo,
    required this.mapeadoDesdeRafael,
    required this.nomNyquist,
    required this.dates,
    required this.kpi,
    required this.tecnicos,
  });

  int get nTecnicos => tecnicos.length;

  double get rguDia => NyquistPanelCoordService.asDouble(kpi['rgu_dia']);
  double get rguMesActual =>
      NyquistPanelCoordService.asDouble(kpi['rgu_mes_actual']);
  int get operativos => NyquistPanelCoordService.entero(kpi['operativos']);
  int get ausentes => NyquistPanelCoordService.entero(kpi['ausentes']);
  int get permisos => NyquistPanelCoordService.entero(kpi['permiso']);
  int get compDia => NyquistPanelCoordService.entero(kpi['comp_dia']);
  int get cursoDia => NyquistPanelCoordService.entero(kpi['curso_dia']);
  int get sinCierreDia => NyquistPanelCoordService.entero(kpi['sc_dia']);
  int get otsMesActual => NyquistPanelCoordService.entero(kpi['ots_pago_act']);
  int get otsMesPago => NyquistPanelCoordService.entero(kpi['ots_pago']);
  double get pctReitPago =>
      NyquistPanelCoordService.asDouble(kpi['pct_reit_pago']);
  int get reitPago => NyquistPanelCoordService.entero(kpi['reit_pago']);
  double get pctReitActual =>
      NyquistPanelCoordService.asDouble(kpi['pct_reit_actual']);
  int get reitActual => NyquistPanelCoordService.entero(kpi['reit_actual']);
  int get conFirma => NyquistPanelCoordService.entero(kpi['con_firma']);
  int get nTecPlantel => NyquistPanelCoordService.entero(kpi['n_tec']);

  /// Promedio RGU/día por técnico en el mes (campo Nyquist `rgu_prom_dia`).
  double get rguPromDiaMesPorTecnico {
    final vals = <double>[];
    for (final t in tecnicos) {
      final dias =
          NyquistPanelCoordService.entero(t['dias_trabajados_mes_actual']);
      final prom = NyquistPanelCoordService.asDouble(t['rgu_prom_dia']);
      if (dias > 0 || prom > 0) vals.add(prom);
    }
    if (vals.isEmpty) return 0;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  int get tecnicosConPromMes => tecnicos.where((t) {
        final dias =
            NyquistPanelCoordService.entero(t['dias_trabajados_mes_actual']);
        final prom = NyquistPanelCoordService.asDouble(t['rgu_prom_dia']);
        return dias > 0 || prom > 0;
      }).length;

  /// RGU del día del equipo / operativos (promedio hoy por técnico operativo).
  double get rguPromDiaHoyPorTecnico =>
      operativos > 0 ? rguDia / operativos : 0;

  double get metaDia => operativos > 0 ? operativos * 4.0 : nTecnicos * 4.0;

  double get metaMes {
    final n = nTecPlantel > 0 ? nTecPlantel : nTecnicos;
    final dias = NyquistPanelCoordService.diasHabilesMesActual();
    return n * 4.0 * dias;
  }

  double get pctMetaDia =>
      metaDia > 0 ? (rguDia / metaDia).clamp(0.0, 1.0) : 0;

  double get pctMetaMes =>
      metaMes > 0 ? (rguMesActual / metaMes).clamp(0.0, 1.0) : 0;

  /// Técnicos sin cierre hoy → indicador PX0.
  List<Map<String, dynamic>> get px0Hoy =>
      tecnicos.where(NyquistPanelCoordService.esPx0Hoy).toList();

  List<Map<String, dynamic>> get tecnicosConCierreHoy =>
      tecnicos.where((t) => !NyquistPanelCoordService.esPx0Hoy(t)).toList();

  String get periodoActual =>
      dates['filter_fecha_actual']?.toString() ?? '';

  String get periodoPago =>
      dates['filter_fecha_pago']?.toString() ?? '';
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
