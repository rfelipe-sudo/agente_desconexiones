import 'package:intl/intl.dart';

/// Sección del detalle diario (scroll al abrir desde resumen).
enum CombustibleDetalleSeccion { operativo, trayecto }

/// Trayecto personal en dos tramos: casa → 1ª visita (AM) y última visita → casa.
class TrayectoDiaLegs {
  TrayectoDiaLegs({
    required this.kmIda,
    required this.kmVuelta,
    required this.litrosIda,
    required this.litrosVuelta,
    required this.costoIda,
    required this.costoVuelta,
  });

  final double kmIda;
  final double kmVuelta;
  final double litrosIda;
  final double litrosVuelta;
  final double costoIda;
  final double costoVuelta;

  double get kmTotal => kmIda + kmVuelta;
  double get litrosTotal => litrosIda + litrosVuelta;
  double get costoTotal => costoIda + costoVuelta;

  static double _pick(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return 0;
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) {
        return CombustibleFormat.toDouble(m[k]);
      }
    }
    return 0;
  }

  /// Prioriza columnas explícitas ida/vuelta en `combustible_diario_tecnico` / RPC.
  /// Si solo hay un total, reparte mitad/mitad y corrige si parece duplicado (≈2× ida+vuelta).
  factory TrayectoDiaLegs.fromRpcYDia({
    Map<String, dynamic>? rpc,
    Map<String, dynamic>? diaRow,
    double kmTrayectoFijo = 40,
    double precioLitro = 1500,
    double rendimientoKm = 13,
  }) {
    var kmIda = _pick(diaRow, [
      'km_trayecto_ida',
      'km_trayecto_manana',
      'km_trayecto_casa_trabajo',
    ]);
    if (kmIda == 0) {
      kmIda = _pick(rpc, [
        'out_km_trayecto_ida',
        'km_trayecto_ida',
        'out_km_trayecto_manana',
      ]);
    }

    var kmVuelta = _pick(diaRow, [
      'km_trayecto_vuelta',
      'km_trayecto_tarde',
      'km_trayecto_trabajo_casa',
    ]);
    if (kmVuelta == 0) {
      kmVuelta = _pick(rpc, [
        'out_km_trayecto_vuelta',
        'km_trayecto_vuelta',
        'out_km_trayecto_tarde',
      ]);
    }

    if (kmIda <= 0 && kmVuelta <= 0) {
      var total = _pick(diaRow, ['km_trayecto', 'km_trayecto_dia']);
      if (total <= 0) {
        total = _pick(rpc, ['out_km_trayecto', 'km_trayecto']);
      }
      // Si el backend sumó ida+vuelta en un solo número ~el doble del trayecto diario típico.
      if (total > kmTrayectoFijo * 1.25) {
        total = total / 2;
      }
      kmIda = total / 2;
      kmVuelta = total / 2;
    }

    var litIda = _pick(diaRow, ['litros_trayecto_ida', 'litros_trayecto_manana']);
    var litVuelta =
        _pick(diaRow, ['litros_trayecto_vuelta', 'litros_trayecto_tarde']);
    if (litIda <= 0) litIda = kmIda / rendimientoKm;
    if (litVuelta <= 0) litVuelta = kmVuelta / rendimientoKm;

    var costoIda = _pick(diaRow, ['costo_trayecto_ida']);
    var costoVuelta = _pick(diaRow, ['costo_trayecto_vuelta']);
    if (costoIda <= 0) costoIda = litIda * precioLitro;
    if (costoVuelta <= 0) costoVuelta = litVuelta * precioLitro;

    return TrayectoDiaLegs(
      kmIda: kmIda,
      kmVuelta: kmVuelta,
      litrosIda: litIda,
      litrosVuelta: litVuelta,
      costoIda: costoIda,
      costoVuelta: costoVuelta,
    );
  }
}

/// Utilidades de formato numérico para módulo Combustible.
class CombustibleFormat {
  CombustibleFormat._();

  static double toDouble(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  static int toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  static bool toBool(dynamic v, [bool fallback = false]) {
    if (v == null) return fallback;
    if (v is bool) return v;
    final s = v.toString().toLowerCase();
    if (s == 'true' || s == 't' || s == '1') return true;
    if (s == 'false' || s == 'f' || s == '0') return false;
    return fallback;
  }

  /// Siempre `$` antes del número (p. ej. `$8.937`).
  static String formatMoney(num value) {
    final n = value.round();
    final sep = NumberFormat('#,###', 'en_US');
    return '\$${sep.format(n)}';
  }

  /// Misma lógica que la pantalla Combustible: tabla monedero + RPC del día.
  static Map<String, double> mergeSaldoMonederoRpc(
    Map<String, dynamic>? monedero,
    Map<String, dynamic>? rpc, {
    double precioReferencia = 1500,
  }) {
    var litros = 0.0;
    if (monedero != null) {
      litros = toDouble(monedero['saldo_litros']);
    }
    if (litros == 0 && rpc != null) {
      litros = toDouble(rpc['out_saldo_litros']);
    }

    var pesos = 0.0;
    if (monedero != null) {
      pesos = toDouble(
        monedero['saldo_pesos'] ??
            monedero['saldo_en_pesos'] ??
            monedero['pesos_saldo'],
      );
    }
    if (pesos == 0 && rpc != null) {
      pesos = toDouble(rpc['out_saldo_pesos']);
    }

    var precio = toDouble(rpc?['out_precio_litro']);
    if (precio == 0) precio = precioReferencia;
    if (pesos == 0 && litros > 0 && precio > 0) {
      pesos = litros * precio;
    }

    double kmRest = 0;
    if (rpc != null && rpc['out_km_restantes'] != null) {
      kmRest = toDouble(rpc['out_km_restantes']);
    } else if (pesos > 0) {
      kmRest = pesos / precio * 13;
    }

    return {
      'pesos': pesos,
      'litros': litros,
      'km_restantes': kmRest,
      'precio_litro': precio,
    };
  }

  /// Visitas del día según columnas habituales en `combustible_diario_tecnico`.
  static int intVisitasDia(Map<String, dynamic> row) {
    const keys = [
      'cant_ots',
      'cantidad_visitas',
      'visitas',
      'cant_visitas',
      'num_visitas',
      'out_cant_visitas',
      'total_visitas',
      'visitas_del_dia',
      'n_visitas',
      'visitas_count',
      'cant_visitas_dia',
      'visitas_ot',
      'qty_visitas',
    ];
    for (final k in keys) {
      if (row.containsKey(k) && row[k] != null) {
        return toInt(row[k]);
      }
    }
    return 0;
  }

  static String formatKm(double km) => km.toStringAsFixed(2);

  static String formatLitros(double l) => l.toStringAsFixed(3);
}
