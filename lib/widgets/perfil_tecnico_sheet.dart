import 'package:flutter/material.dart';

import 'package:agente_desconexiones/config/constants.dart';
import 'package:agente_desconexiones/services/app_version_service.dart';
import 'package:agente_desconexiones/constants/app_colors.dart';
import 'package:agente_desconexiones/models/usuario.dart';

/// Panel inferior al tocar el avatar del técnico en CREABOX.
class PerfilTecnicoSheet {
  static Future<void> mostrar(
    BuildContext context, {
    required Usuario usuario,
    String rut = '',
    String tipo = '',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0D1B2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A3F5F),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: AppColors.creaGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    usuario.esTecnico
                        ? Icons.engineering
                        : Icons.supervisor_account,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  usuario.nombre,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    usuario.rol.displayName,
                    if (rut.isNotEmpty) rut,
                    if (tipo.isNotEmpty) tipo,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8FA8C8),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131F33),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2A3F5F)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFF00D9FF), size: 18),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CREABOX ${AppVersionService.versionLabel}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            kBuildDistintivo,
                            style: const TextStyle(
                              color: Color(0xFF86EFAC),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
