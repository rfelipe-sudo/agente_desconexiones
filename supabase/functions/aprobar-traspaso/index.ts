import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { enviarCorreoAprobacion } from '../_shared/traspaso_email.ts'
import {
  nombreBodegueroPorRut,
  nombreTecnicoPorRut,
  rutCanonicoBodeguero,
} from '../_shared/nomina.ts'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
}

const KEPLER_BASE  = 'https://logistica.sbip.cl'
const KEPLER_PATH  = '/intercambio/api/solicitar'
const KEPLER_TOKEN = '5de53e7b5f89b6b547c5c93d635f162ae2594756'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { 'Content-Type': 'application/json', ...CORS },
    })

  try {
    const { traspaso_id, aprobado_por, nombre_aprobador } = await req.json()
    if (!traspaso_id) return json({ error: 'traspaso_id requerido' }, 400)
    if (!aprobado_por) return json({ error: 'aprobado_por requerido' }, 400)

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const rutAprobador = await rutCanonicoBodeguero(supabase, String(aprobado_por))
    if (!rutAprobador) {
      return json({ error: 'RUT no pertenece a nómina de bodega' }, 403)
    }

    const nombreAprobador =
      (await nombreBodegueroPorRut(supabase, rutAprobador)) ??
      (String(nombre_aprobador ?? '').trim() || rutAprobador)

    const { data: tr, error: trErr } = await supabase
      .from('traspasos_bodega')
      .select('*')
      .eq('id', traspaso_id)
      .single()

    if (trErr || !tr) return json({ error: 'Traspaso no encontrado' }, 404)
    if (tr.estado === 'aprobado') return json({ error: 'Ya aprobado' }, 409)

    const nombreOrigen =
      (await nombreTecnicoPorRut(supabase, tr.rut_tecnico_b)) ??
      tr.nombre_tecnico_b
    const nombreDestino =
      (await nombreTecnicoPorRut(supabase, tr.rut_tecnico_a)) ??
      tr.nombre_tecnico_a

    // Llamar a Kepler
    let folioKepler: string | null = null
    const materiales = tr.series?.length > 0
      ? tr.series.map((s: string) => ({ id_material: tr.id_material, cantidad: 1, serie: s }))
      : [{ id_material: tr.id_material, cantidad: tr.cantidad }]

    try {
      const keplerRes = await fetch(`${KEPLER_BASE}${KEPLER_PATH}`, {
        method: 'POST',
        headers: { 'api-token': KEPLER_TOKEN, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          id_trabajador_origen:  tr.rut_tecnico_b,
          id_trabajador_destino: tr.rut_tecnico_a,
          materiales,
        }),
      })
      const keplerData = await keplerRes.json()
      if (keplerRes.ok) folioKepler = keplerData.folio ?? null
      else console.error('Kepler error:', keplerData)
    } catch (e) {
      console.error('Kepler fetch error:', e)
    }

    const ahora = new Date().toISOString()
    const sapConfirmToken = crypto.randomUUID()
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const sapConfirmUrl = supabaseUrl
      ? `${supabaseUrl}/functions/v1/confirmar-sap?token=${sapConfirmToken}&id=${traspaso_id}`
      : null

    await supabase.from('traspasos_bodega').update({
      estado:                 'aprobado',
      aprobado_por:           rutAprobador,
      nombre_aprobador:       nombreAprobador,
      nombre_tecnico_b:       nombreOrigen,
      nombre_tecnico_a:       nombreDestino,
      aprobado_en:            ahora,
      folio_kepler:           folioKepler,
      sap_confirm_token:      sapConfirmToken,
      sap_ok:                 false,
      sap_confirmado_en:      null,
      sap_confirmado_por:     null,
      nombre_sap_confirmador: null,
    }).eq('id', traspaso_id)

    if (tr.solicitud_material_id) {
      await supabase.from('solicitudes_material').update({
        estado:       'completada',
        folio_kepler: folioKepler,
      }).eq('id', tr.solicitud_material_id)

      if (folioKepler) {
        await supabase.from('solicitudes_bodega').update({
          folio_kepler: folioKepler,
        }).eq('solicitud_id', tr.solicitud_material_id)
      }
    }

    try {
      await supabase.from('tiempos_transferencia').insert({
        traspaso_id:   traspaso_id,
        rut_tecnico_a: tr.rut_tecnico_a,
        rut_tecnico_b: tr.rut_tecnico_b,
        tipo_material: tr.tipo_material,
        cantidad:      tr.cantidad,
        folio_kepler:  folioKepler,
        timestamp_krp: ahora,
      })
    } catch (e) {
      console.error('Error insertando tiempos_transferencia:', e)
    }

    console.log(
      `aprobar-traspaso ok id=${traspaso_id} aprobador=${nombreAprobador} (${rutAprobador})`,
    )

    const emailResult = await enviarCorreoAprobacion(supabase, {
      traspaso_id:      traspaso_id,
      rut_origen:       tr.rut_tecnico_b,
      nombre_origen:    nombreOrigen,
      rut_destino:      tr.rut_tecnico_a,
      nombre_destino:   nombreDestino,
      series:           tr.series ?? [],
      equipo:           tr.tipo_material,
      cantidad:         tr.cantidad,
      nombre_aprobador: nombreAprobador,
      folio_kepler:     folioKepler,
      sap_confirm_url:  sapConfirmUrl,
    })
    if (!emailResult.ok) {
      console.error('Email traspaso falló:', JSON.stringify(emailResult))
    } else {
      console.log('Email traspaso OK:', JSON.stringify(emailResult))
    }

    const ruts = [tr.rut_tecnico_a, tr.rut_tecnico_b]
    for (const rut of ruts) {
      try {
        const { data: tec } = await supabase
          .from('nomina_tecnicos')
          .select('fcm_token')
          .eq('rut', rut)
          .maybeSingle()
        const token = tec?.fcm_token
        if (token) {
          await supabase.functions.invoke('fcm-send', {
            body: {
              token,
              accion:      'krp_aprobado',
              tipo:        'Transferencia KRP realizada',
              descripcion: `TRANSFERENCIA EN KRP LISTA, TRANSFERENCIA EN TOA EN PROCESO${folioKepler ? ` — Folio: ${folioKepler}` : ''}`,
            },
          })
        }
      } catch (e) {
        console.error('FCM KRP error para', rut, e)
      }
    }

    return json({
      ok: true,
      folio_kepler: folioKepler,
      nombre_aprobador: nombreAprobador,
      email_ok: emailResult.ok,
      email_enviados: emailResult.enviados,
      email_fallidos: emailResult.fallidos,
      email_detalle: emailResult.detalle,
    })
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e)
    return json({ error: msg }, 500)
  }
})
