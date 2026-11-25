-- Simula lo mínimo de Supabase (roles, esquema auth, privilegios por defecto) para correr
-- migraciones y tests sin Docker. En Supabase real esto ya existe.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text unique,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  last_sign_in_at timestamptz,
  banned_until timestamptz
);

create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid
$$;
create function auth.role() returns text language sql stable as $$
  select coalesce(auth.jwt() ->> 'role', 'anon')
$$;

grant usage on schema public, auth to anon, authenticated, service_role;
grant execute on all functions in schema auth to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;

-- Ayudantes de test
create schema tests;
grant usage on schema tests to anon, authenticated, service_role;

create function tests.crear_usuario(p_correo text, p_nombre text default null) returns uuid
language plpgsql as $$
declare v_id uuid;
begin
  insert into auth.users (email, raw_user_meta_data)
  values (p_correo, jsonb_build_object('nombre', coalesce(p_nombre, split_part(p_correo, '@', 1))))
  returning id into v_id;
  return v_id;
end $$;

create function tests.correo_de(p_usuario uuid) returns text language sql security definer as $$
  select email from auth.users where id = p_usuario
$$;

create function tests.como(p_usuario uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', p_usuario, 'role', 'authenticated',
      'email', tests.correo_de(p_usuario))::text, false);
  perform set_config('role', 'authenticated', false);
end $$;

create function tests.como_anonimo() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', false);
  perform set_config('role', 'anon', false);
end $$;

create function tests.admin() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', false);
  perform set_config('request.jwt.claims', '', false);
end $$;

-- Verifica que p_sql lance un error (opcionalmente que el mensaje contenga p_fragmento).
create function tests.falla(p_sql text, p_fragmento text default null) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if p_fragmento is not null and position(p_fragmento in sqlerrm) = 0 then
      raise exception 'Falló con otro mensaje. Esperado "%", obtenido "%"', p_fragmento, sqlerrm;
    end if;
    return;
  end;
  raise exception 'Se esperaba un error y no ocurrió: %', p_sql;
end $$;

create function tests.igual(p_real anyelement, p_esperado anyelement, p_msg text) returns void
language plpgsql as $$
begin
  if p_real is distinct from p_esperado then
    raise exception 'FALLO %: esperado %, obtenido %', p_msg, p_esperado, p_real;
  end if;
end $$;
