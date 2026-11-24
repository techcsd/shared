-- Reversa de 18: elimina operación (¡borra check-ins, lecturas, checklists, incidencias y evidencias!). Solo para pruebas.
drop function if exists lectura_corregir(uuid, uuid, text, numeric, text);
drop function if exists checkin_registrar(uuid, uuid, text, uuid, numeric, jsonb, jsonb, text);
drop function if exists evidencia_registrar(uuid, text, uuid, text, text, text);
drop function if exists lectura_guardar(uuid, uuid, text, numeric, uuid, text);
drop function if exists checklist_guardar(uuid, text, jsonb, jsonb, uuid, text);
drop function if exists operacion_puede(reservas);
drop function if exists checklist_items(uuid, text);
drop function if exists capitan_licencia_ok(uuid, uuid, text, date);
drop function if exists es_miembro_id(uuid);
drop view if exists lecturas_vigentes, checklist_vigente;
drop table if exists evidencias, incidencias, combustible_registros, checklist_respuestas, lecturas, operaciones cascade;
drop function if exists checklist_validar();
drop function if exists lecturas_validar();
drop function if exists solo_adicion() cascade;
do $$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists evidencias_leer on storage.objects;
    drop policy if exists evidencias_subir on storage.objects;
  end if;
end $$;
