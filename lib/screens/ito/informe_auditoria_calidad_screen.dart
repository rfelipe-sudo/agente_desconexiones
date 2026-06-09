import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';

import 'package:agente_desconexiones/services/informe_auditoria_service.dart';
import 'package:agente_desconexiones/utils/image_compress_util.dart';

/// Informe Mesa de Calidad — Norma Técnica (ITO Calidad).
class InformeAuditoriaCalidadScreen extends StatefulWidget {
  const InformeAuditoriaCalidadScreen({super.key});

  @override
  State<InformeAuditoriaCalidadScreen> createState() =>
      _InformeAuditoriaCalidadScreenState();
}

class _InformeAuditoriaCalidadScreenState
    extends State<InformeAuditoriaCalidadScreen>
    with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _accent = Color(0xFF00D9FF);
  static const _green = Color(0xFF22C55E);
  static const _textDim = Color(0xFF8FA8C8);

  final _svc = InformeAuditoriaService();
  final _picker = ImagePicker();

  late TabController _tabs;

  String _rutIto = '';
  String _nombreIto = '';
  bool _guardando = false;

  // Datos generales
  final _operacionCtrl = TextEditingController(text: 'Operaciones');
  final _antecedentesTipoCtrl = TextEditingController(text: 'Alta');
  final _involucradosCtrl = TextEditingController();
  final _numClienteCtrl = TextEditingController();
  final _actividadCtrl = TextEditingController();
  final _peticionCtrl = TextEditingController();
  final _rutTecnicoCtrl = TextEditingController();
  final _nombreTecnicoCtrl = TextEditingController();
  DateTime _fechaCitacion = DateTime.now();
  DateTime _fechaToa = DateTime.now();

  // Hechos
  final _motivoCtrl = TextEditingController(text: 'Norma técnica');
  final _causaCtrl = TextEditingController();
  final _antecedentesDetalleCtrl = TextEditingController();
  final _calificacionCtrl = TextEditingController(
    text:
        'Incumplimiento de carácter grave: deficiente ejecución, reiterado por mala práctica, '
        'impacto en continuidad del servicio y deterioro de imagen institucional.',
  );
  final _irregularidadNuevaCtrl = TextEditingController();
  final List<String> _irregularidades = [];

  static const _irregularidadesSugeridas = [
    'No realizó correctamente el embandejado de la fibra óptica (CDOI / Riser).',
    'No efectuó embandejado al interior de la CDOI — fibra expuesta.',
    'No cierre de tapas de paso en el interior del domicilio.',
    'Mal embandejado de fibra al interior de la roseta óptica.',
    'Generó expectativas incorrectas al cliente sin concretar regreso.',
  ];
  final Set<int> _irregularidadesSugeridasSel = {};

  // Regularización y resumen
  final _regularizacionCtrl = TextEditingController();
  final List<String> _fotosRegistroPaths = [];
  final List<String> _fotosRegularizacionPaths = [];

  static const _resumenSugerido = [
    'Técnico reconoce que no aplicó los procedimientos y no tuvo actitud profesional.',
    'Se informa la gravedad de la falta y las sanciones que conllevan sus acciones.',
    'Se deja constancia del riesgo de bloqueos operacionales.',
    'Corresponde aplicación de Política de Sanciones vigente.',
  ];
  final Set<int> _resumenSel = {0, 1, 2, 3};

  bool _sancionVerbal = false;
  bool _sancionEscrita = true;
  bool _sancionReinduccion = false;
  bool _sancionPernoctacion = false;
  bool _sancionFormacion = false;

  final _nombreSupervisorAtcCtrl = TextEditingController();

  late SignatureController _firmaTecnicoCtrl;
  late SignatureController _firmaSupervisorCtrl;
  late SignatureController _firmaAuditorCtrl;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _firmaTecnicoCtrl = _nuevaFirma();
    _firmaSupervisorCtrl = _nuevaFirma();
    _firmaAuditorCtrl = _nuevaFirma();
    _cargarSesion();
  }

  SignatureController _nuevaFirma() => SignatureController(
        penStrokeWidth: 2.5,
        penColor: Colors.white,
        exportBackgroundColor: _surface,
      );

  Future<void> _cargarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _rutIto = prefs.getString('rut_tecnico') ??
          prefs.getString('user_rut') ??
          '';
      _nombreIto = prefs.getString('nombre_tecnico') ??
          prefs.getString('user_nombre') ??
          '';
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _operacionCtrl.dispose();
    _antecedentesTipoCtrl.dispose();
    _involucradosCtrl.dispose();
    _numClienteCtrl.dispose();
    _actividadCtrl.dispose();
    _peticionCtrl.dispose();
    _rutTecnicoCtrl.dispose();
    _nombreTecnicoCtrl.dispose();
    _motivoCtrl.dispose();
    _causaCtrl.dispose();
    _antecedentesDetalleCtrl.dispose();
    _calificacionCtrl.dispose();
    _irregularidadNuevaCtrl.dispose();
    _regularizacionCtrl.dispose();
    _nombreSupervisorAtcCtrl.dispose();
    _firmaTecnicoCtrl.dispose();
    _firmaSupervisorCtrl.dispose();
    _firmaAuditorCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha(bool citacion) async {
    final base = citacion ? _fechaCitacion : _fechaToa;
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    setState(() {
      if (citacion) {
        _fechaCitacion = picked;
      } else {
        _fechaToa = picked;
      }
    });
  }

  Future<void> _agregarFoto(bool regularizacion) async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: _surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: _accent),
              title: const Text('Cámara', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: _accent),
              title: const Text('Galería', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (src == null) return;
    final photo = await _picker.pickImage(source: src, imageQuality: 85);
    if (photo == null) return;
    setState(() {
      if (regularizacion) {
        _fotosRegularizacionPaths.add(photo.path);
      } else {
        _fotosRegistroPaths.add(photo.path);
      }
    });
  }

  List<String> _irregularidadesFinales() {
    final out = <String>[];
    for (final i in _irregularidadesSugeridasSel) {
      out.add(_irregularidadesSugeridas[i]);
    }
    out.addAll(_irregularidades);
    return out;
  }

  List<String> _resumenFinal() {
    return _resumenSel.map((i) => _resumenSugerido[i]).toList();
  }

  Future<void> _guardar() async {
    if (_rutTecnicoCtrl.text.trim().isEmpty ||
        _nombreTecnicoCtrl.text.trim().isEmpty) {
      _snack('Indica RUT y nombre del técnico auditado', Colors.orange);
      return;
    }
    if (_antecedentesDetalleCtrl.text.trim().isEmpty) {
      _snack('Completa los antecedentes / hechos', Colors.orange);
      return;
    }
    if (_irregularidadesFinales().isEmpty) {
      _snack('Selecciona o agrega al menos una irregularidad', Colors.orange);
      return;
    }

    setState(() => _guardando = true);
    try {
      final fotosReg = await ImageCompressUtil.pathsToCompressedList(
        _fotosRegistroPaths,
        prefix: 'registro',
      );
      final fotosRegul = await ImageCompressUtil.pathsToCompressedList(
        _fotosRegularizacionPaths,
        prefix: 'regularizacion',
      );

      String? firmaTec;
      String? firmaSup;
      String? firmaAud;
      final bT = await _firmaTecnicoCtrl.toPngBytes();
      final bS = await _firmaSupervisorCtrl.toPngBytes();
      final bA = await _firmaAuditorCtrl.toPngBytes();
      if (bT != null && bT.isNotEmpty) firmaTec = base64Encode(bT);
      if (bS != null && bS.isNotEmpty) firmaSup = base64Encode(bS);
      if (bA != null && bA.isNotEmpty) firmaAud = base64Encode(bA);

      final involucrados = _involucradosCtrl.text.trim().isNotEmpty
          ? _involucradosCtrl.text.trim()
          : _nombreTecnicoCtrl.text.trim();

      await _svc.guardarInforme({
        'estado': 'finalizado',
        'rut_ito': _rutIto,
        'nombre_ito': _nombreIto,
        'rut_tecnico_auditado': _rutTecnicoCtrl.text.trim(),
        'nombre_tecnico_auditado': _nombreTecnicoCtrl.text.trim(),
        'empresa': 'CREACIONES TECNOLOGICAS',
        'operacion': _operacionCtrl.text.trim(),
        'antecedentes_tipo': _antecedentesTipoCtrl.text.trim(),
        'fecha_citacion': DateFormat('yyyy-MM-dd').format(_fechaCitacion),
        'fecha_toa': DateFormat('yyyy-MM-dd').format(_fechaToa),
        'involucrados': involucrados,
        'numero_cliente': _numClienteCtrl.text.trim(),
        'actividad': _actividadCtrl.text.trim(),
        'peticion': _peticionCtrl.text.trim(),
        'motivo': _motivoCtrl.text.trim(),
        'causa': _causaCtrl.text.trim(),
        'antecedentes_detalle': _antecedentesDetalleCtrl.text.trim(),
        'irregularidades': _irregularidadesFinales(),
        'calificacion_incumplimiento': _calificacionCtrl.text.trim(),
        'fotos_registro': fotosReg,
        'regularizacion_texto': _regularizacionCtrl.text.trim(),
        'fotos_regularizacion': fotosRegul,
        'resumen_mesa': _resumenFinal(),
        'sancion_amonestacion_verbal': _sancionVerbal,
        'sancion_amonestacion_escrita': _sancionEscrita,
        'sancion_reinduccion_formacion': _sancionReinduccion,
        'sancion_pernoctacion_vehiculo': _sancionPernoctacion,
        'sancion_programacion_formacion': _sancionFormacion,
        'nombre_supervisor_atc': _nombreSupervisorAtcCtrl.text.trim(),
        'firma_tecnico': firmaTec,
        'firma_supervisor_atc': firmaSup,
        'firma_auditor_calidad': firmaAud,
      });

      if (!mounted) return;
      _snack('Informe guardado en Supabase', _green);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _snack('Error al guardar: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Informe Auditoría',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('Mesa de Calidad · Norma Técnica',
                style: TextStyle(fontSize: 11, color: _textDim)),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: _accent,
          labelColor: _accent,
          unselectedLabelColor: _textDim,
          tabs: const [
            Tab(text: 'Generales'),
            Tab(text: 'Hechos'),
            Tab(text: 'Fotos'),
            Tab(text: 'Regularización'),
            Tab(text: 'Sanciones'),
            Tab(text: 'Firmas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _tabGenerales(),
          _tabHechos(),
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _bloqueFotos(
                titulo: 'Registro fotográfico',
                paths: _fotosRegistroPaths,
                regularizacion: false,
              ),
            ],
          ),
          _tabRegularizacion(),
          _tabSanciones(),
          _tabFirmas(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (_tabs.index > 0)
                TextButton(
                  onPressed: () => _tabs.animateTo(_tabs.index - 1),
                  child: const Text('Anterior'),
                ),
              const Spacer(),
              if (_tabs.index < 5)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _accent),
                  onPressed: () => _tabs.animateTo(_tabs.index + 1),
                  child: const Text('Siguiente',
                      style: TextStyle(color: Colors.black)),
                )
              else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _green),
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Finalizar informe'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabGenerales() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card([
          _ro('ITO Calidad', _nombreIto.isNotEmpty ? _nombreIto : _rutIto),
          const Divider(color: _textDim),
          _campo('Operación', _operacionCtrl),
          _campo('Antecedentes (tipo)', _antecedentesTipoCtrl),
          _fechaRow('Fecha citación', _fechaCitacion, true),
          _fechaRow('Fecha TOA', _fechaToa, false),
          _campo('N° Cliente', _numClienteCtrl),
          _campo('Actividad', _actividadCtrl,
              hint: 'Ej: 2 play'),
          _campo('Petición / OT', _peticionCtrl),
          const SizedBox(height: 12),
          const Text('Técnico auditado',
              style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
          _campo('RUT técnico', _rutTecnicoCtrl),
          _campo('Nombre técnico', _nombreTecnicoCtrl),
          _campo('Involucrados', _involucradosCtrl),
        ]),
      ],
    );
  }

  Widget _tabHechos() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card([
          _campo('Motivo', _motivoCtrl),
          _campo('Causa', _causaCtrl),
          _campoMultiline('Antecedentes (narrativa)', _antecedentesDetalleCtrl,
              minLines: 6),
          const SizedBox(height: 8),
          const Text('Irregularidades detectadas',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ...List.generate(_irregularidadesSugeridas.length, (i) {
            return CheckboxListTile(
              value: _irregularidadesSugeridasSel.contains(i),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _irregularidadesSugeridasSel.add(i);
                } else {
                  _irregularidadesSugeridasSel.remove(i);
                }
              }),
              title: Text(_irregularidadesSugeridas[i],
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              activeColor: _accent,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            );
          }),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _irregularidadNuevaCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration('Otra irregularidad'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle, color: _accent),
                onPressed: () {
                  final t = _irregularidadNuevaCtrl.text.trim();
                  if (t.isEmpty) return;
                  setState(() {
                    _irregularidades.add(t);
                    _irregularidadNuevaCtrl.clear();
                  });
                },
              ),
            ],
          ),
          ..._irregularidades.map(
            (t) => ListTile(
              dense: true,
              title: Text('• $t',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.red),
                onPressed: () => setState(() => _irregularidades.remove(t)),
              ),
            ),
          ),
          _campoMultiline('Calificación del incumplimiento', _calificacionCtrl,
              minLines: 4),
        ]),
      ],
    );
  }

  Widget _tabRegularizacion() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card([
          _campoMultiline(
            'Regularización (texto)',
            _regularizacionCtrl,
            minLines: 5,
            hint:
                'Describa la intervención posterior y corrección de desviaciones…',
          ),
        ]),
        const SizedBox(height: 12),
        _bloqueFotos(
          titulo: 'Fotos regularización',
          paths: _fotosRegularizacionPaths,
          regularizacion: true,
        ),
      ],
    );
  }

  Widget _bloqueFotos({
    required String titulo,
    required List<String> paths,
    required bool regularizacion,
  }) {
    return _card([
      Text(titulo,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text(
        'Las fotos se comprimen (JPEG) antes de subir a Supabase.',
        style: TextStyle(color: _textDim, fontSize: 12),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...paths.asMap().entries.map((e) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(e.value),
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () => setState(() => paths.removeAt(e.key)),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              )),
          InkWell(
            onTap: () => _agregarFoto(regularizacion),
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _accent),
              ),
              child: const Icon(Icons.add_a_photo, color: _accent),
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _tabSanciones() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card([
          const Text('Resumen Mesa de Calidad',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ...List.generate(_resumenSugerido.length, (i) {
            return CheckboxListTile(
              value: _resumenSel.contains(i),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _resumenSel.add(i);
                } else {
                  _resumenSel.remove(i);
                }
              }),
              title: Text(_resumenSugerido[i],
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              activeColor: _accent,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            );
          }),
          const Divider(color: _textDim),
          const Text('Medida según Política de Sanciones',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          _checkSancion('Amonestación verbal', _sancionVerbal, (v) => _sancionVerbal = v),
          _checkSancion('Amonestación escrita', _sancionEscrita, (v) => _sancionEscrita = v),
          _checkSancion('Reinducción formación técnica', _sancionReinduccion,
              (v) => _sancionReinduccion = v),
          _checkSancion('Pernoctación vehículo corporativo', _sancionPernoctacion,
              (v) => _sancionPernoctacion = v),
          _checkSancion('Programación formación técnica', _sancionFormacion,
              (v) => _sancionFormacion = v),
        ]),
      ],
    );
  }

  Widget _checkSancion(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return CheckboxListTile(
      value: value,
      onChanged: (v) => setState(() => onChanged(v ?? false)),
      title: Text(label, style: const TextStyle(color: Colors.white70)),
      activeColor: _accent,
    );
  }

  Widget _tabFirmas() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card([
          _campo('Supervisor Técnico ATC (nombre)', _nombreSupervisorAtcCtrl),
          _padFirma('Firma técnico auditado', _firmaTecnicoCtrl),
          _padFirma('Firma Supervisor ATC', _firmaSupervisorCtrl),
          _padFirma('Firma Auditoría y Calidad (ITO)', _firmaAuditorCtrl),
        ]),
      ],
    );
  }

  Widget _padFirma(String titulo, SignatureController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(titulo,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () => setState(() => ctrl.clear()),
              child: const Text('Limpiar'),
            ),
          ],
        ),
        Container(
          height: 140,
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _textDim.withValues(alpha: 0.4)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Signature(
              controller: ctrl,
              backgroundColor: _surface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _textDim.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _campo(
    String label,
    TextEditingController ctrl, {
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white),
        decoration: _decoration(label, hint: hint),
      ),
    );
  }

  Widget _campoMultiline(
    String label,
    TextEditingController ctrl, {
    int minLines = 3,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        minLines: minLines,
        maxLines: minLines + 4,
        style: const TextStyle(color: Colors.white),
        decoration: _decoration(label, hint: hint),
      ),
    );
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: _textDim),
      hintStyle: TextStyle(color: _textDim.withValues(alpha: 0.6)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _textDim.withValues(alpha: 0.35)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _accent),
      ),
    );
  }

  Widget _fechaRow(String label, DateTime fecha, bool citacion) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(color: _textDim, fontSize: 13)),
      subtitle: Text(
        DateFormat('dd/MM/yyyy').format(fecha),
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.calendar_today, color: _accent),
        onPressed: () => _elegirFecha(citacion),
      ),
    );
  }

  Widget _ro(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: _textDim, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
