// ============================================================
// equipos_reversa_sync.gs
// Sincroniza equipos pendientes de devolución desde Kepler
// hacia dos destinos:
//   1. Tabla equipos_reversa en Supabase
//   2. Sistema KRP (POST /inventario/api/reversa)
//
// Solo sincroniza equipos cuya fecha_trabajo >= primer día del mes.
//
// SETUP:
//   1. Completa KRP_BASE_URL cuando el equipo KRP entregue el host.
//   2. Completa MATERIAL_MAP cuando KRP cree los id_material por tipo de equipo.
//   3. Ejecuta crearTrigger() UNA SOLA VEZ para agendar las 7 AM diarias.
// ============================================================

var SUPABASE_URL    = 'https://efvicvqffvxocnrqjxrs.supabase.co';
var SUPABASE_KEY    = 'TU_SERVICE_ROLE_KEY'; // ← reemplazar
var KEPLER_ENDPOINT = 'https://kepler.sbip.cl/api/v1/toa/get_toa_equipos';
var TZ              = 'America/Santiago';

// ── KRP ──────────────────────────────────────────────────────
// Completar con el host cuando el equipo KRP lo entregue.
// Ejemplo: 'https://krp.sbip.cl'
var KRP_BASE_URL = 'https://logistica.sbip.cl';
var KRP_TOKEN    = '5de53e7b5f89b6b547c5c93d635f162ae2594756';

// Mapeo tipo_equipo (MOD_EQUIPO / TIPO_CPE de Kepler) → id_material en KRP.
// Completar cuando el equipo KRP cree los materiales.
// Los equipos cuyo tipo no esté aquí (o tenga null) se saltean en KRP
// pero igual se sincronizan en Supabase.
var MATERIAL_MAP = {
  // 'HG8245Q2': 1,
  // 'EG8145X6': 2,
  // Agregar más tipos aquí cuando KRP entregue los IDs
};

// ── Función principal ────────────────────────────────────────
function sincronizarEquiposReversa() {
  var hoy = new Date();
  var primerDiaMes = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
  var fechaMinStr = Utilities.formatDate(primerDiaMes, TZ, 'yyyy-MM-dd');
  Logger.log('Sincronizando equipos con fecha_trabajo >= ' + fechaMinStr);

  // 1. Fetch Kepler
  var keplerResp = UrlFetchApp.fetch(KEPLER_ENDPOINT, { muteHttpExceptions: true });
  if (keplerResp.getResponseCode() !== 200) {
    Logger.log('Error Kepler (' + keplerResp.getResponseCode() + '): ' + keplerResp.getContentText());
    return;
  }

  var raw = JSON.parse(keplerResp.getContentText());
  var todos = Array.isArray(raw) ? raw : (raw.data || []);

  // 2. Filtrar solo CREACIONES TECNOLOGICAS con SERIAL y OT
  var items = todos.filter(function(r) {
    return r.DESC_EMPRESA === 'CREACIONES TECNOLOGICAS' && r.SERIAL_NO && r.ID_ACTIVIDAD;
  });

  Logger.log('Equipos CREA encontrados en Kepler: ' + items.length);
  if (items.length === 0) return;

  // 3. Colectar IDs únicos para consultas batch
  var actividades = unique(items.map(function(r) { return r.ID_ACTIVIDAD; }));
  var ruts        = unique(items.map(function(r) { return r.RUT_TECNICO_FS; }).filter(Boolean));

  // 4. Fechas desde produccion_creaciones en chunks de 50
  var fechaMap = {};
  if (actividades.length > 0) {
    chunkArray(actividades, 50).forEach(function(chunk) {
      var url = SUPABASE_URL
        + '/rest/v1/produccion_creaciones'
        + '?select=orden_trabajo,fecha_trabajo'
        + '&orden_trabajo=in.(' + chunk.join(',') + ')';
      supabaseGet(url).forEach(function(r) {
        fechaMap[r.orden_trabajo] = r.fecha_trabajo || null;
      });
    });
    Logger.log('Fechas encontradas en produccion_creaciones: ' + Object.keys(fechaMap).length);
  }

  // 5. Nombres desde plantel_tecnicos en chunks de 50
  var nombreMap = {};
  if (ruts.length > 0) {
    chunkArray(ruts, 50).forEach(function(chunk) {
      var url = SUPABASE_URL
        + '/rest/v1/plantel_tecnicos'
        + '?select=rut,nombre_completo'
        + '&rut=in.(' + chunk.join(',') + ')';
      supabaseGet(url).forEach(function(r) {
        nombreMap[r.rut] = r.nombre_completo || '';
      });
    });
    Logger.log('Técnicos encontrados en plantel_tecnicos: ' + Object.keys(nombreMap).length);
  }

  // 6. Construir registros filtrando por fecha mínima
  var registros = [];
  var sinFecha = 0, anteriorAlMes = 0;

  items.forEach(function(r) {
    var fechaDesinstalacion = parseFecha(fechaMap[r.ID_ACTIVIDAD] || null);
    if (!fechaDesinstalacion)          { sinFecha++;       return; }
    if (fechaDesinstalacion < fechaMinStr) { anteriorAlMes++;  return; }

    registros.push({
      serial:               r.SERIAL_NO,
      ot:                   r.ID_ACTIVIDAD,
      tecnico_rut:          r.RUT_TECNICO_FS || '',
      tecnico_nombre:       nombreMap[r.RUT_TECNICO_FS] || r.RUT_TECNICO_FS || '',
      tipo_equipo:          r.MOD_EQUIPO || r.TIPO_CPE || '',
      descripcion:          r.ACTIVIDAD || '',
      fecha_desinstalacion: fechaDesinstalacion,
      estado:               'pendiente'
    });
  });

  Logger.log('Filtro fechas — sin fecha: ' + sinFecha
    + ', anteriores al mes: ' + anteriorAlMes
    + ', a sincronizar: ' + registros.length);

  if (registros.length === 0) {
    Logger.log('Sin equipos recientes para sincronizar');
    return;
  }

  // 7. Destino 1: Upsert en Supabase (ignore-duplicates por serial+ot)
  enviarSupabase(registros);

  // 8. Destino 2: POST individual a KRP por cada registro
  enviarKrp(registros);
}

