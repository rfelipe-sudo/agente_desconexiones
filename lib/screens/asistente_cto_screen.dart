import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:agente_desconexiones/providers/alerta_provider.dart';
import 'package:agente_desconexiones/services/nyquist_service.dart';

// ── Colores globales ────────────────────────────────────────────────────────
const _bgColor      = Color(0xFF0D1B2A);
const _surfaceColor = Color(0xFF1A2C3D);
const _cyanColor    = Color(0xFF00BCD4);
const _alertRed     = Color(0xFFE53935);

// ── Modelo de puerto ─────────────────────────────────────────────────────
/// Vista combinada de un puerto: ambos valores (anterior y actual) vienen
/// del MISMO response de Nyquist (`u_cto_portN_rx_before` y `_rx_actual`).
class _PuertoCombinado {
  final int numero;
  final double? rxAnterior;
  final double? rxActual;
  final bool activo;

  const _PuertoCombinado({
    required this.numero,
    required this.rxAnterior,
    required this.rxActual,
    required this.activo,
  });

  double? get diferencia {
    if (rxActual == null || rxAnterior == null) return null;
    return rxActual! - rxAnterior!;
  }

  bool get esAlerta {
    if (!activo || rxAnterior == null) return false;
    if (rxActual == null || rxActual == 0.0) return true;
    final diff = diferencia;
    return diff != null && diff < -3.0;
  }
}

// ── Widget principal ─────────────────────────────────────────────────────────

class AsistenteCtoScreen extends StatefulWidget {
  const AsistenteCtoScreen({super.key});

  @override
  State<AsistenteCtoScreen> createState() => _AsistenteCtoScreenState();
}

/// Vista actual de la pantalla
enum _Vista { inicio, menuRevisarEstado, iniciadaCto, finalizadasCto, potencias }

class _AsistenteCtoScreenState extends State<AsistenteCtoScreen> {
  final NyquistService _nyquist = NyquistService();

  _Vista _vista = _Vista.inicio;

  bool _cargando = false;
  bool _actualizandoEndpoint = false;
  String? _error;
  String? _tipoRedError;
  EstadoCTO? _resultado;
  String? _accessIdCorto;
  String? _accessIdNyquist;
  String? _nyquistError;
  /// Hora a la que Nyquist respondió la última consulta exitosa.
  String? _horaConsulta;
  /// Ruta local de la imagen del CTO capturada por el scanner nativo.
  String? _imagenCTO;
  /// Número de OT asociado a la medición actual (distinto del access_id).
  String? _ordenTrabajo;

  // ── Estado de la vista historial ───────────────────────────────────────
  List<OrdenHistorial> _historial = [];
  List<OrdenHistorial> _ordenesPendientes = [];
  List<OrdenHistorial> _ordenesIniciadas = [];
  OrdenHistorial? _ordenIniciada;
  bool _cargandoHistorial = false;
  String? _historialError;
  /// Si la vista de potencias se abrió desde el historial, volver allá
  /// con el back en vez de a la pantalla de cards.
  bool _vinoDelHistorial = false;

  /// Estado de alerta por OT (poblado en background tras cargar historial).
  /// Una OT queda en `true` si Nyquist reporta al menos un puerto con drop
  /// > 3 dB o sin lectura actual cuando había anterior.
  final Map<String, bool> _alertasPorOt = {};
  /// Cuántas consultas Nyquist en paralelo siguen activas (para mostrar
  /// un indicador discreto en el header del historial).
  int _alertasPendientes = 0;

  // ── Estado de la sección "Trabajo Iniciado" en revisarEstado ───────────
  EstadoCTO? _resultadoIniciada;
  bool       _cargandoIniciada     = false;
  String?    _accessIdIniciadaNyquist;
  bool       _actualizandoIniciada = false;
  String?    _horaConsultaIniciada;
  String?    _nyquistErrorIniciada;
  /// FTTH/CFTTH/HFC/CHFC: no consultar Nyquist, mostrar aviso de red no neutra.
  String?    _tipoRedNoMedibleIniciada;
  /// access_id_corto → estado (de produccion_crea, usado para filtrar completados)
  Map<String, String> _estadosHoy = {};
  /// OT resuelta cuando no hay match en tabla_access_id/historial.
  String? _otActivaResuelta;
  String? _tipoOrdenActiva;

  static const _ctoChannel = MethodChannel(
    'com.creacionestecnologicas.agente_desconexiones/cto_scan',
  );

