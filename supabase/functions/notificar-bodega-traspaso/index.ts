/**
 * Edge Function: notificar-bodega-traspaso
 *
 * Envía FCM a todos los bodegueros con token registrado (data-only vía fcm-send).
 * Usa service role (RLS no bloquea lectura de nomina_bodega).
 *
 * Body: { traspaso_id: string }
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
    const traspasoId = body.traspaso_id as string | undefined;
    if (!traspasoId) {
      return json(400, { error: "traspaso_id requerido" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceKey) {
      return json(500, { error: "Supabase no configurado" });
    }

    const supabase = createClient(supabaseUrl, serviceKey);

    const { data: traspaso, error: trErr } = await supabase
      .from("traspasos_bodega")
      .select(
        "id, tipo_material, nombre_tecnico_a, nombre_tecnico_b, estado",
      )
      .eq("id", traspasoId)
      .maybeSingle();

    if (trErr) {
      console.error("notificar-bodega-traspaso traspaso error:", trErr);
      return json(500, { error: trErr.message });
    }
    if (!traspaso || traspaso.estado !== "pendiente") {
      return json(200, { ok: true, skipped: true, reason: "no pendiente" });
    }

    const tipo = String(traspaso.tipo_material ?? "Material");
    const entregador = String(traspaso.nombre_tecnico_b ?? "");
    const solicitante = String(traspaso.nombre_tecnico_a ?? "");
    const descripcion = `${tipo} · ${entregador} → ${solicitante}`;

    const { data: bodegueros, error: nomErr } = await supabase
      .from("nomina_bodega")
      .select("rut, fcm_token");

    if (nomErr) {
      console.error("notificar-bodega-traspaso nomina error:", nomErr);
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
          accion: "traspaso_bodega",
          title: "Nuevo traspaso en bodega",
          tipo: "Nuevo traspaso en bodega",
          body: descripcion,
          descripcion,
          traspaso_id: traspasoId,
          android_channel_id: "mat_alertas_7",
          android_priority: "high",
        }),
      });

      if (fcmRes.ok) {
        enviados++;
      } else {
        const detail = await fcmRes.text();
        console.error(`FCM falló rut=${row.rut}:`, detail);
      }
    }

    console.log(
      `notificar-bodega-traspaso ok traspaso=${traspasoId} enviados=${enviados} sin_token=${sinToken}`,
    );
    return json(200, { ok: true, enviados, sin_token: sinToken });
  } catch (e) {
    console.error(e);
    return json(500, { error: String(e) });
  }
});
