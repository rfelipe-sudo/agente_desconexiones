-- Ernesto Cordero (26293743-7) → equipo Luis García (equipo 2)
-- supervisor_tecnicos_crea y plantel ya estaban correctos; equipos_crea seguía en equipo 4 (Sergio).

UPDATE public.equipos_crea
SET equipo = 2,
    nombre = 'ERNESTO JOSE CORDERO CHIRINOS'
WHERE rut_tecnico = '26293743-7'
  AND rol = 'tecnico';

DELETE FROM public.supervisor_tecnicos_crea
WHERE rut_tecnico = '26293743-7';

INSERT INTO public.supervisor_tecnicos_crea (rut_tecnico, rut_supervisor)
VALUES ('26293743-7', '25626541-9');

UPDATE public.plantel_tecnicos
SET supervisor = 'LUIS GARCIA BENITEZ',
    cargo = 'TECNICO 5TO CICLO',
    dia_bodega = 'MIERCOLES',
    updated_at = now()
WHERE rut = '26293743-7';
