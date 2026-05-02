import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:agente_desconexiones/constants/app_colors.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<_PhotoWithLocation> _photos = [];
  Position? _currentPosition;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);
    
    try {
      // Verificar permisos
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        _currentPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
      }
    } catch (e) {
      print('Error obteniendo ubicación: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (photo != null) {
        // Obtener ubicación actual
        Position? position;
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );
        } catch (e) {
          position = _currentPosition;
        }
        
        setState(() {
          _photos.add(_PhotoWithLocation(
            path: photo.path,
            position: position,
            timestamp: DateTime.now(),
          ));
        });
      }
    } catch (e) {
      _showError('Error al tomar foto: $e');
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _photos.removeAt(index);
    });
  }

  void _confirmPhotos() {
    if (_photos.isEmpty) {
      _showError('Debes tomar al menos una foto');
      return;
    }
    
    Navigator.of(context).pop(_photos.map((p) => p.path).toList());
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.alertUrgent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Fotos Georeferenciadas'),
        actions: [
          if (_photos.isNotEmpty)
            TextButton.icon(
              onPressed: _confirmPhotos,
              icon: const Icon(Icons.check, color: AppColors.alertSuccess),
              label: Text(
                'LISTO (${_photos.length})',
                style: const TextStyle(color: AppColors.alertSuccess),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Info de ubicación
          _buildLocationInfo(),
          
          // Grid de fotos
          Expanded(
            child: _photos.isEmpty
                ? _buildEmptyState()
                : _buildPhotosGrid(),
          ),
          
          // Botón de cámara
          _buildCameraButton(),
        ],
      ),
    );
  }

  Widget _buildLocationInfo() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Icon(
            _currentPosition != null ? Icons.location_on : Icons.location_off,
            color: _currentPosition != null
                ? AppColors.alertSuccess
                : AppColors.alertWarning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _isLoading
                ? const Text(
                    'Obteniendo ubicación...',
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                : _currentPosition != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ubicación detectada',
                            style: TextStyle(
                              color: AppColors.alertSuccess,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${_currentPosition!.latitude.toStringAsFixed(6)}, '
                            '${_currentPosition!.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        'No se pudo obtener ubicación',
                        style: TextStyle(color: AppColors.alertWarning),
                      ),
          ),
          if (!_isLoading)
            IconButton(
              onPressed: _getCurrentLocation,
              icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.2);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.camera_alt_outlined,
              size: 64,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Toma fotos de la CTO',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Las fotos se guardarán con su ubicación GPS',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotosGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: _photos.length,
      itemBuilder: (context, index) {
        final photo = _photos[index];
        return _buildPhotoCard(photo, index);
      },
    );
  }

  Widget _buildPhotoCard(_PhotoWithLocation photo, int index) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Imagen
            Image.file(
              File(photo.path),
              fit: BoxFit.cover,
            ),
            
            // Overlay con info
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (photo.position != null)
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: AppColors.alertSuccess,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${photo.position!.latitude.toStringAsFixed(4)}, '
                              '${photo.position!.longitude.toStringAsFixed(4)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 2),
                    Text(
                      _formatTime(photo.timestamp),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Botón eliminar
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => _removePhoto(index),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.alertUrgent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
            
            // Número de foto
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.creaVoice,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: (index * 100).ms).fadeIn().scale(begin: const Offset(0.9, 0.9));
  }

  Widget _buildCameraButton() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.surfaceBorder),
        ),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Contador de fotos
            if (_photos.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_photos.length} foto(s)',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            
            const SizedBox(width: 16),
            
            // Botón de cámara
            GestureDetector(
              onTap: _takePhoto,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: AppColors.creaGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.creaVoice.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Espacio para balance visual
            if (_photos.isNotEmpty)
              const SizedBox(width: 80),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
           '${time.minute.toString().padLeft(2, '0')}:'
           '${time.second.toString().padLeft(2, '0')}';
  }
}

class _PhotoWithLocation {
  final String path;
  final Position? position;
  final DateTime timestamp;

  _PhotoWithLocation({
    required this.path,
    this.position,
    required this.timestamp,
  });
}

