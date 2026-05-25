// ============================================================
// combustible_sync.gs
// Sincroniza cargas Copec → cargas_combustible (cada 30 min)
// y recalcula monedero_combustible descontando km de rutas
// (cada 2 horas). Horario: Lun-Sáb 08:00-22:00 Santiago.
//
// SETUP:
//   1. Reemplaza SUPABASE_KEY con el service_role key.
//   2. Ejecuta crearTriggers() UNA SOLA VEZ desde el editor.
// ============================================================

var SUPABASE_URL = 'https://efvicvqffvxocnrqjxrs.supabase.co';
var SUPABASE_KEY = 'TU_SERVICE_ROLE_KEY'; // ← reemplazar

var COPEC_URL = 'https://ford.sbip.cl/api/combustible/copec-auto/detalle';
var RUTAS_URL = 'https://ford.sbip.cl/api/analisis-ruta-cache?limit=50000';
var FORD_USER = 'ford_api';
var FORD_PASS = 'Sbip2024!';

var RENDIMIENTO_FALLBACK = 12.0; // km/L si no hay parametros_combustible
var PRECIO_FALLBACK      = 1500; // CLP/L fallback
var TZ = 'America/Santiago';

// ── Función 1: Sync cargas Copec (trigger: cada 30 min) ─────────────────────
function sincronizarCargas() {
  if (!_enHorario()) return;
  Logger.log('[Cargas] Iniciando sync Copec...');

  var raw = _fordGet(COPEC_URL);
  if (!raw) return;

  var cargas = Array.isArray(raw) ? raw : (raw.data || []);
  Logger.log('[Cargas] ' + cargas.length + ' registros desde Copec');
  if (cargas.length === 0) return;

  var registros = cargas
    .filter(function(c) { return c.comprobante && c.rut_conductor && c.patente; })
    .map(function(c) {
      return {
        comprobante:    c.comprobante,
        fecha:          c.fecha,
        hora:           c.hora,
        litros:         parseFloat(c.litros)  || 0,
        monto:          parseFloat(c.monto)   || 0,
        numero_tarjeta: c.numero_tarjeta || '',
        patente:        c.patente,
        rut_conductor:  c.rut_conductor
      };
    });

  var upsertUrl = SUPABASE_URL + '/rest/v1/cargas_combustible?on_conflict=comprobante';
  var resp = UrlFetchApp.fetch(upsertUrl, {
    method:  'POST',
    headers: {
      'Content-Type':  'application/json',
      'apikey':        SUPABASE_KEY,
      'Authorization': 'Bearer ' + SUPABASE_KEY,
      'Prefer':        'resolution=ignore-duplicates,return=minimal'
    },
    payload:            JSON.stringify(registros),
    muteHttpExceptions: true
  });

  var code = resp.getResponseCode();
  if (code >= 200 && code < 300) {
    Logger.log('[Cargas] OK — ' + registros.length + ' cargas procesadas');
    _recalcularMonedero();
  } else {
    Logger.log('[Cargas] Error upsert (' + code + '): ' + resp.getContentText());
  }
}

// ── Función 2: Recalcular monedero (trigger: cada 2 horas) ──────────────────
function recalcularMonedero() {
  if (!_enHorario()) return;
  Logger.log('[Monedero] Iniciando recálculo desde rutas...');
  _recalcularMonedero();
}

