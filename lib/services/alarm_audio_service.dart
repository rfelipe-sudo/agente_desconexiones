import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/services.dart';

/// Servicio para reproducir sonido de alarma en loop
class AlarmAudioService {
  static final AlarmAudioService _instance = AlarmAudioService._internal();
  factory AlarmAudioService() => _instance;
  AlarmAudioService._internal();

  AudioPlayer? _player;
  Timer? _systemSoundTimer;
  Timer? _vibrationTimer;
  bool _isPlaying = false;
  String? _currentAlertaId;

  /// Inicia la reproducción del sonido de alarma en loop
  Future<void> iniciarAlarma(String alertaId) async {
    // Si ya está reproduciendo la misma alerta, no hacer nada
    if (_isPlaying && _currentAlertaId == alertaId) {
      print('🔊 Alarma ya está reproduciéndose para alerta $alertaId');
      return;
    }

    // Detener alarma anterior si existe
    await detenerAlarma();

    _currentAlertaId = alertaId;
    
    try {
      print('🔊 Iniciando alarma en loop para alerta $alertaId...');
      
      _player = AudioPlayer();
      
      // Intentar cargar archivo de audio personalizado
      try {
        await _player!.setAsset('assets/sounds/alerta_urgente.mp3');
        await _player!.setLoopMode(LoopMode.one);
        await _player!.setVolume(1.0);
        await _player!.play();
        _isPlaying = true;
        print('✅ Alarma iniciada con archivo personalizado en loop');
        return;
      } catch (e) {
        print('⚠️ Archivo personalizado no encontrado, usando sonido del sistema: $e');
        await _player!.dispose();
        _player = null;
      }
      
      // Si no hay archivo personalizado, usar sonido del sistema en loop
      _iniciarSystemSoundLoop();
      
    } catch (e) {
      print('❌ Error iniciando alarma: $e');
      // Fallback: usar sonido del sistema
      _iniciarSystemSoundLoop();
    }
    
    // Iniciar vibración en loop (funciona incluso en silencio)
    _iniciarVibracionLoop();
  }

  /// Inicia un loop del sonido del sistema
  void _iniciarSystemSoundLoop() {
    print('🔊 Iniciando loop de sonido del sistema...');
    
    // Reproducir inmediatamente
    SystemSound.play(SystemSoundType.alert);
    
    // Repetir cada 2 segundos (duración aproximada del sonido de alerta)
    _systemSoundTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_isPlaying) {
        SystemSound.play(SystemSoundType.alert);
      } else {
        timer.cancel();
      }
    });
    
    _isPlaying = true;
    print('✅ Loop de sonido del sistema iniciado');
  }

  /// Inicia vibración en loop (funciona incluso en modo silencio)
  void _iniciarVibracionLoop() {
    print('📳 Iniciando vibración en loop...');
    
    // Vibración inicial usando HapticFeedback
    HapticFeedback.mediumImpact();
    
    // Repetir cada 2 segundos (mismo intervalo que el sonido)
    _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_isPlaying) {
        HapticFeedback.mediumImpact();
      } else {
        timer.cancel();
      }
    });
    
    print('✅ Vibración en loop iniciada');
  }

  /// Detiene la reproducción del sonido de alarma
  Future<void> detenerAlarma() async {
    print('🔇 detenerAlarma() llamado - _isPlaying: $_isPlaying');
    
    // Detener siempre, incluso si _isPlaying es false (por seguridad)
    try {
      print('🔇 Deteniendo alarma...');
      
      // Detener player si existe
      if (_player != null) {
        try {
          await _player!.stop();
        } catch (e) {
          print('⚠️ Error deteniendo player: $e');
        }
        try {
          await _player!.dispose();
        } catch (e) {
          print('⚠️ Error disposeando player: $e');
        }
        _player = null;
      }
      
      // Detener timer de system sound si existe
      _systemSoundTimer?.cancel();
      _systemSoundTimer = null;
      
      // Detener vibración
      _vibrationTimer?.cancel();
      _vibrationTimer = null;
      
      _isPlaying = false;
      _currentAlertaId = null;
      print('✅ Alarma detenida completamente');
    } catch (e) {
      print('❌ Error deteniendo alarma: $e');
      // Forzar limpieza incluso si hay error
      _player = null;
      _systemSoundTimer?.cancel();
      _systemSoundTimer = null;
      _vibrationTimer?.cancel();
      _vibrationTimer = null;
      _isPlaying = false;
      _currentAlertaId = null;
    }
  }

  /// Verifica si la alarma está reproduciéndose
  bool get estaReproduciendo => _isPlaying;

  /// Obtiene el ID de la alerta actual
  String? get alertaActual => _currentAlertaId;

  /// Detiene la alarma para una alerta específica
  /// Si alertaId es null, detiene cualquier alarma activa
  /// Si alertaId no es null, SIEMPRE detiene la alarma (por seguridad)
  Future<void> detenerAlarmaParaAlerta(String? alertaId) async {
    print('🔇 detenerAlarmaParaAlerta llamado con ID: $alertaId, alarma actual: $_currentAlertaId, está reproduciendo: $_isPlaying');
    
    // Si no hay ID específico o coincide con la alarma actual, detener
    if (alertaId == null || _currentAlertaId == alertaId || _isPlaying) {
      print('🔇 Deteniendo alarma...');
      await detenerAlarma();
    } else {
      // Si el ID no coincide pero hay una alarma reproduciéndose, detener de todas formas
      // (puede ser que el ID haya cambiado o haya un problema de sincronización)
      if (_isPlaying) {
        print('⚠️ ID no coincide pero hay alarma activa, deteniendo de todas formas');
        await detenerAlarma();
      }
    }
  }
}

