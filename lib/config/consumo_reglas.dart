/// Reglas MIN/MAX de consumo por categoría (`kMateriales`) y tipo de actividad.
///
/// Instalación, migración, modificación y traslado: mínimos en algunas categorías + máximos.
/// Reparaciones: solo máximos (sin mínimos).
class ConsumoRegla {
  final String categoria;
  final int? minimo;
  final int? maximo;

  const ConsumoRegla({
    required this.categoria,
    this.minimo,
    this.maximo,
  });
}

/// Límites globales para equipos seriados (independientes del Excel).
const kConsumoMaxOnt = 1;
const kConsumoMaxDeco = 4;
const kConsumoMaxExtensor = 2;

const kConsumoCategoriasOnt = ['ONT ZTE', 'ONT Huawei'];
const kConsumoCategoriasDeco = ['Decodificador Claro', 'Decodificador VTR'];
const kConsumoCategoriaExtensor = 'Extensor';
const kConsumoCategoriasDrop = [
  'Drop 100m',
  'Drop 150m',
  'Drop 200m',
  'Drop 300m',
];
const kConsumoMaxDropTotal = 1;

/// Reglas base (Excel: NEUTRA ALTA / instalación-migración-traslado).
/// Drop: máx 1 por OT en total (cualquier medida), sin mínimo por tipo.
/// Soportes drop, cáncamos y pasacable negro: solo máximo, sin mínimo.
const _reglasInstalacion = [
  ConsumoRegla(categoria: 'Drop 100m', maximo: 1),
  ConsumoRegla(categoria: 'Drop 150m', maximo: 1),
  ConsumoRegla(categoria: 'Drop 200m', maximo: 1),
  ConsumoRegla(categoria: 'Drop 300m', maximo: 1),
  ConsumoRegla(categoria: 'Ficha de abonado', minimo: 1, maximo: 1),
  ConsumoRegla(categoria: 'Soportes drop', maximo: 20),
  ConsumoRegla(categoria: 'Cáncamos', maximo: 2),
  ConsumoRegla(categoria: 'Amarras plásticas', minimo: 5, maximo: 30),
  ConsumoRegla(categoria: 'Pasacable negro', maximo: 4),
  ConsumoRegla(categoria: 'Grampa negra', minimo: 20, maximo: 50),
  ConsumoRegla(categoria: 'Roseta', minimo: 1, maximo: 1),
  ConsumoRegla(categoria: 'Conector de campo', minimo: 1, maximo: 2),
  ConsumoRegla(categoria: 'Jumper', minimo: 1, maximo: 1),
  ConsumoRegla(categoria: 'Micro USB', maximo: 5),
  ConsumoRegla(categoria: 'Cable UTP', maximo: 80),
  ConsumoRegla(categoria: 'Pasacable blanco', maximo: 10),
  ConsumoRegla(categoria: 'Grampa blanca', maximo: 50),
  ConsumoRegla(categoria: 'Conector RJ45', maximo: 10),
];

bool consumoEsReparacion(String tipoActividad) {
  final t = tipoActividad.toLowerCase();
  return t.contains('repar');
}

bool consumoExigirMinimos(String tipoActividad) =>
    !consumoEsReparacion(tipoActividad);

ConsumoRegla? consumoReglaPara(String categoria, String tipoActividad) {
  for (final r in _reglasInstalacion) {
    if (r.categoria == categoria) {
      if (consumoEsReparacion(tipoActividad)) {
        return ConsumoRegla(categoria: categoria, maximo: r.maximo);
      }
      return r;
    }
  }
  return null;
}

int? consumoMinimo(String categoria, String tipoActividad) {
  if (!consumoExigirMinimos(tipoActividad)) return null;
  return consumoReglaPara(categoria, tipoActividad)?.minimo;
}

int? consumoMaximo(String categoria, String tipoActividad) =>
    consumoReglaPara(categoria, tipoActividad)?.maximo;

/// Categorías con regla definida (para mostrar aunque no vengan explícitas en receta).
Set<String> get consumoCategoriasConRegla =>
    _reglasInstalacion.map((r) => r.categoria).toSet();

String? validarConsumoCantidades({
  required String tipoActividad,
  required Map<String, int> totalPorCategoria,
  required int totalOnt,
  required int totalDeco,
  required String? marcaDecoSeleccionada,
  required int totalExtensor,
  Set<String>? limitarCategorias,
}) {
  if (totalOnt > kConsumoMaxOnt) {
    return 'Máximo $kConsumoMaxOnt ONT por OT (sin importar marca).';
  }
  if (totalDeco > kConsumoMaxDeco) {
    return 'Máximo $kConsumoMaxDeco decodificadores por OT.';
  }
  if (totalExtensor > kConsumoMaxExtensor) {
    return 'Máximo $kConsumoMaxExtensor extensores por OT.';
  }

  var totalDrop = 0;
  for (final cat in kConsumoCategoriasDrop) {
    totalDrop += totalPorCategoria[cat] ?? 0;
  }
  if (totalDrop > kConsumoMaxDropTotal) {
    return 'Solo se puede consumir 1 drop por OT (100m, 150m, 200m o 300m).';
  }

  if (consumoExigirMinimos(tipoActividad)) {
    for (final r in _reglasInstalacion) {
      if (limitarCategorias != null && !limitarCategorias.contains(r.categoria)) {
        continue;
      }
      if (r.minimo == null || r.minimo! <= 0) continue;
      final total = totalPorCategoria[r.categoria] ?? 0;
      if (total < r.minimo!) {
        return '${r.categoria}: mínimo ${r.minimo} (tienes $total).';
      }
    }
  }

  for (final entry in totalPorCategoria.entries) {
    if (limitarCategorias != null && !limitarCategorias.contains(entry.key)) {
      continue;
    }
    final max = consumoMaximo(entry.key, tipoActividad);
    if (max != null && entry.value > max) {
      return '${entry.key}: máximo $max (tienes ${entry.value}).';
    }
  }

  return null;
}
