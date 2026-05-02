import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/providers/auth_provider.dart';
import 'package:agente_desconexiones/utils/device_helper.dart';
import 'package:agente_desconexiones/utils/session_manager.dart';
import 'package:agente_desconexiones/utils/session_manager.dart';

/// Clave global del [Navigator] raíz (definida en [main.dart]).
final GlobalKey<NavigatorState> creaboxNavigatorKey = GlobalKey<NavigatorState>();

/// Observa cambios de ruta y dispara verificación de sesión contra el panel.
class CreaboxSesionNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _programar();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _programar();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _programar();
  }

  void _programar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SesionDispositivoService.verificarSiCorresponde();
    });
  }
}

/// Consulta `dispositivos_autorizados` y redirige si el panel bloqueó o eliminó el dispositivo.
class SesionDispositivoService {
  SesionDispositivoService._();

  static DateTime? _inicioApp;
  static const Duration _margenArranqueSplash = Duration(seconds: 4);

  static DateTime? _ultimaVerificacion;
  static const Duration _intervaloMinimo = Duration(seconds: 2);
  static const Duration _intervaloTimer = Duration(seconds: 45);

  static bool _enCurso = false;
  static Timer? _timerPeriodico;

  /// Llamar una vez al iniciar la app ([main]) para no competir con el splash.
  static void marcarInicioApp() {
    _inicioApp = DateTime.now();
  }

  static void iniciarTimerPeriodico() {
    _timerPeriodico?.cancel();
    _timerPeriodico = Timer.periodic(_intervaloTimer, (_) {
      verificarSiCorresponde();
    });
  }

  static void detenerTimerPeriodico() {
    _timerPeriodico?.cancel();
    _timerPeriodico = null;
  }

  /// Llamar al volver la app al foreground (resume).
  static void verificarSiCorresponde() {
    final ahora = DateTime.now();
    if (_ultimaVerificacion != null &&
        ahora.difference(_ultimaVerificacion!) < _intervaloMinimo) {
      return;
    }
    _ultimaVerificacion = ahora;
    unawaited(_ejecutarVerificacion());
  }

  static Future<void> _ejecutarVerificacion() async {
    if (_enCurso) return;
    if (_inicioApp != null &&
        DateTime.now().difference(_inicioApp!) < _margenArranqueSplash) {
      return;
    }
    final ctx = creaboxNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    final rut = await SessionManager.getRutTecnico();
    if (rut.isEmpty) return;

    final nombreRuta = ModalRoute.of(ctx)?.settings.name;
    if (nombreRuta == '/dispositivo_bloqueado') return;

    _enCurso = true;
    try {
      final deviceId = await obtenerIdDispositivo();
      final supabase = Supabase.instance.client;

      final row = await supabase
          .from('dispositivos_autorizados')
          .select('habilitado, rut_tecnico, nombre_tecnico, motivo_bloqueo')
          .eq('imei', deviceId)
          .maybeSingle();

      if (!ctx.mounted) return;

      if (row == null) {
        await _limpiarSesionLocal(ctx);
        if (!ctx.mounted) return;
        Navigator.of(ctx).pushNamedAndRemoveUntil(
          '/registro_rut',
          (_) => false,
        );
        return;
      }

      if (row['habilitado'] == true) {
        final nombreDb = row['nombre_tecnico']?.toString().trim();
        if (nombreDb != null && nombreDb.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_nombre', nombreDb);
          await prefs.setString('nombre_tecnico', nombreDb);
          await SessionManager.marcarNombreGuardadoParaRut(rut);
          if (ctx.mounted) await ctx.read<AuthProvider>().syncUsuarioDesdePrefs();
        }
        return;
      }

      final estado = row['motivo_bloqueo'] != null ? 'bloqueado' : 'pendiente';
      final mensaje = row['motivo_bloqueo']?.toString() ??
          'Dispositivo pendiente de autorización. Contacta a tu coordinador.';

      if (!ctx.mounted) return;
      Navigator.of(ctx).pushNamedAndRemoveUntil(
        '/dispositivo_bloqueado',
        (_) => false,
        arguments: <String, String>{
          'estado': estado,
          'mensaje': mensaje,
        },
      );
    } catch (e) {
      print('⚠️ [SesionDispositivo] Verificación omitida (red/error): $e');
    } finally {
      _enCurso = false;
    }
  }

  static Future<void> _limpiarSesionLocal(BuildContext ctx) async {
    if (ctx.mounted) await ctx.read<AuthProvider>().invalidarSesionCreabox();
  }
}
