import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { enviarCorreoSapOk } from "../_shared/traspaso_email.ts";
import {
  nombreBodegueroPorRut,
  nombreTecnicoPorRut,
  rutCanonicoBodeguero,
} from "../_shared/nomina.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

type TraspasoRow = Record<string, unknown>;

function escHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** Evita caracteres raros (ej. punto medio) al desplegar en Edge Functions. */
function textoSeguro(s: string): string {
  return escHtml(s).replace(/[^\x20-\x7E]/g, (ch) =>
    `&#${ch.charCodeAt(0)};`
  );
}

function htmlPage(
  titulo: string,
  mensaje: string,
  ok = true,
  detalle?: string,
): Response {
  const color = ok ? "#22C55E" : "#EF4444";
  const icono = ok
    ? `<div style="width:64px;height:64px;border-radius:50%;background:#166534;
         display:flex;align-items:center;justify-content:center;margin:0 auto 20px;
         font-size:32px;color:#fff">&#10003;</div>`
    : `<div style="width:64px;height:64px;border-radius:50%;background:#7F1D1D;
         display:flex;align-items:center;justify-content:center;margin:0 auto 20px;
         font-size:32px;color:#fff">&#10007;</div>`;

  const bloqueDetalle = detalle
    ? `<p style="color:#94A3B8;font-size:13px;margin:16px 0 0;padding-top:16px;
         border-top:1px solid #1E3A5F;line-height:1.5">${textoSeguro(detalle)}</p>`
    : "";

  const html = `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${textoSeguro(titulo)}</title>
</head>
<body style="font-family:Arial,Helvetica,sans-serif;background:#0A0F1E;color:#fff;
             display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:16px">
  <div style="background:#0D1B2A;border:1px solid #1E3A5F;border-radius:14px;
              padding:32px 28px;max-width:440px;width:100%;text-align:center;box-sizing:border-box">
    ${icono}
    <h1 style="color:${color};font-size:22px;margin:0 0 12px;font-weight:700">${textoSeguro(titulo)}</h1>
    <p style="color:#CBD5E1;line-height:1.6;margin:0;font-size:15px">${textoSeguro(mensaje)}</p>
    ${bloqueDetalle}
  </div>
</body>
</html>`;

  const bytes = new TextEncoder().encode(html);
  return new Response(bytes, {
    status: ok ? 200 : 400,
    headers: { "Content-Type": "text/html; charset=UTF-8", ...CORS },
  });
}

async function notificarTecnicosSap(
  supabase: ReturnType<typeof createClient>,
  tr: TraspasoRow,
  folioKepler: string | null,
) {
  const ruts = [tr.rut_tecnico_a, tr.rut_tecnico_b] as string[];
  const descripcion = folioKepler
    ? `TRANSFERENCIA EN TOA REALIZADA ✓ — Folio: ${folioKepler}`
    : "TRANSFERENCIA EN TOA REALIZADA ✓";

  for (const rut of ruts) {
    try {
      const { data: tec } = await supabase
        .from("nomina_tecnicos")
        .select("fcm_token")
        .eq("rut", rut)
        .maybeSingle();
      const token = tec?.fcm_token as string | undefined;
      if (!token) continue;

      await supabase.functions.invoke("fcm-send", {
        body: {
          token,
          accion: "sap_confirmado",
          tipo: "Transferencia TOA realizada",
          descripcion,
        },
      });
    } catch (e) {
      console.error("FCM SAP error para", rut, e);
    }
  }
}

async function emailBodegaSapOk(
  supabase: ReturnType<typeof createClient>,
  tr: TraspasoRow,
  nombreConfirmador: string,
  via: string,
) {
  const emailRes = await enviarCorreoSapOk(supabase, {
    traspaso_id: String(tr.id ?? ""),
    rut_origen: String(tr.rut_tecnico_b ?? ""),
    nombre_origen: String(tr.nombre_tecnico_b ?? ""),
    rut_destino: String(tr.rut_tecnico_a ?? ""),
    nombre_destino: String(tr.nombre_tecnico_a ?? ""),
    series: (tr.series as string[] | undefined) ?? [],
    equipo: String(tr.tipo_material ?? "Material"),
    cantidad: Number(tr.cantidad ?? 1),
    folio_kepler: tr.folio_kepler as string | null,
    nombre_confirmador: nombreConfirmador,
    via,
  });
  if (!emailRes.ok) {
    console.error("Email SAP OK bodega falló:", emailRes);
  }
}

