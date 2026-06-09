/**
 * Edge Function: registrar-token-bodeguero
 *
 * Guarda fcm_token en nomina_bodega con service role (evita RLS del cliente).
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

    const { data, error } = await supabase
      .from("nomina_bodega")
      .update({ fcm_token: fcmToken })
      .eq("rut", rut)
      .select("rut");

    if (error) {
      console.error("registrar-token-bodeguero error:", error);
      return json(500, { error: error.message });
    }

    if (!data || data.length === 0) {
      return json(404, {
        error: "RUT no encontrado en nomina_bodega",
        rut,
      });
    }

    console.log(`registrar-token-bodeguero ok rut=${rut}`);
    return json(200, { ok: true, rut });
  } catch (e) {
    console.error(e);
    return json(500, { error: String(e) });
  }
});
