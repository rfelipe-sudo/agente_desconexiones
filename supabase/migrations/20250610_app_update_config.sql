-- Configuración OTA CREABOX + lectura anónima de claves creabox_*

INSERT INTO configuracion_app (clave, valor, descripcion) VALUES
  (
    'creabox_version',
    '1.5.3',
    'Versión semántica del APK publicado (debe coincidir con pubspec.yaml)'
  ),
  (
    'creabox_build',
    '8',
    'Número de build del APK publicado (pubspec.yaml después del +)'
  ),
  (
    'creabox_apk_url',
    '',
    'URL directa de descarga del APK. Si está vacía, la app usa GitHub Releases.'
  ),
  (
    'creabox_actualizacion_forzada',
    'true',
    'true = bloquea uso hasta instalar; false = solo sugiere actualización'
  ),
  (
    'creabox_notas_actualizacion',
    '',
    'Notas opcionales mostradas en logs / futuro diálogo de release'
  )
ON CONFLICT (clave) DO NOTHING;

-- La app consulta esto al abrir con rol anon (antes del login Supabase Auth).
DROP POLICY IF EXISTS "Anon puede leer config creabox" ON configuracion_app;
CREATE POLICY "Anon puede leer config creabox"
  ON configuracion_app FOR SELECT
  USING (clave LIKE 'creabox_%');
