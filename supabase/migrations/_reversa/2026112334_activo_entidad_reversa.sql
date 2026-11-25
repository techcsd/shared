-- Reversa de 34. BORRA datos: fotos, documentos, equipo, ficha, valor, mejoras, contactos y campos propios del activo.
-- Los archivos de Storage no se borran aquí (vaciar los buckets «activo-documentos» y las fotos extra de «activos» desde el panel).
do $p$
declare d text; n text;
begin
  d := pg_get_functiondef('public.cron_mantenimiento()'::regprocedure);
  n := replace(d, 'v_man := mantenimiento_evaluar() + activo_documentos_evaluar();', 'v_man := mantenimiento_evaluar();');
  execute n;
end $p$;
drop function if exists activo_documentos_evaluar();
do $$
begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists activo_docs_ver on storage.objects';
    execute 'drop policy if exists activo_docs_subir on storage.objects';
    execute 'drop policy if exists activo_docs_reemplazar on storage.objects';
    execute 'drop policy if exists activo_docs_borrar on storage.objects';
    execute 'drop policy if exists activos_subir on storage.objects';
    execute 'drop policy if exists activos_reemplazar on storage.objects';
    execute 'drop policy if exists activos_borrar on storage.objects';
    execute $p$create policy activos_subir on storage.objects for insert to authenticated with check (
      bucket_id = 'activos' and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
        then es_socio(((storage.foldername(name))[1])::uuid) else false end)$p$;
    execute $p$create policy activos_reemplazar on storage.objects for update to authenticated
      using (bucket_id = 'activos' and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
        then es_socio(((storage.foldername(name))[1])::uuid) else false end)
      with check (bucket_id = 'activos' and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
        then es_socio(((storage.foldername(name))[1])::uuid) else false end)$p$;
    execute $p$create policy activos_borrar on storage.objects for delete to authenticated using (
      bucket_id = 'activos' and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
        then es_socio(((storage.foldername(name))[1])::uuid) else false end)$p$;
  end if;
end $$;
-- La vitrina vuelve a la versión de la migración 33 (sin 'condicion'): reaplicar esa definición si se necesita.
drop function if exists activo_historial(uuid, int);
drop function if exists activo_detalle(uuid);
drop function if exists activo_reordenar(text, uuid[]);
drop function if exists activo_foto_portada(uuid);
drop function if exists activo_permiso_editar(uuid, uuid, boolean);
drop table if exists activo_campos, activo_contactos, activo_mejoras, activo_valor, activo_ficha,
  activo_equipo, activo_documentos, activo_fotos cascade;
drop function if exists activo_campos_validar();
drop function if exists activo_ficha_condicion();
drop function if exists activo_limites();
drop function if exists activo_fotos_portada_sync();
drop policy if exists activos_update on activos;
create policy activos_update on activos for update to authenticated
  using (es_socio(grupo_id)) with check (es_socio(grupo_id));
alter table activos drop constraint if exists activos_id_grupo_unico;
drop trigger if exists miembros_permiso_inicial on miembros;
drop function if exists miembros_permiso_inicial();
drop function if exists puede_editar_activo(uuid);
drop function if exists es_admin_grupo(uuid);
alter table miembros drop column if exists puede_editar_activo;
