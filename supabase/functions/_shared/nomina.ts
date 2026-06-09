import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export function canonicalRut(rut: string): string {
  const s = rut.trim().toUpperCase().replace(/\./g, "");
  if (s.length < 2) return s;
  const body = s.slice(0, -1).replace(/-/g, "");
  const dv = s.slice(-1);
  return `${body}-${dv}`;
}

export function rutVariantes(rut: string): string[] {
  const canon = canonicalRut(rut);
  const key = canon.replace(/[.\-\s]/g, "");
  return [...new Set([canon, rut.trim(), key])].filter((s) => s.length > 3);
}

export async function nombreBodegueroPorRut(
  supabase: SupabaseClient,
  rut: string,
): Promise<string | null> {
  const vars = rutVariantes(rut);
  if (vars.length === 0) return null;

  const { data } = await supabase
    .from("nomina_bodega")
    .select("rut, nombre")
    .in("rut", vars)
    .limit(1)
    .maybeSingle();

  const nombre = data?.nombre?.toString().trim();
  return nombre || null;
}

export async function nombreTecnicoPorRut(
  supabase: SupabaseClient,
  rut: string,
): Promise<string | null> {
  const vars = rutVariantes(rut);
  if (vars.length === 0) return null;

  const { data } = await supabase
    .from("nomina_tecnicos")
    .select("rut, nombres, paterno, materno")
    .in("rut", vars)
    .limit(1)
    .maybeSingle();

  if (!data) return null;
  const nombre =
    `${data.nombres ?? ""} ${data.paterno ?? ""} ${data.materno ?? ""}`
      .trim()
      .replace(/\s+/g, " ");
  return nombre || null;
}

export async function rutCanonicoBodeguero(
  supabase: SupabaseClient,
  rut: string,
): Promise<string | null> {
  const vars = rutVariantes(rut);
  if (vars.length === 0) return null;

  const { data } = await supabase
    .from("nomina_bodega")
    .select("rut")
    .in("rut", vars)
    .limit(1)
    .maybeSingle();

  const rutDb = data?.rut?.toString().trim();
  return rutDb ? canonicalRut(rutDb) : null;
}
