import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modelos internos del formulario
// ─────────────────────────────────────────────────────────────────────────────

enum _TipoItem { bmna, texto, cantidad }

class _Item {
  final String codigo;
  final String nombre;
  final _TipoItem tipo;
  final String? extra1;
  final String? extra2;
  const _Item(this.codigo, this.nombre,
      {this.tipo = _TipoItem.bmna, this.extra1, this.extra2});
}

// ─────────────────────────────────────────────────────────────────────────────
// Secciones del formulario F-41
// ─────────────────────────────────────────────────────────────────────────────

const _itemsEpp = [
  _Item('1.1',  'Casco dieléctrico',                        extra1: 'Marca'),
  _Item('1.2',  'Barbiquejo 4 puntas'),
  _Item('1.3',  'Legionario'),
  _Item('1.4',  'Arnés 4 argollas',                         extra1: 'Fecha elaboración'),
  _Item('1.5',  'Estrobo',                                  extra1: 'Fecha elaboración'),
  _Item('1.6',  'Lápiz detector de voltaje',                extra1: 'Color'),
  _Item('1.7',  'Guantes dieléctricos Clase 0 o 00',        extra1: 'Talla', extra2: 'Clase'),
  _Item('1.8',  'Guante protector dieléctrico'),
  _Item('1.9',  'Guantes Cabritilla'),
  _Item('1.10', 'Guantes de trabajo Fino'),
  _Item('1.11', 'Calzado dieléctrico'),
  _Item('1.12', 'Geólogo'),
  _Item('1.13', 'Polera ignifuga'),
  _Item('1.14', 'Pantalón Ignifugo'),
  _Item('1.15', 'Polerón ignifugo'),
  _Item('1.16', 'Parka'),
  _Item('1.17', 'Capa de agua'),
  _Item('1.18', 'Protector solar'),
  _Item('1.19', 'Cinta anti-trauma'),
  _Item('1.20', 'Antiparras claras o sobre lentes'),
  _Item('1.21', 'Antiparras oscuras o sobre lentes'),
];

const _itemsVehiculo = [
  _Item('2.1',  'Ppu (PATENTE)',                tipo: _TipoItem.texto),
  _Item('2.2',  'Odómetro (kilometraje)',        tipo: _TipoItem.texto),
  _Item('2.3',  'Revisión Técnica',              tipo: _TipoItem.texto),
  _Item('2.4',  'Permiso de circulación',        tipo: _TipoItem.texto),
  _Item('2.5',  'Seguro SOAP',                   tipo: _TipoItem.texto),
  _Item('2.6',  'Extintor',                      tipo: _TipoItem.texto, extra1: 'Fecha'),
  _Item('2.7',  'Gata',                          tipo: _TipoItem.texto),
  _Item('2.8',  'Llave',                         tipo: _TipoItem.texto),
  _Item('2.9',  'Anillo de remolque',            tipo: _TipoItem.texto),
  _Item('2.10', 'Triángulo',                     tipo: _TipoItem.texto),
  _Item('2.11', 'Chaleco Reflectante tránsito',  tipo: _TipoItem.texto),
  _Item('2.12', 'Conos (4 unidades)',            tipo: _TipoItem.texto),
  _Item('2.13', 'Señal de desvío',               tipo: _TipoItem.texto),
  _Item('2.14', 'Rueda de repuesto',             tipo: _TipoItem.texto),
  _Item('2.15', 'Limpieza del vehículo',         tipo: _TipoItem.texto),
];

