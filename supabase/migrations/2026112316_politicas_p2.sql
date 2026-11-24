-- 2026-11-23 · 16 · Políticas nuevas de la fase P2 (seed GENERADO; upsert)
-- BEGIN:CATALOGO
insert into politicas_catalogo (clave, categoria, tipo, valor_defecto, minimo, maximo, opciones, nullable, df, descripcion, orden) values
  ('prioridad_911.expira_horas', 'reservas', 'entero', '72'::jsonb, 1, 720, null, false, 'DF-42', 'Si el titular no responde en este plazo, la solicitud expira. La reserva del titular no cambia.', 33)
on conflict (clave) do update set valor_defecto = excluded.valor_defecto, minimo = excluded.minimo, maximo = excluded.maximo, opciones = excluded.opciones, descripcion = excluded.descripcion;
-- END:CATALOGO
