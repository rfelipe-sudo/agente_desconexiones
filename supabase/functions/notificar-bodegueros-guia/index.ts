/**
 * Edge Function: notificar-bodegueros-guia
 *
 * FCM a bodegueros cuando una guía queda firmada (data-only vía fcm-send → sonido BG).
 * Body: { guia_id: string }
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

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const guiaId = body.guia_id as string | undefined;
    if (!guiaId) {
      return json(400, { error: "guia_id requerido" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceKey) {
      return json(500, { error: "Supabase no configurado" });
    }

    const supabase = createClient(supabaseUrl, serviceKey);

    const { data: guia, error: guiaErr } = await supabase
      .from("solicitudes_bodega")
      .select(
        "id, solicitud_id, estado, tipo_material, cantidad, nombre_entregador, nombre_solicitante",
      )
      .eq("id", guiaId)
      .maybeSingle();

    if (guiaErr) {
      return json(500, { error: guiaErr.message });
    }
    if (!guia || guia.estado !== "firmada") {
      return json(200, { ok: true, skipped: true, reason: "no firmada" });
    }

    const tipo = String(guia.tipo_material ?? "Material");
    const cant = guia.cantidad != null ? String(guia.cantidad) : "1";
    const detalle = "$tipo x$cant";
    const entregador = String(guia.nombre_entregador ?? "");
    const solicitante = String(guia.nombre_solicitante ?? "");
    const descripcion = "$detalle · $entregador → $solicitante";

    const { data: bodegueros, error: nomErr } = await supabase
      .from("nomina_bodega")
      .select("rut, fcm_token");

    if (nomErr) {
      return json(500, { error: nomErr.message });
    }

    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? serviceKey;
    let enviados = 0;
    let sinToken = 0;

    for (const row of bodegueros ?? []) {
      const token = row.fcm_token as string | undefined;
      if (!token) {
        sinToken++;
        continue;
      }

      const fcmRes = await fetch(`${supabaseUrl}/functions/v1/fcm-send`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${anonKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          token,
          accion: "guia_firmada_bodega",
          title: "Guía firmada — revisar bodega",
          tipo: "Guía firmada — revisar bodega",
          body: descripcion,
          descripcion,
          guia_id: guiaId,
          solicitud_id: guia.solicitud_id,
          android_channel_id: "mat_alertas_7",
          android_priority: "high",
        }),
      });

      if (fcmRes.ok) enviados++;
      else {
        const detail = await fcmRes.text();
        console.error(`FCM guía falló rut=${row.rut}:`, detail);
      }
    }

    console.log(
      `notificar-bodegueros-guia ok guia=${guiaId} enviados=${enviados} sin_token=${sinToken}`,
    );
    return json(200, { ok: true, enviados, sin_token: sinToken });
  } catch (e) {
    console.error(e);
    return json(500, { error: String(e) });
  }
});
