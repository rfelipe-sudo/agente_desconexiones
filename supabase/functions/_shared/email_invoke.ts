/** Invoca `email-traspaso` vía HTTP (más fiable que supabase.functions.invoke). */
export async function llamarEmailTraspaso(
  body: Record<string, unknown>,
): Promise<{ ok: boolean; status: number; data: unknown }> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    return { ok: false, status: 500, data: { error: "Supabase no configurado" } };
  }

  const res = await fetch(`${supabaseUrl}/functions/v1/email-traspaso`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${serviceKey}`,
      apikey: serviceKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  let data: unknown;
  try {
    data = await res.json();
  } catch {
    data = { raw: await res.text().catch(() => "") };
  }

  console.log(`email-traspaso HTTP ${res.status}:`, JSON.stringify(data));
  return { ok: res.ok, status: res.status, data };
}
