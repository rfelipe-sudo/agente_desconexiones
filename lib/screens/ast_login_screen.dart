import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agente_desconexiones/services/creavox_api_service.dart';
import 'package:agente_desconexiones/services/creavox_session_service.dart';
import 'ast_workflow_screen.dart';

const _bg      = Color(0xFF0A1628);
const _surface = Color(0xFF0D1B2A);
const _primary = Color(0xFF2196F3);
const _accent  = Color(0xFF00D9FF);
const _border  = Color(0xFF1E3A5F);
const _textDim = Color(0xFF8FA8C8);

class AstLoginScreen extends StatefulWidget {
  const AstLoginScreen({super.key});

  @override
  State<AstLoginScreen> createState() => _AstLoginScreenState();
}

class _AstLoginScreenState extends State<AstLoginScreen> {
  final _formKey       = GlobalKey<FormState>();
  final _rutController = TextEditingController();
  final _api           = CreavoxApiService();
  final _session       = CreavoxSessionService();

  bool    _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _verificarSesionYAutoLogin();
  }

  Future<void> _verificarSesionYAutoLogin() async {
    await _session.inicializar();

    // Si ya tiene sesión creavox activa, ir directo al workflow
    if (_session.isLoggedIn() && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AstWorkflowScreen()),
      );
      return;
    }

    // Obtener RUT registrado en la app → auto-login sin contraseña
    final prefs = await SharedPreferences.getInstance();
    final rut = prefs.getString('rut_tecnico') ??
                prefs.getString('user_rut') ?? '';

    if (rut.isNotEmpty) {
      _rutController.text = rut;
      await _login(rut);
    }
  }

  Future<void> _login([String? rutOverride]) async {
    final rut = (rutOverride ?? _rutController.text).trim();
    if (rut.isEmpty) return;

    if (!mounted) return;
    setState(() { _loading = true; _error = null; });

    try {
      final tecnico = await _api.loginTecnico(rut);
      if (tecnico == null) {
        if (mounted) setState(() => _error = 'RUT no encontrado o sin acceso');
        return;
      }

      await _session.iniciarSesion(tecnico);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AstWorkflowScreen()),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error al conectar con el servidor');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _rutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'AST — Iniciar sesión',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [_primary, _accent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.assignment_turned_in_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 32),

                  const Text(
                    'Bienvenido al AST',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Análisis de Seguridad en el Trabajo',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _textDim, fontSize: 13),
                  ),
                  const SizedBox(height: 40),

                  if (_loading) ...[
                    const Center(
                      child: CircularProgressIndicator(color: _accent),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Iniciando sesión…',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _textDim, fontSize: 13),
                    ),
                  ] else ...[
                    // RUT (fallback manual si no se detectó automáticamente)
                    TextFormField(
                      controller: _rutController,
                      enabled: !_loading,
                      keyboardType: TextInputType.text,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'RUT',
                        labelStyle: const TextStyle(color: _textDim),
                        hintText: '12.345.678-9',
                        hintStyle: TextStyle(
                            color: _textDim.withValues(alpha: 0.5)),
                        prefixIcon:
                            const Icon(Icons.person, color: _accent),
                        filled: true,
                        fillColor: _surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _accent),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Ingresa tu RUT' : null,
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : () => _login(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _border,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Continuar',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
