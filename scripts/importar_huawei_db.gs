// ─── CONFIGURACIÓN ────────────────────────────────────────────────────────────
const SUPABASE_URL  = 'https://efvicvqffvxocnrqjxrs.supabase.co';
const SUPABASE_KEY  = 'TU_SERVICE_ROLE_KEY'; // Settings → API → service_role
const BATCH_SIZE    = 500;
const CDE_BASE      = 'https://cdevirtual.cl';
const CDE_USER      = '26857054';
const CDE_PASS      = '7054';

// ─── TRIGGER DIARIO ───────────────────────────────────────────────────────────

// Ejecuta esta función UNA SOLA VEZ para activar la sincronización diaria.
// Después de eso corre sola todos los días a las 3 AM.
function activarSincronizacionDiaria() {
  // Eliminar triggers previos del mismo nombre para no duplicar
  ScriptApp.getProjectTriggers()
    .filter(t => t.getHandlerFunction() === 'importarHuaweiDB')
    .forEach(t => ScriptApp.deleteTrigger(t));

  ScriptApp.newTrigger('importarHuaweiDB')
    .timeBased()
    .everyDays(1)
    .atHour(3)       // 3 AM hora del proyecto Google
    .create();

  console.log('✓ Trigger diario activado — correrá todos los días a las 3 AM');
}

// Para desactivar la sincronización automática
function desactivarSincronizacion() {
  const eliminados = ScriptApp.getProjectTriggers()
    .filter(t => t.getHandlerFunction() === 'importarHuaweiDB');
  eliminados.forEach(t => ScriptApp.deleteTrigger(t));
  console.log(`✓ ${eliminados.length} trigger(s) eliminado(s)`);
}

// ─── FUNCIÓN PRINCIPAL ────────────────────────────────────────────────────────
function importarHuaweiDB() {
  const inicio = new Date();
  console.log(`▶ Sincronización iniciada — ${inicio.toLocaleString()}`);

  // 1. Cuántos tenemos actualmente en Supabase
  const antesCount = _contarEnSupabase();
  console.log(`  Registros actuales en Supabase: ${antesCount}`);

  // 2. Login en CDE Virtual
  const cookie = _loginCDE();
  if (!cookie) {
    console.error('✗ No se pudo hacer login en CDE Virtual');
    _registrarLog(inicio, 0, 0, 'Error de login en CDE Virtual');
    return;
  }
  console.log('✓ Login exitoso en CDE Virtual');

  // 3. Descargar database.json
  console.log('⟳ Descargando tabla de contraseñas...');
  const db = _descargarDB(cookie);
  if (!db) {
    console.error('✗ No se pudo descargar la base de datos');
    _registrarLog(inicio, 0, 0, 'Error al descargar database.json');
    return;
  }

  const entradas = Object.entries(db);
  console.log(`✓ CDE Virtual tiene ${entradas.length} registros en total`);

  // 4. Insertar en Supabase — los duplicados se omiten automáticamente
  let procesados = 0;
  let errores    = 0;
  const totalLotes = Math.ceil(entradas.length / BATCH_SIZE);

  for (let i = 0; i < entradas.length; i += BATCH_SIZE) {
    const lote = entradas.slice(i, i + BATCH_SIZE).map(([hash, valor]) => ({
      sn_hash:  hash,
      password: typeof valor === 'object'
        ? (valor.password ?? valor.Password ?? JSON.stringify(valor))
        : String(valor),
    }));

    const ok = _insertarLote(lote);
    if (ok) {
      procesados += lote.length;
    } else {
      errores += lote.length;
    }

    const loteActual = Math.floor(i / BATCH_SIZE) + 1;
    if (loteActual % 20 === 0 || loteActual === totalLotes) {
      const pct = Math.round((procesados / entradas.length) * 100);
      console.log(`  Lote ${loteActual}/${totalLotes} — ${pct}%`);
    }

    Utilities.sleep(80);
  }

  // 5. Calcular cuántos son nuevos
  const despuesCount = _contarEnSupabase();
  const nuevos = despuesCount - antesCount;

  const duracionSeg = Math.round((new Date() - inicio) / 1000);
  console.log(`\n✓ Sincronización completada en ${duracionSeg}s`);
  console.log(`  Total en CDE Virtual: ${entradas.length}`);
  console.log(`  Nuevos insertados:    ${nuevos}`);
  console.log(`  Ya existían:          ${entradas.length - nuevos}`);
  if (errores > 0) console.log(`  Errores de inserción: ${errores}`);

  _registrarLog(inicio, entradas.length, nuevos, errores > 0 ? `${errores} errores` : 'OK');
}

// ─── LOGIN CDE VIRTUAL ────────────────────────────────────────────────────────
function _loginCDE() {
  const paginaLogin = UrlFetchApp.fetch(`${CDE_BASE}/login/index.php`, {
    muteHttpExceptions: true,
    followRedirects: true,
  });

  const html       = paginaLogin.getContentText();
  const tokenMatch = html.match(/name="logintoken"\s+value="([^"]+)"/);
  if (!tokenMatch) {
    console.error('No se encontró logintoken en la página de login');
    return null;
  }

  const logintoken    = tokenMatch[1];
  const cookieInicial = _extraerCookies(paginaLogin.getAllHeaders());

  const respLogin = UrlFetchApp.fetch(`${CDE_BASE}/login/index.php`, {
    method: 'post',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Cookie': cookieInicial,
    },
    payload: [
      `username=${encodeURIComponent(CDE_USER)}`,
      `password=${encodeURIComponent(CDE_PASS)}`,
      `logintoken=${logintoken}`,
      'anchor=',
    ].join('&'),
    muteHttpExceptions: true,
    followRedirects: false,
  });

  const cookieSesion = _extraerCookies(respLogin.getAllHeaders());
  return cookieSesion || cookieInicial;
}

