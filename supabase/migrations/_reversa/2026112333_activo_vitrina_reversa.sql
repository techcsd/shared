-- Reversa de 33. Borra descripción y foto (datos). El bucket «activos» no se elimina aquí: hay que vaciarlo desde Storage.
drop function if exists activo_vista_por_invitacion(uuid);
drop function if exists activo_vista_por_token(text);
drop function if exists activo_resumen_publico(uuid);
drop function if exists activo_vitrina(uuid);
do $$
begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists activos_ver on storage.objects';
    execute 'drop policy if exists activos_subir on storage.objects';
    execute 'drop policy if exists activos_reemplazar on storage.objects';
    execute 'drop policy if exists activos_borrar on storage.objects';
  end if;
end $$;
alter table activos drop constraint if exists activos_imagen_del_grupo;
alter table activos drop column if exists imagen_path, drop column if exists descripcion;