async function resolverNombreConfirmador(
  supabase: ReturnType<typeof createClient>,
  confirmadoPor: string | null | undefined,
  fallback: string,
): Promise<{ rut: string | null; nombre: string }> {
  if (!confirmadoPor) {
    return { rut: null, nombre: fallback };
  }
  const rut = await rutCanonicoBodeguero(supabase, confirmadoPor);
  if (!rut) {
    return { rut: null, nombre: fallback };
  }
  const nombre = (await nombreBodegueroPorRut(supabase, rut)) ?? fallback;
  return { rut, nombre };
}

async function nombresTecnicosTraspaso(
  supabase: ReturnType<typeof createClient>,
  tr: TraspasoRow,
) {
  const nombreOrigen =
    (await nombreTecnicoPorRut(supabase, String(tr.rut_tecnico_b ?? ""))) ??
    String(tr.nombre_tecnico_b ?? "");
  const nombreDestino =
    (await nombreTecnicoPorRut(supabase, String(tr.rut_tecnico_a ?? ""))) ??
    String(tr.nombre_tecnico_a ?? "");
  return { nombreOrigen, nombreDestino };
}

async function ejecutarConfirmacionSap(
  supabase: ReturnType<typeof createClient>,
  tr: TraspasoRow,
  opts: {
    confirmadoPor?: string | null;
    nombreConfirmador: string;
    via: string;
  },
) {
  if (tr.sap_ok) {
    return { yaConfirmado: true as const };
  }

  const ahora = new Date().toISOString();
  const folioKepler = (tr.folio_kepler as string | null) ?? null;

  const confirmador = await resolverNombreConfirmador(
    supabase,
    opts.confirmadoPor,
    opts.nombreConfirmador,
  );

  // No borrar sap_confirm_token: permite reabrir el enlace y ver "Ya confirmado".
  await supabase.from("traspasos_bodega").update({
    sap_ok: true,
    sap_confirmado_en: ahora,
    sap_confirmado_por: confirmador.rut ?? opts.confirmadoPor ?? null,
    nombre_sap_confirmador: confirmador.nombre,
  }).eq("id", tr.id);

  try {
    await supabase.from("tiempos_transferencia")
      .update({ timestamp_sap: ahora })
      .eq("traspaso_id", tr.id);
  } catch (e) {
    console.error("tiempos_transferencia update:", e);
  }

  await notificarTecnicosSap(supabase, tr, folioKepler);
  const { nombreOrigen, nombreDestino } = await nombresTecnicosTraspaso(
    supabase,
    tr,
  );
  const trEmail = {
    ...tr,
    nombre_tecnico_b: nombreOrigen,
    nombre_tecnico_a: nombreDestino,
  };

  await emailBodegaSapOk(
    supabase,
    trEmail,
    confirmador.nombre,
    opts.via,
  );

  return { yaConfirmado: false as const };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json", ...CORS },
    });

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Confirmación desde el botón del correo (GET público con token).
    if (req.method === "GET") {
      const params = new URL(req.url).searchParams;
      const token = params.get("token")?.trim() ?? "";
      const traspasoId = params.get("id")?.trim() ?? "";

      if (!token && !traspasoId) {
        return htmlPage(
          "Enlace invalido",
          "Falta el token de confirmacion. Usa el boton del correo o la app CREABOX.",
          false,
        );
      }

      type TrRow = TraspasoRow;
      let tr: TrRow | null = null;

      if (token) {
        const { data, error } = await supabase
          .from("traspasos_bodega")
          .select("*")
          .eq("sap_confirm_token", token)
          .maybeSingle();
        if (error) {
          console.error("confirmar-sap token lookup:", error);
        }
        tr = data as TrRow | null;
      }

      if (!tr && traspasoId) {
        const { data, error } = await supabase
          .from("traspasos_bodega")
          .select("*")
          .eq("id", traspasoId)
          .maybeSingle();
        if (error) {
          console.error("confirmar-sap id lookup:", error);
        }
        tr = data as TrRow | null;
        if (tr && token) {
          const tokenDb = tr.sap_confirm_token as string | null;
          if (tokenDb && tokenDb !== token) {
            return htmlPage(
              "Enlace invalido",
              "El token no coincide con este traspaso. Usa el boton del correo mas reciente.",
              false,
            );
          }
        }
      }

      if (!tr) {
        return htmlPage(
          "Enlace no valido",
          "No encontramos este traspaso. Confirma desde la app CREABOX (Panel Bodega) o pide una nueva aprobacion.",
          false,
        );
      }

      if (tr.sap_ok) {
        const tipo = String(tr.tipo_material ?? "Material");
        const cuando = tr.sap_confirmado_en
          ? new Date(String(tr.sap_confirmado_en)).toLocaleString("es-CL", {
            timeZone: "America/Santiago",
          })
          : "";
        return htmlPage(
          "Ya confirmado",
          "Esta transferencia ya tenia SAP confirmado.",
          true,
          cuando ? `Material: ${tipo} | ${cuando}` : `Material: ${tipo}`,
        );
      }

      if (!tr.sap_confirm_token && tr.estado === "aprobado") {
        return htmlPage(
          "Enlace sin token",
          "Confirma desde la app CREABOX: Panel Bodega, boton TRANSFERENCIA OK EN SAP.",
          false,
        );
      }

      const aprobadoPor = (tr.aprobado_por as string | null) ?? null;
      const confirmador = await resolverNombreConfirmador(
        supabase,
        aprobadoPor,
        (tr.nombre_aprobador as string | null) ?? "Bodega",
      );
      const result = await ejecutarConfirmacionSap(supabase, tr, {
        confirmadoPor: confirmador.rut ?? aprobadoPor,
        nombreConfirmador: confirmador.nombre,
        via: "correo",
      });

      if (result.yaConfirmado) {
        return htmlPage("Ya confirmado", "SAP ya estaba marcado como OK.");
      }

      const tipo = String(tr.tipo_material ?? "Material");
      const folio = tr.folio_kepler ? String(tr.folio_kepler) : null;
      const detalle = folio
        ? `Material: ${tipo} | Folio KRP: ${folio}`
        : `Material: ${tipo}`;

      return htmlPage(
        "OK - Confirmacion enviada",
        "La transferencia quedo registrada en SAP. Los tecnicos recibiran la notificacion en CREABOX.",
        true,
        detalle,
      );
    }

    const body = await req.json();
    const { traspaso_id, confirmado_por, nombre_confirmador } = body;
    if (!traspaso_id) return json({ error: "traspaso_id requerido" }, 400);

    const { data: tr, error: trErr } = await supabase
      .from("traspasos_bodega")
      .select("*")
      .eq("id", traspaso_id)
      .single();

    if (trErr || !tr) return json({ error: "Traspaso no encontrado" }, 404);
    if (tr.sap_ok) return json({ error: "SAP ya confirmado" }, 409);

    const confirmador = await resolverNombreConfirmador(
      supabase,
      confirmado_por,
      nombre_confirmador ?? "Bodega",
    );
    if (confirmado_por && !confirmador.rut) {
      return json({ error: "RUT no pertenece a nómina de bodega" }, 403);
    }

    await ejecutarConfirmacionSap(supabase, tr, {
      confirmadoPor: confirmador.rut ?? confirmado_por ?? null,
      nombreConfirmador: confirmador.nombre,
      via: "app CREABOX",
    });

    return json({ ok: true });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    if (req.method === "GET") {
      return htmlPage("Error", msg, false);
    }
    return json({ error: msg }, 500);
  }
});
