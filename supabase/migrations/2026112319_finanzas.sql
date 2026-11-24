-- 2026-11-24 · 19 · Finanzas: gastos, libro mayor, pagos, fondo común, daños, liquidación, estado de cuenta (P3·F3–F6)
-- Modo `registro` (DF-27): todo se calcula y se muestra; NADA bloquea (ni reservas por deuda ni pasarelas).
-- Convención: balance = haber − debe. Positivo = le deben. Cada monto guarda moneda original y tasa (DF-05).

-- ---------------------------------------------------------------- reparto exacto por pesos (centavos deterministas)
-- Asigna el centavo sobrante por mayor resto, luego mayor peso, luego id: la suma siempre cuadra.
create function repartir_pesos(p_total numeric, p_ids uuid[], p_pesos numeric[])
returns table (id uuid, monto numeric)
language sql immutable set search_path = public, pg_temp as $$
  with s as (select u.i as id, u.w from unnest(p_ids, p_pesos) as u(i, w) where u.w > 0),
  tot as (select sum(w) as t from s),
  b as (
    select s.id, s.w,
           floor(round(p_total * 100) * s.w / tot.t) as c,
           (round(p_total * 100) * s.w / tot.t) - floor(round(p_total * 100) * s.w / tot.t) as resto
      from s, tot),
  f as (select round(p_total * 100) - coalesce(sum(c), 0) as n from b),
  r as (select b.*, row_number() over (order by b.resto desc, b.w desc, b.id) as rn from b)
  select r.id, (r.c + case when r.rn <= (select n from f) then 1 else 0 end) / 100 from r
$$;

-- Reparto por `porcentaje` entre los socios activos (opcionalmente sin uno).
create function repartir_por_porcentaje(p_grupo uuid, p_monto numeric, p_excluir uuid default null)
returns table (miembro_id uuid, monto numeric)
language sql stable security definer set search_path = public, pg_temp as $$
  select x.id, x.monto from repartir_pesos(
    p_monto,
    (select coalesce(array_agg(m.id order by m.id), '{}') from miembros m
      where m.grupo_id = p_grupo and m.rol = 'socio' and m.estado = 'activo' and m.porcentaje > 0 and m.id is distinct from p_excluir),
    (select coalesce(array_agg(m.porcentaje order by m.id), '{}') from miembros m
      where m.grupo_id = p_grupo and m.rol = 'socio' and m.estado = 'activo' and m.porcentaje > 0 and m.id is distinct from p_excluir)
  ) x
$$;
revoke execute on function repartir_pesos(numeric, uuid[], numeric[]), repartir_por_porcentaje(uuid, numeric, uuid)
  from public, anon, authenticated;

-- Convierte a la moneda del grupo con la tasa dada o la del día (DF-05, SC7).
create function convertir_a_grupo(p_grupo uuid, p_monto numeric, p_moneda text, p_tasa numeric, p_fecha date default current_date)
returns table (tasa numeric, monto_grupo numeric, moneda_grupo char(3))
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_mon char(3); v_t numeric;
begin
  select g.moneda into v_mon from grupos g where g.id = p_grupo;
  if p_moneda = v_mon then
    return query select 1::numeric, round(p_monto, 2), v_mon;
    return;
  end if;
  v_t := coalesce(p_tasa, (select t.tasa from tasas_cambio t
                            where t.grupo_id = p_grupo and t.de = p_moneda and t.a = v_mon and t.fecha <= p_fecha
                            order by t.fecha desc limit 1));
  if v_t is null or v_t <= 0 then
    raise exception 'tasa_requerida: no hay tasa de % a % (regístrala en Configuración)', p_moneda, v_mon using errcode = 'check_violation';
  end if;
  return query select v_t, round(p_monto * v_t, 2), v_mon;
end $$;
revoke execute on function convertir_a_grupo(uuid, numeric, text, numeric, date) from public, anon, authenticated;

-- ---------------------------------------------------------------- libro mayor (solo adición; cada asiento cuadra)
create table libro_mayor (
  id bigint generated always as identity primary key,
  grupo_id uuid not null references grupos (id) on delete cascade,
  asiento_id uuid not null,
  momento timestamptz not null default now(),
  cuenta_tipo text not null check (cuenta_tipo in ('miembro', 'fondo', 'externo')),
  miembro_id uuid references miembros (id),
  debe numeric(14, 2) not null default 0 check (debe >= 0),
  haber numeric(14, 2) not null default 0 check (haber >= 0),
  moneda char(3) not null check (moneda ~ '^[A-Z]{3}$'),
  monto_original numeric(14, 2),
  moneda_original char(3),
  tasa numeric(18, 6),
  origen_tipo text not null check (origen_tipo in ('gasto', 'gasto_anulado', 'fee', 'cancelacion', 'pago', 'aporte', 'dano')),
  origen_id uuid not null,
  nota text check (nota is null or length(nota) <= 300),
  constraint libro_una_cara check ((debe > 0) <> (haber > 0)),
  constraint libro_cuenta_miembro check ((cuenta_tipo = 'miembro') = (miembro_id is not null))
);
create index libro_grupo_idx on libro_mayor (grupo_id, momento desc);
create index libro_miembro_idx on libro_mayor (miembro_id, id);
create index libro_origen_idx on libro_mayor (origen_tipo, origen_id);
create trigger libro_sin_update before update on libro_mayor for each row execute function solo_adicion();
create trigger libro_sin_delete before delete on libro_mayor for each row
  when (current_setting('app.permitir_borrado', true) is distinct from 'on') execute function solo_adicion();
create trigger libro_auditar after insert on libro_mayor for each row execute function auditar();

-- Invariante de partida doble: en cada asiento, debe = haber (se comprueba al cerrar la transacción).
create function libro_asiento_cuadra() returns trigger
language plpgsql set search_path = public, pg_temp as $$
declare v_debe numeric; v_haber numeric;
begin
  select coalesce(sum(debe), 0), coalesce(sum(haber), 0) into v_debe, v_haber
    from libro_mayor where asiento_id = new.asiento_id;
  if v_debe <> v_haber then
    raise exception 'asiento_descuadrado: debe % ≠ haber % en el asiento %', v_debe, v_haber, new.asiento_id
      using errcode = 'check_violation';
  end if;
  return null;
end $$;
create constraint trigger libro_asiento_cuadra after insert on libro_mayor
  deferrable initially deferred for each row execute function libro_asiento_cuadra();

