-- 2026-11-23 · 08 · Activos, componentes, destinos, tarifas, tasas, correos + RLS + RPC

-- ---------------------------------------------------------------- activos
create table activos (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  tipo_id uuid not null references tipos_activo (id),
  nombre text not null check (length(trim(nombre)) between 2 and 80),
  capacidad_legal int check (capacidad_legal is null or capacidad_legal between 1 and 1000),
  valores jsonb not null default '{}'::jsonb check (jsonb_typeof(valores) = 'object'),
  punto_encuentro text check (punto_encuentro is null or length(punto_encuentro) <= 300),
  reglas_invitados text check (reglas_invitados is null or length(reglas_invitados) <= 2000),
  contacto_invitados text check (contacto_invitados is null or length(contacto_invitados) <= 200),
  estado estado_activo not null default 'borrador',
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  -- SA19 / DF-17: sin capacidad legal certificada no se activa.
  constraint activos_capacidad_para_activar check (estado <> 'activo' or coalesce(capacidad_legal, 0) > 0)
);
create index activos_grupo_idx on activos (grupo_id);
create trigger activos_actualizado before update on activos
  for each row execute function set_actualizado_en();
create trigger activos_auditar after insert or update or delete on activos
  for each row execute function auditar();

-- Valida los valores de campos personalizados contra el tipo. Estricto = exige los obligatorios.
create function activo_valores_validar(p_tipo uuid, p_valores jsonb, p_estricto boolean) returns void
language plpgsql stable set search_path = public, pg_temp as $$
declare
  v_def jsonb;
  v_campo jsonb;
  v_clave text;
  v_valor jsonb;
  k text;
