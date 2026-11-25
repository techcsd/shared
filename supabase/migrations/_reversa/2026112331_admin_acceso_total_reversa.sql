drop policy if exists admin_ver on propuestas_compra;
drop policy if exists admin_ver on propuesta_participantes;
drop policy if exists admin_ver on propuesta_aportes;
drop policy if exists admin_ver on propuesta_mensajes;
drop policy if exists admin_ver on propuesta_evidencias;
drop policy if exists admin_ver on directorio_solicitudes;
drop policy if exists admin_ver on directorio_reportes;

create or replace function es_miembro(g uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from miembros where grupo_id = g and usuario_id = auth.uid() and estado = 'activo')
$$;
create or replace function es_socio(g uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(rol_en(g) = 'socio', false)
$$;
create or replace function comparte_grupo(u uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from miembros a join miembros b on a.grupo_id = b.grupo_id
    where a.usuario_id = auth.uid() and a.estado = 'activo' and b.usuario_id = u and b.estado = 'activo')
$$;
-- aceptar_version y capitan_guardar: volver a las definiciones de las migraciones 10 y 23 (los parches solo añaden una guarda).
