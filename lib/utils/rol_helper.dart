/// Resolución de roles CREABOX desde BD / cargo en plantel.
class RolHelper {
  RolHelper._();

  /// `jefe_calidad` / `supervisor_calidad` / `ito_calidad` según cargo; `ito` si es ITO genérico.
  static String? rolDesdeCargo(String? cargo) {
    if (cargo == null || cargo.trim().isEmpty) return null;
    final c = cargo.toLowerCase();
    if (c.contains('jefe') && c.contains('calidad')) return 'jefe_calidad';
    if (c.contains('supervisor') && c.contains('calidad')) {
      return 'supervisor_calidad';
    }
    if (c.contains('ito') && c.contains('calidad')) return 'ito_calidad';
    if (c.contains('ito')) return 'ito';
    return null;
  }

  static String normalizar(String? rol, {String? cargo}) {
    final r = rol?.toLowerCase().trim();
    if (r == 'jefe_calidad') return 'jefe_calidad';
    if (r == 'supervisor_calidad') return 'supervisor_calidad';
    if (r == 'ito_calidad') return 'ito_calidad';
    if (r == 'ito') return 'ito';
    if (r == 'supervisor' || r == 'bodeguero') return r!;
    final desdeCargo = rolDesdeCargo(cargo);
    if (desdeCargo != null) return desdeCargo;
    return (r != null && r.isNotEmpty) ? r : 'tecnico';
  }
}
