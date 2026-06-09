-- Prueba flujo correo SAP (ejecutar una vez en Supabase).
UPDATE public.configuracion_app
SET valor = 'sergio.silva@sbip.cl'
WHERE clave = 'email_jefe_bodega';

INSERT INTO public.configuracion_app (clave, valor)
VALUES ('email_jefe_bodega', 'sergio.silva@sbip.cl')
ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor;

INSERT INTO public.traspasos_bodega (
  rut_tecnico_b, nombre_tecnico_b,
  rut_tecnico_a, nombre_tecnico_a,
  tipo_material, cantidad, series, id_material, estado
) VALUES (
  '26293743-7', 'ERNESTO JOSE CORDERO CHIRINOS',
  '15848521-4', 'FRANCISCO JAVIER MORALES PEREZ',
  '[PRUEBA] Extensor SAP', 1, '{}', 981, 'pendiente'
)
RETURNING id;
