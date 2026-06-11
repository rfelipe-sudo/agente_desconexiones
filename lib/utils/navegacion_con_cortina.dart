import 'package:flutter/material.dart';

import 'package:agente_desconexiones/widgets/cortina_carga_card.dart';

/// Navegación desde Home con cortina de carga hasta que la pantalla esté lista.
class NavegacionConCortina {
  NavegacionConCortina._();

  static Future<T?> push<T>(
    BuildContext context, {
    required Color accentColor,
    required String titulo,
    String? subtitulo,
    required Widget destination,
    Future<void> Function()? hastaListo,
  }) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute<T>(
        builder: (_) => PantallaConCortina(
          accentColor: accentColor,
          titulo: titulo,
          subtitulo: subtitulo,
          destination: destination,
          hastaListo: hastaListo,
        ),
      ),
    );
  }
}