const _itemsBotiquin = [
  _Item('b3.1',  'Parche curitas',               tipo: _TipoItem.cantidad),
  _Item('b3.2',  'Gasas estériles (10x10 cm)',   tipo: _TipoItem.cantidad),
  _Item('b3.3',  'Venda gasa (5-10 cm)',         tipo: _TipoItem.cantidad),
  _Item('b3.4',  'Apósitos',                     tipo: _TipoItem.cantidad),
  _Item('b3.5',  'Apósitos Antisépticos',        tipo: _TipoItem.cantidad),
  _Item('b3.6',  'Apósitos antibacterianos',     tipo: _TipoItem.cantidad),
  _Item('b3.7',  'Cinta Adhesiva (esparadrapo)', tipo: _TipoItem.cantidad),
  _Item('b3.8',  'Pinza',                        tipo: _TipoItem.cantidad),
  _Item('b3.9',  'Desinfectante de mano',        tipo: _TipoItem.cantidad),
  _Item('b3.10', 'Jabón Gel',                    tipo: _TipoItem.cantidad),
  _Item('b3.11', 'Guante quirúrgico',            tipo: _TipoItem.cantidad),
  _Item('b3.12', 'Mascarilla desechable',        tipo: _TipoItem.cantidad),
  _Item('b3.13', 'Tijera',                       tipo: _TipoItem.cantidad),
];

const _itemsEscalaTel = [
  _Item('t3.1',  'Largueros en buen estado'),
  _Item('t3.2',  'Peldaños en buen estado'),
  _Item('t3.3',  'Traba peldaño en buenas condiciones'),
  _Item('t3.4',  'Ganchos en buen estado'),
  _Item('t3.5',  'Peldaño colgante en buen estado (polystrap)'),
  _Item('t3.6',  'Soga de izaje'),
  _Item('t3.7',  'Roldana'),
  _Item('t3.8',  'Zapata'),
  _Item('t3.9',  'Cinta de anclaje'),
  _Item('t3.10', 'Línea de vida',                extra1: 'Diámetro'),
  _Item('t3.11', 'Carro de ascenso y descenso',  extra1: 'Diámetro'),
  _Item('t3.12', 'Vientos',                      extra1: 'Diámetro'),
  _Item('t3.13', 'Banderín de escala'),
  _Item('t3.14', 'Bolso porta cuerdas'),
];

