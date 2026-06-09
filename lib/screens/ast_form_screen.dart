import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';
import 'package:agente_desconexiones/models/ast_registro.dart' show ASTRegistro;
import 'package:agente_desconexiones/models/creavox_orden.dart';
import 'package:agente_desconexiones/services/creavox_session_service.dart';
import 'package:agente_desconexiones/services/ast_service.dart';
import 'package:agente_desconexiones/services/logistica_service.dart';
import 'package:agente_desconexiones/utils/session_manager.dart';

const _bg = Color(0xFF0A1628);
const _surface = Color(0xFF0D1B2A);
const _accent = Color(0xFF00D9FF);
const _border = Color(0xFF1E3A5F);
const _textDim = Color(0xFF8FA8C8);
const _primary = Color(0xFF2196F3);
const _green = Color(0xFF4CAF50);

class AstFormScreen extends StatefulWidget {
  final CreavoxOrden orden;

  const AstFormScreen({super.key, required this.orden});

  @override
  State<AstFormScreen> createState() => _AstFormScreenState();
}

class _AstFormScreenState extends State<AstFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _session = CreavoxSessionService();
  final _astSvc = AstService();
  final _picker = ImagePicker();

  final _fechaCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _jefaturaCtrl = TextEditingController();
  final _otCtrl = TextEditingController();
  final _actividadCtrl = TextEditingController();
  final _cargoCtrl = TextEditingController();
  final _empresaCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();

  final _sigCtrl = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  String? _lugarActividad;
  List<String> _tareas = [];
  List<String> _riesgos = [];
  List<String> _medidas = [];
  List<String> _epp = [];
  List<String> _dispositivos = [];
  List<String> _herramientas = [];
  String? _estadoHerramientas;
  String? _condCriticas;
  String? _condClimaticas;

  File? _foto;
  File? _firmaFile;
  bool _loading = false;

  static const _lugares = ['Calle','Poste','Cámara Subterránea','Azotea','Interior de Edificio','Otro'];
  static const _tareasOpc = ['Instalación de equipos','Mantenimiento preventivo','Reparación','Inspección técnica','Tendido de cables','Configuración de red','Pruebas de señal','Otro'];
  static const _riesgosOpc = ['Caída de altura','Electrocución','Golpes por objetos','Cortes','Quemaduras','Atrapamiento','Exposición a químicos','Tráfico vehicular','Otro'];
  static const _medidasOpc = ['Señalización de área','Uso de arnés','Desconexión de energía','Bloqueo y etiquetado','Delimitación con conos','Trabajo en equipo','Inspección previa','Otro'];
  static const _eppOpc = ['Casco','Guantes dieléctricos','Chaleco reflectante','Botas de seguridad','Lentes de seguridad','Arnés de seguridad','Protección respiratoria','Protección auditiva','Otro'];
  static const _dispositivosOpc = ['Cono de señalización','Cinta de seguridad','Extintor','Botiquín','Linterna','Detector de voltaje','Otro'];
  static const _herramientasOpc = ['Alicate','Destornillador','Multímetro','Escalera','Taladro','Sierra','Pelacables','Fusionadora','Otro'];
  static const _estadoHerramientasOpc = ['Todas en buen estado','Alicate defectuoso','Destornillador defectuoso','Multímetro defectuoso','Escalera defectuosa','Taladro defectuoso','Pelacables defectuoso','Otro defectuoso'];
  static const _condCriticasOpc = ['Ninguna','Altura mayor a 1.8m','Trabajo con energía viva','Espacio confinado','Trabajo en vía pública','Otro'];
  static const _condClimaticasOpc = ['Despejado','Nublado','Lluvia','Viento fuerte','Calor extremo','Frío extremo','Otro'];

  String _rutSesion = '';

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final id = await SessionManager.identidadSesionMaterial();
    final t = _session.getTecnico();
    final now = DateTime.now();
    _rutSesion = id.rut.isNotEmpty
        ? id.rut
        : (t?.rutTecnico ?? '');
    if (!mounted) return;
    setState(() {
      _fechaCtrl.text =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      _nombreCtrl.text = id.nombre.isNotEmpty
          ? id.nombre
          : (t?.nombreTecnico ?? '');
      _jefaturaCtrl.text = t?.nombreSupervisor ?? '';
      _otCtrl.text = widget.orden.ordenDeTrabajo;
      _actividadCtrl.text = widget.orden.tipoActividad;
      _cargoCtrl.text = 'Técnico de Campo';
      _empresaCtrl.text = 'SBIP';
    });
  }

  Future<void> _tomarFoto() async {
    try {
      final f = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1920, maxHeight: 1080, imageQuality: 80);
      if (f != null) setState(() => _foto = File(f.path));
    } catch (e) {
      _snack('Error al tomar foto: $e', error: true);
    }
  }

  Future<void> _mostrarDialogoFirma() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Firma del Técnico', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.85,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 180,
                decoration: BoxDecoration(border: Border.all(color: _border, width: 2), borderRadius: BorderRadius.circular(8), color: Colors.white),
                child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Signature(controller: _sigCtrl, backgroundColor: Colors.white)),
              ),
              const SizedBox(height: 8),
              const Text('Firma aquí con tu dedo', style: TextStyle(color: _textDim, fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => _sigCtrl.clear(), child: const Text('Limpiar', style: TextStyle(color: _textDim))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar', style: TextStyle(color: _textDim))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _primary),
            onPressed: () async { await _guardarFirma(); if (ctx.mounted) Navigator.of(ctx).pop(); },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _guardarFirma() async {
    if (_sigCtrl.isEmpty) { _snack('Firma antes de guardar', error: true); return; }
    final bytes = await _sigCtrl.toPngBytes();
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/firma_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(bytes);
    setState(() => _firmaFile = f);
    _snack('Firma guardada');
  }

  Future<void> _multiSelect({required String titulo, required List<String> opciones, required List<String> seleccionados, required void Function(List<String>) onConfirm}) async {
    List<String> temp = List.from(seleccionados);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: _surface,
          title: Text(titulo, style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: opciones.length,
              itemBuilder: (_, i) {
                final item = opciones[i];
                return CheckboxListTile(
                  title: Text(item, style: const TextStyle(color: Colors.white)),
                  value: temp.contains(item),
                  activeColor: _accent,
                  checkColor: _bg,
                  onChanged: (v) => setD(() { if (v == true) { temp.add(item); } else { temp.remove(item); } }),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar', style: TextStyle(color: _textDim))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _primary),
              onPressed: () { onConfirm(temp); Navigator.of(ctx).pop(); },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _guardarAST() async {
    if (!_formKey.currentState!.validate()) { _snack('Completa todos los campos requeridos', error: true); return; }
    if (_tareas.isEmpty) { _snack('Selecciona al menos una tarea', error: true); return; }
    if (_riesgos.isEmpty) { _snack('Selecciona al menos un riesgo', error: true); return; }
    if (_medidas.isEmpty) { _snack('Selecciona al menos una medida de control', error: true); return; }
    if (_epp.isEmpty) { _snack('Selecciona al menos un EPP', error: true); return; }
    if (_foto == null) { _snack('Toma una foto del área de trabajo', error: true); return; }
    if (_firmaFile == null) { _snack('Firma el documento', error: true); return; }

    setState(() => _loading = true);
    try {
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      } catch (_) {}

      final tecnico = _session.getTecnico();
      final identidad = await SessionManager.identidadSesionMaterial();
      final rut = identidad.rut.isNotEmpty
          ? identidad.rut
          : (tecnico?.rutTecnico ?? 'sin_rut');
      final nombre = identidad.nombre.isNotEmpty
          ? identidad.nombre
          : await LogisticaService().nombrePorRut(
              rut,
              fallback: _nombreCtrl.text,
            );

      final fotoPayload = await _astSvc.comprimirImagen(_foto!, label: 'area_trabajo');
      final firmaPayload =
          await _astSvc.comprimirImagen(_firmaFile!, label: 'firma', maxWidth: 480, quality: 75);

      if (fotoPayload == null || firmaPayload == null) {
        throw StateError('No se pudo comprimir foto o firma');
      }

      final registro = ASTRegistro(
        ordenTrabajo: widget.orden.ordenDeTrabajo,
        rutTecnico: rut,
        nombreTecnico: nombre,
        cargo: _cargoCtrl.text,
        actividad: _actividadCtrl.text.trim(),
        empresa: _empresaCtrl.text,
        lugarActividad: _lugarActividad ?? '',
        tareasRealizar: _tareas,
        riesgosIdentificados: _riesgos,
        medidasControl: _medidas,
        equiposProteccion: _epp,
        dispositivosSeguridad: _dispositivos,
        herramientasUtilizar: _herramientas,
        estadoHerramientas: _estadoHerramientas ?? '',
        condicionesCriticas: _condCriticas ?? '',
        condicionesClimaticas: _condClimaticas ?? '',
        fotoArea: fotoPayload,
        firma: firmaPayload,
        observaciones: _obsCtrl.text,
        latitud: pos?.latitude ?? 0.0,
        longitud: pos?.longitude ?? 0.0,
        fechaHora: DateTime.now(),
      );

      final astId = await _astSvc.insertarAST(registro);
      await _session.guardarUltimaOrden(widget.orden);
      if (mounted) {
        _snack('AST guardado (${(fotoPayload['bytes_comprimidos'] as int? ?? 0) ~/ 1024} KB foto)');
        Navigator.of(context).pop(astId);
      }
    } catch (e) {
      if (mounted) _snack('Error al guardar: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : _green,
    ));
  }

  @override
  void dispose() {
    _fechaCtrl.dispose(); _nombreCtrl.dispose(); _jefaturaCtrl.dispose();
    _otCtrl.dispose(); _actividadCtrl.dispose(); _cargoCtrl.dispose();
    _empresaCtrl.dispose(); _obsCtrl.dispose(); _sigCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
        title: const Text('Formulario AST', style: TextStyle(color: Colors.white, fontSize: 15)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _seccion('📋 Información del Formulario', [
                    _campo(_fechaCtrl, 'Fecha', Icons.calendar_today, readOnly: true),
                    _campo(_nombreCtrl, 'Nombre del Técnico', Icons.person, readOnly: true),
                    _campo(_jefaturaCtrl, 'Jefatura Directa', Icons.supervisor_account, readOnly: true),
                    _campo(_otCtrl, 'Número de Orden', Icons.assignment, readOnly: true),
                    _campo(_actividadCtrl, 'Actividad', Icons.work, readOnly: true),
                    _campo(_cargoCtrl, 'Cargo', Icons.badge, readOnly: true),
                    _campo(_empresaCtrl, 'Empresa', Icons.business, readOnly: true),
                  ]),
                  const SizedBox(height: 20),
                  _seccion('📍 Lugar de Actividad', [_dropdown('Selecciona el lugar', _lugares, _lugarActividad, (v) => setState(() => _lugarActividad = v))]),
                  const SizedBox(height: 20),
                  _seccionMulti('🔧 Tareas a Realizar', _tareas, _tareasOpc, (v) => setState(() => _tareas = v), 'tareas'),
                  const SizedBox(height: 20),
                  _seccionMulti('⚠️ Riesgos Identificados', _riesgos, _riesgosOpc, (v) => setState(() => _riesgos = v), 'riesgos', chipColor: Colors.red.shade900),
                  const SizedBox(height: 20),
                  _seccionMulti('✅ Medidas de Control', _medidas, _medidasOpc, (v) => setState(() => _medidas = v), 'medidas', chipColor: Colors.green.shade900),
                  const SizedBox(height: 20),
                  _seccionMulti('🦺 Equipos de Protección (EPP)', _epp, _eppOpc, (v) => setState(() => _epp = v), 'EPP', chipColor: Colors.blue.shade900),
                  const SizedBox(height: 20),
                  _seccionMulti('🛡️ Dispositivos de Seguridad', _dispositivos, _dispositivosOpc, (v) => setState(() => _dispositivos = v), 'dispositivos', optional: true),
                  const SizedBox(height: 20),
                  _seccionMulti('🔨 Herramientas', _herramientas, _herramientasOpc, (v) => setState(() => _herramientas = v), 'herramientas', optional: true),
                  const SizedBox(height: 20),
                  _seccion('⚙️ Estado de Herramientas', [_dropdown('¿Cuál herramienta está defectuosa?', _estadoHerramientasOpc, _estadoHerramientas, (v) => setState(() => _estadoHerramientas = v))]),
                  const SizedBox(height: 20),
                  _seccion('🚨 Condiciones Críticas', [_dropdown('Selecciona condiciones críticas', _condCriticasOpc, _condCriticas, (v) => setState(() => _condCriticas = v))]),
                  const SizedBox(height: 20),
                  _seccion('🌤️ Condiciones Climáticas', [_dropdown('Selecciona el clima', _condClimaticasOpc, _condClimaticas, (v) => setState(() => _condClimaticas = v))]),
                  const SizedBox(height: 20),
                  _buildFotoSection(),
                  const SizedBox(height: 20),
                  _seccion('📝 Observaciones', [
                    TextFormField(
                      controller: _obsCtrl,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDec('Observaciones (opcional)', Icons.notes),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  _buildFirmaSection(),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _guardarAST,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Guardar AST', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _seccion(String titulo, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          ...children.map((w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w)),
        ],
      ),
    );
  }

  Widget _seccionMulti(String titulo, List<String> seleccionados, List<String> opciones, void Function(List<String>) onConfirm, String label, {Color? chipColor, bool optional = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          InkWell(
            onTap: () => _multiSelect(titulo: 'Selecciona $label', opciones: opciones, seleccionados: seleccionados, onConfirm: onConfirm),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: _border), borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(seleccionados.isEmpty ? 'Seleccionar${optional ? ' (opcional)' : ''}...' : '${seleccionados.length} seleccionado(s)', style: const TextStyle(color: _textDim, fontSize: 13)),
                  const Icon(Icons.arrow_drop_down, color: _textDim),
                ],
              ),
            ),
          ),
          if (seleccionados.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: seleccionados.map((s) => Chip(
                label: Text(s, style: const TextStyle(color: Colors.white, fontSize: 12)),
                backgroundColor: chipColor ?? _primary.withOpacity(0.3),
                deleteIconColor: Colors.white54,
                onDeleted: () => onConfirm(seleccionados.where((x) => x != s).toList()),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFotoSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📸 Foto del Área de Trabajo', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          if (_foto != null) ...[
            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(_foto!, height: 180, width: double.infinity, fit: BoxFit.cover)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => _foto = null),
              icon: const Icon(Icons.delete, color: _textDim),
              label: const Text('Eliminar foto', style: TextStyle(color: _textDim)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: _border)),
            ),
          ] else
            ElevatedButton.icon(
              onPressed: _tomarFoto,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Tomar foto del área'),
              style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _buildFirmaSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✍️ Firma del Técnico', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          if (_firmaFile != null) ...[
            Container(
              height: 130, width: double.infinity,
              decoration: BoxDecoration(border: Border.all(color: _border), borderRadius: BorderRadius.circular(10), color: Colors.white),
              child: Image.file(_firmaFile!, fit: BoxFit.contain),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() { _firmaFile = null; _sigCtrl.clear(); }),
              icon: const Icon(Icons.delete, color: _textDim),
              label: const Text('Limpiar firma', style: TextStyle(color: _textDim)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: _border)),
            ),
          ] else
            ElevatedButton.icon(
              onPressed: _mostrarDialogoFirma,
              icon: const Icon(Icons.draw),
              label: const Text('Firmar con el dedo'),
              style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _campo(TextEditingController ctrl, String label, IconData icon, {bool readOnly = false}) {
    return TextFormField(
      controller: ctrl, readOnly: readOnly, enabled: !readOnly,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDec(label, icon),
    );
  }

  Widget _dropdown(String hint, List<String> items, String? value, void Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      value: value, dropdownColor: _surface,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: hint, labelStyle: const TextStyle(color: _textDim, fontSize: 13),
        filled: true, fillColor: _bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _accent)),
      ),
      items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: const TextStyle(color: Colors.white)))).toList(),
      onChanged: onChanged,
      validator: (v) => v == null ? 'Campo requerido' : null,
    );
  }

  InputDecoration _inputDec(String label, IconData icon) {
    return InputDecoration(
      labelText: label, labelStyle: const TextStyle(color: _textDim, fontSize: 13),
      prefixIcon: Icon(icon, color: _accent, size: 20),
      filled: true, fillColor: _bg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _accent)),
      disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border.withOpacity(0.5))),
    );
  }
}
