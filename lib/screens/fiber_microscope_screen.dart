// ============================================================================
// MÓDULO MICROSCOPIO - INSPECCIÓN DE FIBRA CON GEORREFERENCIA
// ============================================================================
// - Cámara con zoom máximo y filtros
// - Guardado con GPS (latitud, longitud)
// - Historial de inspecciones
// - Exportar reporte
// ============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// MODELO DE INSPECCIÓN
// ============================================================================

class FiberInspection {
  final String id;
  final String imagePath;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final String address;
  final String notes;
  final String result; // 'ok', 'warning', 'bad'

  FiberInspection({
    required this.id,
    required this.imagePath,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.address,
    this.notes = '',
    this.result = 'pending',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'imagePath': imagePath,
    'timestamp': timestamp.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'address': address,
    'notes': notes,
    'result': result,
  };

  factory FiberInspection.fromJson(Map<String, dynamic> json) => FiberInspection(
    id: json['id'],
    imagePath: json['imagePath'],
    timestamp: DateTime.parse(json['timestamp']),
    latitude: json['latitude'],
    longitude: json['longitude'],
    address: json['address'],
    notes: json['notes'] ?? '',
    result: json['result'] ?? 'pending',
  );

  String get formattedDate {
    return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')}/${timestamp.year} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  String get coordinates => '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
}

// ============================================================================
// SERVICIO DE INSPECCIONES
// ============================================================================

class InspectionService {
  static const String _storageKey = 'fiber_inspections';

  static Future<List<FiberInspection>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_storageKey);
    if (data == null) return [];
    
    final List<dynamic> list = jsonDecode(data);
    return list.map((e) => FiberInspection.fromJson(e)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  static Future<void> save(FiberInspection inspection) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getAll();
    list.add(inspection);
    
    final data = jsonEncode(list.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }

  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getAll();
    list.removeWhere((e) => e.id == id);
    
    final data = jsonEncode(list.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }

  static Future<void> update(FiberInspection inspection) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getAll();
    final index = list.indexWhere((e) => e.id == inspection.id);
    if (index >= 0) {
      list[index] = inspection;
      final data = jsonEncode(list.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, data);
    }
  }
}

// ============================================================================
// PANTALLA PRINCIPAL DEL MICROSCOPIO
// ============================================================================

class FiberMicroscopeScreen extends StatefulWidget {
  const FiberMicroscopeScreen({Key? key}) : super(key: key);

  @override
  State<FiberMicroscopeScreen> createState() => _FiberMicroscopeScreenState();
}

class _FiberMicroscopeScreenState extends State<FiberMicroscopeScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _flashOn = true;
  double _zoomLevel = 1.0;
  double _maxZoom = 1.0;
  double _minZoom = 1.0;
  
  // Filtros
  int _filterIndex = 0;
  final List<String> _filterNames = [
    'Normal',
    'Alto Contraste',
    'Bordes',
    'Invertido',
    'B/N Contraste',
  ];
  
  // GPS
  Position? _currentPosition;
  String _currentAddress = 'Obteniendo ubicación...';
  bool _gettingLocation = false;
  
