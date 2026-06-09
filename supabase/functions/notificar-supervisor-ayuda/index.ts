/**
 * Edge Function: notificar-supervisor-ayuda
 *
 * Envía FCM al supervisor asignado cuando un técnico solicita ayuda en terreno.
 * Usa service role (RLS no bloquea lectura de supervisores_crea).
 *
 * Body: { ticket_id: string, es_traspaso?: boolean, evento?: 'cancelacion' }
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

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const ticketId = body.ticket_id as string | undefined;
    const esTraspaso = body.es_traspaso === true;
    const esCancelacion = body.evento === "cancelacion";

    if (!ticketId) {
      return json(400, { error: "ticket_id requerido" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceKey) {
      return json(500, { error: "Supabase no configurado" });
    }

    const supabase = createClient(supabaseUrl, serviceKey);

    const { data: ayuda, error: ayudaErr } = await supabase
      .from("ayuda_terreno_crea")
      .select(
        "ticket_id, rut_tecnico, nombre_tecnico, tipo, estado, rut_supervisor, nombre_supervisor",
      )
      .eq("ticket_id", ticketId)
      .maybeSingle();

    if (ayudaErr) {
      console.error("notificar-supervisor-ayuda ayuda error:", ayudaErr);
      return json(500, { error: ayudaErr.message });
    }
    if (!ayuda) {
      return json(200, { ok: true, skipped: true, reason: "no encontrada" });
    }
    if (String(ayuda.tipo ?? "") === "movimiento_material") {
      return json(200, { ok: true, skipped: true, reason: "movimiento_material" });
    }
    if (esCancelacion) {
      if (String(ayuda.estado ?? "") !== "cancelada") {
        return json(200, { ok: true, skipped: true, reason: "no cancelada" });
      }
    } else if (String(ayuda.estado ?? "") !== "pendiente") {
      return json(200, { ok: true, skipped: true, reason: "no pendiente" });
    }

    let rutSupervisor = String(ayuda.rut_supervisor ?? "").trim();
    const nombreTecnico = String(ayuda.nombre_tecnico ?? "Técnico");
    const tipoAyuda = String(ayuda.tipo ?? "ayuda");

    if (!rutSupervisor) {
      const rutTecnico = String(ayuda.rut_tecnico ?? "").trim();
      if (rutTecnico) {
        const variantes = rutVariantes(rutTecnico);
        const { data: rel } = await supabase
          .from("supervisor_tecnicos_crea")
          .select("rut_supervisor")
          .in("rut_tecnico", variantes)
          .limit(1)
          .maybeSingle();
        rutSupervisor = String(rel?.rut_supervisor ?? "").trim();
      }
    }

    if (!rutSupervisor) {
      return json(200, { ok: true, skipped: true, reason: "sin supervisor" });
    }

    const { data: supRows, error: supErr } = await supabase
      .from("supervisores_crea")
      .select("rut, fcm_token")
      .in("rut", rutVariantes(rutSupervisor));

    if (supErr) {
      console.error("notificar-supervisor-ayuda supervisor error:", supErr);
      return json(500, { error: supErr.message });
    }

    const supRow = (supRows ?? []).find((r) => r.fcm_token);
    const token = supRow?.fcm_token as string | undefined;
    if (!token) {
      return json(200, {
        ok: true,
        skipped: true,
        reason: "supervisor sin fcm_token",
        rut_supervisor: rutSupervisor,
      });
    }

    const titulo = esCancelacion
      ? "Solicitud de ayuda cancelada"
      : esTraspaso
      ? "Solicitud de ayuda transferida"
      : "¡Solicitud de ayuda en terreno!";
    const descripcion = esCancelacion
      ? `${nombreTecnico} canceló su solicitud — ${tipoAyuda}`
      : esTraspaso
      ? `${nombreTecnico} fue transferido a tu equipo — ${tipoAyuda}`
      : `${nombreTecnico} necesita ayuda — ${tipoAyuda}`;

    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? serviceKey;
    const fcmRes = await fetch(`${supabaseUrl}/functions/v1/fcm-send`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${anonKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        token,
        accion: esCancelacion ? "ayuda_cancelada" : "solicitud_ayuda",
        title: titulo,
        tipo: titulo,
        body: descripcion,
        descripcion,
        ticket_id: ticketId,
        rut_supervisor: rutSupervisor,
        android_channel_id: "ayuda_supervisor_1",
        android_priority: "high",
      }),
    });

    if (!fcmRes.ok) {
      const detail = await fcmRes.text();
      console.error(`FCM falló supervisor=${rutSupervisor}:`, detail);
      return json(500, { error: "FCM falló", detail });
    }

    console.log(
      `notificar-supervisor-ayuda ok ticket=${ticketId} supervisor=${rutSupervisor} traspaso=${esTraspaso}`,
    );
    return json(200, { ok: true, enviado: true, rut_supervisor: rutSupervisor });
  } catch (e) {
    console.error(e);
    return json(500, { error: String(e) });
  }
});
