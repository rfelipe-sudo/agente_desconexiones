import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
}

const KEPLER_BASE  = 'https://logistica.sbip.cl'
const KEPLER_TOKEN = '5de53e7b5f89b6b547c5c93d635f162ae2594756'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { 'Content-Type': 'application/json', ...CORS },
    })

  try {
    const { pdf_base64, folio, traspaso_id } = await req.json()

    if (!pdf_base64 || !folio) {
      return json({ error: 'pdf_base64 y folio son requeridos' }, 400)
    }

    // Decodificar base64 → bytes del PDF
    const binaryString = atob(pdf_base64)
    const pdfBytes = new Uint8Array(binaryString.length)
    for (let i = 0; i < binaryString.length; i++) {
      pdfBytes[i] = binaryString.charCodeAt(i)
    }

    // Construir multipart/form-data — solo el campo archivo
    const form = new FormData()
    form.append(
      'archivo',
      new Blob([pdfBytes], { type: 'application/pdf' }),
      `guia_${folio}.pdf`,
    )

    // URL: /intercambio/api/solicitar/{folio}/pdf
    const res = await fetch(`${KEPLER_BASE}/intercambio/api/solicitar/${folio}/pdf`, {
      method:  'POST',
      headers: { 'api-token': KEPLER_TOKEN },
      body:    form,
    })

    let responseData: unknown
    try { responseData = await res.json() } catch { responseData = await res.text() }

    if (!res.ok) {
      console.error('Kepler PDF error:', res.status, responseData)
      return json({ error: 'Kepler rechazó el PDF', status: res.status, detail: responseData }, 502)
    }

    // Kepler confirmó el PDF → marcar en la DB
    if (traspaso_id) {
      const supabase = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      )
      await supabase
        .from('traspasos_bodega')
        .update({ pdf_kepler_ok: true })
        .eq('id', traspaso_id)
    }

    console.log('PDF enviado a Kepler OK — folio:', folio)
    return json({ ok: true, kepler: responseData })
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e)
    return json({ error: msg }, 500)
  }
})