const _itemsEscalaTij = [
  _Item('j4.1', 'Largueros'),
  _Item('j4.2', 'Refuerzo de peldaños'),
  _Item('j4.3', 'Tapa superior'),
  _Item('j4.4', 'Zapatas antideslizantes'),
  _Item('j4.5', 'Bisagras interiores'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Pantalla principal
// ─────────────────────────────────────────────────────────────────────────────

class AuditoriaPrlScreen extends StatefulWidget {
  const AuditoriaPrlScreen({super.key});

  @override
  State<AuditoriaPrlScreen> createState() => _AuditoriaPrlScreenState();
}

class _AuditoriaPrlScreenState extends State<AuditoriaPrlScreen>
    with SingleTickerProviderStateMixin {
  // ── Colores ─────────────────────────────────────────────────────────────────
  static const _colorFondo   = Color(0xFF0A0F1E);
  static const _colorCard    = Color(0xFF0D1B2A);
  static const _colorVerde   = Color(0xFF30D158);
  static const _colorRojo    = Color(0xFFFF3B30);
  static const _colorNaranja = Color(0xFFFF9500);
  static const _colorAzul    = Color(0xFF1E88E5);
  static const _colorAmbar   = Color(0xFFFFD60A);
  static const _colorPrl     = Color(0xFFFF6B35);

  // ── Tabs ─────────────────────────────────────────────────────────────────────
  late TabController _tabController;

  // ── Header ───────────────────────────────────────────────────────────────────
  final _nombreTecnicoCtrl = TextEditingController();
  final _rutTecnicoCtrl    = TextEditingController();
  final _lugarCtrl         = TextEditingController();
  final _supervisorCtrl    = TextEditingController();
  final _horaCtrl          = TextEditingController();
  DateTime _fecha = DateTime.now();
  String? _auditorRut;
  String? _auditorNombre;

  // ── Respuestas B/M/NA (código → valor) ──────────────────────────────────────
  final Map<String, String> _valores = {};

  // ── Campos extra (código_label → valor) ─────────────────────────────────────
  final Map<String, TextEditingController> _extrasCtrl = {};

  // ── Controllers para texto y cantidad ───────────────────────────────────────
  final Map<String, TextEditingController> _textCtrl = {};

  // ── Fotos (código → ruta local) ─────────────────────────────────────────────
  final Map<String, String> _fotos = {};

  // ── Observaciones ────────────────────────────────────────────────────────────
  final _obsEppCtrl    = TextEditingController();
  final _obsVehCtrl    = TextEditingController();
  final _licenciaCtrl  = TextEditingController();
  final _obsEscTelCtrl = TextEditingController();

  // ── Firmas ───────────────────────────────────────────────────────────────────
  late SignatureController _firmaTecnicoCtrl;
  late SignatureController _firmaAuditorCtrl;

  // ── Meta ──────────────────────────────────────────────────────────────────────
  bool _guardando = false;
  final _picker = ImagePicker();

  // ─────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);

    _firmaTecnicoCtrl = SignatureController(
        penStrokeWidth: 2.5, penColor: Colors.white);
    _firmaAuditorCtrl = SignatureController(
        penStrokeWidth: 2.5, penColor: Colors.white);

    _horaCtrl.text = DateFormat('HH:mm').format(DateTime.now());

    // Inicializar controladores para items de texto y cantidad
    for (final item in [..._itemsVehiculo, ..._itemsBotiquin]) {
      _textCtrl[item.codigo] = TextEditingController();
    }
    // Controladores para campos extra de todos los items
    for (final items in [_itemsEpp, _itemsVehiculo, _itemsEscalaTel]) {
      for (final item in items) {
        if (item.extra1 != null) {
          _extrasCtrl['${item.codigo}_${item.extra1}'] = TextEditingController();
        }
        if (item.extra2 != null) {
          _extrasCtrl['${item.codigo}_${item.extra2}'] = TextEditingController();
        }
      }
    }

    _cargarSesion();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _firmaTecnicoCtrl.dispose();
    _firmaAuditorCtrl.dispose();
    for (final c in [
      _nombreTecnicoCtrl, _rutTecnicoCtrl, _lugarCtrl,
      _supervisorCtrl, _horaCtrl, _obsEppCtrl,
      _obsVehCtrl, _licenciaCtrl, _obsEscTelCtrl,
    ]) { c.dispose(); }
    for (final c in _textCtrl.values) { c.dispose(); }
    for (final c in _extrasCtrl.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _cargarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (!mounted) return;
    setState(() {
      _auditorRut    = prefs.getString('rut_tecnico') ?? '';
      _auditorNombre = prefs.getString('nombre_tecnico') ?? '';
    });
  }

  // ── Foto ─────────────────────────────────────────────────────────────────────

  Future<void> _tomarFoto(String codigo) async {
    final photo = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 70);
    if (photo == null) return;
    setState(() => _fotos[codigo] = photo.path);
  }

  // ── Guardar ──────────────────────────────────────────────────────────────────

  Future<void> _guardar({bool completada = false}) async {
    setState(() => _guardando = true);
    try {
      Map<String, dynamic> serializarSeccion(List<_Item> items) {
        final map = <String, dynamic>{};
        for (final item in items) {
          final entry = <String, dynamic>{};
          if (item.tipo == _TipoItem.bmna) {
            entry['valor'] = _valores[item.codigo] ?? '';
          } else {
            entry['valor'] = _textCtrl[item.codigo]?.text.trim() ?? '';
          }
          if (item.extra1 != null) {
            entry['extra1'] =
                _extrasCtrl['${item.codigo}_${item.extra1}']?.text.trim() ?? '';
          }
          if (item.extra2 != null) {
            entry['extra2'] =
                _extrasCtrl['${item.codigo}_${item.extra2}']?.text.trim() ?? '';
          }
          if (_fotos[item.codigo] != null) {
            entry['foto_path'] = _fotos[item.codigo];
          }
          map[item.codigo] = entry;
        }
        return map;
      }

      String? firmaT;
      String? firmaA;
      final bytesT = await _firmaTecnicoCtrl.toPngBytes();
      final bytesA = await _firmaAuditorCtrl.toPngBytes();
      if (bytesT != null && bytesT.isNotEmpty) firmaT = base64Encode(bytesT);
      if (bytesA != null && bytesA.isNotEmpty) firmaA = base64Encode(bytesA);

      final fotosJson = _fotos.entries
          .map((e) => {'codigo': e.key, 'path': e.value})
          .toList();

      await Supabase.instance.client.from('auditorias_prl').insert({
        'rut_tecnico':     _rutTecnicoCtrl.text.trim(),
        'nombre_tecnico':  _nombreTecnicoCtrl.text.trim(),
        'rut_auditor':     _auditorRut ?? '',
        'nombre_auditor':  _auditorNombre ?? '',
        'lugar_auditoria': _lugarCtrl.text.trim(),
        'fecha_auditoria': DateFormat('yyyy-MM-dd').format(_fecha),
        'hora_auditoria':  _horaCtrl.text.trim(),
        'epp':                  serializarSeccion(_itemsEpp),
        'vehiculo':             serializarSeccion(_itemsVehiculo),
        'botiquin':             serializarSeccion(_itemsBotiquin),
        'escala_telescopica':   serializarSeccion(_itemsEscalaTel),
        'escala_tijera':        serializarSeccion(_itemsEscalaTij),
        'observaciones_epp':              _obsEppCtrl.text.trim(),
        'observaciones_vehiculo':         _obsVehCtrl.text.trim(),
        'licencia_conducir':              _licenciaCtrl.text.trim(),
        'observacion_escala_telescopica': _obsEscTelCtrl.text.trim(),
        'fotos':         fotosJson,
        'firma_tecnico': firmaT,
        'firma_auditor': firmaA,
        'estado':        completada ? 'completada' : 'borrador',
      });

      if (!mounted) return;
      if (completada) {
        _mostrarSnack('Auditoría completada y guardada', _colorVerde);
        Navigator.pop(context);
      } else {
        _mostrarSnack('Borrador guardado', _colorAzul);
      }
    } catch (e) {
      if (mounted) _mostrarSnack('Error al guardar: $e', _colorRojo);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _mostrarSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  // ── AppBar + Scaffold ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: _colorCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Auditoría PRL',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16)),
            const Text('F-41 · Check List General',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
        actions: const [],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: _colorPrl,
          labelColor: _colorPrl,
          unselectedLabelColor: Colors.white38,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Datos'),
            Tab(text: 'EPP'),
            Tab(text: 'Vehículo'),
            Tab(text: 'Escalas'),
            Tab(text: 'Firmas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _tabDatos(),
          _tabEpp(),
          _tabVehiculo(),
          _tabEscalas(),
          _tabFirmas(),
        ],
      ),
    );
  }

  // ── Tab 0: Datos ─────────────────────────────────────────────────────────────

  Widget _tabDatos() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _seccionHeader('Identificación', Icons.person_outline, _colorAzul),
          const SizedBox(height: 12),
          _campoTexto('Nombre del Técnico', _nombreTecnicoCtrl),
          const SizedBox(height: 10),
          _campoTexto('RUT del Técnico', _rutTecnicoCtrl, hint: '12345678-9'),
          const SizedBox(height: 10),
          _campoTexto('Lugar de Auditoría', _lugarCtrl),
          const SizedBox(height: 10),
          _campoTexto('Supervisor Responsable', _supervisorCtrl),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _seleccionarFecha,
                  child: _campoStatico(
                    'Fecha',
                    DateFormat('dd/MM/yyyy').format(_fecha),
                    Icons.calendar_today_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: _campoTexto('Hora', _horaCtrl, hint: 'HH:MM')),
            ],
          ),
          const SizedBox(height: 20),
          if (_auditorNombre != null && _auditorNombre!.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _colorPrl.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _colorPrl.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user_rounded,
                      color: _colorPrl, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Auditor',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 11)),
                        Text(
                          _auditorNombre!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                        ),
                        Text(_auditorRut ?? '',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _seleccionarFecha() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark()
            .copyWith(colorScheme: const ColorScheme.dark(primary: _colorPrl)),
        child: child!,
      ),
    );
    if (d != null) setState(() => _fecha = d);
  }

  // ── Tab 1: EPP ───────────────────────────────────────────────────────────────

  Widget _tabEpp() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _seccionHeader('1. Revisión EPP', Icons.health_and_safety, _colorVerde),
        _leyenda(),
        const SizedBox(height: 6),
        ..._itemsEpp.map(_filasBMNA),
        const SizedBox(height: 12),
        _campoObservacion('Observaciones EPP', _obsEppCtrl),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Tab 2: Vehículo ───────────────────────────────────────────────────────────

  Widget _tabVehiculo() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _seccionHeader('2. Vehículo', Icons.directions_car, _colorAzul),
        const SizedBox(height: 8),
        ..._itemsVehiculo.map(_filaTexto),
        const SizedBox(height: 8),
        _campoObservacion('Observaciones Vehículo', _obsVehCtrl),
        const SizedBox(height: 10),
        _campoTexto('Licencia de Conducir', _licenciaCtrl),
        const SizedBox(height: 20),
        _seccionHeader(
            '3. Kit Emergencia / Botiquín', Icons.medical_services, _colorRojo),
        const SizedBox(height: 8),
        ..._itemsBotiquin.map(_filaCantidad),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Tab 3: Escalas ────────────────────────────────────────────────────────────

  Widget _tabEscalas() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _seccionHeader('3. Escala Telescópica', Icons.stairs, _colorAmbar),
        _leyenda(),
        const SizedBox(height: 6),
        ..._itemsEscalaTel.map(_filasBMNA),
        const SizedBox(height: 8),
        _campoObservacion('Observación Escala Telescópica', _obsEscTelCtrl),
        const SizedBox(height: 20),
        _seccionHeader('4. Escala Tijera', Icons.stairs_outlined, _colorNaranja),
        _leyenda(),
        const SizedBox(height: 6),
        ..._itemsEscalaTij.map(_filasBMNA),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Tab 4: Firmas ─────────────────────────────────────────────────────────────

  Widget _tabFirmas() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _seccionHeader(
              'Firma del Técnico Auditado', Icons.draw, _colorAzul),
          const SizedBox(height: 12),
          _padFirma(_firmaTecnicoCtrl, 'Firma del trabajador auditado'),
          const SizedBox(height: 24),
          _seccionHeader('Firma del Auditor', Icons.verified, _colorPrl),
          const SizedBox(height: 12),
          _padFirma(_firmaAuditorCtrl, 'Firma del auditor'),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _guardando ? null : _confirmarCompletar,
              icon: const Icon(Icons.check_circle_rounded),
              label: const Text('Completar Auditoría',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _colorPrl,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _guardando ? null : () => _guardar(),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar Borrador'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _confirmarCompletar() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _colorCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Completar Auditoría',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          '¿Confirmas que la auditoría está finalizada?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _guardar(completada: true);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _colorPrl,
                foregroundColor: Colors.white),
            child: const Text('Completar'),
          ),
        ],
      ),
    );
  }

  // ── Componentes de fila ───────────────────────────────────────────────────────

  Widget _filasBMNA(_Item item) {
    final valor    = _valores[item.codigo];
    final fotoPath = _fotos[item.codigo];
    final esMalo   = valor == 'M';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: _colorCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: esMalo
              ? _colorRojo.withValues(alpha: 0.5)
              : valor == 'B'
                  ? _colorVerde.withValues(alpha: 0.25)
                  : Colors.white12,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    item.codigo.replaceAll(RegExp(r'^[tj]'), ''),
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11),
                  ),
                ),
                Expanded(
                  child: Text(item.nombre,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13)),
                ),
                _btnBMNA('B', item.codigo, _colorVerde),
                const SizedBox(width: 4),
                _btnBMNA('M', item.codigo, _colorRojo),
                const SizedBox(width: 4),
                _btnBMNA('NA', item.codigo, Colors.white38),
                if (esMalo) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _tomarFoto(item.codigo),
                    child: Container(
                      width: 34, height: 32,
                      decoration: BoxDecoration(
                        color: _colorRojo.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _colorRojo.withValues(alpha: 0.4)),
                      ),
                      child: Icon(
                        fotoPath != null
                            ? Icons.photo_camera_rounded
                            : Icons.add_a_photo_rounded,
                        color: _colorRojo,
                        size: 17,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Thumbnail foto
          if (fotoPath != null)
            Padding(
              padding:
                  const EdgeInsets.only(left: 10, right: 10, bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(fotoPath),
                  height: 110,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          // Campos extra
          if (item.extra1 != null)
            Padding(
              padding:
                  const EdgeInsets.only(left: 46, right: 10, bottom: 8),
              child: Row(
                children: [
                  Expanded(child: _campoExtra(item.codigo, item.extra1!)),
                  if (item.extra2 != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                        child: _campoExtra(item.codigo, item.extra2!)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _btnBMNA(String label, String codigo, Color color) {
    final sel = _valores[codigo] == label;
    return GestureDetector(
      onTap: () => setState(() {
        if (sel) {
          _valores.remove(codigo);
        } else {
          _valores[codigo] = label;
        }
      }),
      child: Container(
        width: 34, height: 28,
        decoration: BoxDecoration(
          color: sel
              ? color.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: sel ? color : Colors.white.withValues(alpha: 0.15)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: sel ? color : Colors.white38,
              fontSize: 11,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _filaTexto(_Item item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _colorCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(item.codigo,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ),
              Expanded(
                child: Text(item.nombre,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _inputPequeno(
                    _textCtrl[item.codigo]!, 'Observación'),
              ),
              if (item.extra1 != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                    width: 100,
                    child: _campoExtra(item.codigo, item.extra1!)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _filaCantidad(_Item item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: _colorCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              item.codigo.replaceAll('b', ''),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(item.nombre,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
          SizedBox(
            width: 58,
            child: _inputPequeno(
              _textCtrl[item.codigo]!,
              '0',
              numerico: true,
              centrado: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoExtra(String codigo, String label) {
    final key  = '${codigo}_$label';
    final ctrl = _extrasCtrl[key]!;
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white70, fontSize: 11),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: Colors.white38, fontSize: 10),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _padFirma(SignatureController ctrl, String label) {
    return Column(
      children: [
        Container(
          height: 150,
          decoration: BoxDecoration(
            color: const Color(0xFF0A1628),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Signature(
              controller: ctrl,
              backgroundColor: Colors.transparent,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12)),
            ),
            TextButton.icon(
              onPressed: () => ctrl.clear(),
              icon: const Icon(Icons.refresh_rounded,
                  size: 15, color: Colors.white38),
              label: const Text('Limpiar',
                  style:
                      TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  // ── Helpers UI ────────────────────────────────────────────────────────────────

  Widget _seccionHeader(String titulo, IconData icono, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icono, color: color, size: 18),
          const SizedBox(width: 8),
          Text(titulo,
              style: GoogleFonts.poppins(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
        ],
      ),
    );
  }

  Widget _leyenda() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Row(
        children: [
          _chip('B', 'Bueno',    _colorVerde),
          const SizedBox(width: 10),
          _chip('M', 'Malo',     _colorRojo),
          const SizedBox(width: 10),
          _chip('NA', 'No Aplica', Colors.white38),
        ],
      ),
    );
  }

  Widget _chip(String label, String desc, Color color) {
    return Row(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 3),
        Text(desc,
            style: const TextStyle(
                color: Colors.white38, fontSize: 10)),
      ],
    );
  }

  Widget _campoObservacion(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      maxLines: 3,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: _colorCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _colorPrl),
        ),
      ),
    );
  }

  Widget _campoTexto(String label, TextEditingController ctrl,
      {String? hint}) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white38),
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: _colorCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _colorPrl),
        ),
      ),
    );
  }

  Widget _inputPequeno(TextEditingController ctrl, String hint,
      {bool numerico = false, bool centrado = false}) {
    return TextField(
      controller: ctrl,
      keyboardType:
          numerico ? TextInputType.number : TextInputType.text,
      textAlign: centrado ? TextAlign.center : TextAlign.start,
      style: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: Colors.white24, fontSize: 12),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _campoStatico(String label, String valor, IconData icono) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: _colorCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icono, size: 15, color: Colors.white38),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 10)),
                Text(valor,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
