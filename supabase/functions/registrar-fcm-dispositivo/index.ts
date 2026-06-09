/**
 * Edge Function: registrar-fcm-dispositivo
 *
 * Registra el token FCM del celular en TODAS las tablas donde exista el RUT
 * (nomina_tecnicos, nomina_bodega, roles_flota, supervisores_crea).
 * Una sola llamada al abrir la app.
 *
 * Body: { rut: string, fcm_token: string }
 */
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function rutVariantes(rut: string): string[] {
  const limpio = rut.trim().toUpperCase().replace(/\./g, "");
  const sinGuion = limpio.replace(/-/g, "");
  if (sinGuion.length < 2) return [rut.trim()].filter(Boolean);
  const body = sinGuion.slice(0, -1);
  const dv = sinGuion.slice(-1);
  const canon = `${body}-${dv}`;
  return [...new Set([rut.trim(), limpio, sinGuion, canon])].filter(
    (s) => s.length > 0,
  );
}

async function actualizarTokenEnTabla(
  supabase: ReturnType<typeof createClient>,
  tabla: string,
  rut: string,
  fcmToken: string,
): Promise<boolean> {
  const variantes = rutVariantes(rut);
  const { data: filas, error } = await supabase
    .from(tabla)
    .select("rut")
    .in("rut", variantes);
  if (error || !filas?.length) return false;

  const dbRut = String(filas[0].rut ?? "");
  if (!dbRut) return false;

  const { data: upd, error: updErr } = await supabase
    .from(tabla)
    .update({ fcm_token: fcmToken })
    .eq("rut", dbRut)
    .select("rut");
  return !updErr && (upd?.length ?? 0) > 0;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    const body = await req.json();
    const rut = String(body.rut ?? "").trim();
    const fcmToken = String(body.fcm_token ?? body.token ?? "").trim();

    if (!rut || !fcmToken) {
      return json(400, { error: "rut y fcm_token requeridos" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceKey) {
      return json(500, { error: "Supabase no configurado" });
    }

    const supabase = createClient(supabaseUrl, serviceKey);
    const actualizado: Record<string, boolean> = {
      nomina_tecnicos: await actualizarTokenEnTabla(
        supabase,
        "nomina_tecnicos",
        rut,
        fcmToken,
      ),
      nomina_bodega: await actualizarTokenEnTabla(
        supabase,
        "nomina_bodega",
        rut,
        fcmToken,
      ),
      roles_flota: await actualizarTokenEnTabla(
        supabase,
        "roles_flota",
        rut,
        fcmToken,
      ),
      supervisores_crea: await actualizarTokenEnTabla(
        supabase,
        "supervisores_crea",
        rut,
        fcmToken,
      ),
    };

    console.log(
      `registrar-fcm-dispositivo rut=${rut} → ${JSON.stringify(actualizado)}`,
    );
    return json(200, { ok: true, actualizado });
  } catch (e) {
    console.error(e);
    return json(500, { error: String(e) });
  }
});
