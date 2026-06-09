// ============================================================
// equipos_reversa_sync.gs
// Sincroniza equipos pendientes de devolución desde Kepler
// hacia dos destinos:
//   1. Tabla equipos_reversa en Supabase
//   2. Sistema KRP (POST /inventario/api/reversa)
//
// Solo sincroniza equipos del mes en curso (fecha_trabajo dentro del rango).
// Para un mes fijo: ejecutar sincronizarEquiposReversaMes(2026, 6) → solo junio.
//
// SETUP:
//   1. Completa KRP_BASE_URL cuando el equipo KRP entregue el host.
//   2. Completa MATERIAL_MAP cuando KRP cree los id_material por tipo de equipo.
//   3. Ejecuta crearTrigger() UNA SOLA VEZ para agendar las 7 AM diarias.
//   4. Ejecuta actualizarNombresReversa() UNA VEZ si ya había registros con nombres malos.
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

// Trigger diario: solo el mes en curso (ej. en junio → solo junio 2026).
function sincronizarEquiposReversa() {
  var hoy = new Date();
  sincronizarEquiposReversaMes(hoy.getFullYear(), hoy.getMonth() + 1);
}

// Sincronizar un mes específico. Ej: sincronizarEquiposReversaMes(2026, 6) → solo junio.
function sincronizarEquiposReversaMes(anno, mes) {
  var fechaMinStr = anno + '-' + pad2(mes) + '-01';
  var ultimoDia   = new Date(anno, mes, 0).getDate();
  var fechaMaxStr = anno + '-' + pad2(mes) + '-' + pad2(ultimoDia);
  sincronizarEquiposReversaRango(fechaMinStr, fechaMaxStr);
}

