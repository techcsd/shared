-- La API embebe perfiles desde miembros solo si existe la FK (bug encontrado en pruebas en vivo).
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'miembros_usuario_perfil_fk' and contype = 'f') then
    raise exception 'falta la FK miembros -> perfiles';
  end if;
end $$;
