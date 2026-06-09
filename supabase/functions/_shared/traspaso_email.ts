import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const DESTINATARIOS_BODEGA_DEFAULT = [
  "rfelipe@sbip.cl",
  "marcelo.gonzalez@sbip.cl",
  "sergio.silva@sbip.cl",
  "bastian.caceres@sbip.cl",
  "gabriel.uribe@sbip.cl",
];

const DESTINATARIOS_ERROR_DEFAULT = [
  "marcelo.gonzalez@sbip.cl",
  "rfelipe@sbip.cl",
];

export type ResultadoEmail = {
  email: string;
  ok: boolean;
  status: number;
  resend_id?: string;
  resend_error?: string;
};

export type RespuestaEnvio = {
  ok: boolean;
  from: string;
  enviados: string[];
  fallidos: ResultadoEmail[];
  detalle: ResultadoEmail[];
};

type AprobacionData = {
  rutOrigen: string;
  nombreOrigen: string;
  rutDestino: string;
  nombreDestino: string;
  series: string[];
  equipo: string;
  cantidad: number;
  fecha: string;
  nombreAprobador: string;
  folioKepler?: string | null;
  sapConfirmUrl?: string | null;
};

type SapOkData = {
  rutOrigen: string;
  nombreOrigen: string;
  rutDestino: string;
  nombreDestino: string;
  series: string[];
  equipo: string;
  cantidad: number;
  fecha: string;
  nombreConfirmador: string;
  folioKepler?: string | null;
  via?: string;
};

export function remitenteResend(): string {
  return Deno.env.get("RESEND_FROM")?.trim() ||
    "Traspasos SBIP <noreply@sbip.cl>";
}

function parsearListaEmails(raw: string | null | undefined): string[] {
  const txt = raw?.toString().trim();
  if (!txt) return [];

  try {
    const parsed = JSON.parse(txt) as unknown;
    if (Array.isArray(parsed) && parsed.length > 0) {
      return [...new Set(
        parsed.map((e) => String(e).trim().toLowerCase()).filter(Boolean),
      )];
    }
  } catch {
    const lista = txt.split(",").map((s) => s.trim().toLowerCase()).filter(
      Boolean,
    );
    if (lista.length > 0) return [...new Set(lista)];
  }

  return [];
}

async function leerConfigEmails(
  supabase: SupabaseClient | null,
  clave: string,
  fallback: string[],
): Promise<string[]> {
  if (!supabase) return fallback;

  const { data } = await supabase
    .from("configuracion_app")
    .select("valor")
    .eq("clave", clave)
    .maybeSingle();

  const lista = parsearListaEmails(data?.valor?.toString());
  return lista.length > 0 ? lista : fallback;
}

async function obtenerDestinatariosBodega(
  supabase: SupabaseClient | null,
  solo?: string,
): Promise<string[]> {
  const uno = String(solo ?? "").trim().toLowerCase();
  if (uno) return [uno];
  return leerConfigEmails(
    supabase,
    "emails_bodega_traspaso",
    DESTINATARIOS_BODEGA_DEFAULT,
  );
}

async function obtenerDestinatariosError(
  supabase: SupabaseClient | null,
): Promise<string[]> {
  return leerConfigEmails(
    supabase,
    "emails_errores_traspaso",
    DESTINATARIOS_ERROR_DEFAULT,
  );
}

async function registrarEnvio(
  supabase: SupabaseClient | null,
  row: {
    traspaso_id?: string | null;
    modo: string;
    destinatario: string;
    ok: boolean;
    resend_id?: string | null;
    resend_error?: string | null;
    from_address?: string | null;
    subject?: string | null;
  },
) {
  if (!supabase) return;
  try {
    await supabase.from("email_envios_traspaso").insert(row);
  } catch (e) {
    console.error("email_envios_traspaso insert:", e);
  }
}

