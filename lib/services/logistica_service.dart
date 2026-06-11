import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'produccion_service.dart';

/// Ítem individual del stock de Kepler (antes de agrupar por categoría).
class ItemStock {
  final int idMaterial;
  final String nombre;
  final String categoria;
  final double cantidad;
  final String? serie; // solo para seriados

  const ItemStock({
    required this.idMaterial,
    required this.nombre,
    required this.categoria,
    required this.cantidad,
    this.serie,
  });

  bool get esSeriado => serie != null;
}

/// Stock agrupado de un técnico, usando las categorías de kMateriales.
class TecnicoStock {
  final String rut;
  final String nombre;
  /// Categoría → cantidad total (solo categorías con cantidad > 0)
  final Map<String, double> stock;
  /// Ítems individuales con id_material y serie (para el intercambio con Kepler)
  final List<ItemStock> items;

  const TecnicoStock({
    required this.rut,
    required this.nombre,
    required this.stock,
    this.items = const [],
  });

  bool get sinStock => stock.isEmpty;

  /// Primer ítem no seriado de [categoria] con saldo suficiente para [cantidad].
  /// Lanza [StateError] si no hay ningún ítem disponible.
  ItemStock itemParaCategoria(String categoria, {int cantidad = 1}) {
    return items.firstWhere(
      (i) => i.categoria == categoria && !i.esSeriado && i.cantidad >= cantidad,
      orElse: () => items.firstWhere(
        (i) => i.categoria == categoria && !i.esSeriado,
        orElse: () => throw StateError('Sin ítem para $categoria'),
      ),
    );
  }

  /// Todos los ítems seriados de [categoria] (para que B escanee y elija).
  List<ItemStock> seriadosPorCategoria(String categoria) =>
      items.where((i) => i.categoria == categoria && i.esSeriado).toList();

  /// Busca un ítem por número de serie (exacto o coincidencia parcial de barcode).
  ItemStock? findSerie(String serie) {
    final candidatas = LogisticaService.variantesSerieEscaneada(serie);
    if (candidatas.isEmpty) return null;

    ItemStock? parcial;
    for (final cand in candidatas) {
      for (final i in items) {
        if (i.serie == null) continue;
        final itemSerie = LogisticaService.normalizeSerie(i.serie!);
        if (itemSerie.isEmpty) continue;
        if (itemSerie == cand) return i;
        if (itemSerie.length >= 6 &&
            cand.length >= 6 &&
            (cand.endsWith(itemSerie) ||
                itemSerie.endsWith(cand) ||
                cand.contains(itemSerie) ||
                itemSerie.contains(cand))) {
          parcial ??= i;
        }
      }
    }
    return parcial;
  }
}

class LogisticaService {
  static const _url = 'https://logistica.sbip.cl/api/get_all_saldo';

  /// SKUs Kepler clasificados como decodificador Claro (resto deco → VTR).
  static const Set<String> skusDecodificadorClaro = {
    'CL-000-0040-23017',
    'CL-000-0040-24563',
    'CL-000-0040-24818',
  };

  static bool esTipoDecodificador(String tipoMaterial) =>
      tipoMaterial.contains('Decodificador');

  /// Clave de comparación (sin puntos ni guión).
  static String normalizeRutKey(String rut) =>
      rut.replaceAll(RegExp(r'[.\-\s]'), '').toUpperCase();

  /// Formato estándar Kepler: 12345678-9
  static String canonicalRut(String rut) {
    final k = normalizeRutKey(rut);
    if (k.length < 2) return rut.trim();
    return '${k.substring(0, k.length - 1)}-${k.substring(k.length - 1)}';
  }

  static bool sameRut(String a, String b) =>
      normalizeRutKey(a) == normalizeRutKey(b);

