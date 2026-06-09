import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  enviarCorreoAprobacion,
  enviarCorreoSapOk,
  remitenteResend,
} from "../_shared/traspaso_email.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json", ...CORS },
    });

  try {
    const body = await req.json();
    const modo = String(body.modo ?? "aprobacion");

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = supabaseUrl && serviceKey
      ? createClient(supabaseUrl, serviceKey)
      : null;

    if (!supabase) {
      return json({ ok: false, error: "Supabase no configurado" }, 500);
    }

    const traspasoId = String(body.traspaso_id ?? "").trim() || null;

    if (modo === "sap_ok") {
      const r = await enviarCorreoSapOk(supabase, {
        traspaso_id: traspasoId,
        rut_origen: body.rut_origen,
        nombre_origen: body.nombre_origen,
        rut_destino: body.rut_destino,
        nombre_destino: body.nombre_destino,
        series: body.series ?? [],
        equipo: body.equipo ?? "Material",
        cantidad: body.cantidad ?? 1,
        nombre_confirmador: body.nombre_confirmador ?? "Bodega",
        folio_kepler: body.folio_kepler ?? null,
        via: body.via ?? null,
        solo_destinatario: body.solo_destinatario,
      });

      return json({
        ok: r.ok,
        modo: "sap_ok",
        from: remitenteResend(),
        enviados: r.enviados,
        fallidos: r.fallidos,
        detalle: r.detalle,
      }, r.ok ? 200 : 502);
    }

    const result = await enviarCorreoAprobacion(supabase, {
      traspaso_id: traspasoId,
      rut_origen: body.rut_origen,
      nombre_origen: body.nombre_origen,
      rut_destino: body.rut_destino,
      nombre_destino: body.nombre_destino,
      series: body.series ?? [],
      equipo: body.equipo,
      cantidad: body.cantidad,
      nombre_aprobador: body.nombre_aprobador,
      folio_kepler: body.folio_kepler,
      sap_confirm_url: body.sap_confirm_url,
      solo_destinatario: body.solo_destinatario,
    });

    return json({
      ok: result.ok,
      from: result.from,
      enviados: result.enviados,
      fallidos: result.fallidos,
      detalle: result.detalle,
    }, result.ok ? 200 : 502);
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    return json({ error: msg }, 500);
  }
});