function buildHtmlAprobacion(data: AprobacionData): string {
  const filas = data.series.length > 0
    ? data.series.map((s) => `
      <tr>
        <td style="border:1px solid #000;padding:8px;text-align:center">${data.rutOrigen}</td>
        <td style="border:1px solid #000;padding:8px;text-align:center">${data.nombreOrigen}</td>
        <td style="border:1px solid #000;padding:8px;text-align:center">${data.rutDestino}</td>
        <td style="border:1px solid #000;padding:8px;text-align:center">${data.nombreDestino}</td>
        <td style="border:1px solid #000;padding:8px;text-align:center">${s}</td>
        <td style="border:1px solid #000;padding:8px;text-align:center">${data.equipo}</td>
        <td style="border:1px solid #000;padding:8px;text-align:center">1</td>
      </tr>`).join("")
    : `<tr>
        <td style="border:1px solid #000;padding:8px;text-align:center">${data.rutOrigen}</td>
        <td style="border:1px solid #000;padding:8px;text-align:center">${data.nombreOrigen}</td>
        <td style="border:1px solid #000;padding:8px;text-align:center">${data.rutDestino}</td>
        <td style="border:1px solid #000;padding:8px;text-align:center">${data.nombreDestino}</td>
        <td style="border:1px solid #000;padding:8px;text-align:center">-</td>
        <td style="border:1px solid #000;padding:8px;text-align:center">${data.equipo}</td>
        <td style="border:1px solid #000;padding:8px;text-align:center">${data.cantidad}</td>
      </tr>`;

  const folioLine = data.folioKepler
    ? `<p style="color:#333;font-size:13px;margin-bottom:16px">Folio KRP: <strong>${data.folioKepler}</strong></p>`
    : "";

  const botonSap = data.sapConfirmUrl
    ? `<div style="margin:28px 0;text-align:center">
        <p style="color:#333;font-size:14px;margin-bottom:14px">
          Cuando registres la transferencia en <strong>SAP</strong>, confirma aqu&#237;:
        </p>
        <a href="${data.sapConfirmUrl}"
           style="display:inline-block;background:#00D9FF;color:#0A0F1E;
                  font-weight:bold;font-size:15px;text-decoration:none;
                  padding:14px 28px;border-radius:8px">
          &#10003; TRANSFERENCIA OK EN SAP
        </a>
        <p style="color:#888;font-size:11px;margin-top:12px">
          Tambi&#233;n puedes confirmar desde la app CREABOX (Panel Bodega).
        </p>
      </div>`
    : "";

  return `<!DOCTYPE html>
<html>
<body style="font-family:Arial,sans-serif;padding:24px;background:#f5f5f5">
  <div style="background:#fff;border-radius:8px;padding:24px;max-width:750px;margin:0 auto">
    <h2 style="color:#1a1a1a;margin-bottom:4px">Traspaso de Material Aprobado</h2>
    <p style="color:#555;font-size:13px;margin-bottom:4px">Fecha: ${data.fecha}</p>
    <p style="color:#555;font-size:13px;margin-bottom:20px">Aprobado por: <strong>${data.nombreAprobador}</strong></p>
    <p style="color:#333;margin-bottom:16px">El siguiente traspaso fue aprobado en KRP. Falta confirmar en SAP:</p>
    ${folioLine}
    <table style="border-collapse:collapse;width:100%">
      <thead>
        <tr style="background-color:#FFFF00">
          <th style="border:1px solid #000;padding:10px;text-align:center">Rut origen</th>
          <th style="border:1px solid #000;padding:10px;text-align:center">Nombre origen</th>
          <th style="border:1px solid #000;padding:10px;text-align:center">Rut destino</th>
          <th style="border:1px solid #000;padding:10px;text-align:center">Nombre destino</th>
          <th style="border:1px solid #000;padding:10px;text-align:center">Serie</th>
          <th style="border:1px solid #000;padding:10px;text-align:center">Equipo</th>
          <th style="border:1px solid #000;padding:10px;text-align:center">Cantidad</th>
        </tr>
      </thead>
      <tbody>${filas}</tbody>
    </table>
    ${botonSap}
    <p style="margin-top:24px;color:#666;font-size:12px">Revisa el Panel de Bodega en la app para m&#225;s detalles.</p>
  </div>
</body>
</html>`;
}

function buildHtmlSapOk(data: SapOkData): string {
  const via = data.via ? ` (${data.via})` : "";
  const folioLine = data.folioKepler
    ? `<p style="color:#333;font-size:13px">Folio KRP: <strong>${data.folioKepler}</strong></p>`
    : "";

  return `<!DOCTYPE html>
<html>
<body style="font-family:Arial,sans-serif;padding:24px;background:#f5f5f5">
  <div style="background:#fff;border-radius:8px;padding:24px;max-width:650px;margin:0 auto">
    <h2 style="color:#166534;margin-bottom:8px">&#10003; Transferencia SAP confirmada</h2>
    <p style="color:#555;font-size:13px;margin-bottom:16px">Fecha: ${data.fecha}</p>
    <p style="color:#333;margin-bottom:12px">
      <strong>${data.nombreConfirmador}</strong>${via} confirm&#243; que el traspaso
      qued&#243; registrado en SAP.
    </p>
    ${folioLine}
    <table style="border-collapse:collapse;width:100%;margin-top:16px">
      <tr><td style="padding:8px;border:1px solid #ddd;background:#f9f9f9">Material</td>
          <td style="padding:8px;border:1px solid #ddd">${data.equipo} (${data.cantidad})</td></tr>
      <tr><td style="padding:8px;border:1px solid #ddd;background:#f9f9f9">Origen</td>
          <td style="padding:8px;border:1px solid #ddd">${data.nombreOrigen} · ${data.rutOrigen}</td></tr>
      <tr><td style="padding:8px;border:1px solid #ddd;background:#f9f9f9">Destino</td>
          <td style="padding:8px;border:1px solid #ddd">${data.nombreDestino} · ${data.rutDestino}</td></tr>
      ${
    data.series.length > 0
      ? `<tr><td style="padding:8px;border:1px solid #ddd;background:#f9f9f9">Series</td>
          <td style="padding:8px;border:1px solid #ddd">${data.series.join(", ")}</td></tr>`
      : ""
  }
    </table>
    <p style="margin-top:20px;color:#666;font-size:12px">
      Los t&#233;cnicos involucrados fueron notificados en la app.
    </p>
  </div>
</body>
</html>`;
}