  // Captura
  File? _capturedImage;
  bool _showCapture = false;
  bool _saving = false;
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initCamera();
    _getLocation();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        _showError('Se requiere permiso de cámara');
      }
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          _showError('No se encontró cámara');
        }
        return;
      }

      _controller = CameraController(
        _cameras.first,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      
      _maxZoom = await _controller!.getMaxZoomLevel();
      _minZoom = await _controller!.getMinZoomLevel();
      
      _zoomLevel = _minZoom + (_maxZoom - _minZoom) * 0.5;
      await _controller!.setZoomLevel(_zoomLevel);
      
      await _controller!.setFlashMode(FlashMode.torch);
      _flashOn = true;
      
      await _controller!.setFocusMode(FocusMode.auto);

      if (mounted) {
        setState(() => _isInitialized = true);
      }
      
    } catch (e) {
      if (mounted) {
        _showError('Error cámara: $e');
      }
    }
  }

  Future<void> _getLocation() async {
    if (!mounted) return;
    setState(() => _gettingLocation = true);
    
    try {
      // Verificar permisos
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _currentAddress = 'Permiso GPS denegado';
              _gettingLocation = false;
            });
          }
          return;
        }
      }

      // Verificar si GPS está activo
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _currentAddress = 'GPS desactivado';
            _gettingLocation = false;
          });
        }
        return;
      }

      // Obtener posición
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // Obtener dirección
      try {
        final placemarks = await placemarkFromCoordinates(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
        
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          if (mounted) {
            setState(() {
              _currentAddress = [
                p.street,
                p.locality,
                p.administrativeArea,
              ].where((e) => e != null && e.isNotEmpty).join(', ');
            });
          }
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _currentAddress = '${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}';
          });
        }
      }
      
    } catch (e) {
      if (mounted) {
        setState(() => _currentAddress = 'Error GPS: $e');
      }
    }
    
    if (mounted) {
      setState(() => _gettingLocation = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    
    try {
      if (_flashOn) {
        await _controller!.setFlashMode(FlashMode.off);
      } else {
        await _controller!.setFlashMode(FlashMode.torch);
      }
      if (mounted) {
        setState(() => _flashOn = !_flashOn);
      }
    } catch (e) {}
  }

  Future<void> _setZoom(double value) async {
    if (_controller == null) return;
    await _controller!.setZoomLevel(value);
    if (mounted) {
      setState(() => _zoomLevel = value);
    }
  }

  void _changeFilter() {
    setState(() {
      _filterIndex = (_filterIndex + 1) % _filterNames.length;
    });
  }

  Future<void> _captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    // Refrescar ubicación
    if (_currentPosition == null) {
      await _getLocation();
    }
    
    try {
      final XFile file = await _controller!.takePicture();
      
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'fiber_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${dir.path}/$fileName';
      
      // Aplicar filtro si es necesario
      if (_filterIndex > 0) {
        final bytes = await File(file.path).readAsBytes();
        final processed = await _applyFilter(bytes);
        await File(savedPath).writeAsBytes(processed);
      } else {
        await File(file.path).copy(savedPath);
      }
      
      if (mounted) {
        setState(() {
          _capturedImage = File(savedPath);
          _showCapture = true;
          _notesController.clear();
        });
      }
      
    } catch (e) {
      _showError('Error capturando: $e');
    }
  }

  Future<Uint8List> _applyFilter(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    
    img.Image processed;
    
    switch (_filterIndex) {
      case 1:
        processed = img.adjustColor(image, contrast: 1.8, saturation: 0.5);
        break;
      case 2:
        processed = img.sobel(image);
        break;
      case 3:
        processed = img.invert(image);
        break;
      case 4:
        processed = img.grayscale(image);
        processed = img.adjustColor(processed, contrast: 2.0);
        break;
      default:
        processed = image;
    }
    
    return Uint8List.fromList(img.encodeJpg(processed, quality: 95));
  }

  Future<void> _saveInspection(String result) async {
    if (_capturedImage == null) return;
    
    if (mounted) {
      setState(() => _saving = true);
    }
    
    try {
      final inspection = FiberInspection(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        imagePath: _capturedImage!.path,
        timestamp: DateTime.now(),
        latitude: _currentPosition?.latitude ?? 0,
        longitude: _currentPosition?.longitude ?? 0,
        address: _currentAddress,
        notes: _notesController.text,
        result: result,
      );
      
      await InspectionService.save(inspection);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Inspección guardada con ubicación'),
            backgroundColor: Color(0xFF00D4AA),
          ),
        );
        
        _closeCapture();
      }
      
    } catch (e) {
      _showError('Error guardando: $e');
    }
    
    if (mounted) {
      setState(() => _saving = false);
    }
  }

  void _closeCapture() {
    setState(() {
      _showCapture = false;
      _capturedImage = null;
      _notesController.clear();
    });
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InspectionHistoryScreen()),
    );
  }

  @override
  void dispose() {
    _controller?.setFlashMode(FlashMode.off);
    _controller?.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('MICROSCOPIO FIBRA'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _openHistory,
            tooltip: 'Historial',
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelp,
          ),
        ],
      ),
      body: _showCapture ? _buildCaptureView() : _buildCameraView(),
    );
  }

  Widget _buildCameraView() {
    if (!_isInitialized || _controller == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF00D4AA)),
            SizedBox(height: 16),
            Text('Iniciando cámara...', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Preview
        Positioned.fill(
          child: ClipRect(
            child: ColorFiltered(
              colorFilter: _getColorFilter(),
              child: CameraPreview(_controller!),
            ),
          ),
        ),
        
        // Guía
        Center(
          child: CustomPaint(
            size: const Size(300, 300),
            painter: FiberGuidePainter(),
          ),
        ),
        
        // Info superior
        Positioned(
          top: 8,
          left: 16,
          right: 16,
          child: Column(
            children: [
              // Filtro
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _filterNames[_filterIndex],
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              // Ubicación
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _currentPosition != null 
                      ? const Color(0xFF00D4AA).withOpacity(0.2)
                      : Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _gettingLocation 
                          ? Icons.gps_not_fixed 
                          : _currentPosition != null 
                              ? Icons.gps_fixed 
                              : Icons.gps_off,
                      size: 14,
                      color: _currentPosition != null ? const Color(0xFF00D4AA) : Colors.amber,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _gettingLocation ? 'Obteniendo GPS...' : _currentAddress,
                        style: TextStyle(
                          color: _currentPosition != null ? const Color(0xFF00D4AA) : Colors.amber,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_currentPosition == null && !_gettingLocation) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _getLocation,
                        child: const Icon(Icons.refresh, size: 14, color: Colors.amber),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Controles
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildControls(),
        ),
      ],
    );
  }

  ColorFilter _getColorFilter() {
    switch (_filterIndex) {
      case 1:
        return const ColorFilter.matrix([
          1.5, 0, 0, 0, -0.2,
          0, 1.5, 0, 0, -0.2,
          0, 0, 1.5, 0, -0.2,
          0, 0, 0, 1, 0,
        ]);
      case 2:
        return const ColorFilter.matrix([
          2, -0.5, -0.5, 0, 0,
          -0.5, 2, -0.5, 0, 0,
          -0.5, -0.5, 2, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case 3:
        return const ColorFilter.matrix([
          -1, 0, 0, 0, 255,
          0, -1, 0, 0, 255,
          0, 0, -1, 0, 255,
          0, 0, 0, 1, 0,
        ]);
      case 4:
        return const ColorFilter.matrix([
          0.5, 0.5, 0.5, 0, -0.2,
          0.5, 0.5, 0.5, 0, -0.2,
          0.5, 0.5, 0.5, 0, -0.2,
          0, 0, 0, 1, 0,
        ]);
      default:
        return const ColorFilter.mode(Colors.transparent, BlendMode.multiply);
    }
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.9), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Zoom
          Row(
            children: [
              const Icon(Icons.zoom_out, color: Colors.white54, size: 18),
              Expanded(
                child: Slider(
                  value: _zoomLevel,
                  min: _minZoom,
                  max: _maxZoom,
                  activeColor: const Color(0xFF00D4AA),
                  inactiveColor: Colors.white24,
                  onChanged: _setZoom,
                ),
              ),
              Text(
                '${_zoomLevel.toStringAsFixed(1)}x',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.zoom_in, color: Colors.white54, size: 18),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Botones
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _controlBtn(
                icon: _flashOn ? Icons.flash_on : Icons.flash_off,
                label: 'LUZ',
                isActive: _flashOn,
                onTap: _toggleFlash,
              ),
              
              // Capturar
              GestureDetector(
                onTap: _captureImage,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: Center(
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF00D4AA),
                      ),
                      child: const Icon(Icons.camera, color: Colors.black, size: 28),
                    ),
                  ),
                ),
              ),
              
              _controlBtn(
                icon: Icons.filter,
                label: 'FILTRO',
                isActive: _filterIndex > 0,
                onTap: _changeFilter,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _controlBtn({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? const Color(0xFF00D4AA) : Colors.white24,
            ),
            child: Icon(icon, color: isActive ? Colors.black : Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? const Color(0xFF00D4AA) : Colors.white54,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureView() {
    return Column(
      children: [
        // Imagen
        Expanded(
          child: _capturedImage != null
              ? InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 5.0,
                  child: Image.file(_capturedImage!, fit: BoxFit.contain),
                )
              : const Center(child: Text('Error', style: TextStyle(color: Colors.white))),
        ),
        
        // Info de ubicación
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF161B22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _currentPosition != null ? Icons.gps_fixed : Icons.gps_off,
                    size: 16,
                    color: _currentPosition != null ? const Color(0xFF00D4AA) : Colors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentAddress,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
              if (_currentPosition != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                  ),
                ),
              const SizedBox(height: 12),
              // Notas
              TextField(
                controller: _notesController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Agregar nota (CTO, puerto, cliente...)',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
        ),
        
        // Botones de calificación
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.black,
          child: Column(
            children: [
              const Text(
                '¿Cómo está el corte?',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _resultButton(
                      icon: Icons.check_circle,
                      label: 'BUENO',
                      color: const Color(0xFF00D4AA),
                      result: 'ok',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _resultButton(
                      icon: Icons.warning_amber,
                      label: 'REGULAR',
                      color: Colors.amber,
                      result: 'warning',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _resultButton(
                      icon: Icons.cancel,
                      label: 'MALO',
                      color: const Color(0xFFFF6B6B),
                      result: 'bad',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _closeCapture,
                child: const Text('DESCARTAR', style: TextStyle(color: Colors.white38)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resultButton({
    required IconData icon,
    required String label,
    required Color color,
    required String result,
  }) {
    return ElevatedButton(
      onPressed: _saving ? null : () => _saveInspection(result),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.2),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: color.withOpacity(0.5)),
        ),
      ),
      child: _saving
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Column(
              children: [
                Icon(icon, size: 24),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
    );
  }

  void _showHelp() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📷 MICROSCOPIO FIBRA', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _helpRow('1', 'Enciende la LUZ para iluminar'),
            _helpRow('2', 'Acerca la fibra a 2-3 cm'),
            _helpRow('3', 'ZOOM al máximo posible'),
            _helpRow('4', 'Prueba FILTROS para ver mejor'),
            _helpRow('5', 'Captura y califica el corte'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF00D4AA).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.location_on, color: Color(0xFF00D4AA), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cada foto se guarda con GPS para trazabilidad',
                      style: TextStyle(color: Color(0xFF00D4AA), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _helpRow(String n, String t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00D4AA)),
            child: Center(child: Text(n, style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 10),
          Text(t, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

// ============================================================================
// GUÍA VISUAL
// ============================================================================

class FiberGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    final outerPaint = Paint()
      ..color = const Color(0xFF00D4AA).withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    canvas.drawCircle(center, 80, outerPaint);
    
    final innerPaint = Paint()
      ..color = const Color(0xFF00D4AA).withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    
    canvas.drawCircle(center, 30, innerPaint);
    
    final crossPaint = Paint()
      ..color = const Color(0xFF00D4AA).withOpacity(0.5)
      ..strokeWidth = 1;
    
    canvas.drawLine(Offset(center.dx - 100, center.dy), Offset(center.dx - 85, center.dy), crossPaint);
    canvas.drawLine(Offset(center.dx + 85, center.dy), Offset(center.dx + 100, center.dy), crossPaint);
    canvas.drawLine(Offset(center.dx, center.dy - 100), Offset(center.dx, center.dy - 85), crossPaint);
    canvas.drawLine(Offset(center.dx, center.dy + 85), Offset(center.dx, center.dy + 100), crossPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================================
// HISTORIAL DE INSPECCIONES
// ============================================================================

class InspectionHistoryScreen extends StatefulWidget {
  const InspectionHistoryScreen({Key? key}) : super(key: key);

  @override
  State<InspectionHistoryScreen> createState() => _InspectionHistoryScreenState();
}

class _InspectionHistoryScreenState extends State<InspectionHistoryScreen> {
  List<FiberInspection> _inspections = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _inspections = await InspectionService.getAll();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Color _resultColor(String result) {
    switch (result) {
      case 'ok': return const Color(0xFF00D4AA);
      case 'warning': return Colors.amber;
      case 'bad': return const Color(0xFFFF6B6B);
      default: return Colors.white38;
    }
  }

  IconData _resultIcon(String result) {
    switch (result) {
      case 'ok': return Icons.check_circle;
      case 'warning': return Icons.warning_amber;
      case 'bad': return Icons.cancel;
      default: return Icons.help_outline;
    }
  }

  void _copyReport() {
    if (_inspections.isEmpty) return;
    
    final buffer = StringBuffer();
    buffer.writeln('═══ REPORTE INSPECCIONES FIBRA ═══');
    buffer.writeln('Fecha: ${DateTime.now().toString().substring(0, 16)}');
    buffer.writeln('Total: ${_inspections.length} inspecciones');
    buffer.writeln('');
    
    for (final i in _inspections) {
      buffer.writeln('─────────────────────');
      buffer.writeln('📅 ${i.formattedDate}');
      buffer.writeln('📍 ${i.address}');
      buffer.writeln('🌐 ${i.coordinates}');
      if (i.notes.isNotEmpty) buffer.writeln('📝 ${i.notes}');
      buffer.writeln('✓ ${i.result.toUpperCase()}');
    }
    buffer.writeln('═══════════════════════════════════');
    
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reporte copiado'), backgroundColor: Color(0xFF00D4AA)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('HISTORIAL'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_inspections.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _copyReport,
              tooltip: 'Copiar reporte',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D4AA)))
          : _inspections.isEmpty
              ? const Center(
                  child: Text('Sin inspecciones', style: TextStyle(color: Colors.white38)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _inspections.length,
                  itemBuilder: (_, i) => _buildCard(_inspections[i]),
                ),
    );
  }

  Widget _buildCard(FiberInspection inspection) {
    final color = _resultColor(inspection.result);
    final imageFile = File(inspection.imagePath);
    final imageExists = imageFile.existsSync();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Imagen
          if (imageExists)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.file(
                imageFile,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fecha y resultado
                Row(
                  children: [
                    Icon(_resultIcon(inspection.result), color: color, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      inspection.result.toUpperCase(),
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const Spacer(),
                    Text(
                      inspection.formattedDate,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                // Ubicación
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.white38, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        inspection.address,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                
                // Coordenadas
                Padding(
                  padding: const EdgeInsets.only(left: 18, top: 2),
                  child: Text(
                    inspection.coordinates,
                    style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                  ),
                ),
                
                // Notas
                if (inspection.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      inspection.notes,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}













