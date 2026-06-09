/**
 * Edge Function: escalar-material-sin-respuesta
 *
 * Cron cada minuto: solicitudes `pendiente` con más de 10 min sin aceptar
 * → FCM al supervisor del solicitante (acción material_sin_respuesta).
 * Idempotente vía columna alerta_supervisor_sin_respuesta_at.
 */
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MINUTOS_ESCALA = 10;

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function canonicalRut(rut: string): string {
  const k = rut.replace(/[.\-\s]/g, "").toUpperCase();
  if (k.length < 2) return rut.trim();
  return `${k.slice(0, -1)}-${k.slice(-1)}`;
}

function sameRut(a: string, b: string): boolean {
  return canonicalRut(a) === canonicalRut(b);
}

async function enviarFcmSupervisor(
  supabaseUrl: string,
  authKey: string,
  token: string,
  solicitudId: string,
  rutSup: string,
  titulo: string,
  descripcion: string,
): Promise<boolean> {
  const fcmRes = await fetch(`${supabaseUrl}/functions/v1/fcm-send`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${authKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      token,
      accion: "material_sin_respuesta",
      title: titulo,
      tipo: titulo,
      body: descripcion,
      descripcion,
      solicitud_id: solicitudId,
      rut: rutSup,
      android_channel_id: "ayuda_supervisor_1",
      android_priority: "high",
    }),
  });
  if (!fcmRes.ok) {
    console.error(`FCM supervisor falló:`, await fcmRes.text());
    return false;
  }
  return true;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceKey) {
      return json(500, { error: "Supabase no configurado" });
    }

    const supabase = createClient(supabaseUrl, serviceKey);
    const authKey = Deno.env.get("SUPABASE_ANON_KEY") ?? serviceKey;

    const corte = new Date(Date.now() - MINUTOS_ESCALA * 60 * 1000).toISOString();

    const { data: solicitudes, error: solErr } = await supabase
      .from("solicitudes_material")
      .select(
        "id, rut_solicitante, nombre_solicitante, tipo_material, created_at",
      )
      .eq("estado", "pendiente")
      .is("alerta_supervisor_sin_respuesta_at", null)
      .lte("created_at", corte)
      .order("created_at", { ascending: true })
      .limit(50);

    if (solErr) {
      return json(500, { error: solErr.message });
    }

    if (!solicitudes?.length) {
      return json(200, { ok: true, procesadas: 0, escaladas: 0 });
    }

    const { data: relaciones, error: relErr } = await supabase
      .from("supervisor_tecnicos_crea")
      .select("rut_supervisor, rut_tecnico");

    if (relErr) {
      return json(500, { error: relErr.message });
    }

    const supervisoresPorTecnico = new Map<string, Set<string>>();
    for (const r of relaciones ?? []) {
      const rutTec = canonicalRut(String(r.rut_tecnico ?? ""));
      const rutSup = canonicalRut(String(r.rut_supervisor ?? ""));
      if (!rutTec || !rutSup) continue;
      if (!supervisoresPorTecnico.has(rutTec)) {
        supervisoresPorTecnico.set(rutTec, new Set());
      }
      supervisoresPorTecnico.get(rutTec)!.add(rutSup);
    }

    let escaladas = 0;
    let fcmEnviados = 0;

    for (const sol of solicitudes) {
      const solicitudId = String(sol.id);
      const rutSol = canonicalRut(String(sol.rut_solicitante ?? ""));
      const nombreSol = String(sol.nombre_solicitante ?? "Técnico");
      const tipoMaterial = String(sol.tipo_material ?? "material");

      let supervisores = supervisoresPorTecnico.get(rutSol);
      if (!supervisores?.size) {
        for (const [rutTec, sups] of supervisoresPorTecnico) {
          if (sameRut(rutTec, rutSol)) {
            supervisores = sups;
            break;
          }
        }
      }

      if (!supervisores?.size) {
        console.warn(`Sin supervisor CREA para ${rutSol} solicitud=${solicitudId}`);
        continue;
      }

      const titulo = "Material sin atender";
      const descripcion =
        `${nombreSol} lleva ${MINUTOS_ESCALA} min sin respuesta — solicita ${tipoMaterial}`;

      let algunoEnviado = false;
      for (const rutSup of supervisores) {
        const { data: supRow } = await supabase
          .from("supervisores_crea")
          .select("fcm_token")
          .eq("rut", rutSup)
          .maybeSingle();

        const token = supRow?.fcm_token as string | undefined;
        if (!token) continue;

        const ok = await enviarFcmSupervisor(
          supabaseUrl,
          authKey,
          token,
          solicitudId,
          rutSup,
          titulo,
          descripcion,
        );
        if (ok) {
          algunoEnviado = true;
          fcmEnviados++;
        }
      }

      if (!algunoEnviado) {
        console.warn(
          `Supervisores sin FCM para solicitud=${solicitudId} rut=${rutSol}`,
        );
        continue;
      }

      const { data: updated, error: updErr } = await supabase
        .from("solicitudes_material")
        .update({
          alerta_supervisor_sin_respuesta_at: new Date().toISOString(),
        })
        .eq("id", solicitudId)
        .eq("estado", "pendiente")
        .is("alerta_supervisor_sin_respuesta_at", null)
        .select("id")
        .maybeSingle();

      if (updErr) {
        console.error(`Error marcando escala ${solicitudId}:`, updErr.message);
        continue;
      }
      if (updated) escaladas++;
    }

    console.log(
      `escalar-material-sin-respuesta ok candidatas=${solicitudes.length} escaladas=${escaladas} fcm=${fcmEnviados}`,
    );
    return json(200, {
      ok: true,
      candidatas: solicitudes.length,
      escaladas,
      fcm_enviados: fcmEnviados,
    });
  } catch (e) {
    console.error(e);
    return json(500, { error: String(e) });
  }
});
