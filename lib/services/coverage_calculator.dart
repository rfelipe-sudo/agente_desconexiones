import 'dart:math' as math;

import 'package:agente_desconexiones/services/ont_wifi_service.dart';
import 'package:agente_desconexiones/services/wifi_neighbor_service.dart';

/// Cálculo de radios, score y recomendaciones de cobertura.
class CoverageCalculator {
  CoverageCalculator._();

  static const Map<String, double> factorMaterial = {
    'Madera': 2.0,
    'Albañilería': 2.4,
    'Hormigón': 2.7,
  };

  static const Map<String, Map<String, List<double>>> radiosBase = {
    'Madera': {
      '5 GHz': [8.0, 18.0],
      '2.4 GHz': [12.0, 25.0],
    },
    'Albañilería': {
      '5 GHz': [6.0, 14.0],
      '2.4 GHz': [10.0, 20.0],
    },
    'Hormigón': {
      '5 GHz': [6.0, 10.0],
      '2.4 GHz': [8.0, 15.0],
    },
  };

  static double factorRuido(int vecinos) {
    return math.max(0.6, 1.0 - (vecinos * 0.02));
  }

  static List<double> radiosEfectivos(
    String banda,
    String construccion,
    int vecinosEnBanda,
  ) {
    final base = radiosBase[construccion]![banda]!;
    final factor = factorRuido(vecinosEnBanda);
    return [base[0] * factor, base[1] * factor];
  }

  static int calcularScore({
    required List<OntDevice> devices,
    required List<WifiNeighbor> neighbors,
    required String construccion,
  }) {
    final wifiDevices = devices.where((d) => !d.esCableado).toList();
    if (wifiDevices.isEmpty) return 50;

    final avgRssi = wifiDevices.map((d) => d.rssi).reduce((a, b) => a + b) /
        wifiDevices.length;
    final int ptsSenal = avgRssi >= -60
        ? 40
        : avgRssi >= -70
            ? 30
            : avgRssi >= -75
                ? 20
                : 10;

    final tieneExtCableado =
        devices.any((d) => d.esCableado && d.esExtensor);
    final int ptsExtensor = tieneExtCableado ? 20 : 0;

    final totalVecinos = neighbors.length;
    final int ptsRF = totalVecinos < 5
        ? 20
        : totalVecinos < 10
            ? 15
            : totalVecinos < 15
                ? 10
                : 5;

    final int ptsConstruccion = construccion == 'Madera'
        ? 20
        : construccion == 'Albañilería'
            ? 15
            : 10;

    final decoEn24 = devices.where(
      (d) => d.esDecodificador && !d.es5GHz && !d.esCableado,
    );
    final int penalizacion = decoEn24.isNotEmpty ? 15 : 0;

    return math.min(
      100,
      math.max(
        0,
        ptsSenal + ptsExtensor + ptsRF + ptsConstruccion - penalizacion,
      ),
    );
  }

  static String veredicto(int score, bool tieneDecoEn24g) {
    if (tieneDecoEn24g) return 'Certificación Condicional';
    if (score >= 90) return 'Instalación Excelente';
    if (score >= 75) return 'Instalación Aprobada';
    if (score >= 60) return 'Aprobada con Observaciones';
    return 'Requiere Intervención';
  }

  static String recomendacionExtensor(
    List<OntDevice> devices,
    String construccion,
    List<WifiNeighbor> neighbors,
  ) {
    final n = factorMaterial[construccion] ?? 2.4;
    final vecinos5g = neighbors.where((w) => w.es5GHz).length;
    final radios = radiosEfectivos('5 GHz', construccion, vecinos5g);
    final radioExcelente = radios[0];
    final radioBuena = radios[1];

    final dispositivosCriticos = devices
        .where(
          (d) =>
              !d.esCableado && d.distanciaMetros(n) > radioBuena,
        )
        .toList();

    if (dispositivosCriticos.isEmpty) return '';

    final dist = radioExcelente.toStringAsFixed(0);
    final mejora = dispositivosCriticos.first;
    return 'Se recomienda instalar extensor a ${dist}m del router. '
        '${mejora.name} está recibiendo ${mejora.rssi} dBm — '
        'un extensor a ${dist}m mejoraría su señal a ~-55 dBm.';
  }
}
