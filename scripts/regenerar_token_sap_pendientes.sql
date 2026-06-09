-- Regenera token SAP para traspasos aprobados sin confirmar (enlaces viejos rotos).
UPDATE public.traspasos_bodega
SET sap_confirm_token = gen_random_uuid()
WHERE estado = 'aprobado'
  AND sap_ok = false
  AND (sap_confirm_token IS NULL OR sap_confirm_token::text = '');
