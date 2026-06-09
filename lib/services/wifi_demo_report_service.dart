import 'package:agente_desconexiones/services/cert_builder.dart';
import 'package:agente_desconexiones/services/coverage_calculator.dart';
import 'package:agente_desconexiones/services/ont_wifi_service.dart';
import 'package:agente_desconexiones/services/wifi_neighbor_service.dart';

/// Datos ficticios para demostraciones / presentaciones comerciales.
class WifiDemoReportService {
  WifiDemoReportService._();

  static const demoDistanciaExtensorM = 9;

  static const demoRecomendacionExtensor =
      'Se recomienda instalar extensor cableado a 9 m del router por debilitamiento '
      'de señal. Smart-TV-Dormitorio recibe −79 dBm — un extensor con backhaul '
      'Ethernet a ~9 m mejoraría la cobertura del cuarto a ~−55 dBm.';

  /// Genera el HTML del certificado WiFi con datos de ejemplo (sin ONT real).
  static String buildHtml({
    String? tecnicoNombre,
    String? tecnicoRut,
  }) {
    const ontMac = '48:46:FB:A1:B2:C3';
    const construccion = 'Albañilería';

    final devices = <OntDevice>[
      const OntDevice(
        name: 'iPhone-Cliente',
        mac: 'A4:83:E7:12:34:56',
        ip: '192.168.1.23',
        port: 'SSID5',
        rssi: -58,
        band: '5G',
        wirelessMode: '802.11ax',
      ),
      const OntDevice(
        name: 'Smart-TV-Living',
        mac: 'F0:72:EA:98:76:54',
        ip: '192.168.1.45',
        port: 'SSID5',
        rssi: -64,
        band: '5G',
        wirelessMode: '802.11ac',
      ),
      const OntDevice(
        name: 'Notebook-HP',
        mac: '3C:52:82:11:22:33',
        ip: '192.168.1.88',
        port: 'SSID1',
        rssi: -68,
        band: '2.4G',
        wirelessMode: '802.11n',
      ),
      const OntDevice(
        name: 'Smart-TV-Dormitorio',
        mac: 'B8:27:EB:44:55:66',
        ip: '192.168.1.112',
        port: 'SSID5',
        rssi: -79,
        band: '5G',
        wirelessMode: '802.11ac',
      ),
    ];

    final localNeighbours = <WifiNeighbor>[
      const WifiNeighbor(ssid: 'Vecino_5G', bssid: '11:22:33:44:55:01', rssi: -72, frequency: 5180),
      const WifiNeighbor(ssid: 'Movistar_2.4', bssid: '11:22:33:44:55:02', rssi: -68, frequency: 2437),
      const WifiNeighbor(ssid: 'WOM_WiFi', bssid: '11:22:33:44:55:03', rssi: -75, frequency: 2462),
      const WifiNeighbor(ssid: 'Entel_5G', bssid: '11:22:33:44:55:04', rssi: -80, frequency: 5240),
      const WifiNeighbor(ssid: 'Fibra_24', bssid: '11:22:33:44:55:05', rssi: -70, frequency: 2412),
      const WifiNeighbor(ssid: 'CasaSur', bssid: '11:22:33:44:55:06', rssi: -77, frequency: 5180),
      const WifiNeighbor(ssid: 'RedOculta', bssid: '11:22:33:44:55:07', rssi: -82, frequency: 2437),
      const WifiNeighbor(ssid: 'Starlink_5', bssid: '11:22:33:44:55:08', rssi: -85, frequency: 5745),
    ];

    final ontNeighbours = <OntNeighbour>[
      const OntNeighbour(ssid: 'Vecino_5G', bssid: '11:22:33:44:55:01', channel: 36, rssiDbm: -72, band: '5G'),
      const OntNeighbour(ssid: 'Movistar_2.4', bssid: '11:22:33:44:55:02', channel: 6, rssiDbm: -68, band: '2.4G'),
      const OntNeighbour(ssid: 'WOM_WiFi', bssid: '11:22:33:44:55:03', channel: 11, rssiDbm: -75, band: '2.4G'),
    ];

    final score = CoverageCalculator.calcularScore(
      devices: devices,
      neighbors: localNeighbours,
      construccion: construccion,
    );

    return buildCertificadoHtml(CertContext(
      devices: devices,
      ontNeighbours: ontNeighbours,
      localNeighbours: localNeighbours,
      score: score,
      veredicto: CoverageCalculator.veredicto(score, false),
      tipoPropiedad: 'depto',
      tamano: 'med',
      construccion: construccion,
      ordenTrabajo: '1-284739102856',
      tipoOrden: 'Alta 2 Play',
      ontModelo: 'HG8145X6 WiFi 6',
      ontSerial: '48575443DEMO2026',
      ontMac: ontMac,
      tecnicoNombre: tecnicoNombre ?? 'Técnico CREABOX (demo)',
      tecnicoRut: tecnicoRut ?? '12.345.678-9',
      fechaIso: DateTime.now().toIso8601String(),
      recomendacionExtensor: demoRecomendacionExtensor,
    ));
  }
}
