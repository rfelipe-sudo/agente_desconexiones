import 'package:flutter/material.dart';
import 'package:agente_desconexiones/constants/app_colors.dart';
import 'package:tester_red_shared/tester_red_shared.dart';

/// Pantalla de Mapa de Calor - Tester de Red v2
/// Integra el flujo completo del tester de red v2 desde el paquete compartido
class MapaCalorScreen extends StatelessWidget {
  const MapaCalorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Iniciar el flujo completo del tester de red
    // Comienza con la selección de ONT (Askey o Huawei)
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ONTSelectionScreen(),
    );
  }
}