begin
  select definicion into v_def from tipos_activo where id = p_tipo;
  if v_def is null then
    raise exception 'tipo_no_existe' using errcode = 'foreign_key_violation';
  end if;
  for k in select jsonb_object_keys(p_valores) loop
    if not exists (select 1 from jsonb_array_elements(coalesce(v_def -> 'campos', '[]'::jsonb)) c where c ->> 'clave' = k) then
      raise exception 'valor_invalido: el campo % no existe en el tipo', k using errcode = 'check_violation';
    end if;
  end loop;
  for v_campo in select * from jsonb_array_elements(coalesce(v_def -> 'campos', '[]'::jsonb)) loop
    v_clave := v_campo ->> 'clave';
    v_valor := p_valores -> v_clave;
    if v_valor is null or v_valor = 'null'::jsonb or v_valor = '""'::jsonb then
      if p_estricto and coalesce((v_campo ->> 'obligatorio')::boolean, false) then
        raise exception 'valor_invalido: falta el campo obligatorio %', v_clave using errcode = 'check_violation';
      end if;
      continue;
    end if;
    case v_campo ->> 'tipo'
      when 'texto' then
        if jsonb_typeof(v_valor) <> 'string' or length(v_valor #>> '{}') > 300 then
          raise exception 'valor_invalido: % debe ser texto (máx. 300)', v_clave using errcode = 'check_violation';
        end if;
      when 'numero' then
        if jsonb_typeof(v_valor) <> 'number' then
          raise exception 'valor_invalido: % debe ser un número', v_clave using errcode = 'check_violation';
        end if;
      when 'booleano' then
        if jsonb_typeof(v_valor) <> 'boolean' then
          raise exception 'valor_invalido: % debe ser verdadero/falso', v_clave using errcode = 'check_violation';
        end if;
      when 'fecha' then
        if jsonb_typeof(v_valor) <> 'string' or (v_valor #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$' then
          raise exception 'valor_invalido: % debe ser una fecha AAAA-MM-DD', v_clave using errcode = 'check_violation';
        end if;
      when 'opcion' then
        if jsonb_typeof(v_valor) <> 'string' or not (v_campo -> 'opciones') @> v_valor then
          raise exception 'valor_invalido: % no es una opción permitida', v_clave using errcode = 'check_violation';
        end if;
    end case;
  end loop;
end $$;

create function activos_validar() returns trigger
language plpgsql set search_path = public, pg_temp as $$
declare v_tipo_grupo uuid; v_sistema boolean;
begin
  select grupo_id, es_sistema into v_tipo_grupo, v_sistema from tipos_activo where id = new.tipo_id;
  if not found or not (v_sistema or v_tipo_grupo = new.grupo_id) then
    raise exception 'tipo_no_permitido: el tipo no pertenece al grupo' using errcode = 'check_violation';
  end if;
  perform activo_valores_validar(new.tipo_id, new.valores, new.estado = 'activo');
  return new;
end $$;
create trigger activos_validar before insert or update on activos
  for each row execute function activos_validar();

create table activo_componentes (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  activo_id uuid not null references activos (id) on delete cascade,
  clave text not null check (clave ~ '^[a-z][a-z0-9_]{0,39}$'),
  etiqueta text not null check (length(trim(etiqueta)) between 1 and 80),
  indice int not null default 1 check (indice >= 1),
  unidad text not null check (length(trim(unidad)) between 1 and 10),
  lectura_inicial numeric(12, 1) not null default 0 check (lectura_inicial >= 0),
  unique (activo_id, clave, indice)
);
create index activo_componentes_activo_idx on activo_componentes (activo_id);
create function activo_componentes_grupo() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  select grupo_id into new.grupo_id from activos where id = new.activo_id;
  if new.grupo_id is null then
    raise exception 'activo_no_existe' using errcode = 'foreign_key_violation';
  end if;
  return new;
end $$;
create trigger activo_componentes_grupo before insert or update of activo_id on activo_componentes
  for each row execute function activo_componentes_grupo();
create trigger activo_componentes_auditar after insert or update or delete on activo_componentes
  for each row execute function auditar();

-- ---------------------------------------------------------------- destinos y tarifas
create table destinos (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  nombre text not null check (length(trim(nombre)) between 2 and 80),
  activo boolean not null default true,
  orden int not null default 0,
  creado_en timestamptz not null default now()
);
create unique index destinos_nombre_unico on destinos (grupo_id, lower(nombre));
create trigger destinos_auditar after insert or update or delete on destinos
  for each row execute function auditar();

create table tarifas (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  destino_id uuid references destinos (id) on delete cascade,
  tipo text not null check (tipo in ('fee_destino', 'hora')),
  monto numeric(14, 2) not null check (monto >= 0),
  moneda char(3) not null check (moneda ~ '^[A-Z]{3}$'),
  vigente_desde date not null default current_date,
  vigente_hasta date,
  creado_en timestamptz not null default now(),
  check (vigente_hasta is null or vigente_hasta >= vigente_desde),
  check (tipo = 'hora' or destino_id is not null),
  -- sin vigencias que se solapen para el mismo destino y tipo
  constraint tarifas_sin_solapamiento exclude using gist (
    grupo_id with =,
    (coalesce(destino_id, '00000000-0000-0000-0000-000000000000'::uuid)) with =,
    tipo with =,
    daterange(vigente_desde, coalesce(vigente_hasta + 1, 'infinity'::date), '[)') with &&
  )
);
create trigger tarifas_auditar after insert or update or delete on tarifas
  for each row execute function auditar();

create table tasas_cambio (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  fecha date not null default current_date,
  de char(3) not null check (de ~ '^[A-Z]{3}$'),
  a char(3) not null check (a ~ '^[A-Z]{3}$'),
  tasa numeric(18, 6) not null check (tasa > 0),
  unique (grupo_id, fecha, de, a),
  check (de <> a)
);
create trigger tasas_cambio_auditar after insert or update or delete on tasas_cambio
  for each row execute function auditar();

create table grupo_correos (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  correo citext not null check (correo ~ '^[^@\s]+@[^@\s]+$'),
  tipo text not null check (tipo in ('ordenes', 'alertas', 'invitados')),
  activo boolean not null default true,
  unique (grupo_id, correo, tipo)
);
create trigger grupo_correos_auditar after insert or update or delete on grupo_correos
  for each row execute function auditar();

-- ---------------------------------------------------------------- RLS
alter table tipos_activo enable row level security;
alter table activos enable row level security;
alter table activo_componentes enable row level security;
alter table destinos enable row level security;
alter table tarifas enable row level security;
alter table tasas_cambio enable row level security;
alter table grupo_correos enable row level security;

revoke all on tipos_activo, activos, activo_componentes, destinos, tarifas, tasas_cambio, grupo_correos
  from anon, authenticated;
grant select, insert, update, delete on tipos_activo, activos, activo_componentes, destinos, tarifas,
  tasas_cambio, grupo_correos to authenticated;

-- Lectura: miembros; finanzas (tarifas, tasas) y correos solo socios. Escritura: solo socios (SA16).
create policy tipos_activo_select on tipos_activo for select to authenticated
  using (grupo_id is null or es_miembro(grupo_id));
create policy tipos_activo_insert on tipos_activo for insert to authenticated
  with check (grupo_id is not null and es_socio(grupo_id));
create policy tipos_activo_update on tipos_activo for update to authenticated
  using (grupo_id is not null and es_socio(grupo_id)) with check (grupo_id is not null and es_socio(grupo_id));
create policy tipos_activo_delete on tipos_activo for delete to authenticated
  using (grupo_id is not null and es_socio(grupo_id));

create policy activos_select on activos for select to authenticated using (es_miembro(grupo_id));
create policy activos_insert on activos for insert to authenticated with check (es_socio(grupo_id));
create policy activos_update on activos for update to authenticated
  using (es_socio(grupo_id)) with check (es_socio(grupo_id));
create policy activos_delete on activos for delete to authenticated using (es_socio(grupo_id));

create policy activo_componentes_select on activo_componentes for select to authenticated
  using (es_miembro(grupo_id));
create policy activo_componentes_insert on activo_componentes for insert to authenticated
  with check (es_socio(grupo_id));
create policy activo_componentes_update on activo_componentes for update to authenticated
  using (es_socio(grupo_id)) with check (es_socio(grupo_id));
create policy activo_componentes_delete on activo_componentes for delete to authenticated
  using (es_socio(grupo_id));

create policy destinos_select on destinos for select to authenticated using (es_miembro(grupo_id));
create policy destinos_insert on destinos for insert to authenticated with check (es_socio(grupo_id));
create policy destinos_update on destinos for update to authenticated
  using (es_socio(grupo_id)) with check (es_socio(grupo_id));
create policy destinos_delete on destinos for delete to authenticated using (es_socio(grupo_id));

create policy tarifas_all on tarifas for all to authenticated
  using (es_socio(grupo_id)) with check (es_socio(grupo_id));
create policy tasas_cambio_all on tasas_cambio for all to authenticated
  using (es_socio(grupo_id)) with check (es_socio(grupo_id));
create policy grupo_correos_all on grupo_correos for all to authenticated
  using (es_socio(grupo_id)) with check (es_socio(grupo_id));

-- ---------------------------------------------------------------- RPC
-- Clona una plantilla (de sistema o del grupo) como tipo propio del grupo.
create function clonar_tipo_activo(p_tipo uuid, p_grupo uuid, p_nombre text, p_clave text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_src tipos_activo; v_id uuid;
begin
  if not es_socio(p_grupo) then
    raise exception 'solo_socios' using errcode = 'insufficient_privilege';
  end if;
  select * into v_src from tipos_activo where id = p_tipo and (grupo_id is null or grupo_id = p_grupo);
  if not found then
    raise exception 'tipo_no_existe' using errcode = 'no_data_found';
  end if;
  perform set_config('app.motivo', 'clon de tipo de activo', true);
  insert into tipos_activo (grupo_id, clave, nombre, clonado_de, definicion, prefijo_orden)
  values (p_grupo, p_clave, trim(p_nombre), v_src.id, v_src.definicion, v_src.prefijo_orden)
  returning id into v_id;
  return v_id;
end $$;

-- Crea el activo (borrador) con sus componentes según el tipo (cantidades configurables).
create function crear_activo(
  p_grupo uuid,
  p_tipo uuid,
  p_nombre text,
  p_capacidad_legal int default null,
  p_valores jsonb default '{}'::jsonb,
  p_cantidades jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_id uuid;
  v_def jsonb;
  v_comp jsonb;
  v_n int;
  i int;
begin
  if not es_socio(p_grupo) then
    raise exception 'solo_socios' using errcode = 'insufficient_privilege';
  end if;
  select definicion into v_def from tipos_activo
   where id = p_tipo and (grupo_id is null or grupo_id = p_grupo);
  if v_def is null then
    raise exception 'tipo_no_permitido' using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'creación de activo', true);
  insert into activos (grupo_id, tipo_id, nombre, capacidad_legal, valores)
  values (p_grupo, p_tipo, trim(p_nombre), p_capacidad_legal, coalesce(p_valores, '{}'::jsonb))
  returning id into v_id;
  for v_comp in select * from jsonb_array_elements(coalesce(v_def -> 'componentes', '[]'::jsonb)) loop
    v_n := coalesce((p_cantidades ->> (v_comp ->> 'clave'))::int, (v_comp ->> 'cantidad_defecto')::int);
    if v_n < 0 or v_n > 20 then
      raise exception 'cantidad_invalida' using errcode = 'check_violation';
    end if;
    for i in 1..v_n loop
      insert into activo_componentes (grupo_id, activo_id, clave, etiqueta, indice, unidad)
      values (p_grupo, v_id, v_comp ->> 'clave',
              case when v_n > 1 then (v_comp ->> 'etiqueta') || ' ' || i else v_comp ->> 'etiqueta' end,
              i, v_comp -> 'medidor' ->> 'unidad');
    end loop;
  end loop;
  return v_id;
end $$;

-- Datos básicos del grupo (Configuración). La moneda no se cambia aquí.
create function actualizar_grupo(p_grupo uuid, p_nombre text, p_zona_horaria text, p_prefijo text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not es_socio(p_grupo) then
    raise exception 'solo_socios' using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from pg_timezone_names where name = p_zona_horaria) then
    raise exception 'zona_horaria_invalida: %', p_zona_horaria using errcode = 'invalid_parameter_value';
  end if;
  perform set_config('app.motivo', 'configuración del grupo', true);
  update grupos set nombre = trim(p_nombre), zona_horaria = p_zona_horaria, prefijo = upper(p_prefijo)
   where id = p_grupo;
end $$;

revoke execute on function clonar_tipo_activo(uuid, uuid, text, text),
  crear_activo(uuid, uuid, text, int, jsonb, jsonb), actualizar_grupo(uuid, text, text, text)
  from public, anon;
grant execute on function clonar_tipo_activo(uuid, uuid, text, text),
  crear_activo(uuid, uuid, text, int, jsonb, jsonb), actualizar_grupo(uuid, text, text, text)
  to authenticated;