async function enviarA(
  resendKey: string,
  to: string,
  subject: string,
  html: string,
) {
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${resendKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: remitenteResend(),
      to: [to],
      subject,
      html,
    }),
  });
  let data: Record<string, unknown> = {};
  try {
    data = await res.json() as Record<string, unknown>;
  } catch {
    data = { parse_error: true };
  }
  console.log(`Resend [${res.status}] → ${to}:`, JSON.stringify(data));
  return {
    ok: res.ok,
    status: res.status,
    resend_id: data.id as string | undefined,
    resend_error: (data.message ?? data.error) as string | undefined,
  };
}

function fechaChile(): string {
  return new Date().toLocaleString("es-CL", { timeZone: "America/Santiago" });
}

export async function enviarCorreoAprobacion(
  supabase: SupabaseClient,
  params: {
    traspaso_id?: string | null;
    rut_origen: string;
    nombre_origen: string;
    rut_destino: string;
    nombre_destino: string;
    series?: string[];
    equipo: string;
    cantidad?: number;
    nombre_aprobador: string;
    folio_kepler?: string | null;
    sap_confirm_url?: string | null;
    solo_destinatario?: string;
  },
): Promise<RespuestaEnvio> {
  const resendKey = Deno.env.get("RESEND_API_KEY");
  if (!resendKey) {
    console.error("RESEND_API_KEY no configurada");
    const vacio: RespuestaEnvio = {
      ok: false,
      from: remitenteResend(),
      enviados: [],
      fallidos: [],
      detalle: [],
    };
    await enviarCorreoError(supabase, {
      contexto: "aprobacion",
      traspaso_id: params.traspaso_id ?? null,
      equipo: params.equipo,
      detalle: "RESEND_API_KEY no configurada",
    });
    return vacio;
  }

  const equipo = String(params.equipo ?? "Material");
  const subject = `Traspaso aprobado: ${equipo}`;
  const html = buildHtmlAprobacion({
    rutOrigen: params.rut_origen,
    nombreOrigen: params.nombre_origen,
    rutDestino: params.rut_destino,
    nombreDestino: params.nombre_destino,
    series: params.series ?? [],
    equipo,
    cantidad: params.cantidad ?? 1,
    fecha: fechaChile(),
    nombreAprobador: params.nombre_aprobador,
    folioKepler: params.folio_kepler ?? null,
    sapConfirmUrl: params.sap_confirm_url ?? null,
  });

  const destinatarios = await obtenerDestinatariosBodega(
    supabase,
    params.solo_destinatario,
  );

  const resultados = await enviarATodos(
    supabase,
    resendKey,
    destinatarios,
    subject,
    html,
    "aprobacion",
    params.traspaso_id ?? null,
  );

  if (!resultados.ok) {
    await enviarCorreoError(supabase, {
      contexto: "aprobacion",
      traspaso_id: params.traspaso_id ?? null,
      equipo,
      detalle: resultados.fallidos.map((f) =>
        `${f.email}: ${f.resend_error ?? `HTTP ${f.status}`}`
      ).join("; ") || "Sin destinatarios o RESEND sin respuesta",
    });
  }

  return resultados;
}

