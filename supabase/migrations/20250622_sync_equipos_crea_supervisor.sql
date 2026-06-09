-- Sincroniza equipos_crea.equipo con supervisor_tecnicos_crea (fuente de verdad del dashboard Equipos).
-- Corrige técnicos cuyo número de equipo no coincide con el supervisor asignado.

UPDATE public.equipos_crea ec
SET equipo = sup_ec.equipo
FROM public.supervisor_tecnicos_crea st
JOIN public.equipos_crea sup_ec
  ON sup_ec.rut_tecnico = st.rut_supervisor
 AND sup_ec.rol = 'supervisor'
WHERE ec.rut_tecnico = st.rut_tecnico
  AND ec.rol = 'tecnico'
  AND ec.equipo IS DISTINCT FROM sup_ec.equipo;

-- Alinear plantel_tecnicos.supervisor con supervisores_crea
UPDATE public.plantel_tecnicos pt
SET supervisor = sc.nombre,
    updated_at = now()
FROM public.supervisor_tecnicos_crea st
JOIN public.supervisores_crea sc ON sc.rut = st.rut_supervisor
WHERE pt.rut = st.rut_tecnico
  AND pt.supervisor IS DISTINCT FROM sc.nombre;
