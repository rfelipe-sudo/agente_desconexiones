import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

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
}

class LogisticaService {
  static const _url = 'https://logistica.sbip.cl/api/get_all_saldo';

  // ── Categorización ──────────────────────────────────────────
  // Mapea el nombre del ERP → categoría de kMateriales.
  // Retorna null si no pertenece a ninguna categoría relevante.
  static String? categorizar(String nombreErp) {
    final n = nombreErp.toUpperCase();

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
        n.contains('STB ') || n.contains('SET TOP') ||
        n.contains('CPE ') || n.contains('FUSE4K') ||
        n.contains('FUSE 4K'))                                    return 'Decodificador';

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
    final db = Supabase.instance.client;

    // 1. Todos los RUTs registrados en la relación supervisor-técnico
    final stcRows = await db
        .from('supervisor_tecnicos_crea')
        .select('rut_tecnico');

    final ruts = (stcRows as List)
        .map((r) => r['rut_tecnico'] as String? ?? '')
        .where((r) => r.isNotEmpty)
        .toSet()
        .toList();

    // 2. Nombres desde nómina
    final Map<String, String> nombrePorRut = {};
    if (ruts.isNotEmpty) {
      final nominaRows = await db
          .from('nomina_tecnicos')
          .select('rut, nombres, paterno, materno')
          .inFilter('rut', ruts);

      for (final r in nominaRows as List) {
        final rut = r['rut'] as String? ?? '';
        final nombre =
            '${r['nombres'] ?? ''} ${r['paterno'] ?? ''} ${r['materno'] ?? ''}'
                .trim()
                .replaceAll(RegExp(r'\s+'), ' ');
        if (rut.isNotEmpty && nombre.isNotEmpty) {
          nombrePorRut[rut] = nombre;
        }
      }
    }

    // 2. Llamar API de logística
    final response = await http
        .get(Uri.parse(_url))
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Error logística HTTP ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;

    // 3. Acumular stock por RUT + categoría, guardando también ítems individuales
    final Map<String, Map<String, double>> acum  = {};
    final Map<String, List<ItemStock>>     rawItems = {};

    void procesar(List<dynamic> apiItems, {bool porSerie = false}) {
      for (final item in apiItems) {
        final rut      = item['trabajador_rut'] as String? ?? '';
        final nombre   = item['nombre'] as String? ?? '';
        final idMat    = item['id_material'];
        if (rut.isEmpty || idMat == null) continue;

        final idMaterial = idMat is int ? idMat : int.tryParse(idMat.toString());
        if (idMaterial == null) continue;

        final cantidad = porSerie
            ? 1.0
            : (double.tryParse(item['cantidad']?.toString() ?? '0') ?? 0);
        if (cantidad <= 0) continue;

        final cat = categorizar(nombre);
        if (cat == null) continue;

        final serie = porSerie ? item['serie']?.toString() : null;

        acum.putIfAbsent(rut, () => {});
        acum[rut]![cat] = (acum[rut]![cat] ?? 0) + cantidad;

        rawItems.putIfAbsent(rut, () => []);
        rawItems[rut]!.add(ItemStock(
          idMaterial: idMaterial,
          nombre:     nombre,
          categoria:  cat,
          cantidad:   cantidad,
          serie:      serie,
        ));
      }
    }

    procesar(data['no_seriados'] as List<dynamic>? ?? []);
    procesar(data['seriados']    as List<dynamic>? ?? [], porSerie: true);

    // 4. Construir lista de TecnicoStock — solo técnicos con nombre en Supabase
    final List<TecnicoStock> resultado = [];

    for (final entry in acum.entries) {
      final rut    = entry.key;
      final nombre = nombrePorRut[rut];
      if (nombre == null) continue; // técnico fuera del equipo/sin registro

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
}