// ── Destino 1: Supabase ──────────────────────────────────────

function enviarSupabase(registros) {
  var upsertUrl = SUPABASE_URL + '/rest/v1/equipos_reversa?on_conflict=serial,ot';
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
    Logger.log('[Supabase] OK — ' + registros.length + ' equipos procesados');
  } else {
    Logger.log('[Supabase] Error (' + code + '): ' + resp.getContentText());
  }
}

// ── Destino 2: KRP ───────────────────────────────────────────

function enviarKrp(registros) {
  if (!KRP_BASE_URL) {
    Logger.log('[KRP] Saltado — KRP_BASE_URL no configurada todavía');
    return;
  }

  var url = KRP_BASE_URL + '/inventario/api/reversa';
  var enviados = 0, saltados = 0, errores = 0;

  registros.forEach(function(reg) {
    var idMaterial = MATERIAL_MAP[reg.tipo_equipo];

    if (!idMaterial) {
      Logger.log('[KRP] Saltado — tipo_equipo sin id_material: "' + reg.tipo_equipo
        + '" | serial: ' + reg.serial);
      saltados++;
      return;
    }

    var body = {
      rut:         reg.tecnico_rut,
      serie:       reg.serial,
      id_material: idMaterial
    };

    var resp = UrlFetchApp.fetch(url, {
      method:  'POST',
      headers: {
        'Content-Type': 'application/json',
        'api-token':    KRP_TOKEN
      },
      payload:            JSON.stringify(body),
      muteHttpExceptions: true
    });

    var code = resp.getResponseCode();
    if (code === 201) {
      enviados++;
    } else {
      Logger.log('[KRP] Error serial=' + reg.serial
        + ' (' + code + '): ' + resp.getContentText());
      errores++;
    }
  });

  Logger.log('[KRP] Resultado — enviados: ' + enviados
    + ', saltados (sin id_material): ' + saltados
    + ', errores: ' + errores);
}

// ── Helpers ──────────────────────────────────────────────────

function supabaseGet(url) {
  var resp = UrlFetchApp.fetch(url, {
    headers: {
      'apikey':        SUPABASE_KEY,
      'Authorization': 'Bearer ' + SUPABASE_KEY
    },
    muteHttpExceptions: true
  });
  if (resp.getResponseCode() !== 200) {
    Logger.log('Supabase GET error (' + resp.getResponseCode() + '): ' + resp.getContentText());
    return [];
  }
  return JSON.parse(resp.getContentText());
}

// Extrae YYYY-MM-DD de distintos formatos que puede traer produccion_creaciones
function parseFecha(valor) {
  if (!valor) return null;
  if (/^\d{4}-\d{2}-\d{2}/.test(valor)) return valor.substring(0, 10);
  var m2 = valor.match(/^(\d{2})\/(\d{2})\/(\d{2})$/);
  if (m2) return '20' + m2[3] + '-' + m2[2] + '-' + m2[1];
  var m4 = valor.match(/^(\d{2})[\/\-](\d{2})[\/\-](\d{4})/);
  if (m4) return m4[3] + '-' + m4[2] + '-' + m4[1];
  return null;
}

function unique(arr) {
  var seen = {};
  return arr.filter(function(v) {
    if (seen[v]) return false;
    seen[v] = true;
    return true;
  });
}

function chunkArray(arr, size) {
  var chunks = [];
  for (var i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

// ── Trigger ──────────────────────────────────────────────────
function crearTrigger() {
  ScriptApp.getProjectTriggers()
    .filter(function(t) { return t.getHandlerFunction() === 'sincronizarEquiposReversa'; })
    .forEach(function(t) { ScriptApp.deleteTrigger(t); });

  ScriptApp.newTrigger('sincronizarEquiposReversa')
    .timeBased()
    .everyDays(1)
    .atHour(7)
    .create();

  Logger.log('Trigger creado: sincronizarEquiposReversa diario a las 7:00 AM');
}
