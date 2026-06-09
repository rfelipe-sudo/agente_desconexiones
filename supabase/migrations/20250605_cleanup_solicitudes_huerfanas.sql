-- Limpieza: destinatarios pendientes/aceptados cuya solicitud ya terminó.
-- También limpia PIN residual en solicitudes canceladas de los técnicos de prueba.

UPDATE public.solicitudes_material_destinatarios d
SET estado = 'cancelada'
FROM public.solicitudes_material s
WHERE s.id = d.solicitud_id
  AND d.estado IN ('pendiente', 'aceptada')
  AND s.estado IN ('cancelada', 'completada');

-- PIN residual en canceladas (evita confusión al reintentar flujo)
UPDATE public.solicitudes_material
SET
  pin_codigo    = NULL,
  pin_expira_en = NULL,
  pin_intentos  = 3
WHERE estado = 'cancelada'
  AND pin_codigo IS NOT NULL
  AND (
    rut_solicitante IN ('19878777-9', '16518822-5')
    OR rut_entregador IN ('19878777-9', '16518822-5')
  );

-- Cancelar cualquier solicitud activa atascada entre los dos técnicos de prueba
UPDATE public.solicitudes_material
SET
  estado        = 'cancelada',
  pin_codigo    = NULL,
  pin_expira_en = NULL,
  pin_intentos  = 3
WHERE estado IN ('pendiente', 'aceptada', 'firmada', 'en_camino', 'llegada')
  AND (
    (rut_solicitante = '19878777-9' AND rut_entregador = '16518822-5')
    OR (rut_solicitante = '16518822-5' AND rut_entregador = '19878777-9')
  );

UPDATE public.solicitudes_material_destinatarios d
SET estado = 'cancelada'
FROM public.solicitudes_material s
WHERE s.id = d.solicitud_id
  AND d.rut_tecnico IN ('19878777-9', '16518822-5')
  AND d.estado IN ('pendiente', 'aceptada')
  AND s.estado = 'cancelada';