// ─── DESCARGAR DATABASE.JSON ──────────────────────────────────────────────────
function _descargarDB(cookie) {
  const resp = UrlFetchApp.fetch(
    `${CDE_BASE}/repositorio/consultahuawei/database.json`,
    {
      headers: { 'Cookie': cookie },
      muteHttpExceptions: true,
    }
  );

  if (resp.getResponseCode() !== 200) {
    console.error(`Error HTTP ${resp.getResponseCode()} al descargar DB`);
    return null;
  }

  try {
    return JSON.parse(resp.getContentText());
  } catch (e) {
    console.error(`Error parseando JSON: ${e}`);
    return null;
  }
}

// ─── INSERTAR LOTE EN SUPABASE (duplicados ignorados automáticamente) ─────────
function _insertarLote(registros) {
  const resp = UrlFetchApp.fetch(`${SUPABASE_URL}/rest/v1/huawei_ont_claves`, {
    method: 'post',
    headers: {
      'apikey':        SUPABASE_KEY,
      'Authorization': `Bearer ${SUPABASE_KEY}`,
      'Content-Type':  'application/json',
      'Prefer':        'return=minimal,resolution=ignore-duplicates',
    },
    payload: JSON.stringify(registros),
    muteHttpExceptions: true,
  });

  const code = resp.getResponseCode();
  if (code !== 201) {
    console.error(`Supabase ${code}: ${resp.getContentText().substring(0, 200)}`);
    return false;
  }
  return true;
}

// ─── CONTAR REGISTROS EN SUPABASE ────────────────────────────────────────────
function _contarEnSupabase() {
  const resp = UrlFetchApp.fetch(
    `${SUPABASE_URL}/rest/v1/huawei_ont_claves?select=count`,
    {
      headers: {
        'apikey':        SUPABASE_KEY,
        'Authorization': `Bearer ${SUPABASE_KEY}`,
        'Prefer':        'count=exact',
        'Range':         '0-0',
      },
      muteHttpExceptions: true,
    }
  );
  // Content-Range: 0-0/232145
  const cr = resp.getAllHeaders()['Content-Range'] || '0-0/0';
  return parseInt(cr.split('/')[1]) || 0;
}

// ─── REGISTRAR LOG EN PROPERTIES (visible en Ejecuciones del proyecto) ────────
function _registrarLog(fecha, total, nuevos, estado) {
  const props = PropertiesService.getScriptProperties();
  props.setProperty('ultima_sync', JSON.stringify({
    fecha:  fecha.toISOString(),
    total:  total,
    nuevos: nuevos,
    estado: estado,
  }));
}

// ─── VER ÚLTIMA SINCRONIZACIÓN ────────────────────────────────────────────────
function verUltimaSync() {
  const raw = PropertiesService.getScriptProperties().getProperty('ultima_sync');
  if (!raw) { console.log('Sin sincronizaciones registradas'); return; }
  const log = JSON.parse(raw);
  console.log(`Última sync: ${new Date(log.fecha).toLocaleString()}`);
  console.log(`  Total CDE: ${log.total} — Nuevos: ${log.nuevos} — Estado: ${log.estado}`);
}

// ─── PROBAR UN SN ESPECÍFICO ──────────────────────────────────────────────────
function probarSN() {
  const SN_TEST = 'HWTC2D33FBB6'; // cambia por cualquier SN

  const hash = _sha256(SN_TEST.toUpperCase());
  console.log(`SN: ${SN_TEST}`);
  console.log(`Hash SHA-256: ${hash}`);

  const resp = UrlFetchApp.fetch(
    `${SUPABASE_URL}/rest/v1/huawei_ont_claves?sn_hash=eq.${hash}&select=password`,
    {
      headers: {
        'apikey':        SUPABASE_KEY,
        'Authorization': `Bearer ${SUPABASE_KEY}`,
      },
      muteHttpExceptions: true,
    }
  );

  const data = JSON.parse(resp.getContentText());
  if (data.length > 0) {
    console.log(`✓ Contraseña: ${data[0].password}`);
  } else {
    console.log('✗ SN no encontrado en la base local');
  }
}

// ─── SHA-256 ──────────────────────────────────────────────────────────────────
function _sha256(texto) {
  const bytes = Utilities.computeDigest(
    Utilities.DigestAlgorithm.SHA_256,
    texto,
    Utilities.Charset.UTF_8
  );
  return bytes.map(b => ('0' + (b & 0xff).toString(16)).slice(-2)).join('');
}

// ─── HELPERS ──────────────────────────────────────────────────────────────────
function _extraerCookies(headers) {
  const raw = headers['Set-Cookie'] || headers['set-cookie'] || '';
  if (!raw) return '';
  const lista = Array.isArray(raw) ? raw : [raw];
  return lista.map(c => c.split(';')[0].trim()).join('; ');
}