  /// Normaliza serie escaneada (espacios, prefijos GS1, códigos de barra).
  static String normalizeSerie(String raw) {
    var s = raw.trim().toUpperCase();
    if (s.isEmpty) return s;

    // Prefijos habituales en etiquetas
    for (final p in ['S/N:', 'SN:', 'SERIE:', 'SERIAL:', 'N/S:']) {
      if (s.startsWith(p)) {
        s = s.substring(p.length).trim();
        break;
      }
    }

    // Códigos GS1 / Code128: ]C1, ]E0, FNC1 (␝), etc.
    s = s.replaceAll(RegExp(r'^\](?:C1|E0|E3|d2)'), '');
    s = s.replaceAll(RegExp(r'[\x1D\x1E]'), ' ');

    // AI 21 (número de serie) en cualquier posición
    final m21 = RegExp(r'(?:\(21\)|21)([A-Z0-9]{5,})').firstMatch(s);
    if (m21 != null) return m21.group(1)!;

    // Último bloque alfanumérico largo (típico en etiquetas ONT/deco)
    final bloques = RegExp(r'[A-Z0-9]{8,}')
        .allMatches(s.replaceAll(RegExp(r'[^A-Z0-9]'), ' '))
        .map((m) => m.group(0)!)
        .toList();
    if (bloques.isNotEmpty) return bloques.last;

    return s.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  /// Variantes posibles de una lectura de escáner para cruzar con Kepler.
  static List<String> variantesSerieEscaneada(String raw) {
    final out = <String>{};
    void add(String? v) {
      if (v == null || v.isEmpty) return;
      out.add(v);
    }

    final upper = raw.trim().toUpperCase();
    add(normalizeSerie(raw));

    for (final m in RegExp(r'(?:\(21\)|21)([A-Z0-9]{5,})')
        .allMatches(upper)) {
      add(normalizeSerie(m.group(1)!));
    }
    for (final m
        in RegExp(r'[A-Z0-9]{8,}').allMatches(upper.replaceAll(RegExp(r'[^A-Z0-9]'), ' '))) {
      add(m.group(0));
    }
    add(upper.replaceAll(RegExp(r'[^A-Z0-9]'), ''));

    return out.where((s) => s.length >= 5).toList();
  }

  /// Normaliza serie para almacenar; retorna null si queda vacía.
  static String? _normalizeSerieAlmacenada(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = normalizeSerie(raw);
    return s.isEmpty ? null : s;
  }

  Future<Map<String, dynamic>> _fetchApiData() async {
    final response = await http
        .get(Uri.parse(_url))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Error logística HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  void _procesarItems(
    List<dynamic> apiItems,
    Map<String, Map<String, double>> acum,
    Map<String, List<ItemStock>> rawItems, {
    bool porSerie = false,
  }) {
    for (final item in apiItems) {
      final rutRaw = item['trabajador_rut'] as String? ?? '';
      final rut    = canonicalRut(rutRaw);
      final idMat  = item['id_material'];
      if (rut.isEmpty || idMat == null) continue;

      final idMaterial = idMat is int ? idMat : int.tryParse(idMat.toString());
      if (idMaterial == null) continue;

      final cantidad = porSerie
          ? 1.0
          : (double.tryParse(item['cantidad']?.toString() ?? '0') ?? 0);
      if (cantidad <= 0) continue;

      final nombreErp = item['nombre'] as String? ?? '';
      final sku      = item['sku']?.toString();
      final cat = categorizar(nombreErp, sku: sku);
      if (cat == null) continue;

      final serieRaw = porSerie
          ? _normalizeSerieAlmacenada(item['serie']?.toString())
          : null;

      if (porSerie && (serieRaw == null || serieRaw.isEmpty)) continue;

      acum.putIfAbsent(rut, () => {});
      acum[rut]![cat] = (acum[rut]![cat] ?? 0) + cantidad;

      rawItems.putIfAbsent(rut, () => []);
      rawItems[rut]!.add(ItemStock(
        idMaterial: idMaterial,
        nombre:     nombreErp,
        categoria:  cat,
        cantidad:   cantidad,
        serie:      serieRaw,
      ));
    }
  }

  /// `null` si el RUT puede solicitar material; mensaje legible si debe bloquearse.
  Future<String?> mensajeBloqueoSolicitudMaterial(String rut) async {
    final canon = canonicalRut(rut);
    final db = Supabase.instance.client;

    final results = await Future.wait<dynamic>([
      db.from('nomina_bodega').select('rut').eq('rut', canon).maybeSingle(),
      db.from('supervisores_crea').select('rut').eq('rut', canon).maybeSingle(),
      db.from('roles_flota').select('rut').eq('rut', canon).maybeSingle(),
    ]);

    if (results[0] != null) {
      return 'Los bodegueros no pueden solicitar material de campo desde esta pantalla.';
    }
    if (results[1] != null) {
      return 'Los supervisores gestionan solicitudes desde el panel de supervisor.';
    }
    if (results[2] != null) {
      return 'Tu perfil de flota no puede solicitar material de campo.';
    }

    try {
      await nombreDesdeNomina(rut);
      return null;
    } on StateError catch (e) {
      return e.message;
    }
  }

  /// Nombre por RUT: nómina primero; caché de sesión solo si el RUT es el logueado.
  Future<String> nombreParaSesion(String rut, {String? nombreSesion}) async {
    if (rut.trim().isEmpty) {
      final local = nombreSesion?.trim();
      return (local != null && local.isNotEmpty) ? local : '';
    }
    try {
      return await nombreDesdeNomina(rut);
    } catch (_) {
      final canon = canonicalRut(rut);
      final prefs = await SharedPreferences.getInstance();
      final rutSesion = canonicalRut(
        prefs.getString('rut_tecnico') ??
            prefs.getString('user_rut') ??
            '',
      );
      if (canon == rutSesion) {
        final n = (prefs.getString('nombre_tecnico') ??
                prefs.getString('user_nombre') ??
                '')
            .trim();
        if (n.isNotEmpty) return n;
      }
      final local = nombreSesion?.trim();
      if (local != null && local.isNotEmpty) return local;
      return canon;
    }
  }

  /// Nombre por RUT desde nómina (fuente de verdad en guías / traspasos / PDF).
  Future<String> nombrePorRut(String rut, {String? fallback}) async {
    if (rut.trim().isEmpty) {
      final fb = fallback?.trim();
      return (fb != null && fb.isNotEmpty) ? fb : '';
    }
    try {
      return await nombreDesdeNomina(rut);
    } catch (_) {
      final fb = fallback?.trim();
      return (fb != null && fb.isNotEmpty) ? fb : canonicalRut(rut);
    }
  }

  static String _nombreDesdeFilaNomina(Map<String, dynamic> row) {
    final nombre =
        '${row['nombres'] ?? ''} ${row['paterno'] ?? ''} ${row['materno'] ?? ''}'
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ');
    return nombre;
  }

  static List<String> _variantesRutNomina(String rut) {
    final canon = canonicalRut(rut);
    final key = normalizeRutKey(rut);
    return {
      canon,
      rut.trim(),
      key,
      key.replaceAll(RegExp(r'[.\-\s]'), ''),
      ...ProduccionService.rutVariantes(rut),
      ...ProduccionService.rutVariantes(canon),
    }.where((s) => s.isNotEmpty).toList();
  }

  /// Nombre canónico desde nómina (técnicos o bodegueros).
  Future<String> nombreDesdeNomina(String rut) async {
    final variantes = _variantesRutNomina(rut);
    final db = Supabase.instance.client;

    final bodega = await db
        .from('nomina_bodega')
        .select('rut, nombre')
        .inFilter('rut', variantes)
        .limit(1)
        .maybeSingle();
    if (bodega != null) {
      final nombreBod = bodega['nombre']?.toString().trim() ?? '';
      if (nombreBod.isNotEmpty) return nombreBod;
    }

    final row = await db
        .from('nomina_tecnicos')
        .select('rut, nombres, paterno, materno')
        .inFilter('rut', variantes)
        .limit(1)
        .maybeSingle();
    if (row == null) {
      throw StateError('RUT ${canonicalRut(rut)} no está en nómina de técnicos');
    }
    final nombre = _nombreDesdeFilaNomina(Map<String, dynamic>.from(row as Map));
    if (nombre.isEmpty) {
      throw StateError('RUT ${canonicalRut(rut)} sin nombre en nómina');
    }
    return nombre;
  }

  Future<String?> _nombreNomina(String rut) async {
    try {
      return await nombreDesdeNomina(rut);
    } catch (_) {
      return null;
    }
  }

  /// Mapa RUT canónico → nombre completo para todos los técnicos en nómina.
  Future<Map<String, String>> _cargarNombresNomina() async {
    final rows = await Supabase.instance.client
        .from('nomina_tecnicos')
        .select('rut, nombres, paterno, materno');

    final Map<String, String> nombrePorRut = {};
    for (final r in rows as List) {
      final rut = canonicalRut(r['rut'] as String? ?? '');
      final nombre =
          '${r['nombres'] ?? ''} ${r['paterno'] ?? ''} ${r['materno'] ?? ''}'
              .trim()
              .replaceAll(RegExp(r'\s+'), ' ');
      if (rut.isNotEmpty && nombre.isNotEmpty) {
        nombrePorRut[rut] = nombre;
      }
    }
    return nombrePorRut;
  }

  /// Stock de un técnico directo desde Kepler (sin depender del listado global).
  /// [nombreDisplay]: respaldo si el RUT no está en nómina.
  Future<TecnicoStock?> fetchStockTecnico(
    String rut, {
    String? nombreDisplay,
  }) async {
    final rutCanon = canonicalRut(rut);
    final nombreNomina = await _nombreNomina(rutCanon);
    final display = nombreDisplay?.trim();
    final nombre = (nombreNomina != null && nombreNomina.isNotEmpty)
        ? nombreNomina
        : (display != null && display.isNotEmpty ? display : null);
    if (nombre == null || nombre.isEmpty) return null;
    if (display != null &&
        display.isNotEmpty &&
        nombreNomina != null &&
        nombreNomina.toLowerCase() != display.toLowerCase()) {
      // ignore: avoid_print
      print(
          '[Logistica] nombre cacheado "$display" → nómina "$nombreNomina" '
          '($rutCanon)');
    }

    final data = await _fetchApiData();
    final acum     = <String, Map<String, double>>{};
    final rawItems = <String, List<ItemStock>>{};

    _procesarItems(data['no_seriados'] as List<dynamic>? ?? [], acum, rawItems);
    _procesarItems(
      data['seriados'] as List<dynamic>? ?? [],
      acum,
      rawItems,
      porSerie: true,
    );

    final rutKey = _resolverRutEnMapa(acum, rutCanon);
    final stock  = rutKey != null ? acum[rutKey] : null;
    if (stock == null || stock.isEmpty) {
      return TecnicoStock(rut: rutCanon, nombre: nombre, stock: const {}, items: const []);
    }

    return TecnicoStock(
      rut:    rutCanon,
      nombre: nombre,
      stock:  stock,
      items:  rutKey != null ? (rawItems[rutKey] ?? []) : const [],
    );
  }

  /// Kepler a veces devuelve el RUT con formato distinto al de nómina.
  static String? _resolverRutEnMapa(
    Map<String, Map<String, double>> acum,
    String rutCanon,
  ) {
    if (acum.containsKey(rutCanon)) return rutCanon;
    for (final k in acum.keys) {
      if (sameRut(k, rutCanon)) return k;
    }
    return null;
  }

  /// Busca una serie en Kepler y devuelve el ítem si pertenece al [rut].
  Future<ItemStock?> buscarSerieTecnico(String rut, String serie) async {
    final s = normalizeSerie(serie);
    final tecnico = await fetchStockTecnico(rut);
    return tecnico?.findSerie(s);
  }

  // ── Categorización ──────────────────────────────────────────
  // Mapea el nombre del ERP → categoría de kMateriales.
  // Retorna null si no pertenece a ninguna categoría relevante.
  static String? _categoriaDecodificador(String? sku) {
    final skuNorm = (sku ?? '').trim().toUpperCase();
    return skusDecodificadorClaro.contains(skuNorm)
        ? 'Decodificador Claro'
        : 'Decodificador VTR';
  }

  static String? categorizar(String nombreErp, {String? sku}) {
    final n = nombreErp.toUpperCase();

    // Accesorios / herramientas — no son material consumible en OT.
    if (n.contains('PLANTILLA')) return null;

    if (n.contains('ROSETA'))                                      return 'Roseta';
    if (n.contains('JUMPER') || n.contains('LATIGUILLO'))          return 'Jumper';
    if (n.contains('AMARRA'))                                      return 'Amarras plásticas';
    if (n.contains('FICHA') &&
        (n.contains('ABONADO') || n.contains('CLIENTE')))         return 'Ficha de abonado';
    if ((n.contains('SOPORTE') &&
         (n.contains('DROP') || n.contains('CABLE'))) ||
        (n.contains('ABRAZADERA') && n.contains('DROP')))         return 'Soportes drop';
    if (n.contains('CONECTOR') &&
        (n.contains('CAMPO') || n.contains('SCAPC') ||
         n.contains('SC/APC') || n.contains('SC-APC') ||
         n.contains('SC/UPC') || n.contains('SC APC')))           return 'Conector de campo';

    // Drop: triggered también por HIBRIDO/FSTCONN/FO+MTS (cables sin la palabra DROP)
    if (n.contains('DROP') || n.contains('CABLE DROP') ||
        n.contains('HIBRIDO') || n.contains('FSTCONN') ||
        (n.contains('FO') && n.contains('MTS'))) {
      if (n.contains('300'))                      return 'Drop 300m';
      if (n.contains('220') || n.contains('200')) return 'Drop 200m';
      if (n.contains('150'))                      return 'Drop 150m';
      if (n.contains('100'))                      return 'Drop 100m';
    }

    if (n.contains('EXTENSOR') ||
        n.contains('K562') || n.contains('H3601'))                return 'Extensor';

    // ONT/ONU — evitar matches con "CONTRATO", "CONTROL", etc.
    if (n.contains(' ONT') || n.startsWith('ONT') ||
        n.contains(' ONU') || n.startsWith('ONU')) {
      if (n.contains('ZTE'))    return 'ONT ZTE';
      if (n.contains('HUAWEI')) return 'ONT Huawei';
      return 'ONT ZTE'; // fallback a ZTE si no se puede determinar
    }

    if (n.contains('DECODIFICADOR') || n.contains('DECO ') ||
        n.contains('STB') || n.contains('SET TOP') ||
        n.contains('CPE') || n.contains('FUSE4K') ||
        n.contains('FUSE 4K') || n.contains('FUSE STICK')) {
      return _categoriaDecodificador(sku);
    }

    // ── Nuevas categorías ────────────────────────────────────────
    if (n.contains('CANCAMO') || n.contains('CÁNCAMO'))          return 'Cáncamos';
    if (n.contains('GRAMPA') && n.contains('NEGRA'))             return 'Grampa negra';
    if (n.contains('GRAMPA') &&
        (n.contains('BLANCA') || n.contains('CHS')))             return 'Grampa blanca';
    if (n.contains('PASACABLE') && n.contains('BLANCO'))         return 'Pasacable blanco';
    if (n.contains('PASACABLE') && n.contains('NEGRO'))          return 'Pasacable negro';
    if (n.contains('CABLE UTP') || n.contains('CAT5E'))          return 'Cable UTP';
    if (n.contains('RJ45') || n.contains('RJ 45') ||
        n.contains('RJ-45'))                                     return 'Conector RJ45';
    if (n.contains('MICRO USB'))                                  return 'Micro USB';

    return null;
  }

  // ── Fetch principal ─────────────────────────────────────────

  Future<List<TecnicoStock>> fetchStock() async {
    // Todos los técnicos en nómina (sin filtrar por equipo/supervisor CREA).
    final nombrePorRut = await _cargarNombresNomina();

    final data = await _fetchApiData();

    // Acumular stock por RUT + categoría, guardando también ítems individuales
    final Map<String, Map<String, double>> acum  = {};
    final Map<String, List<ItemStock>>     rawItems = {};

    _procesarItems(data['no_seriados'] as List<dynamic>? ?? [], acum, rawItems);
    _procesarItems(
      data['seriados'] as List<dynamic>? ?? [],
      acum,
      rawItems,
      porSerie: true,
    );

    // Solo técnicos con saldo en Kepler y ficha en nomina_tecnicos.
    final List<TecnicoStock> resultado = [];

    for (final entry in acum.entries) {
      final rut    = entry.key;
      final nombre = nombrePorRut[rut];
      if (nombre == null) continue;

      resultado.add(TecnicoStock(
        rut:    rut,
        nombre: nombre,
        stock:  entry.value,
        items:  rawItems[rut] ?? [],
      ));
    }

    resultado.sort((a, b) =>
        a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));

    return resultado;
  }

  // ── Fetch con índice completo de series ─────────────────────────────────
  // Igual que fetchStock() pero también devuelve un mapa SERIE→nombre que
  // incluye TODOS los técnicos de Kepler (no solo los filtrados por supervisor).
  // Usado en auditoría de bodega para identificar dueños de series ajenas.

  Future<({List<TecnicoStock> tecnicos, Map<String, String> serieDueno})>
      fetchStockConIndice() async {
    final nombreTodos = await _cargarNombresNomina();

    final data = await _fetchApiData();

    final Map<String, Map<String, double>> acum     = {};
    final Map<String, List<ItemStock>>     rawItems = {};
    final Map<String, String>              serieDueno = {};

    void procesarCompleto(List<dynamic> apiItems, {bool porSerie = false}) {
      for (final item in apiItems) {
        final rut    = canonicalRut(item['trabajador_rut'] as String? ?? '');
        final idMat  = item['id_material'];
        if (rut.isEmpty || idMat == null) continue;

        final idMaterial = idMat is int ? idMat : int.tryParse(idMat.toString());
        if (idMaterial == null) continue;

        final cantidad = porSerie
            ? 1.0
            : (double.tryParse(item['cantidad']?.toString() ?? '0') ?? 0);
        if (cantidad <= 0) continue;

        final nombreErp = item['nombre'] as String? ?? '';
        final sku      = item['sku']?.toString();
        final cat = categorizar(nombreErp, sku: sku);
        if (cat == null) continue;

        final serieRaw = porSerie
            ? _normalizeSerieAlmacenada(item['serie']?.toString())
            : null;

        if (porSerie && serieRaw != null && serieRaw.isNotEmpty) {
          serieDueno[serieRaw] = nombreTodos[rut] ?? rut;
        }

        if (!nombreTodos.containsKey(rut)) continue;

        acum.putIfAbsent(rut, () => {});
        acum[rut]![cat] = (acum[rut]![cat] ?? 0) + cantidad;

        rawItems.putIfAbsent(rut, () => []);
        rawItems[rut]!.add(ItemStock(
          idMaterial: idMaterial,
          nombre:     nombreErp,
          categoria:  cat,
          cantidad:   cantidad,
          serie:      serieRaw,
        ));
      }
    }

    procesarCompleto(data['no_seriados'] as List<dynamic>? ?? []);
    procesarCompleto(data['seriados']    as List<dynamic>? ?? [], porSerie: true);

    final List<TecnicoStock> resultado = [];
    for (final entry in acum.entries) {
      final rut    = entry.key;
      final nombre = nombreTodos[rut];
      if (nombre == null) continue;
      resultado.add(TecnicoStock(
        rut:    rut,
        nombre: nombre,
        stock:  entry.value,
        items:  rawItems[rut] ?? [],
      ));
    }
    resultado.sort((a, b) =>
        a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));

    return (tecnicos: resultado, serieDueno: serieDueno);
  }
}
