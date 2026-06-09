/**
 * Edge Function: enviar-comunicado-creabox
 *
 * Crea/reutiliza un comunicado y envía FCM según roles o RUTs personalizados.
 * Body: { titulo, mensaje, tipo, roles_destino?, rut_destino?, ruts_destino?, creado_por?, comunicado_id? }
 */
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const ROLES_VALIDOS = new Set([
  "todos",
  "tecnico",
  "ito",
  "supervisor",
  "bodeguero",
  "flota",
  "administrativo",
]);

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function canonicalRut(rut: string): string {
  const s = rut.trim().toUpperCase().replace(/\./g, "");
  if (s.length < 2) return s;
  const body = s.slice(0, -1).replace(/-/g, "");
  const dv = s.slice(-1);
  return `${body}-${dv}`;
}

function esVigente(v: string | null | undefined): boolean {
  return String(v ?? "").trim().toLowerCase() === "vigente";
}

type Destinatario = { rut: string; nombre: string; token: string };

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceKey) {
      return json(500, { error: "Supabase no configurado" });
    }

    const supabase = createClient(supabaseUrl, serviceKey);
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? serviceKey;

    let comunicadoId = body.comunicado_id as string | undefined;
    let titulo = String(body.titulo ?? "").trim();
    let mensaje = String(body.mensaje ?? "").trim();
    let tipo = String(body.tipo ?? "por_roles").trim();
    const creadoPor = String(body.creado_por ?? "dashboard").trim();

    const rolesRaw = Array.isArray(body.roles_destino)
      ? (body.roles_destino as string[])
      : [];
    const rolesDestino = [
      ...new Set(
        rolesRaw.map((r) => String(r).trim().toLowerCase()).filter((r) =>
          ROLES_VALIDOS.has(r)
        ),
      ),
    ];

    const rutsRaw = Array.isArray(body.ruts_destino)
      ? (body.ruts_destino as string[])
      : [];
    const rutUnico = body.rut_destino
      ? canonicalRut(String(body.rut_destino))
      : null;
    const rutsDestino = [
      ...new Set(
        [
          ...(rutUnico ? [rutUnico] : []),
          ...rutsRaw.map((r) => canonicalRut(String(r))),
        ].filter((r) => r.length > 3),
      ),
    ];

    if (!comunicadoId) {
      if (!titulo || !mensaje) {
        return json(400, { error: "titulo y mensaje requeridos" });
      }
      if (tipo === "personalizado" && rutsDestino.length === 0) {
        return json(400, {
          error: "personalizado requiere rut_destino o ruts_destino",
        });
      }
      if (
        (tipo === "por_roles" || tipo === "masivo") &&
        rolesDestino.length === 0 &&
        tipo !== "masivo"
      ) {
        return json(400, { error: "por_roles requiere roles_destino" });
      }

      const { data: inserted, error: insErr } = await supabase
        .from("comunicados_creabox")
        .insert({
          titulo,
          mensaje,
          tipo: tipo === "personalizado"
            ? "personalizado"
            : rolesDestino.length > 0
            ? "por_roles"
            : "masivo",
          roles_destino: rolesDestino,
          rut_destino: rutsDestino.length === 1 ? rutsDestino[0] : null,
          ruts_destino: rutsDestino,
          creado_por: creadoPor,
          activo: true,
        })
        .select("id, titulo, mensaje, tipo, roles_destino")
        .single();

      if (insErr) return json(500, { error: insErr.message });
      comunicadoId = inserted.id as string;
      titulo = inserted.titulo as string;
      mensaje = inserted.mensaje as string;
      tipo = inserted.tipo as string;
      if (Array.isArray(inserted.roles_destino)) {
        rolesDestino.splice(0, rolesDestino.length,
          ...inserted.roles_destino as string[]);
      }
    } else {
      const { data: existente, error: exErr } = await supabase
        .from("comunicados_creabox")
        .select("id, titulo, mensaje, tipo, activo, roles_destino, ruts_destino")
        .eq("id", comunicadoId)
        .maybeSingle();
      if (exErr) return json(500, { error: exErr.message });
      if (!existente || !existente.activo) {
        return json(404, { error: "comunicado no encontrado o inactivo" });
      }
      titulo = existente.titulo as string;
      mensaje = existente.mensaje as string;
      tipo = existente.tipo as string;
      if (Array.isArray(existente.roles_destino)) {
        rolesDestino.splice(0, rolesDestino.length,
          ...existente.roles_destino as string[]);
      }
      if (tipo === "personalizado" && Array.isArray(existente.ruts_destino)) {
        rutsDestino.splice(0, rutsDestino.length,
          ...existente.ruts_destino as string[]);
      }
    }

    const mapa = new Map<string, Destinatario>();

    const agregar = (rut: string, nombre: string, token: string | undefined) => {
      const canon = canonicalRut(rut);
      if (!token || canon.length < 3) return;
      if (!mapa.has(canon)) {
        mapa.set(canon, { rut: canon, nombre: nombre || canon, token });
      }
    };

    const roles = rolesDestino.length > 0
      ? rolesDestino
      : tipo === "masivo"
      ? ["tecnico"]
      : [];
    const todos = roles.includes("todos");

    if (tipo === "personalizado") {
      const { data: nomina } = await supabase
        .from("nomina_tecnicos")
        .select("rut, nombres, paterno, fcm_token");
      const { data: bodega } = await supabase
        .from("nomina_bodega")
        .select("rut, nombre, fcm_token");
      const { data: sups } = await supabase
        .from("supervisores_crea")
        .select("rut, nombre, fcm_token")
        .eq("activo", true);
      const { data: flota } = await supabase
        .from("roles_flota")
        .select("rut, rol, fcm_token")
        .eq("activo", true);

      const buscarToken = (rut: string): { nombre: string; token?: string } => {
        const canon = canonicalRut(rut);
        for (const t of nomina ?? []) {
          if (canonicalRut(String(t.rut)) === canon) {
            const nom =
              `${t.nombres ?? ""} ${t.paterno ?? ""}`.trim();
            return { nombre: nom, token: t.fcm_token as string | undefined };
          }
        }
        for (const b of bodega ?? []) {
          if (canonicalRut(String(b.rut)) === canon) {
            return {
              nombre: String(b.nombre ?? ""),
              token: b.fcm_token as string | undefined,
            };
          }
        }
        for (const s of sups ?? []) {
          if (canonicalRut(String(s.rut)) === canon) {
            return {
              nombre: String(s.nombre ?? ""),
              token: s.fcm_token as string | undefined,
            };
          }
        }
        for (const f of flota ?? []) {
          if (canonicalRut(String(f.rut)) === canon) {
            return {
              nombre: String(f.rol ?? "flota"),
              token: f.fcm_token as string | undefined,
            };
          }
        }
        return { nombre: canon };
      };

      for (const rut of rutsDestino) {
        const info = buscarToken(rut);
        agregar(rut, info.nombre, info.token);
      }
    } else {
      const quiereTecnico = todos || roles.includes("tecnico");
      const quiereIto = todos || roles.includes("ito");
      const quiereAdmin = todos || roles.includes("administrativo");

      if (quiereTecnico || quiereIto || quiereAdmin || tipo === "masivo") {
        const { data: nomina, error: nomErr } = await supabase
          .from("nomina_tecnicos")
          .select("rut, nombres, paterno, materno, tipo_personal, estado_vigencia, fcm_token");
        if (nomErr) return json(500, { error: nomErr.message });

        for (const t of nomina ?? []) {
          if (!esVigente(t.estado_vigencia as string)) continue;
          const tipoPer = String(t.tipo_personal ?? "").trim().toUpperCase();
          const rut = String(t.rut ?? "");
          const nombre =
            `${t.nombres ?? ""} ${t.paterno ?? ""} ${t.materno ?? ""}`.trim();
          const token = t.fcm_token as string | undefined;

          let incluir = false;
          if (tipo === "masivo" && roles.length === 0) {
            incluir = tipoPer !== "ITO" && tipoPer !== "TA";
          } else if (todos) {
            incluir = true;
          } else {
            if (quiereTecnico && (tipoPer === "T" || tipoPer === "TNE")) {
              incluir = true;
            }
            if (quiereIto && tipoPer === "ITO") incluir = true;
            if (quiereAdmin && tipoPer === "TA") incluir = true;
          }
          if (incluir) agregar(rut, nombre, token);
        }
      }

      if (todos || roles.includes("supervisor")) {
        const { data: sups, error: supErr } = await supabase
          .from("supervisores_crea")
          .select("rut, nombre, fcm_token")
          .eq("activo", true);
        if (supErr) return json(500, { error: supErr.message });
        for (const s of sups ?? []) {
          agregar(
            String(s.rut ?? ""),
            String(s.nombre ?? ""),
            s.fcm_token as string | undefined,
          );
        }
      }

      if (todos || roles.includes("bodeguero")) {
        const { data: bod, error: bodErr } = await supabase
          .from("nomina_bodega")
          .select("rut, nombre, fcm_token");
        if (bodErr) return json(500, { error: bodErr.message });
        for (const b of bod ?? []) {
          agregar(
            String(b.rut ?? ""),
            String(b.nombre ?? ""),
            b.fcm_token as string | undefined,
          );
        }
      }

      if (todos || roles.includes("flota")) {
        const { data: flota, error: flotaErr } = await supabase
          .from("roles_flota")
          .select("rut, rol, fcm_token")
          .eq("activo", true);
        if (flotaErr) return json(500, { error: flotaErr.message });
        for (const f of flota ?? []) {
          agregar(
            String(f.rut ?? ""),
            String(f.rol ?? "flota"),
            f.fcm_token as string | undefined,
          );
        }
      }
    }

    const destinatarios = [...mapa.values()];
    let enviados = 0;
    let sinToken = 0;

    for (const dest of destinatarios) {
      if (!dest.token) {
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
          token: dest.token,
          accion: "comunicado_creabox",
          title: titulo,
          body: mensaje.length > 120 ? `${mensaje.slice(0, 117)}...` : mensaje,
          comunicado_id: comunicadoId,
          android_channel_id: "comunicados_creabox_1",
          android_priority: "high",
        }),
      });

      if (fcmRes.ok) enviados++;
    }

    return json(200, {
      ok: true,
      comunicado_id: comunicadoId,
      enviados,
      sin_token: sinToken,
      destinatarios: destinatarios.length,
      roles: rolesDestino,
    });
  } catch (e) {
    return json(500, { error: String(e) });
  }
});
