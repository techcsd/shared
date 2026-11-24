-- Reversa de 26 (borra propuestas, directorio y configuración de plataforma).
create or replace function cron_mantenimiento() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rec int; v_lim int; v_exp int; v_fon int; v_man int;
begin
  v_rec := recordatorios_acuse(); v_lim := limpiar_borradores(); v_exp := prioridad_911_expirar(); v_fon := fondo_aportes_automaticos(); v_man := mantenimiento_evaluar();
  return jsonb_build_object('recordatorios', v_rec, 'borradores_limpiados', v_lim, 'solicitudes_911_expiradas', v_exp, 'aportes_fondo', v_fon, 'alertas_mantenimiento', v_man);
end $$;
drop function if exists grupo_pasar_a_real(uuid), grupo_checklist_lanzamiento(uuid), salud_sistema(), directorio_ocultar(uuid, boolean),
  directorio_reportar(uuid, text), directorio_responder(uuid, boolean), directorio_solicitar(uuid, text), directorio_listar(),
  propuesta_directorio_visible(uuid, boolean), propuestas_expirar(), propuesta_mensaje(uuid, text), propuesta_reembolsar(uuid, text),
  propuesta_cancelar(uuid, text), propuesta_convertir(uuid, text, text, text), propuesta_acusar_adquisicion(uuid),
  propuesta_registrar_adquisicion(uuid, text), propuesta_evidencia_registrar(uuid, text, text), propuesta_aporte_acusar(uuid),
  propuesta_aporte_confirmar(uuid, boolean), propuesta_aporte_declarar(uuid, numeric, text), propuesta_salir(uuid),
  propuesta_comprometer(uuid, numeric), propuesta_unirse(text), propuesta_vista_previa(text), propuesta_abrir(uuid),
  propuesta_crear(text, uuid, text, numeric, text, date, int), propuesta_totales(uuid);
drop table if exists directorio_reportes, directorio_solicitudes, propuesta_evidencias, propuesta_mensajes, propuesta_aportes,
  propuesta_participantes, propuestas_compra, plataforma_admins, plataforma_config cascade;
drop function if exists es_participante(uuid), es_organizador(uuid), es_admin_plataforma(), directorio_habilitado();
