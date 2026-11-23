-- 2026-11-23 · 03 · Identidad: perfiles, grupos, miembros, invitaciones

create function set_actualizado_en() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  new.actualizado_en := now();
  return new;
end $$;

-- ---------------------------------------------------------------- perfiles
create table perfiles (
  id uuid primary key references auth.users (id) on delete cascade,
  nombre text not null default '' check (length(nombre) <= 120),
  correo citext,
  telefono text check (telefono is null or length(telefono) <= 40),
  idioma text not null default 'es' check (idioma in ('es', 'en')),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
create trigger perfiles_actualizado before update on perfiles
  for each row execute function set_actualizado_en();
create trigger perfiles_auditar after insert or update or delete on perfiles
  for each row execute function auditar();

-- Alta automática del perfil al crearse el usuario en Auth.
create function crear_perfil_para_usuario() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into perfiles (id, correo, nombre)
  values (new.id, new.email,
          coalesce(nullif(new.raw_user_meta_data ->> 'nombre', ''), split_part(coalesce(new.email, ''), '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger auth_usuario_crea_perfil after insert on auth.users
  for each row execute function crear_perfil_para_usuario();

-- ---------------------------------------------------------------- grupos
create table grupos (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (length(trim(nombre)) between 2 and 80),
  moneda char(3) not null default 'DOP' check (moneda ~ '^[A-Z]{3}$'),
  zona_horaria text not null default 'America/Santo_Domingo',
  prefijo text not null default 'ORD' check (prefijo ~ '^[A-Z]{2,5}$'),
  estado estado_grupo not null default 'formacion',
  modo_demo boolean not null default false,
  creado_por uuid references auth.users (id) on delete set null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
create trigger grupos_actualizado before update on grupos
  for each row execute function set_actualizado_en();
create trigger grupos_auditar after insert or update or delete on grupos
  for each row execute function auditar();

-- ---------------------------------------------------------------- miembros
create table miembros (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  usuario_id uuid not null references auth.users (id) on delete cascade,
  rol rol_miembro not null default 'socio',
  porcentaje numeric(5, 2) not null default 0 check (porcentaje between 0 and 100),
  estado estado_miembro not null default 'activo',
  desde timestamptz not null default now(),
  hasta timestamptz,
  unique (grupo_id, usuario_id),
  -- SC1: solo un socio tiene porcentaje de propiedad.
  check (rol = 'socio' or porcentaje = 0)
);
create index miembros_usuario_idx on miembros (usuario_id) where estado = 'activo';
create index miembros_grupo_idx on miembros (grupo_id);
create trigger miembros_auditar after insert or update or delete on miembros
  for each row execute function auditar();

-- Σ porcentaje de socios activos: = 100 si el grupo está activo, ≤ 100 siempre. Validado al cierre
-- de la transacción (diferido) para permitir cambios coordinados en un mismo RPC.
create function validar_porcentajes() returns trigger
language plpgsql set search_path = public, pg_temp as $$
declare
  v_grupo uuid;
  v_estado estado_grupo;
  v_suma numeric;
begin
  if tg_table_name = 'grupos' then
    v_grupo := coalesce(new.id, old.id);
  else
    v_grupo := coalesce(new.grupo_id, old.grupo_id);
  end if;
  select estado into v_estado from grupos where id = v_grupo;
  if not found then
    return null; -- el grupo ya no existe (borrado en cascada)
  end if;
  select coalesce(sum(porcentaje), 0) into v_suma
    from miembros where grupo_id = v_grupo and rol = 'socio' and estado = 'activo';
  if v_suma > 100 then
    raise exception 'porcentajes_invalidos: la suma de socios (%) supera 100', v_suma
      using errcode = 'check_violation';
  end if;
  if v_estado = 'activo' and v_suma <> 100 then
    raise exception 'porcentajes_invalidos: un grupo activo exige suma 100 (actual %)', v_suma
      using errcode = 'check_violation';
  end if;
  return null;
end $$;
create constraint trigger miembros_validar_porcentajes after insert or update or delete on miembros
  deferrable initially deferred for each row execute function validar_porcentajes();
create constraint trigger grupos_validar_porcentajes after insert or update of estado on grupos
  deferrable initially deferred for each row execute function validar_porcentajes();

-- ---------------------------------------------------------------- invitaciones
create table invitaciones_miembro (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  correo citext not null check (correo ~ '^[^@\s]+@[^@\s]+$'),
  rol rol_miembro not null default 'socio',
  porcentaje numeric(5, 2) not null default 0 check (porcentaje between 0 and 100),
  token_hash text not null unique,
  estado estado_invitacion not null default 'pendiente',
  expira_en timestamptz not null default now() + interval '7 days',
  invitado_por uuid references auth.users (id) on delete set null,
  aceptada_por uuid references auth.users (id) on delete set null,
  aceptada_en timestamptz,
  creado_en timestamptz not null default now(),
  check (rol = 'socio' or porcentaje = 0)
);
create unique index invitaciones_pendiente_unica on invitaciones_miembro (grupo_id, correo)
  where estado = 'pendiente';
create trigger invitaciones_auditar after insert or update or delete on invitaciones_miembro
  for each row execute function auditar();
