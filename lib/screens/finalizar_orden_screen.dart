import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';

const _bg          = Color(0xFF0A1628);
const _surface     = Color(0xFF0D1B2A);
const _surfaceElev = Color(0xFF1A2C3D);
const _accent      = Color(0xFF00D9FF);
const _accentDim   = Color(0xFF0099CC);
const _success     = Color(0xFF10B981);
const _danger      = Color(0xFFEF4444);
const _textDim     = Color(0xFF8FA8C8);
const _border      = Color(0xFF1E3A5F);

const _largosDrop = [50, 100, 150, 300];

class FinalizarOrdenScreen extends StatefulWidget {
  const FinalizarOrdenScreen({super.key});

  @override
  State<FinalizarOrdenScreen> createState() => _FinalizarOrdenScreenState();
}

class _FinalizarOrdenScreenState extends State<FinalizarOrdenScreen> {
  final _formKey = GlobalKey<FormState>();

  final _otCtrl              = TextEditingController();
  final _clienteNombreCtrl   = TextEditingController();
  final _clienteRutCtrl      = TextEditingController();
  final _clienteDireccionCtrl= TextEditingController();
  final _clienteTelefonoCtrl = TextEditingController();
  final _ontSerieCtrl        = TextEditingController();
  final _observacionesCtrl   = TextEditingController();

  final Map<int, int> _cantDropPorLargo = {for (final l in _largosDrop) l: 0};
  int _conectorCampo = 0;
  int _roseta        = 0;
  int _jumper        = 0;
  int _grampas       = 0;
  int _soporteDrop   = 0;

