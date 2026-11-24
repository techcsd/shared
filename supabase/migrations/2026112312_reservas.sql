-- 2026-11-23 · 12 · Reservas sin choques, órdenes, acuses, costos, invitados y temporada alta (P2·F1, F4, F6, F7)

create type estado_reserva as enum ('borrador', 'confirmada', 'en_curso', 'finalizada', 'cancelada', 'bloqueada_mantenimiento');
create type uso_reserva as enum ('personal', 'familiar', 'negocios', 'invitado');

-- ---------------------------------------------------------------- helpers internos
create function politica_interna(p_grupo uuid, p_clave text) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v jsonb; d jsonb;
begin
  select valor into v from grupo_politicas where grupo_id = p_grupo and clave = p_clave;
  if found then return v; end if;
  select valor_defecto into d from politicas_catalogo where clave = p_clave;
  if not found then
    raise exception 'politica_desconocida: %', p_clave using errcode = 'invalid_parameter_value';
  end if;
  return d;
end $$;

-- Política como texto (null si es null JSON).
create function pol_txt(p_grupo uuid, p_clave text) returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select politica_interna(p_grupo, p_clave) #>> '{}'
$$;

create function miembro_actual(p_grupo uuid) returns uuid
language sql stable security definer set search_path = public, pg_temp as $$
  select id from miembros where grupo_id = p_grupo and usuario_id = auth.uid() and estado = 'activo'
$$;

