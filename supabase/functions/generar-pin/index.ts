/**
 * Edge Function: generar-pin
 *
 * Genera PIN de 6 dígitos para confirmar traspaso de material y lo envía
 * por FCM al solicitante (pin_intercambio).
 *
 * Idempotente: si ya hay PIN vigente, lo reutiliza (evita bucles al reintentar).
 * Si FCM falla pero el PIN quedó guardado, responde 200 con fcm_sent: false.
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

function generarPin(): string {
  return String(Math.floor(100000 + Math.random() * 900000));
}

function pinVigente(pin: string | null | undefined, expira: string | null | undefined): boolean {
  if (!pin || !expira) return false;
  return new Date(expira).getTime() > Date.now();
}

async function enviarFcm(
  supabaseUrl: string,
  anonKey: string,
  token: string,
  pin: string,
  solicitudId: string,
): Promise<boolean> {
  try {
    const fcmRes = await fetch(`${supabaseUrl}/functions/v1/fcm-send`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${anonKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        token,
        accion: "pin_intercambio",
        title: "Tu PIN de confirmación",
        body: `PIN: ${pin} — válido 15 minutos`,
        pin,
        solicitud_id: solicitudId,
        data_only: true,
        android_channel_id: "mat_alertas_7",
      }),
    });
    if (!fcmRes.ok) {
      const detail = await fcmRes.text();
      console.error("generar-pin fcm-send error:", detail);
      return false;
    }
    return true;
  } catch (e) {
    console.error("generar-pin fcm-send exception:", e);
    return false;
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    const { solicitud_id } = await req.json();
    if (!solicitud_id) {
      return json(400, { error: "solicitud_id requerido" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceKey) {
      return json(500, { error: "Supabase no configurado" });
    }

    const supabase = createClient(supabaseUrl, serviceKey);

    const { data: prev, error: readErr } = await supabase
      .from("solicitudes_material")
      .select("pin_codigo, pin_expira_en, rut_solicitante, nombre_solicitante")
      .eq("id", solicitud_id)
      .maybeSingle();

    if (readErr || !prev) {
      return json(404, { error: readErr?.message ?? "solicitud no encontrada" });
    }

    let pin = prev.pin_codigo as string | null;
    let expira = prev.pin_expira_en as string | null;
    let reutilizado = false;

    if (pinVigente(pin, expira)) {
      reutilizado = true;
      console.log(`generar-pin reutiliza PIN vigente solicitud=${solicitud_id}`);
    } else {
      pin = generarPin();
      expira = new Date(Date.now() + 15 * 60 * 1000).toISOString();

      const { error: updErr } = await supabase
        .from("solicitudes_material")
        .update({
          pin_codigo: pin,
          pin_expira_en: expira,
          pin_intentos: 3,
        })
        .eq("id", solicitud_id);

      if (updErr) {
        console.error("generar-pin update error:", updErr);
        return json(500, { error: updErr.message });
      }
    }

    const rutSolicitante = prev.rut_solicitante as string;
    const { data: tec } = await supabase
      .from("nomina_tecnicos")
      .select("fcm_token")
      .eq("rut", rutSolicitante)
      .maybeSingle();

    const token = tec?.fcm_token as string | undefined;
    let fcmSent = false;
    if (token) {
      const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? serviceKey;
      fcmSent = await enviarFcm(supabaseUrl, anonKey, token, pin!, solicitud_id);
    } else {
      console.warn(
        `generar-pin: sin fcm_token para solicitante ${rutSolicitante}`,
      );
    }

    console.log(
      `generar-pin ok solicitud=${solicitud_id} reutilizado=${reutilizado} fcm=${fcmSent}`,
    );
    return json(200, {
      ok: true,
      pin,
      reutilizado,
      fcm_sent: fcmSent,
    });
  } catch (e) {
    console.error(e);
    return json(500, { error: String(e) });
  }
});
