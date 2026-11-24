-- 2026-11-24 · 25 · El reinicio demo también limpia servicios y siniestros (referencian gastos y casos de daño)
create or replace function demo_reiniciar_operacion(p_grupo uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not es_socio(p_grupo) then
    raise exception 'solo_socios' using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from grupos where id = p_grupo and modo_demo) then
    raise exception 'solo_demo: este grupo no es de demostración; nada se borra' using errcode = 'insufficient_privilege';
  end if;
  perform set_config('app.permitir_borrado', 'on', true);
  perform set_config('app.motivo', 'reinicio de datos demo', true);
  delete from libro_mayor where grupo_id = p_grupo;
  delete from fondo_aportes where grupo_id = p_grupo;
  delete from liquidaciones where grupo_id = p_grupo;
  delete from pagos where grupo_id = p_grupo;
  delete from siniestros where grupo_id = p_grupo;
  delete from servicios where grupo_id = p_grupo;
  delete from gastos where grupo_id = p_grupo;
  delete from danos_casos where grupo_id = p_grupo;
  delete from evidencias where grupo_id = p_grupo;
  delete from incidencias where grupo_id = p_grupo;
  delete from operaciones where grupo_id = p_grupo;
  delete from reservas where grupo_id = p_grupo and estado = 'en_curso';
end $$;
