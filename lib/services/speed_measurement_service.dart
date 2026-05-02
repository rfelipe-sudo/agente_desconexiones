// ============================================================================
// SPEED TEST COMPLETO - DESCARGA + SUBIDA
// ============================================================================
// Usa http package (funciona en Flutter)
// Múltiples conexiones paralelas
// Gauge suave sin caídas
// ============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:http/http.dart' as http;

// ============================================================================
// SERVICIO DE SPEED TEST
// ============================================================================

class SpeedTestService {
  static const String _downloadUrl = 'https://speed.cloudflare.com/__down';
  static const String _uploadUrl = 'https://speed.cloudflare.com/__up';
  
  static const int _connections = 4;
  static const int _testDurationMs = 3000;
  static const int _rounds = 4;
  
  bool _running = false;
  double _lastSpeed = 0;
  
  // Datos para upload
  late Uint8List _uploadData;
  
  SpeedTestService() {
    try {
      final random = math.Random();
      _uploadData = Uint8List.fromList(
        List.generate(512 * 1024, (_) => random.nextInt(256)), // 512KB
      );
    } catch (e) {
      // Fallback si hay error generando datos
      _uploadData = Uint8List(512 * 1024);
    }
  }

  /// Test de DESCARGA con conexiones paralelas
  Future<double> runDownloadTest({
    required Function(double speed) onSpeedUpdate,
    required Function(String status) onStatus,
  }) async {
    _running = true;
    _lastSpeed = 0;
    
    double bestSpeed = 0;
    
    for (int round = 1; round <= _rounds && _running; round++) {
      onStatus('Descarga $round/$_rounds');
      
      final speed = await _measureDownload(onSpeedUpdate);
      
      if (speed > bestSpeed) {
        bestSpeed = speed;
      }
    }
    
    _running = false;
    return bestSpeed;
  }

  /// Test de SUBIDA con conexiones paralelas
  Future<double> runUploadTest({
    required Function(double speed) onSpeedUpdate,
    required Function(String status) onStatus,
  }) async {
    _running = true;
    _lastSpeed = 0;
    
    double bestSpeed = 0;
    
    for (int round = 1; round <= _rounds && _running; round++) {
      onStatus('Subida $round/$_rounds');
      
      final speed = await _measureUpload(onSpeedUpdate);
      
      if (speed > bestSpeed) {
        bestSpeed = speed;
      }
    }
    
    _running = false;
    return bestSpeed;
  }

  Future<double> _measureDownload(Function(double) onSpeedUpdate) async {
    final bytes = List<int>.filled(_connections, 0);
    final sw = Stopwatch()..start();
    final clients = <http.Client>[];
    
    // Lanzar conexiones paralelas
    for (int i = 0; i < _connections; i++) {
      final client = http.Client();
      clients.add(client);
      _downloadStream(client, i, bytes, sw);
    }
    
    double maxSpeed = 0;
    
    // Monitorear progreso
    while (sw.elapsedMilliseconds < _testDurationMs && _running) {
      await Future.delayed(const Duration(milliseconds: 100));
      
      final total = bytes.reduce((a, b) => a + b);
      final elapsed = sw.elapsedMilliseconds / 1000;
      
      if (elapsed > 0.2) {
        final currentSpeed = (total * 8) / (elapsed * 1000000);
        
        // Suavizar - subir rápido, bajar lento
        if (currentSpeed >= _lastSpeed * 0.9 || currentSpeed > _lastSpeed) {
          _lastSpeed = _lastSpeed <= 0
              ? currentSpeed
              : _lastSpeed + (currentSpeed - _lastSpeed) * 0.5;
          onSpeedUpdate(_lastSpeed);
        }
        
        if (currentSpeed > maxSpeed) {
          maxSpeed = currentSpeed;
        }
      }
    }
    
    sw.stop();
    
    // Cerrar clientes
    for (final c in clients) {
      c.close();
    }
    
    return maxSpeed;
  }

  Future<void> _downloadStream(
    http.Client client,
    int index,
    List<int> bytes,
    Stopwatch sw,
  ) async {
    try {
      final url = Uri.parse(
        '$_downloadUrl?bytes=26214400&r=${DateTime.now().millisecondsSinceEpoch}_$index'
      );
      
      final request = http.Request('GET', url);
      request.headers['Cache-Control'] = 'no-cache';
      
      final response = await client.send(request).timeout(
        const Duration(seconds: 15),
      );
      
      if (response.statusCode != 200) {
        return;
      }
      
      await for (final chunk in response.stream) {
        if (sw.elapsedMilliseconds >= _testDurationMs || !_running) break;
        bytes[index] += chunk.length;
      }
    } catch (e) {
      // Ignorar errores de conexión
      print('Error en descarga $index: $e');
    }
  }

  Future<double> _measureUpload(Function(double) onSpeedUpdate) async {
    final bytes = List<int>.filled(_connections, 0);
    final sw = Stopwatch()..start();
    final clients = <http.Client>[];
    
    // Lanzar conexiones paralelas
    for (int i = 0; i < _connections; i++) {
      final client = http.Client();
      clients.add(client);
      _uploadStream(client, i, bytes, sw);
    }
    
    double maxSpeed = 0;
    
    // Monitorear progreso
    while (sw.elapsedMilliseconds < _testDurationMs && _running) {
      await Future.delayed(const Duration(milliseconds: 100));
      
      final total = bytes.reduce((a, b) => a + b);
      final elapsed = sw.elapsedMilliseconds / 1000;
      
      if (elapsed > 0.2) {
        final currentSpeed = (total * 8) / (elapsed * 1000000);
        
        if (currentSpeed >= _lastSpeed * 0.9 || currentSpeed > _lastSpeed) {
          _lastSpeed = _lastSpeed <= 0
              ? currentSpeed
              : _lastSpeed + (currentSpeed - _lastSpeed) * 0.5;
          onSpeedUpdate(_lastSpeed);
        }
        
        if (currentSpeed > maxSpeed) {
          maxSpeed = currentSpeed;
        }
      }
    }
    
    sw.stop();
    
    for (final c in clients) {
      c.close();
    }
    
    return maxSpeed;
  }

  Future<void> _uploadStream(
    http.Client client,
    int index,
    List<int> bytes,
    Stopwatch sw,
  ) async {
    try {
      // Hacer múltiples POSTs pequeños para medir velocidad
      while (sw.elapsedMilliseconds < _testDurationMs && _running) {
        final url = Uri.parse(
          '$_uploadUrl?r=${DateTime.now().millisecondsSinceEpoch}_$index'
        );
        
        try {
          final response = await client.post(
            url,
            headers: {'Content-Type': 'application/octet-stream'},
            body: _uploadData,
          ).timeout(const Duration(seconds: 10));
          
          if (response.statusCode == 200) {
            bytes[index] += _uploadData.length;
          }
        } catch (e) {
          // Si falla un POST, continuar con el siguiente
          if (sw.elapsedMilliseconds >= _testDurationMs || !_running) break;
        }
      }
    } catch (e) {
      // Ignorar errores de conexión
      print('Error en subida $index: $e');
    }
  }

  void stop() {
    _running = false;
  }
}
