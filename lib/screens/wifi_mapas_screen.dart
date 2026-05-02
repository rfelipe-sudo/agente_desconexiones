import 'package:flutter/material.dart';

/// Pantalla WiFi y mapas: acceso a credenciales y cobertura.
class WifiMapasScreen extends StatelessWidget {
  const WifiMapasScreen({super.key});

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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
