/**
 * Edge Function: confirmar-pin
 * Confirma traspaso vía RPC confirmar_traspaso_pin (service role).
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
    const { solicitud_id, pin } = await req.json();
    if (!solicitud_id || !pin) {
      return json(400, { error: "solicitud_id y pin requeridos" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceKey) {
      return json(500, { error: "Supabase no configurado" });
    }

    const supabase = createClient(supabaseUrl, serviceKey);

    const { data, error } = await supabase.rpc("confirmar_traspaso_pin", {
      p_solicitud_id: solicitud_id,
      p_pin: String(pin).trim(),
    });

    if (error) {
      console.error("confirmar-pin rpc error:", error);
      return json(500, { error: error.message });
    }

    console.log(`confirmar-pin ok solicitud=${solicitud_id} result=${JSON.stringify(data)}`);
    return json(200, data ?? { ok: false, error: "sin_respuesta" });
  } catch (e) {
    console.error(e);
    return json(500, { error: String(e) });
  }
});
