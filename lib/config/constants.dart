import 'package:agente_desconexiones/services/app_version_service.dart';

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

/// Versión reportada al panel (incluye build para distinguir OTA).
String get kAppVersion => AppVersionService.versionWithBuild;

/// Texto distintivo del build — derivado del APK instalado.
String get kBuildDistintivo => AppVersionService.buildDistintivo;

/// Repositorio GitHub para releases OTA (fallback si Supabase no tiene config).
const String kGitHubRepoOwner = 'rfelipe-sudo';
const String kGitHubRepoName = 'agente_desconexiones';

// Solicitud de material — radio geográfico de destinatarios.
// `false` desactiva el filtro de distancia (útil en pruebas).
const bool kMaterialFiltroDistanciaActivo = true;
const double kMaterialRadioKm = 5.0;
/// GPS vigente si [ubicaciones_activas.updated_at] es más reciente que esto.
/// El foreground service publica cada 5 min → 10 min tolera dos ciclos + demora de red.
const int kMaterialGpsMaxAntiguedadMinutos = 10;

// Llaves de SharedPreferences
const String kPrefFcmTokenRegistrado = 'fcm_token_registrado';
const String kPrefAlertaBloqueoMisActividades = 'alerta_activa_mis_actividades';
const String kPrefAlertaBloqueoTitulo = 'alerta_bloqueo_titulo';
const String kPrefAlertaBloqueoDescripcion = 'alerta_bloqueo_descripcion';