// ── Núcleo: cálculo de saldo por técnico ─────────────────────────────────────
function _recalcularMonedero() {
  // Parámetros de combustible desde Supabase
  var precioLitro = _obtenerParametro('precio_litro',  PRECIO_FALLBACK);
  var rendimiento = _obtenerParametro('rendimiento_km', RENDIMIENTO_FALLBACK);
  Logger.log('[Monedero] precio=' + precioLitro + ' CLP/L  rendimiento=' + rendimiento + ' km/L');

  // 1. Cargas desde BD ordenadas por fecha+hora asc
  var cargas = _supabaseGet(
    SUPABASE_URL + '/rest/v1/cargas_combustible?select=*&order=fecha.asc,hora.asc'
  );
  if (cargas.length === 0) {
    Logger.log('[Monedero] Sin cargas en BD, saliendo.');
    return;
  }

  // 2. Agrupar cargas por rut normalizado, conservando el rut original
  var cargasPorRut = {};
  var rutOriginalMap = {}; // normRut → rut con formato original (con guión)
  cargas.forEach(function(c) {
    var rutNorm = _normRut(c.rut_conductor);
    if (!cargasPorRut[rutNorm]) {
      cargasPorRut[rutNorm] = [];
      rutOriginalMap[rutNorm] = c.rut_conductor; // conservar "18976494-4"
    }
    cargasPorRut[rutNorm].push(c);
  });
  Logger.log('[Monedero] ' + Object.keys(cargasPorRut).length + ' técnicos con cargas');

  // 3. Rutas desde API (analisis-ruta-cache)
  var rutasRaw = _fordGet(RUTAS_URL);
  var todasRutas = [];
  if (rutasRaw && rutasRaw.data && Array.isArray(rutasRaw.data.registros)) {
    todasRutas = rutasRaw.data.registros;
  } else if (Array.isArray(rutasRaw)) {
    todasRutas = rutasRaw;
  }
  Logger.log('[Monedero] ' + todasRutas.length + ' rutas desde API');

  // 4. Agrupar rutas por rut normalizado
  var rutasPorRut = {};
  todasRutas.forEach(function(r) {
    var rut = _normRut(r.rut || (r.payload && r.payload.rut) || '');
    if (!rut) return;
    if (!rutasPorRut[rut]) rutasPorRut[rut] = [];
    rutasPorRut[rut].push(r);
  });

  // 5. Calcular saldo por técnico
  var upserts = [];
  Object.keys(cargasPorRut).forEach(function(rut) {
    var rutCargas = cargasPorRut[rut]; // ya ordenadas asc

    // Sumar litros y montos de todas las cargas
    var litrosCargados = rutCargas.reduce(function(s, c) {
      return s + (parseFloat(c.litros) || 0);
    }, 0);
    var montoCargado = rutCargas.reduce(function(s, c) {
      return s + (parseFloat(c.monto) || 0);
    }, 0);

    // Patente de la carga más reciente
    var cargaReciente = rutCargas[rutCargas.length - 1];
    var patente       = cargaReciente.patente || '';

    // Fecha+hora de la primera carga → límite inferior para rutas
    var primeraCargas = rutCargas[0];
    var fechaLimite   = _parseFechaCopec(primeraCargas.fecha, primeraCargas.hora);

    // Rutas del técnico desde la primera carga
    var rutasTec = (rutasPorRut[rut] || []).filter(function(r) {
      var fechaRuta = _parseFechaToa(r.fecha_toa);
      return fechaRuta !== null && fechaRuta >= fechaLimite;
    });

    // Sumar km de esas rutas
    var kmTotal = rutasTec.reduce(function(s, r) {
      var km = (r.payload && r.payload.km_osrm_asignado)
               ? parseFloat(r.payload.km_osrm_asignado) || 0
               : 0;
      return s + km;
    }, 0);

    var litrosConsumidos  = kmTotal / rendimiento;
    var saldoLitros       = Math.max(0, litrosCargados - litrosConsumidos);
    var saldoPesos        = Math.round(saldoLitros      * precioLitro);
    var consumidoPesos    = Math.round(litrosConsumidos  * precioLitro);

    Logger.log('[Monedero] ' + rut + ' | ' +
      'cargados=' + litrosCargados.toFixed(1) + 'L ' +
      'km=' + kmTotal.toFixed(0) + ' ' +
      'consumido=' + litrosConsumidos.toFixed(1) + 'L ' +
      'saldo=' + saldoLitros.toFixed(1) + 'L ($' + saldoPesos + ') ' +
      'patente=' + patente);

    upserts.push({
      rut_tecnico:           rutOriginalMap[rut], // formato original: "18976494-4"
      patente:               patente,
      saldo_litros:          Math.round(saldoLitros      * 100) / 100,
      saldo_pesos:           saldoPesos,
      total_cargado:         Math.round(litrosCargados   * 100) / 100,
      total_consumido:       Math.round(litrosConsumidos * 100) / 100,
      total_cargado_pesos:   Math.round(montoCargado),
      total_consumido_pesos: consumidoPesos,
      ultima_carga:          _isoFechaCopec(cargaReciente.fecha, cargaReciente.hora),
      updated_at:            new Date().toISOString()
    });
  });

  if (upserts.length === 0) {
    Logger.log('[Monedero] Sin datos para upsert.');
    return;
  }

  var upsertUrl = SUPABASE_URL + '/rest/v1/monedero_combustible?on_conflict=rut_tecnico';
  var resp = UrlFetchApp.fetch(upsertUrl, {
    method:  'POST',
    headers: {
      'Content-Type':  'application/json',
      'apikey':        SUPABASE_KEY,
      'Authorization': 'Bearer ' + SUPABASE_KEY,
      'Prefer':        'resolution=merge-duplicates,return=minimal'
    },
    payload:            JSON.stringify(upserts),
    muteHttpExceptions: true
  });

  var code = resp.getResponseCode();
  if (code >= 200 && code < 300) {
    Logger.log('[Monedero] OK — ' + upserts.length + ' monederos actualizados');
  } else {
    Logger.log('[Monedero] Error upsert (' + code + '): ' + resp.getContentText());
  }
}