create function lm_linea(
  p_asiento uuid, p_grupo uuid, p_cuenta text, p_miembro uuid, p_debe numeric, p_haber numeric, p_moneda char,
  p_orig numeric, p_mon_orig char, p_tasa numeric, p_origen_tipo text, p_origen uuid, p_nota text
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if coalesce(p_debe, 0) = 0 and coalesce(p_haber, 0) = 0 then return; end if;
  insert into libro_mayor (grupo_id, asiento_id, cuenta_tipo, miembro_id, debe, haber, moneda,
                           monto_original, moneda_original, tasa, origen_tipo, origen_id, nota)
  values (p_grupo, p_asiento, p_cuenta, p_miembro, coalesce(p_debe, 0), coalesce(p_haber, 0), p_moneda,
          p_orig, p_mon_orig, p_tasa, p_origen_tipo, p_origen, left(p_nota, 300));
end $$;
revoke execute on function lm_linea(uuid, uuid, text, uuid, numeric, numeric, char, numeric, char, numeric, text, uuid, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------- daños (SA12, SA24, SC3): nunca cargo automático
create table danos_casos (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  reserva_id uuid references reservas (id),
  operacion_id uuid references operaciones (id),
  incidencia_id uuid references incidencias (id),
  siniestro_id uuid,                     -- vínculo al seguro (PROMPT-4)
  titulo text not null check (length(trim(titulo)) between 2 and 120),
  descripcion text check (descripcion is null or length(descripcion) <= 2000),
  presupuesto numeric(14, 2) check (presupuesto is null or presupuesto > 0),
  moneda char(3) check (moneda is null or moneda ~ '^[A-Z]{3}$'),
  tasa numeric(18, 6),
  pagado_por_tipo text check (pagado_por_tipo is null or pagado_por_tipo in ('miembro', 'fondo', 'externo')),
  pagado_por_miembro uuid references miembros (id),
  propuesta jsonb not null default '[]'::jsonb check (jsonb_typeof(propuesta) = 'array'),
  version int not null default 1,
  estado text not null default 'en_revision' check (estado in ('en_revision', 'acordado', 'rechazado')),
  abierto_por uuid not null references miembros (id),
  creado_en timestamptz not null default now(),
  resuelto_en timestamptz
);
create index danos_grupo_idx on danos_casos (grupo_id, estado);
create trigger danos_auditar after insert or update or delete on danos_casos for each row execute function auditar();

create table danos_acuerdos (
  caso_id uuid not null references danos_casos (id) on delete cascade,
  version int not null,
  miembro_id uuid not null references miembros (id),
  grupo_id uuid not null references grupos (id) on delete cascade,
  acepta boolean not null,
  nota text check (nota is null or length(nota) <= 300),
  creado_en timestamptz not null default now(),
  primary key (caso_id, version, miembro_id)
);
create trigger danos_acuerdos_auditar after insert on danos_acuerdos for each row execute function auditar('caso_id');

create table danos_mensajes (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  caso_id uuid not null references danos_casos (id) on delete cascade,
  autor_id uuid references miembros (id),
  tipo text not null default 'mensaje' check (tipo in ('mensaje', 'propuesta', 'acuerdo', 'rechazo', 'sistema')),
  texto text check (texto is null or length(texto) <= 1000),
  creado_en timestamptz not null default now()
);
create index danos_mensajes_idx on danos_mensajes (caso_id, creado_en);

-- ---------------------------------------------------------------- gastos (SA10, SA11, SA25)
create table gastos (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  alcance text not null check (alcance in ('comun', 'individual', 'dano')),
  categoria text not null check (length(trim(categoria)) between 1 and 60),
  descripcion text check (descripcion is null or length(descripcion) <= 500),
  monto numeric(14, 2) not null check (monto > 0),
  moneda char(3) not null check (moneda ~ '^[A-Z]{3}$'),
  tasa numeric(18, 6) not null default 1 check (tasa > 0),
  monto_grupo numeric(14, 2) not null check (monto_grupo > 0),
  moneda_grupo char(3) not null check (moneda_grupo ~ '^[A-Z]{3}$'),
  pagado_por_tipo text not null default 'miembro' check (pagado_por_tipo in ('miembro', 'fondo', 'externo')),
  pagado_por_miembro uuid references miembros (id),
  proveedor text check (proveedor is null or length(proveedor) <= 120),
  fecha date not null default current_date,
  vencimiento date,
  reserva_id uuid references reservas (id),
  operacion_id uuid references operaciones (id),
  caso_dano_id uuid references danos_casos (id),
  estado text not null default 'registrado' check (estado in ('registrado', 'validado', 'disputado', 'anulado')),
  cargado_por uuid not null references miembros (id),
  validado_por uuid references miembros (id),
  validado_en timestamptz,
  motivo_estado text check (motivo_estado is null or length(motivo_estado) <= 300),
  creado_en timestamptz not null default now(),
  constraint gastos_pagador check ((pagado_por_tipo = 'miembro') = (pagado_por_miembro is not null)),
  constraint gastos_individual_con_reserva check (alcance <> 'individual' or reserva_id is not null),
  constraint gastos_dano_con_caso check (alcance <> 'dano' or caso_dano_id is not null),
  constraint gastos_validado_con_validador check (estado <> 'validado' or alcance = 'dano' or validado_por is not null)
);
create index gastos_grupo_idx on gastos (grupo_id, fecha desc);
create index gastos_reserva_idx on gastos (reserva_id);
create index gastos_vencimiento_idx on gastos (grupo_id, vencimiento) where vencimiento is not null;
create trigger gastos_auditar after insert or update or delete on gastos for each row execute function auditar();

alter table combustible_registros
  add constraint combustible_gasto_fk foreign key (gasto_id) references gastos (id);

-- ---------------------------------------------------------------- pagos entre socios / al fondo (confirma el receptor)
create table pagos (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  de_miembro uuid not null references miembros (id),
  a_tipo text not null check (a_tipo in ('miembro', 'fondo')),
  a_miembro uuid references miembros (id),
  monto numeric(14, 2) not null check (monto > 0),
  moneda char(3) not null check (moneda ~ '^[A-Z]{3}$'),
  tasa numeric(18, 6) not null default 1 check (tasa > 0),
  monto_grupo numeric(14, 2) not null check (monto_grupo > 0),
  moneda_grupo char(3) not null,
  nota text check (nota is null or length(nota) <= 300),
  estado text not null default 'pendiente' check (estado in ('pendiente', 'confirmado', 'rechazado')),
  confirmado_por uuid references miembros (id),
  resuelto_en timestamptz,
  motivo_rechazo text check (motivo_rechazo is null or length(motivo_rechazo) <= 300),
  creado_en timestamptz not null default now(),
  constraint pagos_receptor check ((a_tipo = 'miembro') = (a_miembro is not null)),
  constraint pagos_no_a_si_mismo check (a_miembro is distinct from de_miembro)
);
create index pagos_grupo_idx on pagos (grupo_id, estado, creado_en desc);
create trigger pagos_auditar after insert or update or delete on pagos for each row execute function auditar();

-- ---------------------------------------------------------------- fondo común y liquidaciones
create table fondo_aportes (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  periodo date not null check (periodo = date_trunc('month', periodo)::date),
  miembro_id uuid not null references miembros (id),
  monto numeric(14, 2) not null check (monto > 0),
  moneda char(3) not null,
  creado_en timestamptz not null default now(),
  unique (grupo_id, periodo, miembro_id)
);
create trigger fondo_aportes_auditar after insert on fondo_aportes for each row execute function auditar();

create table liquidaciones (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  operacion_id uuid not null unique references operaciones (id) on delete cascade,
  reserva_id uuid not null references reservas (id),
  miembro_id uuid not null references miembros (id),
  fee_monto numeric(14, 2) not null default 0 check (fee_monto >= 0),
  fee_moneda char(3),
  fee_destino text,
  resumen jsonb not null default '{}'::jsonb,
  liquidada_en timestamptz not null default now()
);
create trigger liquidaciones_auditar after insert on liquidaciones for each row execute function auditar();

-- ---------------------------------------------------------------- asientos
-- Cuenta de «quien pagó» (crédito).
create function lm_credito_pagador(p_asiento uuid, p_grupo uuid, p_tipo text, p_miembro uuid, p_monto numeric, p_moneda char,
  p_orig numeric, p_mon_orig char, p_tasa numeric, p_origen_tipo text, p_origen uuid, p_nota text) returns void
language sql security definer set search_path = public, pg_temp as $$
  select lm_linea(p_asiento, p_grupo,
    case p_tipo when 'miembro' then 'miembro' else p_tipo end,
    case p_tipo when 'miembro' then p_miembro end,
    0, p_monto, p_moneda, p_orig, p_mon_orig, p_tasa, p_origen_tipo, p_origen, p_nota)
$$;
revoke execute on function lm_credito_pagador(uuid, uuid, text, uuid, numeric, char, numeric, char, numeric, text, uuid, text)
  from public, anon, authenticated;

create function gasto_asentar(g gastos) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_as uuid := gen_random_uuid(); v_res uuid; s record; v_nota text; v_a_fondo boolean := false; v_n int := 0;
begin
  v_nota := g.categoria || coalesce(' · ' || g.proveedor, '');
  perform lm_credito_pagador(v_as, g.grupo_id, g.pagado_por_tipo, g.pagado_por_miembro, g.monto_grupo, g.moneda_grupo,
                             g.monto, g.moneda, g.tasa, 'gasto', g.id, v_nota);
  if g.alcance = 'comun' then
    for s in select * from repartir_por_porcentaje(g.grupo_id, g.monto_grupo) loop
      perform lm_linea(v_as, g.grupo_id, 'miembro', s.miembro_id, s.monto, 0, g.moneda_grupo,
                       g.monto, g.moneda, g.tasa, 'gasto', g.id, 'Gasto común · ' || v_nota);
      v_n := v_n + 1;
    end loop;
    if v_n = 0 then
      raise exception 'sin_socios: no hay socios con porcentaje para repartir' using errcode = 'check_violation';
    end if;
  elsif g.alcance = 'individual' then
    select reservado_por into v_res from reservas where id = g.reserva_id;
    -- DF-08 «incluido»: el combustible lo absorbe el fondo (ya va en el fee del destino)
    v_a_fondo := g.categoria = 'combustible' and pol_txt(g.grupo_id, 'combustible.modelo') = 'incluido';
    if v_a_fondo then
      perform lm_linea(v_as, g.grupo_id, 'fondo', null, g.monto_grupo, 0, g.moneda_grupo,
                       g.monto, g.moneda, g.tasa, 'gasto', g.id, 'Combustible incluido en el fee · ' || v_nota);
    else
      perform lm_linea(v_as, g.grupo_id, 'miembro', v_res, g.monto_grupo, 0, g.moneda_grupo,
                       g.monto, g.moneda, g.tasa, 'gasto', g.id, 'Uso individual · ' || v_nota);
    end if;
  end if;
end $$;
revoke execute on function gasto_asentar(gastos) from public, anon, authenticated;

-- Fee (o cargo de cancelación): débito a quien reservó; crédito según `tarifa.destino_fee_a` (DF-07).
create function asentar_fee(p_grupo uuid, p_miembro uuid, p_monto numeric, p_moneda char, p_orig numeric, p_mon_orig char,
  p_tasa numeric, p_origen_tipo text, p_origen uuid, p_nota text) returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_dest text := pol_txt(p_grupo, 'tarifa.destino_fee_a'); v_as uuid := gen_random_uuid(); s record; v_n int := 0;
begin
  if p_monto is null or p_monto <= 0 or v_dest = 'informativo' then return 'informativo'; end if;
  perform lm_linea(v_as, p_grupo, 'miembro', p_miembro, p_monto, 0, p_moneda, p_orig, p_mon_orig, p_tasa, p_origen_tipo, p_origen, p_nota);
  if v_dest = 'socios_proporcional' then
    for s in select * from repartir_por_porcentaje(p_grupo, p_monto, p_miembro) loop
      perform lm_linea(v_as, p_grupo, 'miembro', s.miembro_id, 0, s.monto, p_moneda, p_orig, p_mon_orig, p_tasa, p_origen_tipo, p_origen, p_nota);
      v_n := v_n + 1;
    end loop;
  end if;
  if v_n = 0 then   -- fondo (o un único socio: no hay a quién repartir)
    perform lm_linea(v_as, p_grupo, 'fondo', null, 0, p_monto, p_moneda, p_orig, p_mon_orig, p_tasa, p_origen_tipo, p_origen, p_nota);
    return 'fondo';
  end if;
  return v_dest;
end $$;
revoke execute on function asentar_fee(uuid, uuid, numeric, char, numeric, char, numeric, text, uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------- gastos: registrar / validar / disputar / anular
create function gasto_categoria_valida(p_grupo uuid, p_categoria text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  with cats as (
    select jsonb_array_elements_text(coalesce(t.definicion -> 'categorias_gasto', '[]'::jsonb)) as c
      from activos a join tipos_activo t on t.id = a.tipo_id where a.grupo_id = p_grupo)
  select not exists (select 1 from cats) or exists (select 1 from cats where c = p_categoria)
$$;
revoke execute on function gasto_categoria_valida(uuid, text) from public, anon, authenticated;

create function gasto_crear_interno(
  p_grupo uuid, p_actor uuid, p_alcance text, p_categoria text, p_monto numeric, p_moneda text,
  p_pagado_tipo text, p_pagado_miembro uuid, p_proveedor text, p_descripcion text, p_reserva uuid,
  p_fecha date, p_vencimiento date, p_tasa numeric
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_id uuid; v_cv record; r reservas; v_pagador uuid; v_op uuid; v_fecha date := coalesce(p_fecha, current_date); s record;
begin
  if p_alcance not in ('comun', 'individual') then
    raise exception 'alcance_invalido: los daños se registran como caso de daño' using errcode = 'check_violation';
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'monto_invalido: el monto debe ser mayor que cero' using errcode = 'check_violation';
  end if;
  if p_moneda is null or p_moneda !~ '^[A-Z]{3}$' then
    raise exception 'moneda_invalida' using errcode = 'check_violation';
  end if;
  if not gasto_categoria_valida(p_grupo, trim(p_categoria)) then
    raise exception 'categoria_invalida: % no es una categoría de gasto del activo', p_categoria using errcode = 'check_violation';
  end if;
  v_pagador := case coalesce(p_pagado_tipo, 'miembro') when 'miembro' then coalesce(p_pagado_miembro, p_actor) end;
  if v_pagador is not null and not exists (
       select 1 from miembros where id = v_pagador and grupo_id = p_grupo and estado = 'activo' and rol in ('socio', 'admin_operativo')) then
    raise exception 'pagador_invalido' using errcode = 'check_violation';
  end if;
  if p_alcance = 'individual' then
    select * into r from reservas where id = p_reserva and grupo_id = p_grupo and tipo_bloqueo is null;
    if not found or r.estado not in ('confirmada', 'en_curso', 'finalizada') then
      raise exception 'reserva_invalida: un gasto individual necesita una reserva vigente o finalizada' using errcode = 'check_violation';
    end if;
    select id into v_op from operaciones where reserva_id = r.id;
  end if;
  select * into v_cv from convertir_a_grupo(p_grupo, p_monto, p_moneda, p_tasa, v_fecha);
  if v_cv.monto_grupo <= 0 then
    raise exception 'monto_invalido: el monto convertido es cero' using errcode = 'check_violation';
  end if;
  insert into gastos (grupo_id, alcance, categoria, descripcion, monto, moneda, tasa, monto_grupo, moneda_grupo,
                      pagado_por_tipo, pagado_por_miembro, proveedor, fecha, vencimiento, reserva_id, operacion_id, cargado_por)
  values (p_grupo, p_alcance, trim(p_categoria), left(p_descripcion, 500), round(p_monto, 2), p_moneda, v_cv.tasa,
          v_cv.monto_grupo, v_cv.moneda_grupo, coalesce(p_pagado_tipo, 'miembro'), v_pagador, left(p_proveedor, 120),
          v_fecha, p_vencimiento, case when p_alcance = 'individual' then p_reserva end, v_op, p_actor)
  returning id into v_id;
  perform gasto_asentar((select g from gastos g where g.id = v_id));
  -- aviso a los demás socios: hay un gasto por validar
  for s in select m.usuario_id from miembros m
            where m.grupo_id = p_grupo and m.rol = 'socio' and m.estado = 'activo' and m.id <> p_actor loop
    perform notificar(p_grupo, s.usuario_id, 'gasto_por_validar', 'Gasto por validar',
      trim(p_categoria) || ' · ' || round(p_monto, 2) || ' ' || p_moneda, jsonb_build_object('gasto_id', v_id), false);
  end loop;
  return v_id;
end $$;
revoke execute on function gasto_crear_interno(uuid, uuid, text, text, numeric, text, text, uuid, text, text, uuid, date, date, numeric)
  from public, anon, authenticated;

create function gasto_registrar(
  p_grupo uuid, p_alcance text, p_categoria text, p_monto numeric, p_moneda text,
  p_pagado_tipo text default 'miembro', p_pagado_miembro uuid default null, p_proveedor text default null,
  p_descripcion text default null, p_reserva uuid default null, p_fecha date default null,
  p_vencimiento date default null, p_tasa numeric default null
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_yo uuid := miembro_actual(p_grupo);
begin
  if v_yo is null or not coalesce(rol_en(p_grupo) in ('socio', 'admin_operativo'), false) then
    raise exception 'sin_permiso: solo socios o el administrador operativo cargan gastos' using errcode = 'insufficient_privilege';
  end if;
  perform set_config('app.motivo', 'gasto registrado', true);
  return gasto_crear_interno(p_grupo, v_yo, p_alcance, p_categoria, p_monto, p_moneda, p_pagado_tipo, p_pagado_miembro,
                             p_proveedor, p_descripcion, p_reserva, p_fecha, p_vencimiento, p_tasa);
end $$;

-- DF-12: las valida un socio distinto de quien las cargó; el admin operativo NUNCA valida.
create function gasto_validar(p_gasto uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare g gastos; v_yo uuid; v_pol text;
begin
  select * into g from gastos where id = p_gasto for update;
  if not found then raise exception 'gasto_no_existe' using errcode = 'no_data_found'; end if;
  v_yo := miembro_actual(g.grupo_id);
  if v_yo is null or not es_socio(g.grupo_id) then
    raise exception 'solo_socios: únicamente un socio valida facturas' using errcode = 'insufficient_privilege';
  end if;
  v_pol := coalesce(pol_txt(g.grupo_id, 'administracion.valida_facturas'), 'otro_socio');
  if v_pol = 'otro_socio' and v_yo = g.cargado_por then
    raise exception 'otro_socio: la factura debe validarla un socio distinto de quien la cargó' using errcode = 'insufficient_privilege';
  end if;
  if g.estado not in ('registrado', 'disputado') or g.alcance = 'dano' then
    raise exception 'estado_invalido: el gasto está %', g.estado using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'gasto validado', true);
  update gastos set estado = 'validado', validado_por = v_yo, validado_en = now(), motivo_estado = null where id = g.id;
end $$;

create function gasto_disputar(p_gasto uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare g gastos; v_yo uuid;
begin
  select * into g from gastos where id = p_gasto for update;
  if not found then raise exception 'gasto_no_existe' using errcode = 'no_data_found'; end if;
  v_yo := miembro_actual(g.grupo_id);
  if v_yo is null or not es_socio(g.grupo_id) then
    raise exception 'solo_socios' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(length(trim(p_motivo)), 0) < 3 then
    raise exception 'motivo_requerido' using errcode = 'check_violation';
  end if;
  if g.estado <> 'registrado' then
    raise exception 'estado_invalido: solo se disputa un gasto sin validar' using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', p_motivo, true);
  update gastos set estado = 'disputado', motivo_estado = left(p_motivo, 300) where id = g.id;
end $$;

-- Anular = asiento inverso (nunca se borra nada) con motivo obligatorio.
create function gasto_anular(p_gasto uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare g gastos; v_yo uuid; l record; v_as uuid := gen_random_uuid();
begin
  select * into g from gastos where id = p_gasto for update;
  if not found then raise exception 'gasto_no_existe' using errcode = 'no_data_found'; end if;
  v_yo := miembro_actual(g.grupo_id);
  if v_yo is null or not coalesce(rol_en(g.grupo_id) in ('socio', 'admin_operativo'), false)
     or (rol_en(g.grupo_id) = 'admin_operativo' and (g.cargado_por <> v_yo or g.estado = 'validado')) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(length(trim(p_motivo)), 0) < 3 then
    raise exception 'motivo_requerido' using errcode = 'check_violation';
  end if;
  if g.estado = 'anulado' or g.alcance = 'dano' then
    raise exception 'estado_invalido' using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', p_motivo, true);
  for l in select * from libro_mayor where origen_tipo = 'gasto' and origen_id = g.id loop
    perform lm_linea(v_as, g.grupo_id, l.cuenta_tipo, l.miembro_id, l.haber, l.debe, l.moneda,
                     l.monto_original, l.moneda_original, l.tasa, 'gasto_anulado', g.id, 'Anulación: ' || left(p_motivo, 200));
  end loop;
  update gastos set estado = 'anulado', motivo_estado = left(p_motivo, 300) where id = g.id;
end $$;

-- ---------------------------------------------------------------- pagos
create function pago_registrar(p_grupo uuid, p_a_miembro uuid, p_monto numeric, p_moneda text, p_nota text default null, p_tasa numeric default null)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_yo uuid := miembro_actual(p_grupo); v_cv record; v_id uuid; v_dest uuid;
begin
  if v_yo is null or not es_socio(p_grupo) then
    raise exception 'solo_socios' using errcode = 'insufficient_privilege';
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'monto_invalido' using errcode = 'check_violation';
  end if;
  if p_a_miembro is not null and not exists (
       select 1 from miembros where id = p_a_miembro and grupo_id = p_grupo and estado = 'activo' and rol = 'socio') then
    raise exception 'receptor_invalido' using errcode = 'check_violation';
  end if;
  select * into v_cv from convertir_a_grupo(p_grupo, p_monto, p_moneda, p_tasa, current_date);
  perform set_config('app.motivo', 'pago registrado', true);
  insert into pagos (grupo_id, de_miembro, a_tipo, a_miembro, monto, moneda, tasa, monto_grupo, moneda_grupo, nota)
  values (p_grupo, v_yo, case when p_a_miembro is null then 'fondo' else 'miembro' end, p_a_miembro,
          round(p_monto, 2), p_moneda, v_cv.tasa, v_cv.monto_grupo, v_cv.moneda_grupo, left(p_nota, 300))
  returning id into v_id;
  -- avisa al receptor (o a los demás socios si es al fondo)
  for v_dest in select m.usuario_id from miembros m
                 where m.grupo_id = p_grupo and m.rol = 'socio' and m.estado = 'activo' and m.id <> v_yo
                   and (p_a_miembro is null or m.id = p_a_miembro) loop
    perform notificar(p_grupo, v_dest, 'pago_por_confirmar', 'Pago por confirmar',
      round(p_monto, 2) || ' ' || p_moneda, jsonb_build_object('pago_id', v_id), false);
  end loop;
  return v_id;
end $$;

create function pago_confirmar(p_pago uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare p pagos; v_yo uuid; v_as uuid := gen_random_uuid();
begin
  select * into p from pagos where id = p_pago for update;
  if not found then raise exception 'pago_no_existe' using errcode = 'no_data_found'; end if;
  v_yo := miembro_actual(p.grupo_id);
  if v_yo is null or not es_socio(p.grupo_id) or v_yo = p.de_miembro
     or (p.a_tipo = 'miembro' and v_yo <> p.a_miembro) then
    raise exception 'solo_el_receptor: el pago lo confirma quien lo recibe' using errcode = 'insufficient_privilege';
  end if;
  if p.estado <> 'pendiente' then
    raise exception 'estado_invalido: el pago está %', p.estado using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'pago confirmado', true);
  update pagos set estado = 'confirmado', confirmado_por = v_yo, resuelto_en = now() where id = p.id;
  perform lm_linea(v_as, p.grupo_id, 'miembro', p.de_miembro, 0, p.monto_grupo, p.moneda_grupo, p.monto, p.moneda, p.tasa, 'pago', p.id, 'Pago confirmado');
  if p.a_tipo = 'fondo' then
    perform lm_linea(v_as, p.grupo_id, 'fondo', null, p.monto_grupo, 0, p.moneda_grupo, p.monto, p.moneda, p.tasa, 'pago', p.id, 'Pago al fondo común');
  else
    perform lm_linea(v_as, p.grupo_id, 'miembro', p.a_miembro, p.monto_grupo, 0, p.moneda_grupo, p.monto, p.moneda, p.tasa, 'pago', p.id, 'Pago recibido');
  end if;
  perform notificar(p.grupo_id, (select usuario_id from miembros where id = p.de_miembro), 'pago_confirmado',
    'Pago confirmado', p.monto || ' ' || p.moneda, jsonb_build_object('pago_id', p.id), false);
end $$;

create function pago_rechazar(p_pago uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare p pagos; v_yo uuid;
begin
  select * into p from pagos where id = p_pago for update;
  if not found then raise exception 'pago_no_existe' using errcode = 'no_data_found'; end if;
  v_yo := miembro_actual(p.grupo_id);
  if v_yo is null or not es_socio(p.grupo_id) or v_yo = p.de_miembro
     or (p.a_tipo = 'miembro' and v_yo <> p.a_miembro) then
    raise exception 'solo_el_receptor' using errcode = 'insufficient_privilege';
  end if;
  if p.estado <> 'pendiente' or coalesce(length(trim(p_motivo)), 0) < 3 then
    raise exception 'estado_invalido_o_sin_motivo' using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', p_motivo, true);
  update pagos set estado = 'rechazado', confirmado_por = v_yo, resuelto_en = now(), motivo_rechazo = left(p_motivo, 300) where id = p.id;
  perform notificar(p.grupo_id, (select usuario_id from miembros where id = p.de_miembro), 'pago_rechazado',
    'Pago rechazado', coalesce(p_motivo, ''), jsonb_build_object('pago_id', p.id), false);
end $$;

-- ---------------------------------------------------------------- daños: caso, propuesta, acuerdo (DF-11)
create function dano_abrir(p_grupo uuid, p_titulo text, p_descripcion text default null, p_reserva uuid default null, p_incidencia uuid default null)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_yo uuid := miembro_actual(p_grupo); v_id uuid; v_op uuid; s record;
begin
  if v_yo is null or not coalesce(rol_en(p_grupo) in ('socio', 'admin_operativo'), false) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  if p_reserva is not null then
    select id into v_op from operaciones where reserva_id = p_reserva and grupo_id = p_grupo;
  end if;
  perform set_config('app.motivo', 'caso de daño abierto', true);
  insert into danos_casos (grupo_id, reserva_id, operacion_id, incidencia_id, titulo, descripcion, abierto_por)
  values (p_grupo, p_reserva, v_op, p_incidencia, trim(p_titulo), left(p_descripcion, 2000), v_yo) returning id into v_id;
  insert into danos_mensajes (grupo_id, caso_id, autor_id, tipo, texto) values (p_grupo, v_id, v_yo, 'sistema', 'Caso abierto. No se cobra nada hasta que todos los socios acuerden.');
  for s in select m.usuario_id from miembros m where m.grupo_id = p_grupo and m.rol = 'socio' and m.estado = 'activo' and m.id <> v_yo loop
    perform notificar(p_grupo, s.usuario_id, 'dano_abierto', 'Nuevo caso de daño', trim(p_titulo), jsonb_build_object('caso_id', v_id), false);
  end loop;
  return v_id;
end $$;

-- Propuesta de reparto: presupuesto + quién adelanta + [{miembro_id, monto}]. Reinicia los acuerdos (versión nueva).
create function dano_proponer(
  p_caso uuid, p_presupuesto numeric, p_moneda text, p_pagado_tipo text, p_pagado_miembro uuid, p_propuesta jsonb, p_tasa numeric default null
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare c danos_casos; v_yo uuid; v_suma numeric; e jsonb; v_n int; s record;
begin
  select * into c from danos_casos where id = p_caso for update;
  if not found then raise exception 'caso_no_existe' using errcode = 'no_data_found'; end if;
  v_yo := miembro_actual(c.grupo_id);
  if v_yo is null or not es_socio(c.grupo_id) then
    raise exception 'solo_socios' using errcode = 'insufficient_privilege';
  end if;
  if c.estado = 'acordado' then
    raise exception 'estado_invalido: el caso ya está acordado' using errcode = 'check_violation';
  end if;
  if p_presupuesto is null or p_presupuesto <= 0 or p_moneda !~ '^[A-Z]{3}$' then
    raise exception 'presupuesto_invalido' using errcode = 'check_violation';
  end if;
  if jsonb_typeof(p_propuesta) <> 'array' or jsonb_array_length(p_propuesta) = 0 then
    raise exception 'propuesta_invalida: indica cuánto corresponde a cada socio' using errcode = 'check_violation';
  end if;
  v_suma := 0;
  for e in select * from jsonb_array_elements(p_propuesta) loop
    if not exists (select 1 from miembros where id = (e ->> 'miembro_id')::uuid and grupo_id = c.grupo_id and rol = 'socio' and estado = 'activo') then
      raise exception 'propuesta_invalida: % no es socio activo', e ->> 'miembro_id' using errcode = 'check_violation';
    end if;
    if coalesce((e ->> 'monto')::numeric, -1) <= 0 then
      raise exception 'propuesta_invalida: los montos deben ser mayores que cero' using errcode = 'check_violation';
    end if;
    v_suma := v_suma + (e ->> 'monto')::numeric;
  end loop;
  if round(v_suma, 2) <> round(p_presupuesto, 2) then
    raise exception 'propuesta_descuadrada: el reparto suma % y el presupuesto es %', v_suma, p_presupuesto using errcode = 'check_violation';
  end if;
  if p_pagado_tipo = 'miembro' and not exists (
       select 1 from miembros where id = p_pagado_miembro and grupo_id = c.grupo_id and estado = 'activo') then
    raise exception 'pagador_invalido' using errcode = 'check_violation';
  end if;
  if p_pagado_tipo not in ('miembro', 'fondo', 'externo') then
    raise exception 'pagador_invalido' using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'propuesta de reparto de daño', true);
  update danos_casos
     set presupuesto = round(p_presupuesto, 2), moneda = p_moneda, tasa = p_tasa, pagado_por_tipo = p_pagado_tipo,
         pagado_por_miembro = case when p_pagado_tipo = 'miembro' then p_pagado_miembro end,
         propuesta = p_propuesta, version = c.version + 1, estado = 'en_revision', resuelto_en = null
   where id = c.id;
  insert into danos_mensajes (grupo_id, caso_id, autor_id, tipo, texto)
  values (c.grupo_id, c.id, v_yo, 'propuesta', 'Propuesta de reparto (versión ' || (c.version + 1) || '): presupuesto ' || round(p_presupuesto, 2) || ' ' || p_moneda);
  for s in select m.usuario_id from miembros m where m.grupo_id = c.grupo_id and m.rol = 'socio' and m.estado = 'activo' and m.id <> v_yo loop
    perform notificar(c.grupo_id, s.usuario_id, 'dano_propuesta', 'Propuesta de reparto de daño', c.titulo, jsonb_build_object('caso_id', c.id), false);
  end loop;
  -- quien propone está de acuerdo con su propia propuesta
  perform dano_responder_interno(c.id, v_yo, true, 'Propone el reparto');
end $$;

create function dano_responder_interno(p_caso uuid, p_miembro uuid, p_acepta boolean, p_nota text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c danos_casos; v_faltan int; v_cv record; v_gasto uuid; v_as uuid := gen_random_uuid(); e record; v_cat text := 'daño';
begin
  select * into c from danos_casos where id = p_caso for update;
  insert into danos_acuerdos (caso_id, version, miembro_id, grupo_id, acepta, nota)
  values (c.id, c.version, p_miembro, c.grupo_id, p_acepta, left(p_nota, 300))
  on conflict (caso_id, version, miembro_id) do update set acepta = excluded.acepta, nota = excluded.nota, creado_en = now();
  if not p_acepta then
    update danos_casos set estado = 'rechazado', resuelto_en = now() where id = c.id;
    insert into danos_mensajes (grupo_id, caso_id, autor_id, tipo, texto) values (c.grupo_id, c.id, p_miembro, 'rechazo', coalesce(p_nota, 'Rechaza la propuesta'));
    return;
  end if;
  select count(*) into v_faltan from miembros m
   where m.grupo_id = c.grupo_id and m.rol = 'socio' and m.estado = 'activo'
     and not exists (select 1 from danos_acuerdos a where a.caso_id = c.id and a.version = c.version and a.miembro_id = m.id and a.acepta);
  insert into danos_mensajes (grupo_id, caso_id, autor_id, tipo, texto) values (c.grupo_id, c.id, p_miembro, 'acuerdo', coalesce(p_nota, 'Acepta la propuesta'));
  if v_faltan > 0 then return; end if;

  -- todos los socios aceptaron: recién ahora se crea el cargo (DF-11)
  select * into v_cv from convertir_a_grupo(c.grupo_id, c.presupuesto, c.moneda, c.tasa, current_date);
  insert into gastos (grupo_id, alcance, categoria, descripcion, monto, moneda, tasa, monto_grupo, moneda_grupo,
                      pagado_por_tipo, pagado_por_miembro, reserva_id, operacion_id, caso_dano_id, estado, cargado_por, validado_en, motivo_estado)
  values (c.grupo_id, 'dano', v_cat, left(c.titulo, 500), c.presupuesto, c.moneda, v_cv.tasa, v_cv.monto_grupo, v_cv.moneda_grupo,
          c.pagado_por_tipo, c.pagado_por_miembro, c.reserva_id, c.operacion_id, c.id, 'validado', c.abierto_por, now(), 'Acordado entre todos los socios')
  returning id into v_gasto;
  perform lm_credito_pagador(v_as, c.grupo_id, c.pagado_por_tipo, c.pagado_por_miembro, v_cv.monto_grupo, v_cv.moneda_grupo,
                             c.presupuesto, c.moneda, v_cv.tasa, 'dano', c.id, 'Daño: ' || c.titulo);
  for e in select * from repartir_pesos(
             v_cv.monto_grupo,
             (select array_agg((x ->> 'miembro_id')::uuid order by x ->> 'miembro_id') from jsonb_array_elements(c.propuesta) x),
             (select array_agg((x ->> 'monto')::numeric order by x ->> 'miembro_id') from jsonb_array_elements(c.propuesta) x)) loop
    perform lm_linea(v_as, c.grupo_id, 'miembro', e.id, e.monto, 0, v_cv.moneda_grupo, c.presupuesto, c.moneda, v_cv.tasa, 'dano', c.id, 'Daño acordado: ' || c.titulo);
  end loop;
  update danos_casos set estado = 'acordado', resuelto_en = now() where id = c.id;
  insert into danos_mensajes (grupo_id, caso_id, tipo, texto) values (c.grupo_id, c.id, 'sistema', 'Acuerdo completo: se registraron los cargos según lo acordado.');
end $$;
revoke execute on function dano_responder_interno(uuid, uuid, boolean, text) from public, anon, authenticated;

create function dano_responder(p_caso uuid, p_acepta boolean, p_nota text default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare c danos_casos; v_yo uuid;
begin
  select * into c from danos_casos where id = p_caso;
  if not found then raise exception 'caso_no_existe' using errcode = 'no_data_found'; end if;
  v_yo := miembro_actual(c.grupo_id);
  if v_yo is null or not es_socio(c.grupo_id) then
    raise exception 'solo_socios' using errcode = 'insufficient_privilege';
  end if;
  if c.estado <> 'en_revision' or c.presupuesto is null then
    raise exception 'estado_invalido: no hay una propuesta pendiente de respuesta' using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'respuesta a propuesta de daño', true);
  perform dano_responder_interno(p_caso, v_yo, p_acepta, p_nota);
end $$;

create function dano_mensaje(p_caso uuid, p_texto text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare c danos_casos; v_yo uuid;
begin
  select * into c from danos_casos where id = p_caso;
  v_yo := case when c.id is null then null else miembro_actual(c.grupo_id) end;
  if v_yo is null or not coalesce(rol_en(c.grupo_id) in ('socio', 'admin_operativo'), false) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(length(trim(p_texto)), 0) < 1 then raise exception 'texto_requerido' using errcode = 'check_violation'; end if;
  insert into danos_mensajes (grupo_id, caso_id, autor_id, tipo, texto) values (c.grupo_id, c.id, v_yo, 'mensaje', left(p_texto, 1000));
end $$;

-- ---------------------------------------------------------------- fondo común (SA32, DF-24)
-- Aporte mensual del grupo (0 = apagado), repartido por porcentaje. Idempotente por periodo.
create function fondo_generar_aportes(p_grupo uuid, p_periodo date default (date_trunc('month', current_date))::date)
returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_monto numeric := coalesce(pol_txt(p_grupo, 'fondo.aporte_mensual')::numeric, 0); v_mon char(3); s record; v_n int := 0; v_id uuid; v_as uuid;
begin
  if v_monto <= 0 or exists (select 1 from fondo_aportes where grupo_id = p_grupo and periodo = p_periodo) then
    return 0;
  end if;
  select moneda into v_mon from grupos where id = p_grupo;
  for s in select * from repartir_por_porcentaje(p_grupo, v_monto) loop
    insert into fondo_aportes (grupo_id, periodo, miembro_id, monto, moneda) values (p_grupo, p_periodo, s.miembro_id, s.monto, v_mon)
    returning id into v_id;
    v_as := gen_random_uuid();
    perform lm_linea(v_as, p_grupo, 'miembro', s.miembro_id, s.monto, 0, v_mon, s.monto, v_mon, 1, 'aporte', v_id, 'Aporte mensual al fondo ' || to_char(p_periodo, 'YYYY-MM'));
    perform lm_linea(v_as, p_grupo, 'fondo', null, 0, s.monto, v_mon, s.monto, v_mon, 1, 'aporte', v_id, 'Aporte mensual ' || to_char(p_periodo, 'YYYY-MM'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
revoke execute on function fondo_generar_aportes(uuid, date) from public, anon, authenticated;

create function fondo_aportes_automaticos() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare g record; v_n int := 0;
begin
  for g in select id from grupos where estado = 'activo' loop
    v_n := v_n + fondo_generar_aportes(g.id);
  end loop;
  return v_n;
end $$;
revoke execute on function fondo_aportes_automaticos() from public, anon, authenticated;

-- Un socio también puede generarlo a mano.
create function fondo_generar_aportes_manual(p_grupo uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not es_socio(p_grupo) then raise exception 'solo_socios' using errcode = 'insufficient_privilege'; end if;
  perform set_config('app.motivo', 'aportes del fondo generados', true);
  return fondo_generar_aportes(p_grupo);
end $$;

-- ---------------------------------------------------------------- liquidación (SA2 paso 5)
create function liquidar_operacion(p_operacion uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  o operaciones; r reservas; v_modelo text; v_fee numeric := 0; v_mon char(3); v_cv record; v_dest text := 'informativo';
  v_resumen jsonb; v_horas jsonb; v_ind numeric; v_cod text; v_cons numeric; v_id uuid;
begin
  select * into o from operaciones where id = p_operacion;
  if exists (select 1 from liquidaciones where operacion_id = p_operacion) then
    return (select to_jsonb(l) from liquidaciones l where l.operacion_id = p_operacion);
  end if;
  select * into r from reservas where id = o.reserva_id;
  v_modelo := pol_txt(o.grupo_id, 'tarifa.modelo');
  if v_modelo in ('hora', 'ambos') then
    select f.monto, f.moneda into v_fee, v_mon from fee_calc(o.grupo_id, coalesce(o.destino_id, r.destino_id),
      o.salida_real, coalesce(o.regreso_real, now())) f;
  else
    select c.fee, c.moneda into v_fee, v_mon from reserva_costos c where c.reserva_id = r.id;
    if v_fee is null then
      select f.monto, f.moneda into v_fee, v_mon from fee_calc(o.grupo_id, coalesce(o.destino_id, r.destino_id), lower(r.rango), upper(r.rango)) f;
    end if;
  end if;
  select codigo into v_cod from ordenes where reserva_id = r.id;
  if coalesce(v_fee, 0) > 0 then
    select * into v_cv from convertir_a_grupo(o.grupo_id, v_fee, v_mon, null, current_date);
    v_id := gen_random_uuid();
    v_dest := asentar_fee(o.grupo_id, r.reservado_por, v_cv.monto_grupo, v_cv.moneda_grupo, v_fee, v_mon, v_cv.tasa, 'fee', v_id,
                          'Fee del destino · ' || coalesce(v_cod, ''));
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'componente_id', c.id, 'etiqueta', c.etiqueta, 'unidad', c.unidad,
           'inicio', i.valor, 'fin', f.valor, 'horas', f.valor - i.valor) order by c.clave, c.indice), '[]'::jsonb)
    into v_horas
    from activo_componentes c
    join lecturas_vigentes i on i.componente_id = c.id and i.operacion_id = o.id and i.momento = 'inicio'
    join lecturas_vigentes f on f.componente_id = c.id and f.operacion_id = o.id and f.momento = 'fin'
   where c.activo_id = o.activo_id;
  select coalesce(sum(monto_grupo), 0) into v_ind from gastos
   where reserva_id = r.id and alcance = 'individual' and estado <> 'anulado';
  select cantidad into v_cons from combustible_registros where operacion_id = o.id and tipo = 'consumido' order by creado_en desc limit 1;
  v_resumen := jsonb_build_object('orden', v_cod, 'horas_por_componente', v_horas, 'combustible_consumido', v_cons,
                                  'gastos_individuales', v_ind, 'fee', coalesce(v_fee, 0), 'fee_destino_a', v_dest);
  insert into liquidaciones (id, grupo_id, operacion_id, reserva_id, miembro_id, fee_monto, fee_moneda, fee_destino, resumen)
  values (coalesce(v_id, gen_random_uuid()), o.grupo_id, o.id, r.id, r.reservado_por, coalesce(v_fee, 0), v_mon, v_dest, v_resumen)
  returning id into v_id;
  return v_resumen;
end $$;
revoke execute on function liquidar_operacion(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- lecturas del estado de cuenta
create function balances_grupo(p_grupo uuid)
returns table (cuenta_tipo text, miembro_id uuid, nombre text, rol rol_miembro, moneda char(3), confirmado numeric, provisional numeric, balance numeric)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not es_socio(p_grupo) then
    raise exception 'solo_socios' using errcode = 'insufficient_privilege';
  end if;
  return query
  with monedas as (
    select gr.moneda as mon from grupos gr where gr.id = p_grupo
    union select lm.moneda from libro_mayor lm where lm.grupo_id = p_grupo),
  l as (
    select lm.cuenta_tipo as ct, lm.miembro_id as mid, lm.moneda as mon, lm.haber - lm.debe as neto,
           (lm.origen_tipo in ('gasto', 'gasto_anulado')
            and exists (select 1 from gastos g where g.id = lm.origen_id and g.estado in ('registrado', 'disputado'))) as prov
      from libro_mayor lm where lm.grupo_id = p_grupo),
  agg as (
    select ct, mid, mon, sum(case when not prov then neto else 0 end) as conf, sum(case when prov then neto else 0 end) as pro
      from l group by ct, mid, mon),
  cuentas as (
    select 'miembro'::text as ct, m.id as mid from miembros m
     where m.grupo_id = p_grupo and m.estado = 'activo' and m.rol in ('socio', 'admin_operativo')
    union all select 'fondo', null::uuid
    union all select 'externo', null::uuid where exists (select 1 from libro_mayor lm where lm.grupo_id = p_grupo and lm.cuenta_tipo = 'externo'))
  select c.ct, c.mid, coalesce(pf.nombre, pf.correo::text, case c.ct when 'fondo' then 'Fondo común' else 'Externo' end),
         m.rol, mo.mon, coalesce(a.conf, 0), coalesce(a.pro, 0), coalesce(a.conf, 0) + coalesce(a.pro, 0)
    from cuentas c cross join monedas mo
    left join agg a on a.ct = c.ct and a.mid is not distinct from c.mid and a.mon = mo.mon
    left join miembros m on m.id = c.mid
    left join perfiles pf on pf.id = m.usuario_id
   order by c.ct, 3, mo.mon;
end $$;

create function estado_cuenta(p_miembro uuid, p_desde date default null, p_hasta date default null)
returns table (
  id bigint, momento timestamptz, origen_tipo text, origen_id uuid, nota text, debe numeric, haber numeric,
  monto_original numeric, moneda_original char(3), tasa numeric, moneda char(3), provisional boolean, saldo numeric, comprobantes int)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_grupo uuid;
begin
  select m.grupo_id into v_grupo from miembros m where m.id = p_miembro;
  if v_grupo is null or not es_socio(v_grupo) then
    raise exception 'solo_socios' using errcode = 'insufficient_privilege';
  end if;
  return query
  select t.* from (
    select lm.id, lm.momento, lm.origen_tipo, lm.origen_id, lm.nota, lm.debe, lm.haber,
           lm.monto_original, lm.moneda_original, lm.tasa, lm.moneda,
           (lm.origen_tipo in ('gasto', 'gasto_anulado')
            and exists (select 1 from gastos g where g.id = lm.origen_id and g.estado in ('registrado', 'disputado'))) as provisional,
           sum(lm.haber - lm.debe) over (partition by lm.moneda order by lm.id) as saldo,
           (select count(*)::int from evidencias e
             where e.ref_id = lm.origen_id
               and e.ref_tipo = case lm.origen_tipo when 'gasto' then 'gasto' when 'gasto_anulado' then 'gasto' when 'pago' then 'pago' when 'dano' then 'dano' else '-' end) as comprobantes
      from libro_mayor lm where lm.miembro_id = p_miembro and lm.cuenta_tipo = 'miembro') t
   where (p_desde is null or t.momento::date >= p_desde) and (p_hasta is null or t.momento::date <= p_hasta)
   order by t.id;
end $$;

-- ---------------------------------------------------------------- vistas
create view cargos with (security_invoker = true) as
select lm.id, lm.grupo_id, lm.momento, lm.miembro_id, lm.debe as monto, lm.moneda, lm.origen_tipo, lm.origen_id,
       lm.nota, lm.monto_original, lm.moneda_original, lm.tasa
  from libro_mayor lm
 where lm.cuenta_tipo = 'miembro' and lm.debe > 0 and lm.origen_tipo not in ('pago', 'gasto_anulado');

create view fondo_movimientos with (security_invoker = true) as
select lm.id, lm.grupo_id, lm.momento, lm.debe, lm.haber, lm.moneda, lm.origen_tipo, lm.origen_id, lm.nota
  from libro_mayor lm where lm.cuenta_tipo = 'fondo';

-- ---------------------------------------------------------------- RLS (finanzas solo `socio`; el admin operativo ve lo que registró)
alter table libro_mayor enable row level security;
alter table gastos enable row level security;
alter table pagos enable row level security;
alter table fondo_aportes enable row level security;
alter table liquidaciones enable row level security;
alter table danos_casos enable row level security;
alter table danos_acuerdos enable row level security;
alter table danos_mensajes enable row level security;

revoke all on libro_mayor, gastos, pagos, fondo_aportes, liquidaciones, danos_casos, danos_acuerdos, danos_mensajes from anon, authenticated;
grant select on libro_mayor, gastos, pagos, fondo_aportes, liquidaciones, danos_casos, danos_acuerdos, danos_mensajes to authenticated;
grant select on cargos, fondo_movimientos to authenticated;

create policy libro_select on libro_mayor for select to authenticated using (es_socio(grupo_id));
create policy gastos_select on gastos for select to authenticated using (
  es_socio(grupo_id) or (coalesce(rol_en(grupo_id) = 'admin_operativo', false) and es_miembro_id(cargado_por)));
create policy pagos_select on pagos for select to authenticated using (es_socio(grupo_id));
create policy fondo_aportes_select on fondo_aportes for select to authenticated using (es_socio(grupo_id));
create policy liquidaciones_select on liquidaciones for select to authenticated using (es_socio(grupo_id));
create policy danos_casos_select on danos_casos for select to authenticated using (
  es_socio(grupo_id) or (coalesce(rol_en(grupo_id) = 'admin_operativo', false) and es_miembro_id(abierto_por)));
create policy danos_acuerdos_select on danos_acuerdos for select to authenticated using (es_socio(grupo_id));
create policy danos_mensajes_select on danos_mensajes for select to authenticated using (
  es_socio(grupo_id) or (coalesce(rol_en(grupo_id) = 'admin_operativo', false)
    and exists (select 1 from danos_casos d where d.id = caso_id and es_miembro_id(d.abierto_por))));

revoke execute on function gasto_registrar(uuid, text, text, numeric, text, text, uuid, text, text, uuid, date, date, numeric),
  gasto_validar(uuid), gasto_disputar(uuid, text), gasto_anular(uuid, text),
  pago_registrar(uuid, uuid, numeric, text, text, numeric), pago_confirmar(uuid), pago_rechazar(uuid, text),
  dano_abrir(uuid, text, text, uuid, uuid), dano_proponer(uuid, numeric, text, text, uuid, jsonb, numeric),
  dano_responder(uuid, boolean, text), dano_mensaje(uuid, text), fondo_generar_aportes_manual(uuid),
  balances_grupo(uuid), estado_cuenta(uuid, date, date) from public, anon;
grant execute on function gasto_registrar(uuid, text, text, numeric, text, text, uuid, text, text, uuid, date, date, numeric),
  gasto_validar(uuid), gasto_disputar(uuid, text), gasto_anular(uuid, text),
  pago_registrar(uuid, uuid, numeric, text, text, numeric), pago_confirmar(uuid), pago_rechazar(uuid, text),
  dano_abrir(uuid, text, text, uuid, uuid), dano_proponer(uuid, numeric, text, text, uuid, jsonb, numeric),
  dano_responder(uuid, boolean, text), dano_mensaje(uuid, text), fondo_generar_aportes_manual(uuid),
  balances_grupo(uuid), estado_cuenta(uuid, date, date) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table gastos, pagos, danos_casos, danos_mensajes;
  end if;
end $$;
