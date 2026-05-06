// Entry point de demo para visualizar la pantalla del Mapa de Calor sin
// arrancar todos los servicios nativos del app real (Firebase, Hive, audio,
// etc.). Útil para `flutter run -d chrome -t lib/main_demo.dart`.

import 'package:flutter/material.dart';

import 'package:agente_desconexiones/constants/app_colors.dart';
import 'package:agente_desconexiones/screens/mapa_calor_screen.dart';

void main() {
  runApp(const MapaCalorDemoApp());
}

class MapaCalorDemoApp extends StatelessWidget {
  const MapaCalorDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CREABOX — Mapa de Calor (demo)',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MapaCalorScreen(),
    );
  }
}
