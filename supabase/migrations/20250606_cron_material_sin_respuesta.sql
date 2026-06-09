-- Cron servidor: escalar solicitudes de material sin respuesta (10 min) al supervisor.
-- Requiere: pg_cron, pg_net y edge function escalar-material-sin-respuesta desplegada.

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'escalar-material-sin-respuesta') THEN
      PERFORM cron.unschedule('escalar-material-sin-respuesta');
    END IF;

    PERFORM cron.schedule(
      'escalar-material-sin-respuesta',
      '* * * * *',
      $job$
      SELECT net.http_post(
        url := 'https://efvicvqffvxocnrqjxrs.supabase.co/functions/v1/escalar-material-sin-respuesta',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVmdmljdnFmZnZ4b2NucnFqeHJzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU0Mzc4MjMsImV4cCI6MjA4MTAxMzgyM30._RIVNg4_FoMKDJWbdi8QuS6LSsjjaAapwkTa_9Gb0Cc'
        ),
        body := '{}'::jsonb
      );
      $job$
    );
  ELSE
    RAISE NOTICE 'pg_cron no habilitado — activar en Database → Extensions y re-ejecutar esta migración';
  END IF;
END;
$cron$;
