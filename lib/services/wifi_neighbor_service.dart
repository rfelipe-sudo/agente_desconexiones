import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

/// Vecino WiFi escaneado (redes ajenas).
class WifiNeighbor {
  const WifiNeighbor({
    required this.ssid,
    required this.bssid,
    required this.rssi,
    required this.frequency,
  });

  final String ssid;
  final String bssid;
  final int rssi;
  final int frequency;

  String get banda => frequency > 3000 ? '5 GHz' : '2.4 GHz';

  bool get es5GHz => frequency > 3000;
}

/// Escaneo de redes WiFi con [wifi_scan].
class WifiNeighborService {
  Future<List<WifiNeighbor>> scan() async {
    final loc = await Permission.location.request();
    if (!loc.isGranted) {
      final locWhen = await Permission.locationWhenInUse.request();
      if (!locWhen.isGranted) return [];
    }

    try {
      final can = await WiFiScan.instance.canStartScan();
      if (can != CanStartScan.yes) return [];

      final started = await WiFiScan.instance.startScan();
      if (!started) return [];

      await Future<void>.delayed(const Duration(milliseconds: 600));

      final canGet = await WiFiScan.instance.canGetScannedResults();
      if (canGet != CanGetScannedResults.yes) return [];

      final results = await WiFiScan.instance.getScannedResults();
      final list = results
          .map(
            (ap) => WifiNeighbor(
              ssid: ap.ssid,
              bssid: ap.bssid,
              rssi: ap.level,
              frequency: ap.frequency,
            ),
          )
          .toList();

      list.sort((a, b) => b.rssi.compareTo(a.rssi));
      return list;
    } catch (_) {
      return [];
    }
  }

  int interferencia2g(List<WifiNeighbor> neighbors) {
    return neighbors.where((n) => !n.es5GHz && n.rssi > -75).length;
  }

  int interferencia5g(List<WifiNeighbor> neighbors) {
    return neighbors.where((n) => n.es5GHz && n.rssi > -75).length;
  }
}
