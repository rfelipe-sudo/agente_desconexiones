import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:agente_desconexiones/constants/app_colors.dart';

/// Widget de carga con identidad CREABOX (sin pantalla azul CT legada).
/// 
/// Muestra el logo animado con partículas flotantes y texto opcional.
/// Úsalo cuando la app esté cargando datos.
/// 
/// Ejemplo de uso:
/// ```dart
/// // Opción 1: Loading simple con partículas
/// CreacionesLoading()
/// 
/// // Opción 2: Con mensaje personalizado
/// CreacionesLoading(mensaje: 'Cargando órdenes...')
/// 
/// // Opción 3: Versión mini (para cards, sin partículas)
/// CreacionesLoading.mini()
/// 
/// // Opción 4: Overlay sobre contenido
/// Stack(
///   children: [
///     MiContenido(),
///     if (_cargando) CreacionesLoading.overlay(),
///   ],
/// )
/// ```
class CreacionesLoading extends StatefulWidget {
  final String? mensaje;
  final double? logoSize;
  final bool showLogo;
  final Color? backgroundColor;
  final bool showParticles;
  
  const CreacionesLoading({
    super.key,
    this.mensaje,
    this.logoSize,
    this.showLogo = true,
    this.backgroundColor,
    this.showParticles = true,
  });
  
  /// Constructor para versión mini (usar en cards pequeños, sin partículas)
  const CreacionesLoading.mini({
    super.key,
    this.mensaje,
    this.logoSize = 80,
    this.showLogo = true,
    this.backgroundColor,
    this.showParticles = false,
  });
  
  /// Constructor para overlay (fondo semi-transparente sobre contenido)
  const CreacionesLoading.overlay({
    super.key,
    this.mensaje,
    this.logoSize = 120,
    this.showLogo = true,
    this.backgroundColor = const Color(0xDD0A0A0A),
    this.showParticles = true,
  });

  @override
  State<CreacionesLoading> createState() => _CreacionesLoadingState();
}

class _CreacionesLoadingState extends State<CreacionesLoading> 
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  
  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
    
    // Animación de pulso para el logo
    _pulseAnimation = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final size = widget.logoSize ?? 140.0;
    final showBackground = widget.backgroundColor != null;
    
    final logoContent = Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo animado
          if (widget.showLogo) ...[
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: child,
                );
              },
              child: Container(
                padding: EdgeInsets.all(size * 0.15),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(
                        alpha: 0.1 * _pulseAnimation.value,
                      ),
                      blurRadius: 40 * _pulseAnimation.value,
                      spreadRadius: 10 * _pulseAnimation.value,
                    ),
                    BoxShadow(
                      color: AppColors.creaVoice.withValues(
                        alpha: 0.22 * _pulseAnimation.value,
                      ),
                      blurRadius: 50 * _pulseAnimation.value,
                      spreadRadius: 15 * _pulseAnimation.value,
                    ),
                  ],
                ),
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) {
                    return AppColors.creaGradient.createShader(bounds);
                  },
                  child: Text(
                    'CREABOX',
                    style: TextStyle(
                      fontSize: size * 0.22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: size * 0.4),
          ],
          
          // Spinner minimalista
          SizedBox(
            width: widget.showLogo ? 40 : 35,
            height: widget.showLogo ? 40 : 35,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                showBackground
                    ? Colors.white.withValues(alpha: 0.85)
                    : AppColors.creaVoice,
              ),
            ),
          ),
          
          // Mensaje de carga
          if (widget.mensaje != null) ...[
            SizedBox(height: size * 0.2),
            Text(
              widget.mensaje!,
              style: TextStyle(
                color: showBackground
                    ? Colors.white.withValues(alpha: 0.9)
                    : Colors.grey[300],
                fontSize: 15,
                fontWeight: FontWeight.w300,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
    
    // Contenido con o sin partículas
    // ParticleAnimation temporalmente comentado
    final Widget content = logoContent; // widget.showParticles ? ParticleAnimation(...) : logoContent;
    
    // Si tiene backgroundColor, envolver en contenedor
    if (showBackground) {
      return Container(
        decoration: BoxDecoration(
          color: widget.backgroundColor,
          gradient: widget.showParticles
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.background,
                    widget.backgroundColor ?? AppColors.surface,
                  ],
                )
              : null,
        ),
        child: content,
      );
    }
    
    return content;
  }
}

/// Barra de progreso lineal con color CREABOX.
class CreacionesLinearProgress extends StatelessWidget {
  final double? value;
  final String? mensaje;
  
  const CreacionesLinearProgress({
    super.key,
    this.value,
    this.mensaje,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (mensaje != null) ...[
          Text(
            mensaje!,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
        ],
        LinearProgressIndicator(
          value: value,
          backgroundColor: Colors.grey[800],
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      ],
    );
  }
}

/// Widget de loading para usar en AppBar
class CreacionesAppBarLoading extends StatelessWidget {
  const CreacionesAppBarLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 24,
      height: 24,
      child: SpinKitRing(
        color: Colors.white,
        size: 24.0,
        lineWidth: 3.0,
      ),
    );
  }
}

