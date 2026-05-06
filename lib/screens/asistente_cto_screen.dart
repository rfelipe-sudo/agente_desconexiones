import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
enum _Vista { inicio, historial, potencias }

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

  // ── Estado de la vista historial ───────────────────────────────────────
  List<OrdenHistorial> _historial = [];
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
      await _ctoChannel.invokeMethod('openCtoScan', {'rut': rut});
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir escáner CTO: ${e.message}'),
            backgroundColor: _alertRed,
          ),
        );
      }
    }
  }

  // ── Vista historial: lista de OTs últimos 30 días + iniciada ──────────

  Future<void> _cargarHistorial() async {
    setState(() {
      _vista = _Vista.historial;
      _cargandoHistorial = true;
      _historialError = null;
      _historial = [];
      _ordenIniciada = null;
      _vinoDelHistorial = false;
      _alertasPorOt.clear();
      _alertasPendientes = 0;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final rut = prefs.getString('rut_tecnico') ?? '';
      if (rut.isEmpty) {
        if (mounted) {
          setState(() {
            _cargandoHistorial = false;
            _historialError = 'No hay RUT registrado en la sesión.';
          });
        }
        return;
      }
      final lista = await _nyquist.buscarHistorialPorRut(rut);
      if (!mounted) return;

      // Filtrado a HOY (comparación por año/mes/día contra fechaReferencia).
      final hoy = DateTime.now();
      bool esHoy(DateTime d) =>
          d.year == hoy.year && d.month == hoy.month && d.day == hoy.day;
      final hoyOnly = lista.where((o) => esHoy(o.fechaReferencia)).toList();
      debugPrint('🔍 [AsistenteCTO] hoy=${hoy.year}-${hoy.month.toString().padLeft(2, "0")}-${hoy.day.toString().padLeft(2, "0")} | recibidas=${lista.length} | matchHoy=${hoyOnly.length}');
      for (final o in lista.take(5)) {
        final f = o.fechaReferencia;
        debugPrint('  → OT=${o.ordenTrabajo} | fechaRef=${f.year}-${f.month.toString().padLeft(2, "0")}-${f.day.toString().padLeft(2, "0")} | esHoy=${esHoy(f)}');
      }

      // "Trabajo iniciado": primero en hoy; si no hay, buscamos en toda la
      // lista por si arrastra de ayer.
      OrdenHistorial? iniciada;
      for (final o in hoyOnly) {
        if (o.esIniciada) { iniciada = o; break; }
      }
      if (iniciada == null) {
        for (final o in lista) {
          if (o.esIniciada) { iniciada = o; break; }
        }
      }

      setState(() {
        _historial = hoyOnly;
        _ordenIniciada = iniciada;
        _cargandoHistorial = false;
      });

      _evaluarAlertasHistorial(hoyOnly);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoHistorial = false;
        _historialError = 'Error al cargar el historial: $e';
      });
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
      _accessIdCorto = orden.ordenTrabajo.isNotEmpty
          ? orden.ordenTrabajo
          : orden.accessIdPrefijado.replaceFirst(RegExp(r'^\d{1,2}-'), '');
    });

    try {
      final r = await _nyquist.consultarEstado(orden.accessIdPrefijado);
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
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final rut = prefs.getString('rut_tecnico') ?? '';

      if (rut.isEmpty) {
        setState(() { _cargando = false; _error = 'sin_trabajo'; });
        return;
      }

      debugPrint('🔍 [AsistenteCTO] get_pelo_db para RUT: $rut');
      KeplerActiveOrder? activa;
      try {
        activa = await _nyquist.fetchActiveOrderFromKepler(rut);
      } catch (e) {
        if (mounted) setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _cargando = false;
        });
        return;
      }
      if (activa == null) {
        setState(() { _cargando = false; _error = 'sin_trabajo'; });
        return;
      }

      _accessIdNyquist = activa.accessIdPrefijado;
      _accessIdCorto = activa.accessIdCorto.isNotEmpty
          ? activa.accessIdCorto
          : activa.accessIdPrefijado.replaceFirst(RegExp(r'^\d{1,2}-'), '');

      if (mounted) {
        setState(() {
          _resultado = activa!.estado;
          _horaConsulta = _formatHoraAhora();
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
      // Si la vista vino del historial, refrescamos contra Nyquist (esa
      // OT puede no ser la "activa" del técnico). En cualquier otro caso,
      // re-consultamos Kepler para mantener la numeración física.
      if (_vinoDelHistorial && _accessIdNyquist != null) {
        final r = await _nyquist.consultarEstado(_accessIdNyquist!);
        if (mounted) {
          setState(() {
            _resultado = r;
            _horaConsulta = _formatHoraAhora();
            _actualizandoEndpoint = false;
          });
        }
      } else {
        final prefs = await SharedPreferences.getInstance();
        final rut = prefs.getString('rut_tecnico') ?? '';
        if (rut.isEmpty) {
          if (mounted) setState(() => _actualizandoEndpoint = false);
          return;
        }
        final activa = await _nyquist.fetchActiveOrderFromKepler(rut);
        if (mounted) {
          setState(() {
            if (activa != null) {
              _resultado = activa.estado;
              _accessIdNyquist = activa.accessIdPrefijado;
              _accessIdCorto = activa.accessIdCorto;
              _horaConsulta = _formatHoraAhora();
            }
            _actualizandoEndpoint = false;
          });
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
                  _vista = _Vista.historial;
                  _error = null;
                  _resultado = null;
                  _nyquistError = null;
                });
              } else {
                setState(() { _vista = _Vista.inicio; _error = null; });
              }
            } else if (_vista == _Vista.historial) {
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
        _Vista.inicio => _buildInicio(),
        _Vista.historial => _buildHistorial(),
        _Vista.potencias => _buildPotencias(),
      },
    );
  }

  IconData _iconoTitulo() {
    switch (_vista) {
      case _Vista.inicio:
        return Icons.router;
      case _Vista.historial:
        return Icons.history;
      case _Vista.potencias:
        return Icons.bar_chart;
    }
  }

  String _tituloVista() {
    switch (_vista) {
      case _Vista.inicio:
        return 'Asistente de CTO';
      case _Vista.historial:
        return 'Estado CTO';
      case _Vista.potencias:
        return 'Potencias CTO';
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
                    onTap: _cargarHistorial,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.work_off_outlined, size: 72, color: Colors.white30),
            const SizedBox(height: 24),
            const Text('Sin trabajo activo',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 12),
            const Text(
              'No se encontró ninguna orden en estado "Iniciado".\nEl Asistente CTO requiere una orden activa.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.white54, height: 1.5),
            ),
            const SizedBox(height: 32),
            _buildBotonActualizar(onPressed: _cargarPotencias),
          ],
        ),
      ),
    );
  }

  Widget _buildTecnologiaIncompatible() {
    final tipo = _tipoRedError ?? '';
    final String mensaje;
    final IconData icono;
    final Color color;

    if (tipo.contains('FTTH')) {
      mensaje = 'ORDEN FTTH\nSOLO PUEDO MEDIR RED NEUTRA';
      icono = Icons.settings_input_component;
      color = Colors.purple[300]!;
    } else if (tipo.contains('HFC')) {
      mensaje = 'ORDEN HFC\nSOLO PUEDO MEDIR RED NEUTRA';
      icono = Icons.cable;
      color = Colors.orange[300]!;
    } else {
      mensaje = 'Este trabajo pertenece a una tecnología\ndiferente a NFTT';
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _actualizandoEndpoint
              ? const SizedBox(height: 48, child: Center(child: CircularProgressIndicator(color: _cyanColor)))
              : _buildBotonActualizar(onPressed: _actualizarEndpoint),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
          if (_accessIdCorto != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.cable, color: _cyanColor, size: 14),
              const SizedBox(width: 6),
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

  /// Construye 8 filas de puertos. Ambos valores (anterior y actual)
  /// vienen del mismo response Nyquist (`u_cto_portN_rx_before/_actual`).
  List<_PuertoCombinado> _buildPuertosCombinados() {
    final nyquistByNum = <int, PuertoCTO>{};
    for (final p in (_resultado?.puertos ?? [])) {
      nyquistByNum[p.numero] = p;
    }

    return List.generate(8, (i) {
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

  /// Pie minimal: solo el timestamp de la consulta a Nyquist.
  Widget _buildPieConsulta() {
    if (_horaConsulta == null) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Icon(Icons.access_time, color: Colors.white38, size: 13),
        const SizedBox(width: 6),
        Text(
          'Última consulta: ${_horaConsulta!}',
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

  Widget _thCell(String text, {int flex = 1}) => Expanded(
    flex: flex,
    child: Text(text, textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600, height: 1.3)),
  );

  Widget _buildBotonActualizar({required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.refresh, color: Colors.white),
        label: const Text('Actualizar', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _cyanColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  // ── Vista historial ────────────────────────────────────────────────────

  Widget _buildHistorial() {
    if (_cargandoHistorial) return _buildCargando();
    if (_historialError != null) {
      return _buildHistorialError(_historialError!);
    }
    return RefreshIndicator(
      color: _cyanColor,
      backgroundColor: _surfaceColor,
      onRefresh: _cargarHistorial,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _cardIniciada(),
          const SizedBox(height: 22),
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
                    '${_historial.length}',
                    style: const TextStyle(
                      color: _cyanColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Spacer(),
                if (_alertasPendientes > 0) ...[
                  const SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: _cyanColor),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Verificando alertas…',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          ..._historial.map((o) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _filaOrden(o),
              )),
          if (_historial.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surfaceColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: const Text(
                'No hay órdenes para hoy.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
        ],
      ),
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
              onPressed: _cargarHistorial,
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

  Widget _cardIniciada() {
    final iniciada = _ordenIniciada;
    if (iniciada == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: const [
            Icon(Icons.info_outline, color: Colors.white54, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No tienes trabajos iniciados.\nElige una OT del historial para consultar potencias.',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }
    final enAlerta = _alertasPorOt[iniciada.ordenTrabajo] == true;
    final coloresGradient = enAlerta
        ? const [Color(0xFFB91C1C), Color(0xFF7F1D1D)]
        : const [Color(0xFF1E88E5), Color(0xFF1565C0)];
    final colorSombra = enAlerta
        ? const Color(0xFFB91C1C)
        : const Color(0xFF1E88E5);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: iniciada.tieneAccessId
            ? () => _cargarPotencias(desdeHistorial: true)
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sin access_id, imposible leer potencias.')),
                );
              },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: coloresGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: colorSombra.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                enAlerta ? Icons.warning_amber_rounded : Icons.play_circle_filled,
                color: Colors.white,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      enAlerta ? 'TRABAJO INICIADO · ALERTA' : 'TRABAJO INICIADO',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      iniciada.ordenTrabajo.isEmpty ? '(sin OT)' : iniciada.ordenTrabajo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (iniciada.tipoOrden.isNotEmpty)
                      Text(
                        iniciada.tipoOrden,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white, size: 28),
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
