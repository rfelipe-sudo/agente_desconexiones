import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/constants/app_constants.dart';
import 'package:agente_desconexiones/providers/auth_provider.dart';
import 'package:agente_desconexiones/utils/device_helper.dart';
import 'package:agente_desconexiones/utils/rut_helper.dart';
import 'package:agente_desconexiones/utils/session_manager.dart';
import 'package:agente_desconexiones/widgets/creabox_wordmark.dart';
import 'package:agente_desconexiones/services/tecnico_service.dart';

/// Primera instalación: identificar técnico por RUT antes de registrar el dispositivo.
class RegistroRutScreen extends StatefulWidget {
  const RegistroRutScreen({super.key});

  @override
  State<RegistroRutScreen> createState() => _RegistroRutScreenState();
}

class _RegistroRutScreenState extends State<RegistroRutScreen> {
  final TextEditingController _rutController = TextEditingController();
  bool _validando = false;
  bool _confirmando = false;
  Map<String, dynamic>? _validacion;
  String? _errorText;

  @override
  void dispose() {
    _rutController.dispose();
    super.dispose();
  }

  void _onRutChanged(String value) {
    final clean = value.replaceAll(RegExp(r'[^0-9kK]'), '').toUpperCase();
    if (clean.length <= 1) {
      if (_rutController.text != clean) {
        _rutController.value = TextEditingValue(
          text: clean,
          selection: TextSelection.collapsed(offset: clean.length),
        );
      }
      return;
    }
    final body = clean.substring(0, clean.length - 1);
    final dv = clean.substring(clean.length - 1);
    if (body.length > 8) return;
    final limpio = '$body-$dv';
    final formatted = RutHelper.formatear(limpio);
    if (_rutController.text != formatted) {
      _rutController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  Future<void> _verificarRut() async {
    setState(() {
      _errorText = null;
      _validacion = null;
    });

    final limpio = RutHelper.limpiar(_rutController.text);
    if (limpio.isEmpty) {
      setState(() => _errorText = 'Ingresa tu RUT');
      return;
    }
    if (!RutHelper.validar(limpio)) {
      setState(() => _errorText = 'RUT inválido (revisa el dígito verificador)');
      return;
    }

    setState(() => _validando = true);
    try {
      final data = await validarRutTecnicoSupabase(limpio);
      if (!mounted) return;

      if (data == null) {
        setState(() {
          _validando = false;
          _errorText = 'No se pudo validar. Revisa tu conexión.';
        });
        return;
      }
      final existe = data['existe'] == true;
      if (!existe) {
        setState(() {
          _validando = false;
          _validacion = null;
          _errorText =
              'RUT no encontrado en el sistema CREA. Contacta a tu coordinador.';
        });
        return;
      }

      final conflicto = await comprobarConflictoDispositivoRut(limpio);
      if (!mounted) return;
      if (conflicto != null) {
        setState(() {
          _validando = false;
          _validacion = null;
          _errorText = conflicto;
        });
        return;
      }

      setState(() {
        _validando = false;
        _validacion = Map<String, dynamic>.from(data);
        _errorText = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _validando = false;
          _errorText = 'Error: $e';
        });
      }
    }
  }

  Future<void> _confirmarYContinuar() async {
    final data = _validacion;
    if (data == null || data['existe'] != true) return;

    final limpio = RutHelper.limpiar(_rutController.text);
    final nombreTecnico = data['nombre']?.toString() ?? '';

    setState(() => _confirmando = true);
    try {
      final conflicto = await comprobarConflictoDispositivoRut(limpio);
      if (!mounted) return;
      if (conflicto != null) {
        setState(() {
          _confirmando = false;
          _errorText = conflicto;
        });
        return;
      }

      final supabase = Supabase.instance.client;

      final raw = await rpcVerificarDispositivo(
        supabase,
        rutTecnico: limpio,
        nombreTecnico: nombreTecnico.isNotEmpty ? nombreTecnico : null,
      );

      final row = _parseRpcPrimeraFila(raw);
      print('[RegistroRut] resultado: $row');

      if (!mounted) return;

      if (row == null) {
        setState(() => _confirmando = false);
        setState(() => _errorText =
            'No se pudo registrar el dispositivo. Intenta de nuevo.');
        return;
      }

      final prefs = await SharedPreferences.getInstance();

      final rutFinal = row['rut_tecnico']?.toString() ?? limpio;
      final rawNombre = row['nombre_tecnico']?.toString() ?? '';
      final nombreFinal =
          rawNombre.trim().isNotEmpty ? rawNombre : nombreTecnico;

      await prefs.remove('user_nombre');
      await prefs.remove('rut_tecnico');
      await prefs.remove('user_rut');
      await prefs.remove('tipo_personal');
      await prefs.remove('user_rol');
      await prefs.remove('nombre_supervisor');
      await prefs.remove('rut_supervisor');
      await prefs.remove('nombre_tecnico');
      await prefs.remove(AppConstants.storageKeyUsuario);

      // Evita que el mock legacy `tecnico_registrado` deje un nombre distinto al RUT nuevo.
      await TecnicoService.limpiarRegistro();

      await prefs.setString('rut_tecnico', rutFinal);
      await prefs.setString('user_rut', rutFinal);
      await prefs.setString('user_nombre', nombreFinal);
      await prefs.setString('nombre_tecnico', nombreFinal);
      await prefs.setString(
        'tipo_personal',
        row['tipo_personal']?.toString() ??
            data['tipo_personal']?.toString() ??
            '',
      );
      await prefs.setString('user_rol', 'tecnico');

      await SessionManager.marcarNombreGuardadoParaRut(rutFinal);

      print('[RegistroRut] Guardado: $rutFinal → $nombreFinal');

      if (mounted) {
        await context.read<AuthProvider>().syncUsuarioDesdePrefs();
      }

      Navigator.of(context).pushReplacementNamed(
        '/dispositivo_bloqueado',
        arguments: <String, String>{
          'estado': row['estado']?.toString() ?? 'pendiente',
          'mensaje': row['mensaje']?.toString() ??
              'Tu dispositivo fue registrado. Espera que el coordinador '
                  'lo autorice para ingresar a CREABOX.',
        },
      );
    } catch (e, st) {
      print('[RegistroRut] ERROR: $e');
      print(st);
      if (mounted) {
        setState(() {
          _errorText = 'Error al registrar. Verifica tu conexión.';
          _confirmando = false;
        });
      }
    }
  }

  bool get _puedeConfirmar {
    final d = _validacion;
    if (d == null || d['existe'] != true) return false;
    return !_confirmando;
  }

  @override
  Widget build(BuildContext context) {
    final vigente = _validacion?['es_vigente'] == true;
    final nombre = _validacion?['nombre']?.toString() ?? '';
    final tipo = _validacion?['tipo_personal']?.toString() ?? '';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                const Center(
                  child: CreaboxWordmark(fontSize: 40, letterSpacing: 4),
                ),
                const SizedBox(height: 36),
                const Text(
                  'Bienvenido a CREABOX',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ingresa tu RUT para continuar',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _rutController,
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  decoration: InputDecoration(
                    labelText: 'RUT',
                    labelStyle: TextStyle(color: Colors.grey[500]),
                    hintText: '12.345.678-9',
                    hintStyle: TextStyle(color: Colors.grey[700]),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[700]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF38BDF8)),
                    ),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9kK.\-]')),
                  ],
                  onChanged: _onRutChanged,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _validando ? null : _verificarRut,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0EA5E9),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _validando
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Verificar RUT'),
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorText!,
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ],
                if (_validacion != null && _validacion!['existe'] == true) ...[
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: vigente
                          ? const Color(0xFF14532D).withValues(alpha: 0.5)
                          : const Color(0xFF713F12).withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: vigente
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEAB308),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: vigente
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFEAB308),
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                nombre.isNotEmpty ? nombre : 'Nombre no disponible',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${tipo.isNotEmpty ? tipo : '—'} · ${vigente ? 'Vigente' : 'No vigente'}',
                          style: TextStyle(
                            color: vigente
                                ? const Color(0xFF86EFAC)
                                : const Color(0xFFFDE047),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: _puedeConfirmar ? _confirmarYContinuar : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF38BDF8),
                      side: const BorderSide(color: Color(0xFF38BDF8)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _confirmando
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Confirmar y continuar'),
                  ),
                ],
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Primera fila del resultado de `verificar_dispositivo` (lista o mapa).
Map<String, dynamic>? _parseRpcPrimeraFila(dynamic res) {
  if (res == null) return null;
  if (res is List) {
    if (res.isEmpty) return null;
    final f = res.first;
    if (f is Map<String, dynamic>) return Map<String, dynamic>.from(f);
    if (f is Map) return Map<String, dynamic>.from(f);
    return null;
  }
  if (res is Map<String, dynamic>) return Map<String, dynamic>.from(res);
  if (res is Map) return Map<String, dynamic>.from(res);
  return null;
}
