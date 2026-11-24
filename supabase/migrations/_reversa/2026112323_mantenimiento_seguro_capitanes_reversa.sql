-- Reversa de 23 (borra mantenimiento, seguro y capitanes). El gancho de licencias vuelve a ser permisivo.
create or replace function capitan_licencia_ok(p_grupo uuid, p_miembro uuid, p_nombre text, p_fecha date) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$ select true $$;
create or replace function cron_mantenimiento() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rec int; v_lim int; v_exp int; v_fon int;
begin
  v_rec := recordatorios_acuse(); v_lim := limpiar_borradores(); v_exp := prioridad_911_expirar(); v_fon := fondo_aportes_automaticos();
  return jsonb_build_object('recordatorios', v_rec, 'borradores_limpiados', v_lim, 'solicitudes_911_expiradas', v_exp, 'aportes_fondo', v_fon);
end $$;
drop function if exists mantenimiento_evaluar(), servicio_registrar(uuid, uuid, uuid, uuid, uuid, date, numeric, text, text, numeric, text, text, date, text, uuid),
  tarea_programar(uuid, timestamptz, timestamptz, text), tarea_crear(uuid, uuid, text, uuid, date, numeric, text, text),
  plan_guardar(uuid, uuid, uuid, uuid, text, text, int, numeric, int, numeric, boolean), plan_estado(uuid), lectura_actual(uuid),
  siniestro_estado(uuid, text), siniestro_abrir(uuid, uuid, text, uuid), activo_poliza_vigente(uuid),
  poliza_guardar(uuid, uuid, uuid, text, text, text, date, date, numeric, text),
  capitan_guardar(uuid, uuid, text, uuid, text, date, numeric, text, text), avisar_equipo(uuid, text, text, text, jsonb, boolean), alerta_una_vez(text);
drop table if exists servicios, mantenimiento_tareas, mantenimiento_planes, siniestros, polizas_seguro, capitanes, alertas_emitidas cascade;