// ── Parámetros combustible ────────────────────────────────────────────────────
function _obtenerParametro(columna, fallback) {
  var url = SUPABASE_URL +
    '/rest/v1/parametros_combustible?select=' + columna +
    '&order=vigente_desde.desc&limit=1';
  var rows = _supabaseGet(url);
  if (rows.length > 0 && rows[0][columna]) return parseFloat(rows[0][columna]);
  return fallback;
}

// ── HTTP helpers ──────────────────────────────────────────────────────────────
function _fordGet(url) {
  var creds = Utilities.base64Encode(FORD_USER + ':' + FORD_PASS);
  var resp = UrlFetchApp.fetch(url, {
    headers: { 'Authorization': 'Basic ' + creds },
    muteHttpExceptions: true
  });
  if (resp.getResponseCode() !== 200) {
    Logger.log('[Ford] Error ' + resp.getResponseCode() + ' en ' + url);
    return null;
  }
  return JSON.parse(resp.getContentText());
}

function _supabaseGet(url) {
  var resp = UrlFetchApp.fetch(url, {
    headers: {
      'apikey':        SUPABASE_KEY,
      'Authorization': 'Bearer ' + SUPABASE_KEY
    },
    muteHttpExceptions: true
  });
  if (resp.getResponseCode() !== 200) {
    Logger.log('[Supabase] GET error ' + resp.getResponseCode() + ': ' +
               resp.getContentText().substring(0, 200));
    return [];
  }
  return JSON.parse(resp.getContentText());
}

// ── Helpers de fecha ──────────────────────────────────────────────────────────
// "02/03/26" (DD/MM/YY) → Date al inicio del día
function _parseFechaToa(fechaToa) {
  if (!fechaToa) return null;
  var p = fechaToa.split('/');
  if (p.length !== 3) return null;
  var d = parseInt(p[0]), m = parseInt(p[1]) - 1, y = 2000 + parseInt(p[2]);
  if (isNaN(d) || isNaN(m) || isNaN(y)) return null;
  return new Date(y, m, d, 0, 0, 0);
}

// "2026-05-19", "08:29" → Date
function _parseFechaCopec(fecha, hora) {
  var fp = fecha.split('-');
  var tp = (hora || '00:00').split(':');
  return new Date(parseInt(fp[0]), parseInt(fp[1]) - 1, parseInt(fp[2]),
                  parseInt(tp[0]), parseInt(tp[1]), 0);
}

// "2026-05-19", "08:29" → ISO string con offset Santiago
function _isoFechaCopec(fecha, hora) {
  return fecha + 'T' + (hora || '00:00') + ':00-04:00';
}

// Normaliza RUT: quita puntos, guiones, espacios → minúsculas
function _normRut(rut) {
  return (rut || '').replace(/[\.\-\s]/g, '').toLowerCase();
}

// ── Horario Lun-Sáb 08:00-22:00 Santiago ─────────────────────────────────────
function _enHorario() {
  var ahora   = new Date();
  var dia     = parseInt(Utilities.formatDate(ahora, TZ, 'u'));  // 1=Lun 7=Dom
  var hora    = parseInt(Utilities.formatDate(ahora, TZ, 'HH')); // 00-23
  return dia >= 1 && dia <= 6 && hora >= 8 && hora < 22;
}

// ── Triggers ──────────────────────────────────────────────────────────────────
// Ejecutar UNA SOLA VEZ desde el editor de Apps Script.
function crearTriggers() {
  ScriptApp.getProjectTriggers()
    .filter(function(t) {
      return t.getHandlerFunction() === 'sincronizarCargas' ||
             t.getHandlerFunction() === 'recalcularMonedero';
    })
    .forEach(function(t) { ScriptApp.deleteTrigger(t); });

  ScriptApp.newTrigger('sincronizarCargas')
    .timeBased()
    .everyMinutes(30)
    .create();

  ScriptApp.newTrigger('recalcularMonedero')
    .timeBased()
    .everyHours(2)
    .create();

  Logger.log('Triggers creados:\n' +
    '  sincronizarCargas  → cada 30 min\n' +
    '  recalcularMonedero → cada 2 horas\n' +
    '  Ambos activos sólo Lun-Sáb 08:00-22:00 (America/Santiago)');
}
