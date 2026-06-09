-- 5 bodegueros: correos de aprobacion y SAP OK.
-- Errores del flujo: solo marcelo + rfelipe.

UPDATE public.configuracion_app
SET valor = '["rfelipe@sbip.cl","marcelo.gonzalez@sbip.cl","sergio.silva@sbip.cl","bastian.caceres@sbip.cl","gabriel.uribe@sbip.cl"]'
WHERE clave = 'emails_bodega_traspaso';

INSERT INTO public.configuracion_app (clave, valor)
VALUES (
  'emails_bodega_traspaso',
  '["rfelipe@sbip.cl","marcelo.gonzalez@sbip.cl","sergio.silva@sbip.cl","bastian.caceres@sbip.cl","gabriel.uribe@sbip.cl"]'
)
ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor;

INSERT INTO public.configuracion_app (clave, valor)
VALUES (
  'emails_errores_traspaso',
  '["marcelo.gonzalez@sbip.cl","rfelipe@sbip.cl"]'
)
ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor;
