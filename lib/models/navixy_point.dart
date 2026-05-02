import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Punto devuelto por Navixy `POST /track/read` (`get_time`, `lat`, `lng`, …).
class NavixyPoint {
  const NavixyPoint({
    required this.lat,
    required this.lng,
    required this.getTime,
    this.speed = 0,
    this.mileage = 0,
    this.time,
  });

  final double lat;
  final double lng;
  final String getTime;
  final double speed;
  final double mileage;
  final DateTime? time;

  LatLng get latLng => LatLng(lat, lng);

  factory NavixyPoint.fromJson(Map<String, dynamic> json) {
    double g(String a, String b) {
      final x = json[a] ?? json[b];
      if (x is num) return x.toDouble();
      return double.tryParse(x?.toString() ?? '') ?? 0;
    }

    final rawTime = json['get_time'] ?? json['getTime'] ?? json['time'];
    String getTimeStr = '';
    DateTime? t;
    if (rawTime is String) {
      getTimeStr = rawTime;
      t = DateTime.tryParse(rawTime.replaceFirst(' ', 'T'));
    } else if (rawTime is int) {
      getTimeStr = rawTime.toString();
      t = DateTime.fromMillisecondsSinceEpoch(
        rawTime > 20000000000 ? rawTime : rawTime * 1000,
      );
    }

    return NavixyPoint(
      lat: g('lat', 'y'),
      lng: g('lng', 'x'),
      getTime: getTimeStr,
      speed: (json['speed'] as num?)?.toDouble() ?? g('speed', 's'),
      mileage: (json['mileage'] as num?)?.toDouble() ?? g('mileage', 'm'),
      time: t,
    );
  }
}
