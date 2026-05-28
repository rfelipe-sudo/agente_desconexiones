import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/config/constants.dart';
import 'package:agente_desconexiones/constants/app_colors.dart';
import 'package:agente_desconexiones/providers/auth_provider.dart';
import 'package:agente_desconexiones/utils/device_helper.dart';
import 'package:agente_desconexiones/utils/session_manager.dart';

/// Splash CREABOX (imagen 1): wordmark en gradiente + glow, sin asset CT.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const Color _bgTop = Color(0xFF0A0A0A);
  static const Color _bgMid = Color(0xFF0A0A12);
  static const Color _track = Color(0xFF1E293B);
  static const String _versionLabel = 'v1.0.0';
  static const String _leyendaConexion = 'Conectando......';

  static const Duration _splashTotal = Duration(milliseconds: 2500);

  late final AnimationController _logoController;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;

  late final AnimationController _textController;
  late final Animation<double> _textFade;

  late final AnimationController _progressController;
  late final Animation<double> _progress;

  late final AnimationController _ambientController;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutCubic),
    );
    _logoScale = Tween<double>(begin: 0.88, end: 1).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _textFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic),
    );

    _progressController = AnimationController(
      vsync: this,
      duration: _splashTotal,
    );
    _progress = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _progressController,
        curve: Curves.easeInOutCubic,
      ),
    );

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();

    _logoController.forward();
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (mounted) _textController.forward();
    });
    _progressController.forward();

    _startSplash();
  }

  Future<void> _startSplash() async {
    await Future<void>.delayed(_splashTotal);
    if (!mounted) return;

    try {
      final deviceId = await obtenerIdDispositivo();
      final prefs = await SharedPreferences.getInstance();

      final rutGuardado = prefs.getString('rut_tecnico');
      final nombreGuardado = prefs.getString('user_nombre');

      print('[Splash] deviceId: $deviceId');
      print('[Splash] rutGuardado: $rutGuardado');

      if (rutGuardado == null || rutGuardado.isEmpty) {
        print('[Splash] Primera vez → /registro_rut');
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/registro_rut');
        return;
      }

      final supabase = Supabase.instance.client;
      final existe = await supabase
          .from('dispositivos_autorizados')
          .select(
            'imei, habilitado, rut_tecnico, nombre_tecnico, motivo_bloqueo',
          )
          .eq('imei', deviceId)
          .maybeSingle();

      print('[Splash] existe en DB: $existe');

      if (!mounted) return;

      if (existe == null) {
        await prefs.remove('rut_tecnico');
        await prefs.remove('user_nombre');
        await prefs.remove('user_rol');
        print('[Splash] Dispositivo eliminado del panel → /registro_rut');
        Navigator.pushReplacementNamed(context, '/registro_rut');
        return;
      }

      if (existe['habilitado'] == true) {
        final nombreDb = existe['nombre_tecnico']?.toString().trim();
        if (nombreDb != null && nombreDb.isNotEmpty) {
          await prefs.setString('user_nombre', nombreDb);
          await prefs.setString('nombre_tecnico', nombreDb);
          print('[Splash] Nombre actualizado desde DB: $nombreDb');
          if (rutGuardado != null && rutGuardado.isNotEmpty) {
            await SessionManager.marcarNombreGuardadoParaRut(rutGuardado);
          }
        }

        await rpcVerificarDispositivo(
          supabase,
          rutTecnico: rutGuardado,
          nombreTecnico: (nombreGuardado != null &&
                  nombreGuardado.trim().isNotEmpty)
              ? nombreGuardado
              : existe['nombre_tecnico']?.toString(),
        );
        // Reportar versión al panel (fire-and-forget)
        supabase
            .from('dispositivos_autorizados')
            .update({'app_version': kAppVersion})
            .eq('imei', deviceId)
            .then((_) {}, onError: (_) {});
        if (!mounted) return;
        try {
          await context.read<AuthProvider>().syncUsuarioDesdePrefs();
        } catch (e) {
          print('[Splash] syncUsuarioDesdePrefs: $e');
        }
        if (!mounted) return;
        print('[Splash] Autorizado → /home');
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        final estado = existe['motivo_bloqueo'] != null
            ? 'bloqueado'
            : 'pendiente';
        final mensaje = existe['motivo_bloqueo']?.toString() ??
            'Dispositivo pendiente de autorización. Contacta a tu coordinador.';
        print('[Splash] $estado → /dispositivo_bloqueado');
        Navigator.pushReplacementNamed(
          context,
          '/dispositivo_bloqueado',
          arguments: <String, String>{'estado': estado, 'mensaje': mensaje},
        );
      }
    } catch (e, stack) {
      print('[Splash] ERROR: $e');
      print(stack);
      final prefs = await SharedPreferences.getInstance();
      final rutGuardado = prefs.getString('rut_tecnico');
      if (!mounted) return;
      if (rutGuardado != null && rutGuardado.isNotEmpty) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pushReplacementNamed(context, '/registro_rut');
      }
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _progressController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  /// Wordmark CREABOX (gradiente violeta → azul + halo azul, estilo imagen 1).
  Widget _creaboxWordmark() {
    const text = 'CREABOX';

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Halo difuso (azul / cyan)
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: const Text(
            text,
            style: TextStyle(
              fontSize: 46,
              fontWeight: FontWeight.w800,
              letterSpacing: 5,
              color: Color(0xFF448AFF),
            ),
          ),
        ),
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: const Text(
            text,
            style: TextStyle(
              fontSize: 46,
              fontWeight: FontWeight.w800,
              letterSpacing: 5,
              color: Color(0xFF7C4DFF),
            ),
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return const LinearGradient(
              colors: [
                Color(0xFFE9D5FF),
                Color(0xFFE9D5FF),
                Color(0xFF7C4DFF),
                Color(0xFF448AFF),
                Color(0xFF4FC3F7),
              ],
              stops: [0.0, 0.15, 0.4, 0.72, 1.0],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ).createShader(bounds);
          },
          child: const Text(
            text,
            style: TextStyle(
              fontSize: 46,
              fontWeight: FontWeight.w800,
              letterSpacing: 5,
              color: Colors.white,
              height: 1.05,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: _bgTop,
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _bgTop,
                  _bgMid,
                  const Color(0xFF050508),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.25),
                  radius: 1.15,
                  colors: [
                    const Color(0xFF1E3A5F).withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _ambientController,
            builder: (context, _) {
              final t = _ambientController.value * math.pi * 2;
              final pulse = 0.55 + 0.45 * math.sin(t);
              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: -80,
                    left: -40,
                    child: _glowOrb(300, [
                      const Color(0xFF448AFF).withValues(alpha: 0.12 * pulse),
                      Colors.transparent,
                    ]),
                  ),
                  Positioned(
                    bottom: -60,
                    right: -50,
                    child: _glowOrb(260, [
                      AppColors.creaVoice.withValues(alpha: 0.10 * pulse),
                      Colors.transparent,
                    ]),
                  ),
                ],
              );
            },
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _logoController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _logoFade.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: child,
                      ),
                    );
                  },
                  child: _creaboxWordmark(),
                ),
                const SizedBox(height: 36),
                AnimatedBuilder(
                  animation: _textFade,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _textFade.value,
                      child: child,
                    );
                  },
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) {
                      return LinearGradient(
                        colors: [
                          AppColors.creaVoice,
                          AppColors.primaryLight,
                          const Color(0xFF4FC3F7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds);
                    },
                    child: Text(
                      _leyendaConexion,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.8,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: AppColors.primary.withValues(alpha: 0.55),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _progress,
                    builder: (context, _) {
                      final pctInt =
                          (_progress.value * 100).clamp(0, 100).round();
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Conectando',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF7DD3FC),
                                  letterSpacing: 0.4,
                                ),
                              ),
                              Text(
                                '$pctInt%',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  color: const Color(0xFF38BDF8),
                                  shadows: [
                                    Shadow(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.65,
                                      ),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              height: 7,
                              decoration: BoxDecoration(
                                color: _track,
                                border: Border.all(
                                  color: AppColors.surfaceBorder.withValues(
                                    alpha: 0.75,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: _progress.value.clamp(0.0, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      gradient: LinearGradient(
                                        colors: [
                                          AppColors.creaVoice,
                                          primary,
                                          AppColors.primaryLight,
                                          const Color(0xFF22D3EE),
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: primary.withValues(alpha: 0.5),
                                          blurRadius: 12,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _versionLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted.withValues(alpha: 0.9),
                      letterSpacing: 0.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glowOrb(double size, List<Color> colors) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}
