import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agente_desconexiones/services/wifi_demo_report_service.dart';

/// Pantalla WiFi y mapas: acceso a credenciales y cobertura.
class WifiMapasScreen extends StatelessWidget {
  const WifiMapasScreen({super.key});

  Future<void> _generarDemo(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final nombre = prefs.getString('nombre_tecnico') ??
        prefs.getString('user_nombre');
    final rut = prefs.getString('rut_tecnico') ?? prefs.getString('user_rut');

    final html = WifiDemoReportService.buildHtml(
      tecnicoNombre: nombre,
      tecnicoRut: rut,
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Reporte demo — datos ficticios para presentación',
        ),
        duration: Duration(seconds: 3),
      ),
    );
    Navigator.of(context).pushNamed('/certificado-wifi', arguments: html);
  }

  Widget _buildLargeActionCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 140, maxHeight: 180),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: Colors.white),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: AppBar(
        title: const Text('WiFi & Mapas'),
        backgroundColor: const Color(0xFF0D1B2A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLargeActionCard(
                    context: context,
                    icon: Icons.wifi_password,
                    label: 'Cambiar\nCredenciales',
                    color: const Color(0xFF00D9FF),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00D9FF), Color(0xFF0099CC)],
                    ),
                    onTap: () {
                      Navigator.of(context).pushNamed('/wifi-credenciales');
                    },
                  ),
                  const SizedBox(height: 20),
                  _buildLargeActionCard(
                    context: context,
                    icon: Icons.radar,
                    label: 'Cobertura\nWiFi',
                    color: const Color(0xFFFF6B35),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B35), Color(0xFFE65100)],
                    ),
                    onTap: () {
                      Navigator.of(context).pushNamed('/wifi-cobertura');
                    },
                  ),
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    onPressed: () => _generarDemo(context),
                    icon: const Icon(Icons.slideshow_outlined, size: 20),
                    label: const Text('Generar reporte demo'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00D9FF),
                      side: const BorderSide(color: Color(0xFF00D9FF)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Certificado demo con extensor cableado recomendado a 9 m por debilitamiento de señal.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF8FA8C8), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
