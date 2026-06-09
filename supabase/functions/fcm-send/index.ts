/**
 * Edge Function: fcm-send
 *
 * Envía mensajes FCM v1. Alertas técnicas (material, flota): data_only para
 * onMessageReceived + Kotlin. Bodeguero (traspaso_bodega, guia_firmada_bodega):
 * siempre notification+data con canal mat_alertas_7 — respaldo si Android no
 * invoca onMessageReceived en background.
 *
 * Acepta `token` (uno) o `tokens` (array) para envío masivo.
 *
 * Secretos requeridos en Supabase (Settings → Edge Functions → Secrets):
 *   FCM_PROJECT_ID
 *   FCM_CLIENT_EMAIL
 *   FCM_PRIVATE_KEY   (con \n escapados como en el JSON de service account)
 */
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.8/mod.ts";

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

/** FCM exige que todos los valores en `data` sean strings. */
function toDataStrings(
  input: Record<string, unknown>,
): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(input)) {
    if (v === undefined || v === null) continue;
    out[k] = typeof v === "string" ? v : JSON.stringify(v);
  }
  return out;
}

async function getAccessToken(): Promise<string> {
  const projectId = Deno.env.get("FCM_PROJECT_ID");
  const clientEmail = Deno.env.get("FCM_CLIENT_EMAIL");
  let privateKey = Deno.env.get("FCM_PRIVATE_KEY") ?? "";
  privateKey = privateKey.replace(/\\n/g, "\n");

  if (!projectId || !clientEmail || !privateKey) {
    throw new Error(
      "Faltan secretos FCM_PROJECT_ID, FCM_CLIENT_EMAIL o FCM_PRIVATE_KEY",
    );
  }

  const pemBody = privateKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binary,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const jwt = await create(
    { alg: "RS256", typ: "JWT" },
    {
      iss: clientEmail,
      sub: clientEmail,
      aud: "https://oauth2.googleapis.com/token",
      iat: getNumericDate(0),
      exp: getNumericDate(3600),
      scope: "https://www.googleapis.com/auth/firebase.messaging",
    },
    cryptoKey,
  );

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!tokenRes.ok) {
    const err = await tokenRes.text();
    throw new Error(`OAuth token error: ${err}`);
  }

  const { access_token } = await tokenRes.json();
  return access_token as string;
}

function buildDataPayload(
  body: Record<string, unknown>,
  accion: string,
  title: string,
  msgBody: string,
): Record<string, string> {
  return toDataStrings({
    accion,
    title,
    body: msgBody,
    descripcion: String(body.descripcion ?? msgBody),
    tipo: String(body.tipo ?? title),
    ...(typeof body.extra === "object" && body.extra !== null
      ? body.extra as Record<string, unknown>
      : {}),
    ...Object.fromEntries(
      Object.entries(body).filter(([k]) =>
        ![
          "token",
          "tokens",
          "data_only",
          "skip_notification",
          "dataOnly",
          "android_channel_id",
          "android_priority",
          "extra",
        ].includes(k)
      ),
    ),
  });
}

async function sendOne(
  projectId: string,
  accessToken: string,
  deviceToken: string,
  dataPayload: Record<string, string>,
  dataOnly: boolean,
  channelId: string,
  title: string,
  msgBody: string,
  notificationSound: string,
): Promise<{ ok: boolean; detail?: unknown }> {
  const message: Record<string, unknown> = {
    token: deviceToken,
    data: dataPayload,
    android: {
      priority: "HIGH",
      directBootOk: true,
      ttl: "86400s",
    },
  };

  if (!dataOnly) {
    message.notification = { title, body: msgBody };
    (message.android as Record<string, unknown>).notification = {
      channel_id: channelId,
      sound: notificationSound,
    };
  }

  const fcmRes = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ message }),
    },
  );

  const fcmBody = await fcmRes.json();
  if (!fcmRes.ok) {
    return { ok: false, detail: fcmBody };
  }
  return { ok: true, detail: fcmBody };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    const body = await req.json();
    const tokensRaw = body.tokens as string[] | undefined;
    const singleToken = body.token as string | undefined;
    const allTokens = [
      ...(tokensRaw ?? []).filter((t) => typeof t === "string" && t.length > 0),
      ...(singleToken ? [singleToken] : []),
    ];
    if (allTokens.length === 0) {
      return json(400, { error: "token o tokens requerido" });
    }

    const accion = String(body.accion ?? "");
    const title = String(body.title ?? body.tipo ?? "CREABOX");
    const msgBody = String(body.body ?? body.descripcion ?? "");

    const dataOnly =
      body.data_only === true ||
      body.skip_notification === true ||
      body.dataOnly === true;

    // Bodeguero / comunicados / ayuda supervisor: notification + data para que
    // Android muestre notificación con sonido aunque no invoque onMessageReceived.
    const esAlertaBodega =
      accion === "traspaso_bodega" || accion === "guia_firmada_bodega";
    const esAlertaComunicado = accion === "comunicado_creabox";
    const esAyudaSupervisor =
      accion === "solicitud_ayuda" ||
      accion === "material_sin_respuesta" ||
      accion === "ayuda_cancelada";
    const effectiveDataOnly =
      esAlertaBodega || esAlertaComunicado || esAyudaSupervisor
        ? false
        : dataOnly;

    let channelId = String(body.android_channel_id ?? "mat_alertas_7");
    let notificationSound = "alerta_urgente";
    if (esAlertaComunicado) {
      channelId = "comunicados_creabox_1";
      notificationSound = "comunicado_mushroom";
    } else if (esAyudaSupervisor) {
      channelId = "ayuda_supervisor_1";
      notificationSound = accion === "ayuda_cancelada"
        ? "default"
        : "ayuda_supervisor_mario";
    }
    const dataPayload = buildDataPayload(body, accion, title, msgBody);

    const projectId = Deno.env.get("FCM_PROJECT_ID");
    if (!projectId) {
      return json(500, { error: "FCM_PROJECT_ID no configurado" });
    }

    const accessToken = await getAccessToken();

    if (allTokens.length === 1) {
      const result = await sendOne(
        projectId,
        accessToken,
        allTokens[0],
        dataPayload,
        effectiveDataOnly,
        channelId,
        title,
        msgBody,
        notificationSound,
      );
      if (!result.ok) {
        console.error("FCM error:", result.detail);
        return json(502, { error: "FCM send failed", detail: result.detail });
      }
      console.log(
        `FCM ok accion=${accion} data_only=${effectiveDataOnly} channel=${channelId}`,
      );
      return json(200, { ok: true, data_only: effectiveDataOnly, sent: 1, failed: 0 });
    }

    const results = await Promise.all(
      allTokens.map((t) =>
        sendOne(
          projectId,
          accessToken,
          t,
          dataPayload,
          effectiveDataOnly,
          channelId,
          title,
          msgBody,
          notificationSound,
        )
      ),
    );
    const sent = results.filter((r) => r.ok).length;
    const failed = results.length - sent;
    console.log(
      `FCM batch accion=${accion} sent=${sent} failed=${failed}`,
    );
    return json(200, { ok: sent > 0, data_only: effectiveDataOnly, sent, failed });
  } catch (e) {
    console.error(e);
    return json(500, { error: String(e) });
  }
});
