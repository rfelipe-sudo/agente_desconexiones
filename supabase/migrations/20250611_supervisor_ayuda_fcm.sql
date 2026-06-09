-- ═══════════════════════════════════════════════════════════════════════════
-- CREABOX: notificaciones supervisor ayuda en terreno (servidor)
--
-- Requisitos previos:
--   1. Edge functions desplegadas: fcm-send, notificar-supervisor-ayuda
--   2. Secretos FCM configurados en Edge Functions
-- ═══════════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ── Nueva solicitud de ayuda → push al supervisor asignado ─────────────────
CREATE OR REPLACE FUNCTION public.fn_notificar_supervisor_ayuda_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.tipo IS NOT DISTINCT FROM 'movimiento_material' THEN
    RETURN NEW;
  END IF;
  IF NEW.estado IS DISTINCT FROM 'pendiente' THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := 'https://efvicvqffvxocnrqjxrs.supabase.co/functions/v1/notificar-supervisor-ayuda',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVmdmljdnFmZnZ4b2NucnFqeHJzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU0Mzc4MjMsImV4cCI6MjA4MTAxMzgyM30._RIVNg4_FoMKDJWbdi8QuS6LSsjjaAapwkTa_9Gb0Cc'
    ),
    body := jsonb_build_object('ticket_id', NEW.ticket_id::text)
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ayuda_notificar_supervisor_insert ON public.ayuda_terreno_crea;

CREATE TRIGGER trg_ayuda_notificar_supervisor_insert
  AFTER INSERT ON public.ayuda_terreno_crea
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_notificar_supervisor_ayuda_insert();

-- ── Traspaso de solicitud a otro supervisor → push al nuevo supervisor ─────
CREATE OR REPLACE FUNCTION public.fn_notificar_supervisor_ayuda_traspaso()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.tipo IS NOT DISTINCT FROM 'movimiento_material' THEN
    RETURN NEW;
  END IF;
  IF NEW.estado IS DISTINCT FROM 'pendiente' THEN
    RETURN NEW;
  END IF;
  IF OLD.rut_supervisor IS NOT DISTINCT FROM NEW.rut_supervisor THEN
    RETURN NEW;
  END IF;
  IF NEW.rut_supervisor IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := 'https://efvicvqffvxocnrqjxrs.supabase.co/functions/v1/notificar-supervisor-ayuda',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVmdmljdnFmZnZ4b2NucnFqeHJzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU0Mzc4MjMsImV4cCI6MjA4MTAxMzgyM30._RIVNg4_FoMKDJWbdi8QuS6LSsjjaAapwkTa_9Gb0Cc'
    ),
    body := jsonb_build_object(
      'ticket_id', NEW.ticket_id::text,
      'es_traspaso', true
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ayuda_notificar_supervisor_traspaso ON public.ayuda_terreno_crea;

CREATE TRIGGER trg_ayuda_notificar_supervisor_traspaso
  AFTER UPDATE OF rut_supervisor ON public.ayuda_terreno_crea
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_notificar_supervisor_ayuda_traspaso();
