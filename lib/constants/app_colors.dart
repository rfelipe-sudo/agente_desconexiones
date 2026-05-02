import 'package:flutter/material.dart';

/// Paleta de colores de la aplicación
/// Tema oscuro profesional con acentos de alerta
class AppColors {
  AppColors._();

  // Colores primarios
  static const Color primary = Color(0xFF1E88E5);       // Azul corporativo
  static const Color primaryDark = Color(0xFF1565C0);
  static const Color primaryLight = Color(0xFF42A5F5);
  
  // Colores de fondo
  static const Color background = Color(0xFF0D1117);     // Fondo oscuro
  static const Color surface = Color(0xFF161B22);        // Superficie elevada
  static const Color surfaceLight = Color(0xFF21262D);   // Tarjetas
  static const Color surfaceBorder = Color(0xFF30363D);  // Bordes
  
  // Colores de texto
  static const Color textPrimary = Color(0xFFF0F6FC);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF6E7681);
  
  // Colores de estado - Alertas
  static const Color alertUrgent = Color(0xFFFF6B6B);    // Rojo urgente
  static const Color alertWarning = Color(0xFFFFB347);   // Naranja advertencia
  static const Color alertInfo = Color(0xFF4DABF7);      // Azul información
  static const Color alertSuccess = Color(0xFF51CF66);   // Verde éxito
  
  // Colores de acción
  static const Color atender = Color(0xFF40C057);        // Verde para atender
  static const Color postergar = Color(0xFFFFA94D);      // Naranja para postergar
  static const Color escalar = Color(0xFFFA5252);        // Rojo para escalar
  
  // Colores del agente CREA
  static const Color creaVoice = Color(0xFF7C4DFF);      // Púrpura para voz
  static const Color creaListening = Color(0xFF00E676);  // Verde escuchando
  static const Color creaSpeaking = Color(0xFF448AFF);   // Azul hablando
  
  // Gradientes
  static const LinearGradient alertGradient = LinearGradient(
    colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient creaGradient = LinearGradient(
    colors: [Color(0xFF7C4DFF), Color(0xFF448AFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF40C057), Color(0xFF51CF66)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Tema de la aplicación
class AppTheme {
  AppTheme._();
  
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.creaVoice,
        surface: AppColors.surface,
        error: AppColors.alertUrgent,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.surfaceBorder),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textMuted),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
        headlineMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        labelLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

