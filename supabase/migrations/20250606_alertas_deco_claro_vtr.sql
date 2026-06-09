-- Separación de stock decodificador Claro / VTR en alertas de auditoría.
ALTER TABLE alertas_auditoria_material
  ADD COLUMN IF NOT EXISTS stock_deco_claro numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS stock_deco_vtr   numeric DEFAULT 0;
