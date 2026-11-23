-- 2026-11-23 · 01 · Extensiones y tipos enumerados (aditiva)
create extension if not exists btree_gist;
create extension if not exists citext;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pgcrypto') then
    create extension if not exists pgcrypto;
  end if;
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      create extension if not exists pg_cron;
    exception when others then
      raise notice 'pg_cron no se pudo activar: %', sqlerrm;
    end;
  end if;
end $$;

create type rol_miembro as enum ('socio', 'admin_operativo', 'capitan', 'mediador');
create type estado_miembro as enum ('invitado', 'activo', 'inactivo', 'salido');
create type estado_grupo as enum ('formacion', 'activo', 'archivado');
create type estado_invitacion as enum ('pendiente', 'aceptada', 'cancelada', 'expirada');
create type estado_version as enum ('pendiente', 'vigente', 'reemplazada', 'rechazada');
create type estado_activo as enum ('borrador', 'activo', 'inactivo');

-- Por defecto nada es accesible para anon/authenticated: cada migración concede lo estricto.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
