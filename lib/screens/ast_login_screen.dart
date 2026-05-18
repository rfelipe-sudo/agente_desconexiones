import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agente_desconexiones/services/creavox_api_service.dart';
import 'package:agente_desconexiones/services/creavox_session_service.dart';
import 'ast_workflow_screen.dart';

const _bg = Color(0xFF0A1628);
const _surface = Color(0xFF0D1B2A);
const _primary = Color(0xFF2196F3);
const _accent = Color(0xFF00D9FF);
const _border = Color(0xFF1E3A5F);
const _textDim = Color(0xFF8FA8C8);

class AstLoginScreen extends StatefulWidget {
  const AstLoginScreen({super.key});

  @override
  State<AstLoginScreen> createState() => _AstLoginScreenState();
}

class _AstLoginScreenState extends State<AstLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _rutController = TextEditingController();
  final _passController = TextEditingController();
  final _api = CreavoxApiService();
  final _session = CreavoxSessionService();

  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _verificarSesionYPrellenar();
  }

  Future<void> _verificarSesionYPrellenar() async {
    await _session.inicializar();

    // Si ya tiene sesión creavox activa, ir directo al workflow
    if (_session.isLoggedIn() && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AstWorkflowScreen()),
      );
      return;
    }

    // Pre-llenar RUT desde la sesión principal de la app
    final prefs = await SharedPreferences.getInstance();
    final rut = prefs.getString('rut_tecnico') ?? prefs.getString('user_rut') ?? '';
    if (rut.isNotEmpty && mounted) {
      _rutController.text = rut;
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      final rut = _rutController.text.trim();
      final pass = _passController.text.trim();

      // La contraseña debe ser el mismo RUT (sin formato)
      final rutNorm = rut.replaceAll(RegExp(r'[.\-]'), '').toLowerCase();
      final passNorm = pass.replaceAll(RegExp(r'[.\-]'), '').toLowerCase();

      if (rutNorm != passNorm) {
        setState(() => _error = 'La contraseña debe ser tu mismo RUT');
        return;
      }

      final tecnico = await _api.loginTecnico(rut);
      if (tecnico == null) {
        setState(() => _error = 'RUT no encontrado o sin acceso');
        return;
      }

      await _session.iniciarSesion(tecnico);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AstWorkflowScreen()),
        );
      }
    } catch (e) {
      setState(() => _error = 'Error al conectar con el servidor');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _rutController.dispose();
    _passController.dispose();
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
                          color: _accent.withOpacity(0.3),
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

                  // RUT
                  TextFormField(
                    controller: _rutController,
                    enabled: !_loading,
                    keyboardType: TextInputType.text,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'RUT',
                      labelStyle: const TextStyle(color: _textDim),
                      hintText: '12.345.678-9',
                      hintStyle: TextStyle(color: _textDim.withOpacity(0.5)),
                      prefixIcon: const Icon(Icons.person, color: _accent),
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
                  const SizedBox(height: 16),

                  // Contraseña
                  TextFormField(
                    controller: _passController,
                    enabled: !_loading,
                    obscureText: _obscure,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      labelStyle: const TextStyle(color: _textDim),
                      hintText: 'Tu RUT sin puntos ni guión',
                      hintStyle: TextStyle(color: _textDim.withOpacity(0.5)),
                      prefixIcon: const Icon(Icons.lock, color: _accent),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: _textDim,
                        ),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
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
                        (v == null || v.isEmpty) ? 'Ingresa tu contraseña' : null,
                  ),
                  const SizedBox(height: 12),

                  // Hint
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _accent.withOpacity(0.2)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: _accent, size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tu contraseña es tu RUT',
                            style: TextStyle(color: _accent, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Botón login
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _border,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Iniciar Sesión',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
