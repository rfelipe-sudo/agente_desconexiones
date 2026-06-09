-- Tramos GPS supervisores + solicitud combustible directa a jefe de operaciones

ALTER TABLE sol_comb_adicional
  ADD COLUMN IF NOT EXISTS tipo_solicitante text NOT NULL DEFAULT 'tecnico';

COMMENT ON COLUMN sol_comb_adicional.tipo_solicitante IS
  'tecnico | supervisor — flujo de aprobación según rol';

-- tipo_leg opcional en tramos (supervisor_actividad, supervisor_ayuda, material_ida, …)
ALTER TABLE combustible_tramos
  ADD COLUMN IF NOT EXISTS tipo_leg text;

-- Ampliar CHECK de estado si existe (pendiente_jefe_ops = supervisor → jefe ops)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'sol_comb_adicional_estado_check'
      AND conrelid = 'public.sol_comb_adicional'::regclass
  ) THEN
    ALTER TABLE public.sol_comb_adicional
      DROP CONSTRAINT sol_comb_adicional_estado_check;
    ALTER TABLE public.sol_comb_adicional
      ADD CONSTRAINT sol_comb_adicional_estado_check CHECK (
        estado IN (
          'pendiente_supervisor',
          'aprobado_supervisor',
          'pendiente_jefe_ops',
          'pendiente_flota',
          'completada',
          'rechazado_supervisor',
          'rechazado_jefe_ops'
        )
      );
  END IF;
END $$;