  File? _mapaCalor;
  late final SignatureController _firma;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _firma = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.white,
      exportBackgroundColor: _surfaceElev,
    );
  }

  @override
  void dispose() {
    _otCtrl.dispose();
    _clienteNombreCtrl.dispose();
    _clienteRutCtrl.dispose();
    _clienteDireccionCtrl.dispose();
    _clienteTelefonoCtrl.dispose();
    _ontSerieCtrl.dispose();
    _observacionesCtrl.dispose();
    _firma.dispose();
    super.dispose();
  }

  // ── Submit ────────────────────────────────────────────────────────────

  Future<void> _enviar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_firma.isEmpty) {
      _toast('Falta la firma del cliente', _danger);
      return;
    }

    setState(() => _enviando = true);
    try {
      final firmaBytes = await _firma.toPngBytes();

      final payload = {
        'ot': _otCtrl.text.trim(),
        'cliente': {
          'nombre':    _clienteNombreCtrl.text.trim(),
          'rut':       _clienteRutCtrl.text.trim(),
          'direccion': _clienteDireccionCtrl.text.trim(),
          'telefono':  _clienteTelefonoCtrl.text.trim(),
        },
        'materiales': {
          'ont_serie': _ontSerieCtrl.text.trim(),
          'drops': [
            for (final l in _largosDrop)
              {'largo_m': l, 'cantidad': _cantDropPorLargo[l] ?? 0},
          ],
          'conector_campo': _conectorCampo,
          'roseta':         _roseta,
          'jumper':         _jumper,
          'grampas':        _grampas,
          'soporte_drop':   _soporteDrop,
        },
        'observaciones':   _observacionesCtrl.text.trim(),
        'mapa_calor_path': _mapaCalor?.path,
        'firma_png_bytes': firmaBytes?.length ?? 0,
        'timestamp':       DateTime.now().toIso8601String(),
      };

      // STUB: backend pendiente. Por ahora logueamos el payload completo.
      // Cuando definas Supabase / PDF / share, reemplazar este bloque por
      // la llamada real (mantener la misma estructura del payload).
      debugPrint('==== FINALIZAR ORDEN ====');
      debugPrint(const JsonEncoder.withIndent('  ').convert(payload));

      if (!mounted) return;
      await _showExito();
    } catch (e) {
      if (!mounted) return;
      _toast('Error al finalizar: $e', _danger);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _showExito() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: _border),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 78, height: 78,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [_success, _accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 48),
              ),
              const SizedBox(height: 20),
              const Text(
                'Orden finalizada',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              const Text(
                'El formulario quedó registrado.\n(El envío al backend está pendiente de configurar.)',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textDim, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(context); // cierra dialog
                    Navigator.pop(context); // cierra pantalla
                  },
                  child: const Text('Listo', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Mapa de calor (image picker) ─────────────────────────────────────

  Future<void> _pickMapa(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(source: source, imageQuality: 85);
      if (x == null) return;
      if (!mounted) return;
      setState(() => _mapaCalor = File(x.path));
    } catch (e) {
      if (mounted) _toast('No se pudo adjuntar el mapa: $e', _danger);
    }
  }

  void _abrirSelectorMapa() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 38, height: 4,
              decoration: BoxDecoration(
                color: _border, borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: _accent),
              title: const Text('Tomar foto', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _pickMapa(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: _accent),
              title: const Text('Galería', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _pickMapa(ImageSource.gallery); },
            ),
            if (_mapaCalor != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: _danger),
                title: const Text('Quitar mapa adjunto', style: TextStyle(color: _danger)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _mapaCalor = null);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: Row(
          children: const [
            Icon(Icons.fact_check_outlined, color: _accent),
            SizedBox(width: 10),
            Text('Formulario de Finalización',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _section(
              icon: Icons.assignment_outlined,
              titulo: 'Orden de Trabajo',
              children: [
                _input(
                  controller: _otCtrl,
                  label: 'Número de OT',
                  hint: 'Ej: 1-3FCTFPHL',
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Ingresa la OT'
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _section(
              icon: Icons.person_outline,
              titulo: 'Datos del Cliente',
              children: [
                _input(
                  controller: _clienteNombreCtrl,
                  label: 'Nombre',
                  hint: 'Nombre completo',
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 10),
                _input(
                  controller: _clienteRutCtrl,
                  label: 'RUT',
                  hint: '12.345.678-9',
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9kK.\-]')),
                  ],
                ),
                const SizedBox(height: 10),
                _input(
                  controller: _clienteDireccionCtrl,
                  label: 'Dirección',
                  hint: 'Calle, número, comuna',
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),
                _input(
                  controller: _clienteTelefonoCtrl,
                  label: 'Teléfono',
                  hint: '+56 9 1234 5678',
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _section(
              icon: Icons.inventory_2_outlined,
              titulo: 'Declaración de Materiales',
              children: [
                _input(
                  controller: _ontSerieCtrl,
                  label: 'ONT - Número de serie',
                  hint: 'Ej: ZTEGAB12345678',
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 18),
                const _DividerLabel(label: 'DROP (por largo)'),
                const SizedBox(height: 10),
                ..._largosDrop.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _filaCantidad(
                    icon: Icons.cable,
                    label: 'Drop ${l}m',
                    value: _cantDropPorLargo[l] ?? 0,
                    onChanged: (v) => setState(() => _cantDropPorLargo[l] = v),
                  ),
                )),
                const SizedBox(height: 10),
                const _DividerLabel(label: 'OTROS MATERIALES'),
                const SizedBox(height: 10),
                _filaCantidad(
                  icon: Icons.electrical_services,
                  label: 'Conector de Campo',
                  value: _conectorCampo,
                  onChanged: (v) => setState(() => _conectorCampo = v),
                ),
                const SizedBox(height: 8),
                _filaCantidad(
                  icon: Icons.power_outlined,
                  label: 'Roseta',
                  value: _roseta,
                  onChanged: (v) => setState(() => _roseta = v),
                ),
                const SizedBox(height: 8),
                _filaCantidad(
                  icon: Icons.cable_outlined,
                  label: 'Jumper',
                  value: _jumper,
                  onChanged: (v) => setState(() => _jumper = v),
                ),
                const SizedBox(height: 8),
                _filaCantidad(
                  icon: Icons.push_pin_outlined,
                  label: 'Grampas',
                  value: _grampas,
                  onChanged: (v) => setState(() => _grampas = v),
                ),
                const SizedBox(height: 8),
                _filaCantidad(
                  icon: Icons.handyman_outlined,
                  label: 'Soporte Drop',
                  value: _soporteDrop,
                  onChanged: (v) => setState(() => _soporteDrop = v),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _section(
              icon: Icons.notes,
              titulo: 'Observaciones',
              children: [
                _input(
                  controller: _observacionesCtrl,
                  label: 'Notas adicionales',
                  hint: 'Detalles relevantes de la instalación, condiciones del sitio, etc.',
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _section(
              icon: Icons.thermostat_auto_outlined,
              titulo: 'Mapa de Calor',
              children: [
                if (_mapaCalor == null)
                  _buttonGhost(
                    icon: Icons.add_photo_alternate_outlined,
                    label: 'Adjuntar imagen del mapa',
                    onPressed: _abrirSelectorMapa,
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_mapaCalor!, height: 220, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 8),
                      _buttonGhost(
                        icon: Icons.swap_horiz,
                        label: 'Cambiar / quitar mapa',
                        onPressed: _abrirSelectorMapa,
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _section(
              icon: Icons.draw_outlined,
              titulo: 'Firma del Cliente',
              children: [
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: _surfaceElev,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Signature(
                    controller: _firma,
                    backgroundColor: _surfaceElev,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buttonGhost(
                        icon: Icons.refresh,
                        label: 'Limpiar',
                        onPressed: () => _firma.clear(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'El cliente debe firmar dentro del recuadro.',
                  style: TextStyle(color: _textDim, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _enviando ? null : _enviar,
                icon: _enviando
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle_outline, size: 22),
                label: Text(
                  _enviando ? 'Procesando…' : 'Finalizar Orden',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.4),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers de UI ─────────────────────────────────────────────────────

  Widget _section({
    required IconData icon,
    required String titulo,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_accent, _accentDim],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType ?? (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _textDim, fontSize: 13),
        hintText: hint,
        hintStyle: TextStyle(color: _textDim.withValues(alpha: 0.6), fontSize: 13),
        filled: true,
        fillColor: _surfaceElev,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _danger, width: 1.5),
        ),
      ),
    );
  }

  Widget _filaCantidad({
    required IconData icon,
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _surfaceElev,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(icon, color: _accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          _CantidadSelector(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buttonGhost({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: _accent, size: 18),
        label: Text(label, style: const TextStyle(color: _accent, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: _border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: _surfaceElev,
        ),
      ),
    );
  }
}

class _DividerLabel extends StatelessWidget {
  const _DividerLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: _border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: const TextStyle(
              color: _textDim,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: _border)),
      ],
    );
  }
}

/// Selector de cantidad estilo dropdown moderno (0..50). Despliega un menú
/// compacto al tap, no un picker pesado.
class _CantidadSelector extends StatelessWidget {
  const _CantidadSelector({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: value > 0 ? _accent : _border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          dropdownColor: _surface,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: _textDim, size: 18),
          style: TextStyle(
            color: value > 0 ? _accent : Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          items: [
            for (int i = 0; i <= 50; i++)
              DropdownMenuItem(
                value: i,
                child: Text(
                  i.toString().padLeft(2, '0'),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
