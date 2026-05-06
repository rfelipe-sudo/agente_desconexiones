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

// Plataforma única por ahora
const String kFcmPlatform = 'android';

// Llaves de SharedPreferences
const String kPrefFcmTokenRegistrado = 'fcm_token_registrado';
const String kPrefAlertaBloqueoMisActividades = 'alerta_activa_mis_actividades';