revoke execute on function politica_interna(uuid, text), pol_txt(uuid, text), miembro_actual(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------- tablas
create table invitados (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  nombre text not null check (length(trim(nombre)) between 2 and 120),
  correo citext not null check (correo ~ '^[^@\s]+@[^@\s]+$'),
  anfitrion_id uuid not null references miembros (id),
  creado_en timestamptz not null default now()
);
create trigger invitados_auditar after insert or update or delete on invitados
  for each row execute function auditar();

create table reservas (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  activo_id uuid not null references activos (id) on delete restrict,
  rango tstzrange not null check (
    not isempty(rango) and lower_inc(rango) and not upper_inc(rango)
    and lower(rango) is not null and upper(rango) is not null),
  -- rango + margen de preparación (DF-18): la exclusión usa este, así «preparación» también bloquea.
  rango_bloqueo tstzrange not null,
  estado estado_reserva not null default 'borrador',
  tipo_bloqueo text check (tipo_bloqueo in ('mantenimiento', 'preparacion')),
  motivo_bloqueo text check (motivo_bloqueo is null or length(motivo_bloqueo) <= 300),
  uso uso_reserva,
  destino_id uuid references destinos (id),
  personas int check (personas between 1 and 1000),
  reservado_por uuid references miembros (id),
  responsable_miembro uuid references miembros (id),
  responsable_invitado uuid references invitados (id),
  notas text check (notas is null or length(notas) <= 1000),
  borrador_expira_en timestamptz,
  cancelada_en timestamptz,
  cancelada_por uuid references miembros (id),
  motivo_cancelacion text check (motivo_cancelacion is null or length(motivo_cancelacion) <= 300),
  cancelacion_tardia boolean not null default false,
  cargo_cancelacion numeric(14, 2) check (cargo_cancelacion is null or cargo_cancelacion >= 0),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  -- una reserva normal exige uso, quien reserva, personas y responsable; un bloqueo, su tipo
  constraint reservas_datos_completos check (
    tipo_bloqueo is not null
    or (uso is not null and reservado_por is not null and personas is not null
        and ((uso = 'invitado' and responsable_invitado is not null)
          or (uso <> 'invitado' and responsable_miembro is not null)))),
  -- SA5: nunca dos reservas que ocupan calendario se solapan, ni con carreras concurrentes.
  constraint reservas_sin_solapamiento exclude using gist (
    activo_id with =, rango_bloqueo with &&
  ) where (estado in ('confirmada', 'en_curso', 'bloqueada_mantenimiento'))
);
create index reservas_grupo_estado_idx on reservas (grupo_id, estado);
create index reservas_activo_rango_idx on reservas using gist (activo_id, rango);
create trigger reservas_actualizado before update on reservas
  for each row execute function set_actualizado_en();
create trigger reservas_auditar after insert or update or delete on reservas
  for each row execute function auditar();

create table orden_contadores (
  grupo_id uuid not null references grupos (id) on delete cascade,
  anio int not null,
  ultimo int not null default 0,
  primary key (grupo_id, anio)
);

create table ordenes (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  reserva_id uuid not null unique references reservas (id) on delete cascade,
  anio int not null,
  numero int not null check (numero > 0),
  codigo text not null,
  creado_en timestamptz not null default now(),
  unique (grupo_id, anio, numero),
  unique (grupo_id, codigo)
);
create trigger ordenes_auditar after insert or update or delete on ordenes
  for each row execute function auditar();

-- Costos solo para socios (el admin operativo y los invitados no ven tarifas, SA16).
create table reserva_costos (
  reserva_id uuid primary key references reservas (id) on delete cascade,
  grupo_id uuid not null references grupos (id) on delete cascade,
  fee numeric(14, 2) not null check (fee >= 0),
  moneda char(3) not null check (moneda ~ '^[A-Z]{3}$'),
  calculado_en timestamptz not null default now()
);

create table reserva_acuses (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  reserva_id uuid not null references reservas (id) on delete cascade,
  miembro_id uuid not null references miembros (id) on delete cascade,
  momento timestamptz not null default now(),
  unique (reserva_id, miembro_id)
);
create trigger reserva_acuses_auditar after insert or update or delete on reserva_acuses
  for each row execute function auditar();

create table invitado_enlaces (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  reserva_id uuid not null references reservas (id) on delete cascade,
  invitado_id uuid not null references invitados (id) on delete cascade,
  token_hash text not null unique,
  expira_en timestamptz not null,
  creado_en timestamptz not null default now()
);
create table invitado_intentos (
  id bigint generated always as identity primary key,
  ip_hash text not null,
  momento timestamptz not null default now()
);
create index invitado_intentos_idx on invitado_intentos (ip_hash, momento desc);

create table temporadas (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  periodo text not null check (periodo in ('semana_santa', 'navidad', 'ano_nuevo', 'verano', 'otro')),
  anio int not null check (anio between 2000 and 2200),
  desde date not null,
  hasta date not null check (hasta >= desde),
  miembro_prioridad uuid not null references miembros (id),
  libre_desde timestamptz not null,
  creado_en timestamptz not null default now(),
  unique (grupo_id, periodo, anio)
);
create trigger temporadas_auditar after insert or update or delete on temporadas
  for each row execute function auditar();

-- ---------------------------------------------------------------- cálculos
create function capacidad_efectiva_interna(p_activo uuid, p_uso uso_reserva) returns int
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare a activos; v_lim int;
begin
  select * into a from activos where id = p_activo;
  v_lim := pol_txt(a.grupo_id, case when p_uso = 'invitado' then 'capacidad.invitado' else 'capacidad.socio' end)::int;
  -- SA9: el límite legal certificado siempre manda
  return least(v_lim, coalesce(a.capacidad_legal, v_lim));
end $$;

create function capacidad_efectiva(p_activo uuid, p_uso uso_reserva) returns int
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare g uuid;
begin
  select grupo_id into g from activos where id = p_activo;
  if g is null or not es_miembro(g) then return null; end if;
  return capacidad_efectiva_interna(p_activo, p_uso);
end $$;

create function fee_calc(p_grupo uuid, p_destino uuid, p_inicio timestamptz, p_fin timestamptz)
returns table (monto numeric, moneda char(3))
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_modelo text := pol_txt(p_grupo, 'tarifa.modelo');
  v_fee numeric := 0; v_hora numeric := 0; v_mon char(3); v_horas numeric; v_total numeric := 0;
  v_hoy date := current_date;
begin
  v_horas := extract(epoch from (p_fin - p_inicio)) / 3600;
  select gr.moneda into v_mon from grupos gr where gr.id = p_grupo;
  if v_modelo in ('destino', 'ambos') and p_destino is not null then
    select t.monto, t.moneda into v_fee, v_mon from tarifas t
     where t.grupo_id = p_grupo and t.destino_id = p_destino and t.tipo = 'fee_destino'
       and t.vigente_desde <= v_hoy and (t.vigente_hasta is null or t.vigente_hasta >= v_hoy) limit 1;
    v_total := v_total + coalesce(v_fee, 0);
  end if;
  if v_modelo in ('hora', 'ambos') then
    select t.monto into v_hora from tarifas t
     where t.grupo_id = p_grupo and t.destino_id is null and t.tipo = 'hora'
       and t.vigente_desde <= v_hoy and (t.vigente_hasta is null or t.vigente_hasta >= v_hoy) limit 1;
    v_total := v_total + coalesce(v_hora, 0) * v_horas;
  end if;
  return query select round(v_total, 2), v_mon;
end $$;

-- Fee estimado para mostrar antes de confirmar: solo socios (las tarifas son finanzas).
create function fee_estimado(p_grupo uuid, p_destino uuid, p_inicio timestamptz, p_fin timestamptz)
returns table (monto numeric, moneda char(3))
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not es_socio(p_grupo) then return; end if;
  return query select * from fee_calc(p_grupo, p_destino, p_inicio, p_fin);
end $$;

revoke execute on function capacidad_efectiva_interna(uuid, uso_reserva), fee_calc(uuid, uuid, timestamptz, timestamptz)
  from public, anon, authenticated;
revoke execute on function capacidad_efectiva(uuid, uso_reserva), fee_estimado(uuid, uuid, timestamptz, timestamptz)
  from public, anon;
grant execute on function capacidad_efectiva(uuid, uso_reserva), fee_estimado(uuid, uuid, timestamptz, timestamptz)
  to authenticated;
