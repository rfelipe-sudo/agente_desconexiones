-- ═══════════════════════════════════════════════════════════════════════════
-- CREABOX: notificaciones bodeguero 100% automáticas (servidor)
--
-- Ejecutar UNA VEZ en Supabase → SQL Editor → Run
-- No requiere que cada bodeguero haga nada manual.
--
-- Requisitos previos:
--   1. Edge functions desplegadas: fcm-send, notificar-bodega-traspaso,
--      notificar-bodegueros-guia
--   2. Secretos FCM configurados en Edge Functions
-- ═══════════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ── Traspaso nuevo → push a todos los bodegueros ─────────────────────────
CREATE OR REPLACE FUNCTION public.fn_notificar_bodega_traspaso()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.estado IS DISTINCT FROM 'pendiente' THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := 'https://efvicvqffvxocnrqjxrs.supabase.co/functions/v1/notificar-bodega-traspaso',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVmdmljdnFmZnZ4b2NucnFqeHJzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU0Mzc4MjMsImV4cCI6MjA4MTAxMzgyM30._RIVNg4_FoMKDJWbdi8QuS6LSsjjaAapwkTa_9Gb0Cc'
    ),
    body := jsonb_build_object('traspaso_id', NEW.id::text)
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_traspaso_notificar_bodega ON public.traspasos_bodega;

CREATE TRIGGER trg_traspaso_notificar_bodega
  AFTER INSERT ON public.traspasos_bodega
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_notificar_bodega_traspaso();

-- ── Guía firmada → push a bodegueros ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_notificar_bodega_guia()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.estado IS DISTINCT FROM 'firmada' THEN
    RETURN NEW;
  END IF;
  IF OLD.estado IS NOT DISTINCT FROM NEW.estado THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := 'https://efvicvqffvxocnrqjxrs.supabase.co/functions/v1/notificar-bodegueros-guia',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVmdmljdnFmZnZ4b2NucnFqeHJzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU0Mzc4MjMsImV4cCI6MjA4MTAxMzgyM30._RIVNg4_FoMKDJWbdi8QuS6LSsjjaAapwkTa_9Gb0Cc'
    ),
    body := jsonb_build_object('guia_id', NEW.id::text)
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guia_notificar_bodega ON public.solicitudes_bodega;

CREATE TRIGGER trg_guia_notificar_bodega
  AFTER UPDATE OF estado ON public.solicitudes_bodega
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_notificar_bodega_guia();
