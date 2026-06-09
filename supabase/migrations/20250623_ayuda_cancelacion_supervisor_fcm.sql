-- CREABOX: notificar al supervisor cuando el técnico cancela una solicitud de ayuda.

CREATE OR REPLACE FUNCTION public.fn_notificar_supervisor_ayuda_cancelacion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.tipo IS NOT DISTINCT FROM 'movimiento_material' THEN
    RETURN NEW;
  END IF;
  IF OLD.estado IS NOT DISTINCT FROM 'cancelada' THEN
    RETURN NEW;
  END IF;
  IF NEW.estado IS DISTINCT FROM 'cancelada' THEN
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
      'evento', 'cancelacion'
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ayuda_notificar_supervisor_cancelacion ON public.ayuda_terreno_crea;

CREATE TRIGGER trg_ayuda_notificar_supervisor_cancelacion
  AFTER UPDATE OF estado ON public.ayuda_terreno_crea
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_notificar_supervisor_ayuda_cancelacion();
