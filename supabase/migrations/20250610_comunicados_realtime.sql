-- Habilitar Realtime en comunicados para que la app abierta reciba el INSERT al instante.

ALTER TABLE public.comunicados_creabox REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'comunicados_creabox'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.comunicados_creabox;
  END IF;
END $$;