function sincronizarEquiposReversaRango(fechaMinStr, fechaMaxStr) {
  Logger.log('Sincronizando equipos con fecha_trabajo entre '
    + fechaMinStr + ' y ' + fechaMaxStr);

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

  // 3. Colectar OTs únicas para consultas batch de fechas
  var actividades = unique(items.map(function(r) { return r.ID_ACTIVIDAD; }));

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

  // 5. Nombres desde produccion_creaciones (técnicos operativos CREABOX)
  var rutsKepler = unique(items.map(function(r) { return r.RUT_TECNICO_FS; }).filter(Boolean));
  var nombreMap  = cargarMapaNombresProduccion(fechaMinStr, rutsKepler);
  Logger.log('Técnicos con producción cargados: ' + contarRutsEnMapa(nombreMap) + ' personas');

  // 6. Construir registros filtrando por rango de fechas del mes
  var registros = [];
  var sinFecha = 0, fueraDeRango = 0;

  items.forEach(function(r) {
    var fechaDesinstalacion = parseFecha(fechaMap[r.ID_ACTIVIDAD] || null);
    if (!fechaDesinstalacion) { sinFecha++; return; }
    if (fechaDesinstalacion < fechaMinStr || fechaDesinstalacion > fechaMaxStr) {
      fueraDeRango++;
      return;
    }

    var rutCanon = canonicalRut(r.RUT_TECNICO_FS || '');
    registros.push({
      serial:               r.SERIAL_NO,
      ot:                   r.ID_ACTIVIDAD,
      tecnico_rut:          rutCanon,
      tecnico_nombre:       resolverNombre(r.RUT_TECNICO_FS, nombreMap) || rutCanon,
      tipo_equipo:          r.MOD_EQUIPO || r.TIPO_CPE || '',
      descripcion:          r.ACTIVIDAD || '',
      fecha_desinstalacion: fechaDesinstalacion,
      estado:               'pendiente'
    });
  });

  Logger.log('Filtro fechas — sin fecha: ' + sinFecha
    + ', fuera de rango: ' + fueraDeRango
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

// ── Corrección one-shot de nombres ya insertados ─────────────
// Ejecutar UNA VEZ después de corregir la fuente de nómina.
// Por defecto solo el mes en curso; usar actualizarNombresReversaTodos() para todo el histórico.

function actualizarNombresReversaTodos() {
  actualizarNombresReversa(null);
}

function actualizarNombresReversa(fechaMin) {
  if (fechaMin === undefined) {
    var hoy = new Date();
    var primerDiaMes = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
    fechaMin = Utilities.formatDate(primerDiaMes, TZ, 'yyyy-MM-dd');
  }

  Logger.log('[Nombres] Iniciando corrección'
    + (fechaMin ? ' desde ' + fechaMin : ' (todo el histórico)'));

  var filtro = fechaMin ? 'fecha_desinstalacion=gte.' + fechaMin : '';
  var filas = supabaseGetAll(
    'equipos_reversa',
    'serial,ot,tecnico_rut,tecnico_nombre,fecha_desinstalacion',
    filtro
  );

  Logger.log('[Nombres] Registros a revisar: ' + filas.length);

  var rutsEnReversa = unique(filas.map(function(r) { return r.tecnico_rut; }).filter(Boolean));
  var nombreMap = cargarMapaNombresProduccion(fechaMin, rutsEnReversa);
  Logger.log('[Nombres] Técnicos con producción: ' + contarRutsEnMapa(nombreMap) + ' personas');

  var actualizaciones = [];
  var yaOk = 0, sinNombre = 0;

  filas.forEach(function(row) {
    var rutCanon   = canonicalRut(row.tecnico_rut || '');
    var nombreNuevo = resolverNombre(row.tecnico_rut, nombreMap);

    if (!nombreNuevo) {
      sinNombre++;
      return;
    }

    var nombreActual = (row.tecnico_nombre || '').trim();
    var rutActual    = canonicalRut(row.tecnico_rut || '');

    if (nombreActual === nombreNuevo && rutActual === rutCanon) {
      yaOk++;
      return;
    }

    actualizaciones.push({
      serial:         row.serial,
      ot:             row.ot,
      tecnico_rut:    rutCanon,
      tecnico_nombre: nombreNuevo
    });
  });

  Logger.log('[Nombres] Ya correctos: ' + yaOk
    + ' | Sin nombre en nómina: ' + sinNombre
    + ' | A actualizar: ' + actualizaciones.length);

  if (actualizaciones.length === 0) {
    Logger.log('[Nombres] Nada que corregir');
    return;
  }

  var actualizados = 0, errores = 0;
  actualizaciones.forEach(function(reg) {
    if (patchNombreReversa(reg)) actualizados++;
    else errores++;
  });

  Logger.log('[Nombres] Resultado — actualizados: ' + actualizados + ', errores: ' + errores);
}

function patchNombreReversa(reg) {
  var url = SUPABASE_URL
    + '/rest/v1/equipos_reversa'
    + '?serial=eq.' + encodeURIComponent(reg.serial)
    + '&ot=eq.' + encodeURIComponent(reg.ot);

  var resp = UrlFetchApp.fetch(url, {
    method:  'PATCH',
    headers: {
      'Content-Type':  'application/json',
      'apikey':        SUPABASE_KEY,
      'Authorization': 'Bearer ' + SUPABASE_KEY,
      'Prefer':        'return=minimal'
    },
    payload: JSON.stringify({
      tecnico_rut:    reg.tecnico_rut,
      tecnico_nombre: reg.tecnico_nombre
    }),
    muteHttpExceptions: true
  });

  var code = resp.getResponseCode();
  if (code >= 200 && code < 300) return true;

  Logger.log('[Nombres] PATCH falló serial=' + reg.serial
    + ' ot=' + reg.ot + ' (' + code + '): ' + resp.getContentText());
  return false;
}

// ── Destino 1: Supabase ──────────────────────────────────────

function enviarSupabase(registros) {
  return upsertEquiposReversa(registros, 'ignore-duplicates', '[Supabase]');
}

function upsertEquiposReversa(registros, resolution, logPrefix) {
  var upsertUrl = SUPABASE_URL + '/rest/v1/equipos_reversa?on_conflict=serial,ot';
  var resp = UrlFetchApp.fetch(upsertUrl, {
    method:  'POST',
    headers: {
      'Content-Type':  'application/json',
      'apikey':        SUPABASE_KEY,
      'Authorization': 'Bearer ' + SUPABASE_KEY,
      'Prefer':        'resolution=' + resolution + ',return=minimal'
    },
    payload:            JSON.stringify(registros),
    muteHttpExceptions: true
  });

  var code = resp.getResponseCode();
  if (code >= 200 && code < 300) {
    Logger.log(logPrefix + ' OK — ' + registros.length + ' equipos procesados');
    return true;
  }
  Logger.log(logPrefix + ' Error (' + code + '): ' + resp.getContentText());
  return false;
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

// ── Técnicos operativos CREABOX (produccion_creaciones) ──────
// Misma lógica que paneles AST / producción: rut_tecnico + campo tecnico.

function cargarMapaNombresProduccion(fechaMinStr, rutsExtra) {
  var mapa = {};
  var filtro = fechaMinStr ? filtroProduccionMes(fechaMinStr) : '';

  supabaseGetAll('produccion_creaciones', 'rut_tecnico,tecnico,fecha_trabajo', filtro)
    .forEach(function(r) {
      if (!r.rut_tecnico) return;
      if (fechaMinStr && parseFecha(r.fecha_trabajo) && parseFecha(r.fecha_trabajo) < fechaMinStr) return;
      var nombre = (r.tecnico || '').trim().replace(/\s+/g, ' ');
      if (nombre) registrarNombreEnMapa(mapa, r.rut_tecnico, nombre);
    });

  // Fallback puntual: RUTs de Kepler/reversa que no aparecieron en el mes filtrado
  completarNombresDesdeNomina(mapa, rutsExtra || []);

  Logger.log('Mapa nombres listo: ' + contarRutsEnMapa(mapa) + ' RUTs');
  return mapa;
}

function filtroProduccionMes(fechaMinStr) {
  var p = fechaMinStr.split('-');
  var mes  = p[1];
  var anno = p[0].length >= 4 ? p[0].substring(2) : p[0];
  return 'fecha_trabajo=ilike.*/' + mes + '/' + anno;
}

function completarNombresDesdeNomina(mapa, ruts) {
  var faltantes = unique((ruts || []).filter(function(r) {
    return r && !resolverNombre(r, mapa);
  }));
  if (!faltantes.length) return;

  chunkArray(faltantes, 50).forEach(function(chunk) {
    var inList = chunk.map(function(r) { return canonicalRut(r); }).join(',');
    var url = SUPABASE_URL
      + '/rest/v1/nomina_tecnicos'
      + '?select=rut,nombres,paterno,materno'
      + '&rut=in.(' + inList + ')';
    supabaseGet(url).forEach(function(r) {
      var nombre = nombreDesdeNomina(r);
      if (nombre) registrarNombreEnMapa(mapa, r.rut, nombre);
    });
  });

  Logger.log('Fallback nomina_tecnicos — RUTs consultados: ' + faltantes.length);
}

function nombreDesdeNomina(row) {
  return [row.nombres, row.paterno, row.materno]
    .filter(Boolean)
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function registrarNombreEnMapa(mapa, rut, nombre) {
  if (!rut || !nombre) return;
  var canon = canonicalRut(rut);
  var key   = normalizeRutKey(rut);
  mapa[canon]       = nombre;
  mapa[key]         = nombre;
  mapa[rut.trim()]  = nombre;
}

function resolverNombre(rut, mapa) {
  if (!rut) return '';
  return mapa[canonicalRut(rut)]
    || mapa[normalizeRutKey(rut)]
    || mapa[rut.trim()]
    || '';
}

function contarRutsEnMapa(mapa) {
  var ruts = {};
  Object.keys(mapa).forEach(function(k) {
    var canon = canonicalRut(k);
    if (canon.length >= 3) ruts[canon] = true;
  });
  return Object.keys(ruts).length;
}

function normalizeRutKey(rut) {
  return String(rut).replace(/[.\-\s]/g, '').toUpperCase();
}

function canonicalRut(rut) {
  var k = normalizeRutKey(rut);
  if (k.length < 2) return String(rut).trim();
  return k.substring(0, k.length - 1) + '-' + k.substring(k.length - 1);
}

// ── Helpers ──────────────────────────────────────────────────

function supabaseGetAll(table, select, filterOrPageSize, pageSize) {
  var filter = '';
  if (typeof filterOrPageSize === 'string') {
    filter = filterOrPageSize;
    pageSize = pageSize || 1000;
  } else {
    pageSize = filterOrPageSize || 1000;
  }

  var all = [];
  var from = 0;

  while (true) {
    var url = SUPABASE_URL + '/rest/v1/' + table + '?select=' + encodeURIComponent(select);
    if (filter) url += '&' + filter;
    var resp = UrlFetchApp.fetch(url, {
      headers: {
        'apikey':        SUPABASE_KEY,
        'Authorization': 'Bearer ' + SUPABASE_KEY,
        'Range':         from + '-' + (from + pageSize - 1)
      },
      muteHttpExceptions: true
    });

    if (resp.getResponseCode() !== 200 && resp.getResponseCode() !== 206) {
      Logger.log('Supabase GET ALL error ' + table + ' (' + resp.getResponseCode() + '): ' + resp.getContentText());
      break;
    }

    var rows = JSON.parse(resp.getContentText());
    if (!rows.length) break;
    all = all.concat(rows);
    if (rows.length < pageSize) break;
    from += pageSize;
  }

  return all;
}

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

function pad2(n) {
  return (n < 10 ? '0' : '') + n;
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