async function enviarATodos(
  supabase: SupabaseClient,
  resendKey: string,
  destinatarios: string[],
  subject: string,
  html: string,
  modo: string,
  traspasoId: string | null,
): Promise<RespuestaEnvio> {
  const resultados: ResultadoEmail[] = await Promise.all(
    destinatarios.map(async (email) => {
      const r = await enviarA(resendKey, email, subject, html);
      await registrarEnvio(supabase, {
        traspaso_id: traspasoId,
        modo,
        destinatario: email,
        ok: r.ok,
        resend_id: r.resend_id ?? null,
        resend_error: r.resend_error ?? null,
        from_address: remitenteResend(),
        subject,
      });
      return {
        email,
        ok: r.ok,
        status: r.status,
        resend_id: r.resend_id,
        resend_error: r.resend_error,
      };
    }),
  );

  const enviados = resultados.filter((r) => r.ok).map((r) => r.email);
  const fallidos = resultados.filter((r) => !r.ok);
  console.log(`Correo ${modo} — enviados:`, enviados, "fallidos:", fallidos);

  return {
    ok: fallidos.length === 0 && enviados.length > 0,
    from: remitenteResend(),
    enviados,
    fallidos,
    detalle: resultados,
  };
}

export async function enviarCorreoError(
  supabase: SupabaseClient,
  params: {
    contexto: string;
    traspaso_id?: string | null;
    equipo?: string;
    detalle: string;
  },
): Promise<void> {
  const resendKey = Deno.env.get("RESEND_API_KEY");
  if (!resendKey) {
    console.error("No se puede enviar correo de error: RESEND_API_KEY ausente");
    return;
  }

  const destinatarios = await obtenerDestinatariosError(supabase);
  const equipo = params.equipo ? ` · ${params.equipo}` : "";
  const subject = `ERROR traspaso CREABOX (${params.contexto})${equipo}`;
  const html = `<!DOCTYPE html>
<html><body style="font-family:Arial,sans-serif;padding:24px">
  <h2 style="color:#B91C1C">Error en flujo de traspaso</h2>
  <p><strong>Contexto:</strong> ${params.contexto}</p>
  ${params.traspaso_id ? `<p><strong>Traspaso:</strong> ${params.traspaso_id}</p>` : ""}
  ${params.equipo ? `<p><strong>Material:</strong> ${params.equipo}</p>` : ""}
  <p><strong>Detalle:</strong> ${params.detalle}</p>
  <p style="color:#666;font-size:12px">CREABOX · ${fechaChile()}</p>
</body></html>`;

  for (const email of destinatarios) {
    const r = await enviarA(resendKey, email, subject, html);
    await registrarEnvio(supabase, {
      traspaso_id: params.traspaso_id ?? null,
      modo: "error",
      destinatario: email,
      ok: r.ok,
      resend_id: r.resend_id ?? null,
      resend_error: r.resend_error ?? null,
      from_address: remitenteResend(),
      subject,
    });
  }
}

export async function enviarCorreoSapOk(
  supabase: SupabaseClient,
  params: {
    traspaso_id?: string | null;
    rut_origen: string;
    nombre_origen: string;
    rut_destino: string;
    nombre_destino: string;
    series?: string[];
    equipo: string;
    cantidad?: number;
    nombre_confirmador: string;
    folio_kepler?: string | null;
    via?: string | null;
    solo_destinatario?: string;
  },
): Promise<RespuestaEnvio> {
  const resendKey = Deno.env.get("RESEND_API_KEY");
  if (!resendKey) {
    const vacio: RespuestaEnvio = {
      ok: false,
      from: remitenteResend(),
      enviados: [],
      fallidos: [],
      detalle: [],
    };
    await enviarCorreoError(supabase, {
      contexto: "sap_ok",
      traspaso_id: params.traspaso_id ?? null,
      equipo: params.equipo,
      detalle: "RESEND_API_KEY no configurada",
    });
    return vacio;
  }

  const equipo = String(params.equipo ?? "Material");
  const subject = `SAP OK — Traspaso ${equipo}`;
  const html = buildHtmlSapOk({
    rutOrigen: params.rut_origen,
    nombreOrigen: params.nombre_origen,
    rutDestino: params.rut_destino,
    nombreDestino: params.nombre_destino,
    series: params.series ?? [],
    equipo,
    cantidad: params.cantidad ?? 1,
    fecha: fechaChile(),
    nombreConfirmador: params.nombre_confirmador,
    folioKepler: params.folio_kepler ?? null,
    via: params.via ?? null,
  });

  const destinatarios = await obtenerDestinatariosBodega(
    supabase,
    params.solo_destinatario,
  );

  const resultados = await enviarATodos(
    supabase,
    resendKey,
    destinatarios,
    subject,
    html,
    "sap_ok",
    params.traspaso_id ?? null,
  );

  if (!resultados.ok) {
    await enviarCorreoError(supabase, {
      contexto: "sap_ok",
      traspaso_id: params.traspaso_id ?? null,
      equipo,
      detalle: resultados.fallidos.map((f) =>
        `${f.email}: ${f.resend_error ?? `HTTP ${f.status}`}`
      ).join("; ") || "Fallo al notificar SAP OK a bodega",
    });
  }

  return resultados;
}