  @override
  void initState() {
    super.initState();
    // Si la ruta se invoca con `arguments: 'potencias'`, saltarse la card
    // inicial y arrancar directo en la consulta de estado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.toLowerCase() == 'potencias') {
        _cargarPotencias();
      }
    });
  }

  // ── Canal nativo ────────────────────────────────────────────────────────────

  Future<void> _abrirAsistenteVisual() async {
    final prefs = await SharedPreferences.getInstance();
    final rut = prefs.getString('rut_tecnico') ?? '';
    try {
      // Espera hasta que el scanner cierre. Kotlin devuelve la ruta de la
      // imagen del CTO si la encontró, o null si no.
      final imagePath = await _ctoChannel.invokeMethod<String>('openCtoScan', {'rut': rut});
      if (!mounted) return;
      setState(() => _imagenCTO = imagePath);
      _cargarPotencias();
    } on PlatformException catch (e) {
      if (mounted && e.code != 'CTO_CANCELLED') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir escáner CTO: ${e.message}'),
            backgroundColor: _alertRed,
          ),
        );
      }
    }
  }

  // ── Vista revisarEstado: potencias iniciada + completados del día ──────

  Future<void> _cargarRevisarEstado() async {
    setState(() {
      _vista = _Vista.iniciadaCto;
      _cargandoHistorial = true;
      _historialError = null;
      _historial = [];
      _ordenIniciada = null;
      _vinoDelHistorial = false;
      _alertasPorOt.clear();
      _alertasPendientes = 0;
      _resultadoIniciada = null;
      _cargandoIniciada = false;
      _nyquistErrorIniciada = null;
      _horaConsultaIniciada = null;
      _accessIdIniciadaNyquist = null;
      _estadosHoy = {};
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final rut = prefs.getString('rut_tecnico') ?? '';
      if (rut.isEmpty) {
        if (mounted) setState(() { _cargandoHistorial = false; _historialError = 'No hay RUT registrado en la sesión.'; });
        return;
      }

      // Ejecutar en paralelo: historial (acceso_ids) + orden activa (Kepler TOA + get_pelo_db)
      final results = await Future.wait([
        _nyquist.buscarHistorialPorRut(rut),
        _nyquist.resolveOrdenActivaCto(rut),
        _fetchEstadosHoy(rut),
      ]);
      if (!mounted) return;

      final lista      = results[0] as List<OrdenHistorial>;
      final activa     = results[1] as OrdenActivaCto?;
      final estadosMap = results[2] as Map<String, String>;

      final hoy = DateTime.now();
      bool esHoy(DateTime d) => d.year == hoy.year && d.month == hoy.month && d.day == hoy.day;
      final hoyOnly = lista.where((o) => esHoy(o.fechaReferencia)).toList();

      setState(() {
        _historial = hoyOnly;
        _estadosHoy = estadosMap;
        _cargandoHistorial = false;
        _cargandoIniciada = activa != null &&
            !activa.tieneEstado &&
            activa.tieneAccessId &&
            !activa.esRedNoNeutra;
        _nyquistErrorIniciada = null;
        _tipoRedNoMedibleIniciada = null;
      });

      _aplicarOrdenActiva(activa, historial: lista);

      if (!mounted) return;
      setState(() {});

      _evaluarAlertasHistorial(hoyOnly);

      if (activa != null && !activa.tieneEstado && activa.tieneAccessId) {
        if (activa.esRedNoNeutra) {
          setState(() {
            _tipoRedNoMedibleIniciada = activa.tipoRedProducto;
            _nyquistErrorIniciada =
                mensajeOrdenSinAccessIdRedNeutra(activa.tipoRedProducto);
          });
        } else {
          final orden = _ordenIniciada ?? activa.toHistorial();
          _cargarIniciadaPotencias(orden);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _cargandoHistorial = false; _historialError = 'Error al cargar: $e'; });
    }
  }

  /// Consulta produccion_crea para obtener el estado de cada OT de hoy.
  /// Retorna Map<access_id_corto, estado>.
  Future<Map<String, String>> _fetchEstadosHoy(String rut) async {
    try {
      final hoy = DateTime.now();
      final hoyStr = '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
      final rows = await Supabase.instance.client
          .from('produccion_crea')
          .select('access_id, estado')
          .eq('rut_tecnico', rut)
          .gte('hora_inicio', hoyStr)
          .order('hora_inicio', ascending: false);
      final map = <String, String>{};
      for (final r in (rows as List)) {
        final aid = r['access_id']?.toString().trim() ?? '';
        final est = r['estado']?.toString() ?? '';
        if (aid.isNotEmpty) map[aid] = est;
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<bool> _bloquearSiRedNoMedible(String ot, {required bool iniciada}) async {
    if (ot.trim().isEmpty) return false;
    final tipo = await _nyquist.obtenerTipoRedProductoPorOt(ot);
    if (!esTipoRedNoMedible(tipo)) return false;
    if (!mounted) return true;
    setState(() {
      if (iniciada) {
        _tipoRedNoMedibleIniciada = tipo;
        _nyquistErrorIniciada = mensajeOrdenSinAccessIdRedNeutra(tipo!);
        _resultadoIniciada = null;
        _cargandoIniciada = false;
        _actualizandoIniciada = false;
      } else {
        _tipoRedError = tipo;
        _error = 'tecnologia_incompatible';
        _cargando = false;
      }
    });
    return true;
  }

  Future<void> _cargarIniciadaPotencias(OrdenHistorial orden) async {
    setState(() {
      _cargandoIniciada = true;
      _resultadoIniciada = null;
      _nyquistErrorIniciada = null;
      _tipoRedNoMedibleIniciada = null;
      _accessIdIniciadaNyquist = orden.accessIdPrefijado;
    });
    if (await _bloquearSiRedNoMedible(orden.ordenTrabajo, iniciada: true)) return;
    try {
      final r = await _nyquist.consultarEstado(orden.accessIdPrefijado);
      if (!mounted) return;
      setState(() {
        _resultadoIniciada = r;
        _horaConsultaIniciada = _formatHoraAhora();
        _cargandoIniciada = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _nyquistErrorIniciada = e.toString().replaceFirst('Exception: ', '');
        _cargandoIniciada = false;
      });
    }
  }

  Future<void> _actualizarIniciadaPotencias() async {
    if (_accessIdIniciadaNyquist == null) return;
    final ot = _ordenIniciada?.ordenTrabajo ?? _otActivaResuelta ?? '';
    if (await _bloquearSiRedNoMedible(ot, iniciada: true)) return;
    setState(() => _actualizandoIniciada = true);
    try {
      final r = await _nyquist.consultarEstado(_accessIdIniciadaNyquist!);
      if (!mounted) return;
      setState(() {
        _resultadoIniciada = r;
        _horaConsultaIniciada = _formatHoraAhora();
        _actualizandoIniciada = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _actualizandoIniciada = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceFirst("Exception: ", "")}'),
          backgroundColor: _alertRed,
        ),
      );
    }
  }

  /// Pregunta a Nyquist por cada OT con access_id y marca `_alertasPorOt`
  /// si tiene al menos un puerto con drop > 3 dB. Se ejecuta en background
  /// y va llamando setState a medida que llegan respuestas.
  Future<void> _evaluarAlertasHistorial(List<OrdenHistorial> ordenes) async {
    final paraConsultar = ordenes.where((o) => o.tieneAccessId).toList();
    if (paraConsultar.isEmpty) return;

    if (mounted) {
      setState(() => _alertasPendientes = paraConsultar.length);
    }

    await Future.wait(paraConsultar.map((o) async {
      try {
        final tipo = await _nyquist.obtenerTipoRedProductoPorOt(o.ordenTrabajo);
        if (esTipoRedNoMedible(tipo)) {
          if (mounted) {
            setState(() {
              _alertasPendientes = (_alertasPendientes - 1).clamp(0, 999);
            });
          }
          return;
        }
        final r = await _nyquist.consultarEstado(o.accessIdPrefijado);
        final tiene = r.puertos.any((p) {
          if (!p.activo || p.rxBefore == null) return false;
          if (p.rxActual == null || p.rxActual == 0.0) return true;
          final delta = p.rxActual! - p.rxBefore!;
          return delta < -3.0;
        });
        if (mounted) {
          setState(() {
            _alertasPorOt[o.ordenTrabajo] = tiene;
            _alertasPendientes = (_alertasPendientes - 1).clamp(0, 999);
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _alertasPendientes = (_alertasPendientes - 1).clamp(0, 999);
          });
        }
      }
    }));
  }

  /// Tap en una OT histórica → consulta solo Nyquist (sin Kepler) y muestra
  /// el resultado en la vista potencias. Skip si no tiene access_id.
  Future<void> _consultarHistorial(OrdenHistorial orden) async {
    if (!orden.tieneAccessId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sin access_id, imposible leer potencias.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // accessIdCorto: sin prefijo VNO (ej. "1-3L47FQ8J")
    final accessIdCorto =
        orden.accessIdPrefijado.replaceFirst(RegExp(r'^\d{1,2}-'), '');

    setState(() {
      _vinoDelHistorial = true;
      _vista = _Vista.potencias;
      _cargando = true;
      _error = null;
      _tipoRedError = null;
      _nyquistError = null;
      _resultado = null;
      _horaConsulta = null;
      _accessIdNyquist = orden.accessIdPrefijado;
      _ordenTrabajo = orden.ordenTrabajo.isNotEmpty ? orden.ordenTrabajo : null;
      _accessIdCorto = accessIdCorto;
    });

    try {
      // El access_id ya viene resuelto desde tabla_access_id en el batch de carga.
      // Si por algún motivo quedó vacío, mostrar error claro en lugar de consultar con OT.
      final accessIdNyquist = orden.accessIdPrefijado;
      if (accessIdNyquist.isEmpty) {
        debugPrint('⚠️ [CTO] OT=${orden.ordenTrabajo} sin access_id en tabla_access_id');
        setState(() {
          _nyquistError = 'No se encontró el access_id de la CTO para esta orden.\n'
              'Es posible que aún no esté registrada en tabla_access_id.';
          _cargando = false;
        });
        return;
      }

      if (await _bloquearSiRedNoMedible(orden.ordenTrabajo, iniciada: false)) return;

      debugPrint('🔍 [CTO] Consultando Nyquist → $accessIdNyquist');
      setState(() => _accessIdNyquist = accessIdNyquist);

      final r = await _nyquist.consultarEstado(accessIdNyquist);
      if (!mounted) return;
      setState(() {
        _resultado = r;
        _horaConsulta = _formatHoraAhora();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _nyquistError = e.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  // ── Carga de potencias ──────────────────────────────────────────────────────

  Future<void> _cargarPotencias({bool desdeHistorial = false}) async {
    setState(() {
      _cargando = true;
      _error = null;
      _tipoRedError = null;
      _nyquistError = null;
      _resultado = null;
      _horaConsulta = null;
      _vista = _Vista.potencias;
      _vinoDelHistorial = desdeHistorial;
      _ordenTrabajo = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final rut = prefs.getString('rut_tecnico') ?? '';

      if (rut.isEmpty) {
        setState(() { _cargando = false; _error = 'sin_trabajo'; });
        return;
      }

      debugPrint('🔍 [AsistenteCTO] resolveOrdenActivaCto para RUT: $rut');
      final activa = await _nyquist.resolveOrdenActivaCto(rut);
      if (activa == null) {
        setState(() { _cargando = false; _error = 'sin_trabajo'; });
        return;
      }

      _accessIdNyquist = activa.accessIdPrefijado.isNotEmpty
          ? activa.accessIdPrefijado
          : null;
      _accessIdCorto = activa.accessIdCorto.isNotEmpty
          ? activa.accessIdCorto
          : activa.accessIdPrefijado.replaceFirst(RegExp(r'^\d{1,2}-'), '');
      _ordenTrabajo = activa.ordenTrabajo.isNotEmpty ? activa.ordenTrabajo : null;

      if (activa.tieneEstado) {
        if (mounted) {
          setState(() {
            _resultado = activa.estado;
            _horaConsulta = _formatHoraAhora();
            _cargando = false;
          });
        }
        return;
      }

      if (!activa.tieneAccessId) {
        setState(() { _cargando = false; _error = 'sin_trabajo'; });
        return;
      }

      if (activa.esRedNoNeutra) {
        setState(() {
          _tipoRedError = activa.tipoRedProducto;
          _error = 'tecnologia_incompatible';
          _cargando = false;
        });
        return;
      }

      try {
        final r = await _nyquist.consultarEstado(activa.accessIdPrefijado);
        if (!mounted) return;
        setState(() {
          _resultado = r;
          _horaConsulta = _formatHoraAhora();
          _cargando = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _nyquistError = e.toString().replaceFirst('Exception: ', '');
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  Future<void> _actualizarEndpoint() async {
    setState(() => _actualizandoEndpoint = true);
    try {
      if (_accessIdNyquist != null) {
        final ot = _ordenTrabajo ?? '';
        if (await _bloquearSiRedNoMedible(ot, iniciada: false)) {
          if (mounted) setState(() => _actualizandoEndpoint = false);
          return;
        }
        final r = await _nyquist.consultarEstado(_accessIdNyquist!);
        if (mounted) {
          setState(() {
            _resultado = r;
            _horaConsulta = _formatHoraAhora();
            _actualizandoEndpoint = false;
          });
          await _verificarYDesbloquearSiSinAlertas();
        }
      } else {
        final prefs = await SharedPreferences.getInstance();
        final rut = prefs.getString('rut_tecnico') ?? '';
        if (rut.isEmpty) {
          if (mounted) setState(() => _actualizandoEndpoint = false);
          return;
        }
        final activa = await _nyquist.resolveOrdenActivaCto(rut);
        if (mounted) {
          setState(() {
            if (activa != null && activa.tieneEstado) {
              _resultado = activa.estado;
              _accessIdNyquist = activa.accessIdPrefijado.isNotEmpty
                  ? activa.accessIdPrefijado
                  : null;
              _accessIdCorto = activa.accessIdCorto;
              _horaConsulta = _formatHoraAhora();
            }
            _actualizandoEndpoint = false;
          });
          await _verificarYDesbloquearSiSinAlertas();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actualizandoEndpoint = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar: ${e.toString().replaceFirst("Exception: ", "")}'),
            backgroundColor: _alertRed,
          ),
        );
      }
    }
  }

  /// Si la card está bloqueada y la lectura actual no tiene ningún puerto
  /// en alerta, levanta el bloqueo localmente y sincroniza con Supabase.
  Future<void> _verificarYDesbloquearSiSinAlertas() async {
    if (!mounted) return;
    final alertaProvider = context.read<AlertaProvider>();
    if (!alertaProvider.misActividadesBloqueada) return;

    final puertos = _buildPuertosCombinados();
    final hayAlerta = puertos.any((p) => p.esAlerta);
    if (hayAlerta) return;

    // Sin alertas → desbloquear
    await alertaProvider.resolver();
    debugPrint('[CTO] Sin alertas en niveles → card desbloqueada');

    // Sincronizar con Supabase
    try {
      final prefs = await SharedPreferences.getInstance();
      final rut = prefs.getString('rut_tecnico') ?? '';
      if (rut.isNotEmpty) {
        await Supabase.instance.client.from('alertas_fcm').upsert({
          'rut_tecnico':  rut,
          'activa':       false,
          'resuelto_en':  DateTime.now().toIso8601String(),
          'resuelto_por': 'cto_niveles',
          'updated_at':   DateTime.now().toIso8601String(),
        }, onConflict: 'rut_tecnico');
        debugPrint('[CTO] alertas_fcm actualizado: resuelta por cto_niveles');
      }
    } catch (e) {
      debugPrint('[CTO] error actualizando alertas_fcm: $e');
    }

    if (mounted) {
      _mostrarDialogoCtoSana();
    }
  }

  void _mostrarDialogoCtoSana() {
    var enviando = false;
    String? errorEnvio;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDlg) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0D2137), Color(0xFF0D1B2A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.45),
                  width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.20),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                    border: Border.all(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.5),
                        width: 2),
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    color: Color(0xFF22C55E),
                    size: 44,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '¡FELICITACIONES!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF22C55E),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'TU CTO ESTÁ SANA\nPUEDES AVANZAR',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.08)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _cyanColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _cyanColor.withValues(alpha: 0.25)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.monitor_heart_outlined,
                          color: _cyanColor, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Recuerda que estaremos monitoreando la CTO hasta el final de la actividad.',
                          style: TextStyle(
                            color: _cyanColor,
                            fontSize: 13,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Banner de error si el POST falla
                if (errorEnvio != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _alertRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _alertRed.withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: _alertRed, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorEnvio!,
                            style: const TextStyle(
                                color: _alertRed, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: enviando
                        ? null
                        : () async {
                            final accessId = _accessIdNyquist;
                            final resultado = _resultado;
                            // Si por alguna razón no hay datos, cerrar directo.
                            if (accessId == null || resultado == null) {
                              Navigator.of(ctx).pop();
                              return;
                            }
                            setStateDlg(() {
                              enviando = true;
                              errorEnvio = null;
                            });
                            try {
                              final ok = await _nyquist.certificarNiveles(
                                  accessId, resultado);
                              if (!ctx.mounted) return;
                              if (ok) {
                                Navigator.of(ctx).pop();
                              } else {
                                setStateDlg(() {
                                  enviando = false;
                                  errorEnvio =
                                      'El servidor no confirmó la certificación. Intenta de nuevo.';
                                });
                              }
                            } catch (e) {
                              if (!ctx.mounted) return;
                              setStateDlg(() {
                                enviando = false;
                                errorEnvio =
                                    'Error de red: ${e.toString().replaceFirst("Exception: ", "")}';
                              });
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: enviando
                          ? const Color(0xFF22C55E).withValues(alpha: 0.6)
                          : const Color(0xFF22C55E),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: enviando
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Text(
                            'Continuar',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _surfaceColor,
        leading: IconButton(
          icon: Icon(
            _vista == _Vista.inicio ? Icons.arrow_back : Icons.arrow_back,
            color: Colors.white,
          ),
          onPressed: () {
            if (_vista == _Vista.potencias) {
              if (_vinoDelHistorial) {
                setState(() {
                  _vista = _Vista.finalizadasCto;
                  _error = null;
                  _resultado = null;
                  _nyquistError = null;
                });
              } else {
                setState(() { _vista = _Vista.inicio; _error = null; _imagenCTO = null; });
              }
            } else if (_vista == _Vista.iniciadaCto || _vista == _Vista.finalizadasCto) {
              setState(() => _vista = _Vista.menuRevisarEstado);
            } else if (_vista == _Vista.menuRevisarEstado) {
              setState(() => _vista = _Vista.inicio);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Row(
          children: [
            Icon(
              _iconoTitulo(),
              color: _cyanColor,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              _tituloVista(),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: switch (_vista) {
        _Vista.inicio           => _buildInicio(),
        _Vista.menuRevisarEstado => _buildMenuRevisarEstado(),
        _Vista.iniciadaCto      => _buildIniciadaView(),
        _Vista.finalizadasCto   => _buildFinalizadasView(),
        _Vista.potencias        => _buildPotencias(),
      },
    );
  }

  IconData _iconoTitulo() {
    switch (_vista) {
      case _Vista.inicio:            return Icons.router;
      case _Vista.menuRevisarEstado: return Icons.cable;
      case _Vista.iniciadaCto:       return Icons.play_circle_outline;
      case _Vista.finalizadasCto:    return Icons.checklist_rounded;
      case _Vista.potencias:         return Icons.bar_chart;
    }
  }

  String _tituloVista() {
    switch (_vista) {
      case _Vista.inicio:            return 'Asistente de CTO';
      case _Vista.menuRevisarEstado: return 'Estado CTO';
      case _Vista.iniciadaCto:       return 'Orden Iniciada';
      case _Vista.finalizadasCto:    return 'Órdenes del Día';
      case _Vista.potencias:         return 'Potencias CTO';
    }
  }

  // ── Vista inicio: dos tarjetas ──────────────────────────────────────────────

  Widget _buildInicio() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTarjetaSolida(
                    icono: Icons.qr_code_scanner,
                    titulo: 'Escanear CTO',
                    color: const Color(0xFF1E88E5),
                    onTap: _abrirAsistenteVisual,
                  ),
                  const SizedBox(height: 24),
                  _buildTarjetaSolida(
                    icono: Icons.cable,
                    titulo: 'Revisar Estado CTO',
                    color: const Color(0xFFFFA94D),
                    onTap: () => setState(() => _vista = _Vista.menuRevisarEstado),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTarjetaSolida({
    required IconData icono,
    required String titulo,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 180,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icono, color: Colors.white, size: 56),
              const SizedBox(height: 16),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // ── Vista potencias ─────────────────────────────────────────────────────────

  Widget _buildPotencias() {
    if (_cargando) return _buildCargando();
    if (_error == 'sin_trabajo') return _buildSinTrabajo();
    if (_error == 'tecnologia_incompatible' || _error == 'otra_tecnologia') return _buildTecnologiaIncompatible();
    if (_error != null) return _buildError();
    if (_resultado != null || _nyquistError != null) return _buildResultado();
    return _buildCargando();
  }

  Widget _buildCargando() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          CircularProgressIndicator(color: _cyanColor),
          SizedBox(height: 20),
          Text(
            'Consultando niveles en Nyquist…',
            style: TextStyle(color: Colors.white70, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSinTrabajo() {
    return _buildSinOrdenIniciadaPantalla(onRefresh: _cargarPotencias);
  }

  Widget _buildSinOrdenIniciadaPantalla({VoidCallback? onRefresh}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.work_off_outlined, size: 72, color: Colors.white30),
            const SizedBox(height: 24),
            const Text(
              'Sin orden iniciada',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Inicia la orden en TOA para revisar el estado de la CTO.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.white54, height: 1.5),
            ),
            if (onRefresh != null) ...[
              const SizedBox(height: 32),
              _buildBotonActualizar(onPressed: onRefresh),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvisoRedNoNeutra(String tipo) {
    final color = tipo.toUpperCase().contains('FTTH')
        ? Colors.purple[300]!
        : Colors.orange[300]!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Column(children: [
        Icon(
          tipo.toUpperCase().contains('FTTH')
              ? Icons.settings_input_component
              : Icons.cable,
          size: 48,
          color: color,
        ),
        const SizedBox(height: 14),
        Text(
          mensajeOrdenSinAccessIdRedNeutra(tipo),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.45,
          ),
        ),
      ]),
    );
  }

  Widget _buildTecnologiaIncompatible() {
    final tipo = _tipoRedError ?? '';
    final mensaje = tipo.isNotEmpty
        ? mensajeOrdenSinAccessIdRedNeutra(tipo)
        : 'Este trabajo pertenece a una tecnología\ndiferente a red neutra.';
    final IconData icono;
    final Color color;

    if (tipo.contains('FTTH')) {
      icono = Icons.settings_input_component;
      color = Colors.purple[300]!;
    } else if (tipo.contains('HFC')) {
      icono = Icons.cable;
      color = Colors.orange[300]!;
    } else {
      icono = Icons.fiber_manual_record;
      color = Colors.orange;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, size: 72, color: color),
            const SizedBox(height: 24),
            Text(
              tipo.isNotEmpty ? 'Orden $tipo detectada' : 'Tecnología no compatible',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withOpacity(0.45)),
              ),
              child: Text(
                mensaje,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color, height: 1.5),
              ),
            ),
            const SizedBox(height: 32),
            _buildBotonActualizar(onPressed: _cargarPotencias),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: _alertRed),
            const SizedBox(height: 20),
            const Text('Error al consultar CTO',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _alertRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _alertRed.withOpacity(0.4)),
              ),
              child: Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: _alertRed, fontSize: 13, height: 1.4)),
            ),
            const SizedBox(height: 24),
            _buildBotonActualizar(onPressed: _cargarPotencias),
          ],
        ),
      ),
    );
  }

  Widget _buildResultado() {
    final puertos = _buildPuertosCombinados();
    final resumen = _resumenPuertos(puertos);

    return Column(
      children: [
        // Botón refrescar: SIEMPRE visible. Mientras actualiza muestra spinner
        // en el ícono y queda deshabilitado para evitar llamadas dobles.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _buildBotonActualizar(
            onPressed: _actualizandoEndpoint ? null : _actualizarEndpoint,
            isLoading: _actualizandoEndpoint,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Imagen del CTO capturada por el scanner (si está disponible)
                if (_imagenCTO != null) _buildImagenCTO(_imagenCTO!),
                _buildHeaderResultado(resumen),
                if (_nyquistError != null) ...[
                  const SizedBox(height: 12),
                  _buildBannerNyquistError(),
                ],
                const SizedBox(height: 14),
                _buildTablaPuertos(puertos),
                const SizedBox(height: 14),
                _buildPieConsulta(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagenCTO(String path) {
    final file = File(path);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(
          file,
          width: double.infinity,
          height: 220,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  // Encabezado con OT, hora y chips de OK/Alerta. Reemplaza al título +
  // pill de orden + bloque de horas viejo.
  Widget _buildHeaderResultado(({int ok, int alerta, int total}) r) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF13283F), Color(0xFF0D1B2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_cyanColor, Color(0xFF0099CC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.bar_chart, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Niveles de Puertos',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.3),
              ),
            ),
          ]),
          if (_ordenTrabajo != null || _accessIdCorto != null) ...[
            const SizedBox(height: 12),
            if (_ordenTrabajo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.work_outline, color: Colors.white54, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'OT  ',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      _ordenTrabajo!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ),
            if (_accessIdCorto != null)
              Row(children: [
                const Icon(Icons.cable, color: _cyanColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  'CTO ',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                Flexible(
                  child: Text(
                    _accessIdCorto!,
                    style: const TextStyle(
                      color: _cyanColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
          ],
          const SizedBox(height: 12),
          Row(children: [
            _ResumenChip(
              icon: Icons.check_circle_outline,
              label: 'OK',
              value: r.ok,
              color: const Color(0xFF22C55E),
            ),
            const SizedBox(width: 8),
            _ResumenChip(
              icon: Icons.warning_amber_rounded,
              label: 'Alerta',
              value: r.alerta,
              color: _alertRed,
            ),
            const SizedBox(width: 8),
            _ResumenChip(
              icon: Icons.power_outlined,
              label: 'Activos',
              value: r.total,
              color: _cyanColor,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildBannerNyquistError() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: const Row(children: [
        Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Medición no disponible. Presiona Actualizar para reintentar.',
            style: TextStyle(color: Colors.orange, fontSize: 12),
          ),
        ),
      ]),
    );
  }

  // ── Tabla de puertos ────────────────────────────────────────────────────────

  List<_PuertoCombinado> _buildPuertosCombinadosFrom(EstadoCTO? estado) {
    final nyquistByNum = <int, PuertoCTO>{};
    for (final p in (estado?.puertos ?? [])) {
      nyquistByNum[p.numero] = p;
    }
    final maxPorts = nyquistByNum.keys.isEmpty
        ? 8
        : nyquistByNum.keys.fold(0, (a, b) => a > b ? a : b);
    return List.generate(maxPorts, (i) {
      final portNum = i + 1;
      final n = nyquistByNum[portNum];
      return _PuertoCombinado(
        numero: portNum,
        rxAnterior: n?.rxBefore,
        rxActual: n?.rxActual,
        activo: n != null && n.activo,
      );
    });
  }

  List<_PuertoCombinado> _buildPuertosCombinados() =>
      _buildPuertosCombinadosFrom(_resultado);

  ({int ok, int alerta, int total}) _resumenPuertos(List<_PuertoCombinado> puertos) {
    var ok = 0, alerta = 0, total = 0;
    for (final p in puertos) {
      if (!p.activo) continue;
      total++;
      if (p.esAlerta) {
        alerta++;
      } else {
        ok++;
      }
    }
    return (ok: ok, alerta: alerta, total: total);
  }

  Widget _buildTablaPuertos(List<_PuertoCombinado> puertos) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0D2137),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
            ),
            child: Row(children: [
              _thCell('Pto', flex: 2),
              _thCell('RX\nAnterior', flex: 3),
              _thCell('RX\nActual', flex: 3),
              _thCell('Δ', flex: 2),
              _thCell('Status', flex: 3),
            ]),
          ),
          ...puertos.asMap().entries.map((entry) =>
              _buildFilaPuerto(entry.value, isLast: entry.key == puertos.length - 1)),
        ],
      ),
    );
  }

  Widget _buildFilaPuerto(_PuertoCombinado p, {required bool isLast}) {
    final esAlerta = p.esAlerta;
    final inactivo = !p.activo;
    final diff = p.diferencia;

    final txtAnt = p.rxAnterior != null ? p.rxAnterior!.toStringAsFixed(2) : '—';
    final txtAct = p.rxActual != null ? p.rxActual!.toStringAsFixed(2) : '—';
    final txtDiff = diff != null ? (diff > 0 ? '+${diff.toStringAsFixed(2)}' : diff.toStringAsFixed(2)) : '—';

    final Color diffColor;
    if (diff == null) {
      diffColor = Colors.white30;
    } else if (diff < -3.0) {
      diffColor = _alertRed;
    } else if (diff.abs() <= 1.5) {
      diffColor = const Color(0xFF22C55E);
    } else {
      diffColor = const Color(0xFFFBBF24);
    }

    return Container(
      decoration: BoxDecoration(
        color: esAlerta ? _alertRed.withOpacity(0.10) : Colors.transparent,
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
        borderRadius: isLast
            ? const BorderRadius.only(bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14))
            : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Row(children: [
        // Badge circular del puerto
        Expanded(
          flex: 2,
          child: Center(
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: esAlerta
                    ? _alertRed
                    : inactivo
                        ? Colors.white.withOpacity(0.06)
                        : const Color(0xFF173656),
                border: Border.all(
                  color: esAlerta
                      ? _alertRed
                      : inactivo
                          ? Colors.white.withOpacity(0.12)
                          : _cyanColor.withOpacity(0.4),
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '${p.numero}',
                style: TextStyle(
                  color: inactivo ? Colors.white38 : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            txtAnt,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.rxAnterior == null ? Colors.white30 : Colors.white70,
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            txtAct,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.rxActual == null ? Colors.white30 : Colors.white,
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            txtDiff,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: diffColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Center(child: _statusPill(esAlerta, inactivo)),
        ),
      ]),
    );
  }

  Widget _statusPill(bool esAlerta, bool inactivo) {
    if (inactivo) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: const Text(
          '— libre —',
          style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4),
        ),
      );
    }
    if (esAlerta) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _alertRed.withOpacity(0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _alertRed.withOpacity(0.55)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, color: _alertRed, size: 12),
            SizedBox(width: 4),
            Text('Alerta', style: TextStyle(color: _alertRed, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.5)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, color: Color(0xFF22C55E), size: 12),
          SizedBox(width: 4),
          Text('OK', style: TextStyle(color: Color(0xFF22C55E), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
        ],
      ),
    );
  }

  Widget _buildPieConsulta([String? horaOverride]) {
    final hora = horaOverride ?? _horaConsulta;
    if (hora == null) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Icon(Icons.access_time, color: Colors.white38, size: 13),
        const SizedBox(width: 6),
        Text(
          'Última consulta: $hora',
          style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _formatHoraAhora() {
    final now = TimeOfDay.now();
    final h = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
    final m = now.minute.toString().padLeft(2, '0');
    final period = now.period == DayPeriod.am ? 'AM' : 'PM';
    return '${h.toString().padLeft(2, '0')}:$m $period';
  }

  /// Aplica el resultado de [NyquistService.resolveOrdenActivaCto] al estado UI.
  void _aplicarOrdenActiva(OrdenActivaCto? activa, {List<OrdenHistorial>? historial}) {
    if (activa == null) {
      _ordenIniciada = null;
      _otActivaResuelta = null;
      _tipoOrdenActiva = null;
      _accessIdIniciadaNyquist = null;
      _resultadoIniciada = null;
      _horaConsultaIniciada = null;
      return;
    }

    OrdenHistorial? iniciada;
    if (historial != null) {
      for (final o in historial) {
        final otMatch = activa.ordenTrabajo.isNotEmpty &&
            o.ordenTrabajo == activa.ordenTrabajo;
        final aidMatch = activa.accessIdPrefijado.isNotEmpty &&
            (o.accessIdPrefijado == activa.accessIdPrefijado ||
                o.accessIdPrefijado.endsWith('-${activa.accessIdCorto}'));
        if (otMatch || aidMatch) {
          iniciada = o;
          break;
        }
      }
    }

    iniciada ??= activa.tieneAccessId || activa.ordenTrabajo.isNotEmpty
        ? activa.toHistorial()
        : null;

    _ordenIniciada = iniciada;
    _otActivaResuelta =
        activa.ordenTrabajo.isNotEmpty ? activa.ordenTrabajo : null;
    _tipoOrdenActiva =
        activa.tipoOrden.isNotEmpty ? activa.tipoOrden : null;
    _accessIdIniciadaNyquist =
        activa.accessIdPrefijado.isNotEmpty ? activa.accessIdPrefijado : null;
    _resultadoIniciada = activa.estado;
    _horaConsultaIniciada =
        activa.tieneEstado ? _formatHoraAhora() : null;
  }

  bool get _hayTrabajoIniciado =>
      _ordenIniciada != null ||
      _otActivaResuelta != null ||
      _accessIdIniciadaNyquist != null ||
      _resultadoIniciada != null;

  String get _otIniciadaDisplay =>
      _ordenIniciada?.ordenTrabajo ??
      _otActivaResuelta ??
      '(sin OT)';

  String get _tipoOrdenIniciadaDisplay =>
      _ordenIniciada?.tipoOrden ??
      _tipoOrdenActiva ??
      '';

  Widget _thCell(String text, {int flex = 1}) => Expanded(
    flex: flex,
    child: Text(text, textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600, height: 1.3)),
  );

  Widget _buildBotonActualizar({required VoidCallback? onPressed, bool isLoading = false}) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.refresh, color: Colors.white),
        label: Text(
          isLoading ? 'Actualizando...' : 'Actualizar',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isLoading ? _cyanColor.withValues(alpha: 0.6) : _cyanColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  // ── Submenú "Revisar Estado CTO" ──────────────────────────────────────

  Widget _buildMenuRevisarEstado() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTarjetaSolida(
                    icono: Icons.play_circle_outline,
                    titulo: 'Orden Iniciada',
                    color: const Color(0xFF1E88E5),
                    onTap: _intentarAbrirOrdenIniciada,
                  ),
                  const SizedBox(height: 24),
                  _buildTarjetaSolida(
                    icono: Icons.checklist_rounded,
                    titulo: 'Órdenes del Día',
                    color: const Color(0xFF10B981),
                    onTap: _cargarFinalizadasView,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _intentarAbrirOrdenIniciada() async {
    final prefs = await SharedPreferences.getInstance();
    final rut = prefs.getString('rut_tecnico') ?? '';
    if (rut.isEmpty) {
      if (!mounted) return;
      _mostrarSinOrdenIniciada();
      return;
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          color: _surfaceColor,
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: _cyanColor),
                SizedBox(height: 16),
                Text(
                  'Verificando orden iniciada…',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    OrdenActivaCto? activa;
    try {
      activa = await _nyquist.resolveOrdenActivaCto(rut);
    } catch (_) {
      activa = null;
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (activa == null) {
      _mostrarSinOrdenIniciada();
      return;
    }

    await _cargarIniciadaView();
  }

  void _mostrarSinOrdenIniciada() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.work_off_outlined, color: Colors.orange, size: 40),
        title: const Text(
          'Sin orden iniciada',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: const Text(
          'No tienes una orden en estado iniciado. '
          'Inicia el trabajo en TOA para revisar el estado de la CTO.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _cargarIniciadaView() async {
    setState(() {
      _vista = _Vista.iniciadaCto;
      _cargandoHistorial = false;
      _historialError = null;
      _resultadoIniciada = null;
      _cargandoIniciada = true;
      _nyquistErrorIniciada = null;
      _tipoRedNoMedibleIniciada = null;
      _horaConsultaIniciada = null;
      _accessIdIniciadaNyquist = null;
      _ordenIniciada = null;
      _otActivaResuelta = null;
      _tipoOrdenActiva = null;
      _estadosHoy = {};
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final rut = prefs.getString('rut_tecnico') ?? '';
      if (rut.isEmpty) {
        if (mounted) setState(() => _cargandoIniciada = false);
        return;
      }

      final results = await Future.wait([
        _nyquist.resolveOrdenActivaCto(rut),
        _nyquist.buscarHistorialPorRut(rut),
      ]);
      if (!mounted) return;

      final activa = results[0] as OrdenActivaCto?;
      final historial = results[1] as List<OrdenHistorial>;

      if (activa == null) {
        setState(() {
          _cargandoIniciada = false;
          _ordenIniciada = null;
        });
        return;
      }

      _aplicarOrdenActiva(activa, historial: historial);

      if (!mounted) return;
      setState(() {
        _cargandoIniciada = false;
        if (!activa.tieneEstado && activa.tieneAccessId) {
          _nyquistErrorIniciada =
              'Orden iniciada detectada. Cargando niveles de la CTO…';
        }
      });

      if (!activa.tieneEstado && activa.tieneAccessId) {
        if (activa.esRedNoNeutra) {
          setState(() {
            _tipoRedNoMedibleIniciada = activa.tipoRedProducto;
            _nyquistErrorIniciada =
                mensajeOrdenSinAccessIdRedNeutra(activa.tipoRedProducto);
          });
        } else {
          final orden = _ordenIniciada ?? activa.toHistorial();
          await _cargarIniciadaPotencias(orden);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _nyquistErrorIniciada = e.toString().replaceFirst('Exception: ', '');
        _cargandoIniciada = false;
      });
    }
  }

  Future<void> _cargarFinalizadasView() async {
    setState(() {
      _vista = _Vista.finalizadasCto;
      _cargandoHistorial = true;
      _historialError = null;
      _historial = [];
      _ordenesPendientes = [];
      _ordenesIniciadas = [];
      _ordenIniciada = null;
      _alertasPorOt.clear();
      _alertasPendientes = 0;
      _estadosHoy = {};
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final rut = prefs.getString('rut_tecnico') ?? '';
      if (rut.isEmpty) {
        if (mounted) setState(() { _cargandoHistorial = false; _historialError = 'No hay RUT registrado.'; });
        return;
      }

      // 1. Buscar órdenes de hoy y ayer en produccion_creaciones (estado, tipo, hora).
      final hoy = DateTime.now();
      final ayer = hoy.subtract(const Duration(days: 1));
      final manana = hoy.add(const Duration(days: 1));
      final ayerStr   = '${ayer.year}-${ayer.month.toString().padLeft(2, '0')}-${ayer.day.toString().padLeft(2, '0')}';
      final mananaStr = '${manana.year}-${manana.month.toString().padLeft(2, '0')}-${manana.day.toString().padLeft(2, '0')}';
      const vno = '02';

      final rutQuery = formatRutForKepler(rut);

      final rawRows = await Supabase.instance.client
          .from('produccion_creaciones')
          .select('orden_trabajo, estado, tipo_orden, hora_inicio, fecha_proceso')
          .eq('rut_tecnico', rutQuery)
          .gte('fecha_proceso', ayerStr)
          .lt('fecha_proceso', mananaStr)
          .order('fecha_proceso', ascending: false);

      if (!mounted) return;

      // 2. Conservar solo la fila con el estado más reciente por OT.
      final vistas = <String>{};
      final ultimoEstadoRows = <dynamic>[];
      for (final r in (rawRows as List)) {
        final ot = r['orden_trabajo']?.toString() ?? '';
        if (ot.isEmpty || vistas.contains(ot)) continue;
        vistas.add(ot);
        ultimoEstadoRows.add(r);
      }

      // 3. Batch-lookup en tabla_access_id para obtener el access_id real de la CTO.
      //    produccion_creaciones.access_id == orden_trabajo (no sirve para Nyquist).
      final todasOTs = ultimoEstadoRows
          .map((r) => r['orden_trabajo']?.toString() ?? '')
          .where((ot) => ot.isNotEmpty)
          .toList();

      final Map<String, String> accessPorOT = {};
      if (todasOTs.isNotEmpty) {
        try {
          final accRows = await Supabase.instance.client
              .from('tabla_access_id')
              .select('orden_trabajo, access_id')
              .inFilter('orden_trabajo', todasOTs)
              .not('access_id', 'is', null)
              .neq('access_id', '')
              .neq('access_id', 'Sin Datos');
          for (final a in (accRows as List)) {
            final ot  = a['orden_trabajo']?.toString() ?? '';
            final aid = a['access_id']?.toString().trim() ?? '';
            if (ot.isNotEmpty && aid.isNotEmpty) accessPorOT[ot] = aid;
          }
          debugPrint('🔍 [CTO] tabla_access_id: ${accessPorOT.length}/${todasOTs.length} OTs con access_id real');
        } catch (e) {
          debugPrint('⚠️ [CTO] Error batch tabla_access_id: $e');
        }
      }

      // 4. Clasificar por último estado (Cancelado excluido).
      bool _esCompletada(dynamic r) =>
          (r['estado']?.toString() ?? '').toLowerCase() == 'completado';
      bool _esIniciada(dynamic r) =>
          (r['estado']?.toString() ?? '').toLowerCase() == 'iniciado';
      bool _esPendiente(dynamic r) {
        final est = (r['estado']?.toString() ?? '').toLowerCase();
        return !_esCompletada(r) && !_esIniciada(r) && est != 'cancelado';
      }

      final completadasRows = ultimoEstadoRows.where(_esCompletada).toList();
      DateTime _instanteIniciada(dynamic r) {
        final fp = DateTime.tryParse(r['fecha_proceso']?.toString() ?? '') ?? hoy;
        final hi = r['hora_inicio']?.toString() ?? '00:00';
        final partes = hi.split(':');
        final horas = int.tryParse(partes.first) ?? 0;
        final mins = partes.length > 1 ? int.tryParse(partes[1]) ?? 0 : 0;
        return DateTime(fp.year, fp.month, fp.day, horas, mins);
      }

      final iniciadasRows = ultimoEstadoRows.where(_esIniciada).toList()
        ..sort((a, b) => _instanteIniciada(b).compareTo(_instanteIniciada(a)));
      final pendientesRows  = ultimoEstadoRows.where(_esPendiente).toList();

      // 5. Construir OrdenHistorial con el access_id real de tabla_access_id.
      OrdenHistorial _toOrden(dynamic r) {
        final ot        = r['orden_trabajo']?.toString() ?? '';
        final accessRaw = accessPorOT[ot] ?? '';
        final accessFull = accessRaw.isNotEmpty ? '$vno-$accessRaw' : '';
        return OrdenHistorial(
          ordenTrabajo:      ot,
          accessIdPrefijado: accessFull,
          tipoOrden:         r['tipo_orden']?.toString() ?? '',
          estado:            r['estado']?.toString() ?? '',
          fechaReferencia:   hoy,
          horaInicio:        hoy,
          horaTermino:       null,
        );
      }

      final completadas = completadasRows.map(_toOrden).toList();
      var iniciadas   = iniciadasRows.map(_toOrden).toList();
      final pendientes  = pendientesRows.map(_toOrden).toList();

      // 6. Complementar iniciadas con TOA Kepler (fuente de verdad en tiempo real).
      final toaIniciada = await _nyquist.fetchOrdenIniciadaDesdeToa(rut);
      if (toaIniciada != null) {
        final otToa = toaIniciada['orden_trabajo'] ?? '';
        if (otToa.isNotEmpty && !iniciadas.any((o) => o.ordenTrabajo == otToa)) {
          var accessRaw = accessPorOT[otToa] ?? '';
          if (accessRaw.isEmpty) {
            accessRaw = await _nyquist.buscarAccessIdEnTablaAccesId(otToa) ?? '';
            if (accessRaw.isNotEmpty) accessPorOT[otToa] = accessRaw;
          }
          final accessFull =
              accessRaw.isNotEmpty ? '$vno-$accessRaw' : '';
          iniciadas = [
            OrdenHistorial(
              ordenTrabajo: otToa,
              accessIdPrefijado: accessFull,
              tipoOrden: toaIniciada['tipo_orden'] ?? '',
              estado: 'Iniciado',
              fechaReferencia: hoy,
              horaInicio: hoy,
            ),
            ...iniciadas,
          ];
          debugPrint('🔍 [CTO] iniciada TOA agregada: $otToa');
        }
      }

      setState(() {
        _historial         = completadas;
        _ordenesIniciadas  = iniciadas;
        _ordenesPendientes = pendientes;
        _cargandoHistorial = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _cargandoHistorial = false; _historialError = 'Error: $e'; });
    }
  }

  // ── Vista revisarEstado (combinada, se mantiene para compatibilidad interna) ─

  Widget _buildRevisarEstado() {
    if (_cargandoHistorial) return _buildCargando();
    if (_historialError != null) return _buildHistorialError(_historialError!);

    return RefreshIndicator(
      color: _cyanColor,
      backgroundColor: _surfaceColor,
      onRefresh: _cargarRevisarEstado,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildSeccionIniciada(),
          const SizedBox(height: 24),
          _buildSeccionCompletados(),
        ],
      ),
    );
  }

  // ── Vistas individuales ────────────────────────────────────────────────

  Widget _buildIniciadaView() {
    if (_cargandoIniciada) return _buildCargando();
    if (!_hayTrabajoIniciado) return _buildSinOrdenIniciadaPantalla();
    return RefreshIndicator(
      color: _cyanColor,
      backgroundColor: _surfaceColor,
      onRefresh: _cargarIniciadaView,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [_buildSeccionIniciada()],
      ),
    );
  }

  Widget _buildFinalizadasView() {
    if (_cargandoHistorial) return _buildCargando();
    if (_historialError != null) return _buildHistorialError(_historialError!);
    return RefreshIndicator(
      color: _cyanColor,
      backgroundColor: _surfaceColor,
      onRefresh: _cargarFinalizadasView,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildSeccionCompletados(),
          const SizedBox(height: 24),
          _buildSeccionIniciadas(),
        ],
      ),
    );
  }

  Widget _buildSeccionIniciadas() {
    final iniciadas = _ordenesIniciadas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              const Text(
                'Iniciadas',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E88E5).withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${iniciadas.length}',
                  style: const TextStyle(
                    color: Color(0xFF1E88E5),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (iniciadas.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: const Text(
              'No hay órdenes iniciadas.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          )
        else
          ...iniciadas.map((o) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _filaOrdenDelDia(o, grupo: _GrupoOrden.iniciada),
              )),
      ],
    );
  }

  Widget _buildSeccionPendientes() {
    final pendientes = _ordenesPendientes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              const Text(
                'Pendientes',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${pendientes.length}',
                  style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (pendientes.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: const Text(
              'No hay órdenes pendientes de iniciar.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          )
        else
          ...pendientes.map((o) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _filaOrdenDelDia(o, grupo: _GrupoOrden.pendiente),
              )),
      ],
    );
  }

  // ── Sección superior: potencias del trabajo iniciado ──────────────────

  Widget _buildSeccionIniciada() {
    if (!_hayTrabajoIniciado) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline, color: Colors.white54, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sin orden iniciada.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
          ),
        ]),
      );
    }

    final puertos = _buildPuertosCombinadosFrom(_resultadoIniciada);
    final resumen = _resumenPuertos(puertos);
    final accessDisplay = _accessIdIniciadaNyquist
            ?.replaceFirst(RegExp(r'^\d{1,2}-'), '') ??
        _ordenIniciada?.accessIdPrefijado.replaceFirst(RegExp(r'^\d{1,2}-'), '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cabecera azul: OT iniciada
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: const Color(0xFF1E88E5).withValues(alpha: 0.30), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Row(children: [
            const Icon(Icons.play_circle_filled, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('TRABAJO INICIADO',
                    style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                const SizedBox(height: 2),
                Text(
                  _otIniciadaDisplay,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                ),
                if (_tipoOrdenIniciadaDisplay.isNotEmpty)
                  Text(_tipoOrdenIniciadaDisplay, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                if (accessDisplay != null && accessDisplay.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.cable, color: Colors.white54, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      accessDisplay,
                      style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        if (_tipoRedNoMedibleIniciada == null)
          _buildBotonActualizar(
            onPressed: _actualizandoIniciada ? null : _actualizarIniciadaPotencias,
            isLoading: _actualizandoIniciada,
          ),
        if (_tipoRedNoMedibleIniciada == null) const SizedBox(height: 10),
        // Contenido: loading / error / tabla
        if (_cargandoIniciada)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator(color: _cyanColor, strokeWidth: 2)),
          )
        else if (_tipoRedNoMedibleIniciada != null)
          _buildAvisoRedNoNeutra(_tipoRedNoMedibleIniciada!)
        else if (_nyquistErrorIniciada != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withOpacity(0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(_nyquistErrorIniciada!, style: const TextStyle(color: Colors.orange, fontSize: 12))),
            ]),
          )
        else ...[
          Row(children: [
            _ResumenChip(icon: Icons.check_circle_outline, label: 'OK',     value: resumen.ok,    color: const Color(0xFF22C55E)),
            const SizedBox(width: 8),
            _ResumenChip(icon: Icons.warning_amber_rounded, label: 'Alerta', value: resumen.alerta, color: _alertRed),
            const SizedBox(width: 8),
            _ResumenChip(icon: Icons.power_outlined,        label: 'Activos', value: resumen.total,  color: _cyanColor),
          ]),
          const SizedBox(height: 10),
          _buildTablaPuertos(puertos),
          const SizedBox(height: 8),
          _buildPieConsulta(_horaConsultaIniciada),
        ],
      ],
    );
  }

  // ── Sección inferior: completados del día ─────────────────────────────

  Widget _buildSeccionCompletados() {
    // _historial ya viene filtrado a completadas desde _cargarFinalizadasView()
    final completados = _historial;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              const Text(
                'Tu día',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _cyanColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${completados.length}',
                  style: const TextStyle(color: _cyanColor, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
              const Spacer(),
              if (_alertasPendientes > 0) ...[
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: _cyanColor)),
                const SizedBox(width: 6),
                const Text('Verificando…', style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...completados.map((o) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _filaOrdenDelDia(o, grupo: _GrupoOrden.completada),
            )),
        if (completados.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: const Text(
              'No hay órdenes completadas aún hoy.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _buildHistorialError(String msg) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 56),
            const SizedBox(height: 12),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _cargarRevisarEstado,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _cyanColor,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaOrdenDelDia(OrdenHistorial o, {required _GrupoOrden grupo}) {
    final canTap = o.tieneAccessId;
    final enAlerta = _alertasPorOt[o.ordenTrabajo] == true;

    final Color puntoColor;
    final Color fondoColor;
    final Color bordeColor;
    final Widget estadoChip;

    if (grupo == _GrupoOrden.iniciada) {
      puntoColor = const Color(0xFF1E88E5);
      fondoColor = const Color(0xFF1E88E5).withValues(alpha: 0.07);
      bordeColor = const Color(0xFF1E88E5).withValues(alpha: 0.30);
      estadoChip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF1E88E5).withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF1E88E5).withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_circle_outline, color: Color(0xFF1E88E5), size: 11),
            const SizedBox(width: 4),
            Text(
              o.estado.isEmpty ? 'Iniciado' : o.estado,
              style: const TextStyle(
                color: Color(0xFF1E88E5),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      );
    } else if (grupo == _GrupoOrden.pendiente) {
      puntoColor = const Color(0xFFF59E0B);
      fondoColor = const Color(0xFFF59E0B).withValues(alpha: 0.07);
      bordeColor = const Color(0xFFF59E0B).withValues(alpha: 0.30);
      estadoChip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule_rounded, color: Color(0xFFF59E0B), size: 11),
            const SizedBox(width: 4),
            Text(
              o.estado.isEmpty ? 'Pendiente' : o.estado,
              style: const TextStyle(
                color: Color(0xFFF59E0B),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      );
    } else if (enAlerta) {
      puntoColor = _alertRed;
      fondoColor = _alertRed.withValues(alpha: 0.10);
      bordeColor = _alertRed.withValues(alpha: 0.55);
      estadoChip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _alertRed.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _alertRed.withValues(alpha: 0.6)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, color: _alertRed, size: 11),
            SizedBox(width: 4),
            Text(
              'Alerta',
              style: TextStyle(
                color: _alertRed,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      );
    } else {
      puntoColor = const Color(0xFF10B981);
      fondoColor = const Color(0xFF10B981).withValues(alpha: 0.07);
      bordeColor = const Color(0xFF10B981).withValues(alpha: 0.30);
      estadoChip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.55)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 11),
            SizedBox(width: 4),
            Text(
              'Completada',
              style: TextStyle(
                color: Color(0xFF10B981),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canTap ? () => _consultarHistorial(o) : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: fondoColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: bordeColor, width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: puntoColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            o.ordenTrabajo.isEmpty ? '(sin OT)' : o.ordenTrabajo,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        estadoChip,
                      ],
                    ),
                    if (o.tipoOrden.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        o.tipoOrden,
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                    if (!canTap)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'SIN POSIBILIDAD DE CONSULTA ORDEN FTTH',
                          style: TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (canTap)
                const Icon(Icons.chevron_right, color: Colors.white38, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filaOrden(OrdenHistorial o) {
    final canTap = o.tieneAccessId;
    final enAlerta = _alertasPorOt[o.ordenTrabajo] == true;

    final fondo = enAlerta
        ? _alertRed.withValues(alpha: 0.10)
        : const Color(0xFF1A2332);
    final borde = enAlerta
        ? _alertRed.withValues(alpha: 0.55)
        : Colors.white10;
    final estadoLower = o.estado.toLowerCase();
    Color puntoColor = enAlerta ? _alertRed : Colors.white54;
    if (!enAlerta) {
      if (estadoLower == 'iniciado') puntoColor = const Color(0xFF1E88E5);
      else if (estadoLower == 'finalizado' || estadoLower == 'terminado') puntoColor = const Color(0xFF10B981);
      else if (estadoLower == 'cancelado') puntoColor = const Color(0xFFEF4444);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canTap ? () => _consultarHistorial(o) : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: fondo,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borde, width: enAlerta ? 1.4 : 1),
            boxShadow: enAlerta
                ? [
                    BoxShadow(
                      color: _alertRed.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: puntoColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            o.ordenTrabajo.isEmpty ? '(sin OT)' : o.ordenTrabajo,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        if (enAlerta)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _alertRed.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _alertRed.withValues(alpha: 0.6)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warning_amber_rounded, color: _alertRed, size: 12),
                                SizedBox(width: 4),
                                Text(
                                  'Alerta',
                                  style: TextStyle(
                                    color: _alertRed,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (o.tipoOrden.isNotEmpty || o.estado.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (o.tipoOrden.isNotEmpty) o.tipoOrden,
                          if (o.estado.isNotEmpty) o.estado,
                        ].join(' · '),
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                    if (!canTap)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Sin access_id, imposible leer potencias.',
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (canTap)
                const Icon(Icons.chevron_right, color: Colors.white38, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

enum _GrupoOrden { iniciada, pendiente, completada }

class _ResumenChip extends StatelessWidget {
  const _ResumenChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.85),
                fontWeight: FontWeight.w700,
                fontSize: 10,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
