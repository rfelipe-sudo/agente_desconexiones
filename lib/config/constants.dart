// Constantes de configuración global del proyecto.
//
// Aviso: estas credenciales están hardcodeadas porque se usan para autenticar
// al backend Kepler desde la app. No exponen datos del usuario final, son
// del cliente de servicios (kep). Si rotan, actualizar acá.

// Backend Kepler
const String kKeplerBaseUrl = 'https://keplerv2.sbip.cl';
const String kKeplerUser = 'kep';
const String kKeplerPassword = 'lercito';

// Endpoint registro de token FCM
const String kKeplerRegisterTokenPath = '/api/v1/toa/devices/register-token';

// Endpoint reporte de transacción de material (POST al completar guía)
// TODO: actualizar la ruta cuando el endpoint esté disponible en Kepler
const String kKeplerTransaccionPath = '/api/v1/toa/material/transaccion';

// Endpoint intercambio entre técnicos (servidor logística, no keplerv2)
const String kKeplerIntercambioBaseUrl = 'https://logistica.sbip.cl';
const String kKeplerIntercambioPath    = '/intercambio/api/solicitar';
const String kKeplerApiToken           = '5de53e7b5f89b6b547c5c93d635f162ae2594756';

// Plataforma única por ahora
const String kFcmPlatform = 'android';

// Llaves de SharedPreferences
const String kPrefFcmTokenRegistrado = 'fcm_token_registrado';
const String kPrefAlertaBloqueoMisActividades = 'alerta_activa_mis_actividades';
