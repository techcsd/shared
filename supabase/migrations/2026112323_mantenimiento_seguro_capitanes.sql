-- 2026-11-24 · 23 · Mantenimiento (SA26), seguro y siniestros (SA29), capitanes y licencias (SA28), alertas (P4·F1–F3)

-- ---------------------------------------------------------------- utilidades: alertas una sola vez y aviso al equipo
create table alertas_emitidas (
  clave text primary key,
  creado_en timestamptz not null default now()
);
alter table alertas_emitidas enable row level security;
revoke all on alertas_emitidas from anon, authenticated;

create function alerta_una_vez(p_clave text) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into alertas_emitidas (clave) values (p_clave) on conflict do nothing;
  return found;
end $$;
revoke execute on function alerta_una_vez(text) from public, anon, authenticated;

-- Aviso in-app a los socios y al administrador operativo activos del grupo.
create function avisar_equipo(p_grupo uuid, p_tipo text, p_titulo text, p_cuerpo text, p_datos jsonb default '{}'::jsonb, p_solo_socios boolean default false)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare s record;
begin
  for s in select usuario_id from miembros
            where grupo_id = p_grupo and estado = 'activo'
              and (rol = 'socio' or (not p_solo_socios and rol = 'admin_operativo')) loop
    perform notificar(p_grupo, s.usuario_id, p_tipo, p_titulo, p_cuerpo, p_datos, false);
  end loop;
end $$;
revoke execute on function avisar_equipo(uuid, text, text, text, jsonb, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------- evidencias: más tipos de referencia
alter table evidencias drop constraint evidencias_ref_tipo_check;
alter table evidencias add constraint evidencias_ref_tipo_check
  check (ref_tipo in ('operacion', 'incidencia', 'gasto', 'pago', 'dano', 'poliza', 'siniestro', 'servicio', 'licencia', 'salida_socio', 'disputa'));

create or replace function evidencia_registrar(p_grupo uuid, p_ref_tipo text, p_ref_id uuid, p_ruta text, p_tipo text default 'foto', p_mime text default null)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_yo uuid := miembro_actual(p_grupo); v_id uuid;
begin
  if v_yo is null then raise exception 'sin_permiso' using errcode = 'insufficient_privilege'; end if;
  if p_ref_tipo in ('gasto', 'pago', 'dano', 'poliza', 'siniestro', 'servicio', 'licencia')
     and not coalesce(rol_en(p_grupo) in ('socio', 'admin_operativo'), false) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  if p_ref_tipo in ('salida_socio', 'disputa') and not es_socio(p_grupo) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  if position(p_grupo::text || '/' in p_ruta) <> 1 then
    raise exception 'ruta_invalida: la ruta debe empezar por el grupo' using errcode = 'check_violation';
  end if;
  insert into evidencias (grupo_id, ref_tipo, ref_id, tipo, ruta, mime, creado_por)
  values (p_grupo, p_ref_tipo, p_ref_id, p_tipo, p_ruta, p_mime, v_yo) returning id into v_id;
  return v_id;
end $$;

drop policy evidencias_select on evidencias;
create policy evidencias_select on evidencias for select to authenticated using (
  case when ref_tipo in ('operacion', 'incidencia', 'poliza', 'siniestro', 'servicio', 'licencia') then es_miembro(grupo_id)
       else es_socio(grupo_id) or es_miembro_id(creado_por) end);

-- ---------------------------------------------------------------- capitanes (SA28, DF-20)
create table capitanes (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  miembro_id uuid references miembros (id),
  nombre text not null check (length(trim(nombre)) between 2 and 120),
  licencia_numero text check (licencia_numero is null or length(licencia_numero) <= 60),
  licencia_vence date,
  experiencia_anios numeric(4, 1) check (experiencia_anios is null or experiencia_anios >= 0),
  experiencia_notas text check (experiencia_notas is null or length(experiencia_notas) <= 500),
  estado text not null default 'activo' check (estado in ('activo', 'inactivo')),
  creado_en timestamptz not null default now()
);
create index capitanes_grupo_idx on capitanes (grupo_id);
create trigger capitanes_auditar after insert or update or delete on capitanes for each row execute function auditar();

-- Reemplaza el gancho de P3: hay un capitán activo, con licencia vigente a la fecha, que es la persona indicada.
create or replace function capitan_licencia_ok(p_grupo uuid, p_miembro uuid, p_nombre text, p_fecha date) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from capitanes c
     where c.grupo_id = p_grupo and c.estado = 'activo'
       and c.licencia_vence is not null and c.licencia_vence >= p_fecha
       and ((p_miembro is not null and c.miembro_id = p_miembro)
         or (p_nombre is not null and lower(trim(c.nombre)) = lower(trim(p_nombre)))))
$$;

create function capitan_guardar(
  p_grupo uuid, p_id uuid, p_nombre text, p_miembro uuid, p_licencia text, p_vence date, p_anios numeric, p_notas text, p_estado text default 'activo'
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid;
begin
  if not coalesce(rol_en(p_grupo) in ('socio', 'admin_operativo'), false) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  if p_miembro is not null and not exists (select 1 from miembros where id = p_miembro and grupo_id = p_grupo) then
    raise exception 'capitan_invalido' using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'registro de capitán', true);
  if p_id is null then
    insert into capitanes (grupo_id, miembro_id, nombre, licencia_numero, licencia_vence, experiencia_anios, experiencia_notas, estado)
    values (p_grupo, p_miembro, trim(p_nombre), p_licencia, p_vence, p_anios, left(p_notas, 500), p_estado) returning id into v_id;
  else
    update capitanes set miembro_id = p_miembro, nombre = trim(p_nombre), licencia_numero = p_licencia, licencia_vence = p_vence,
           experiencia_anios = p_anios, experiencia_notas = left(p_notas, 500), estado = p_estado
     where id = p_id and grupo_id = p_grupo returning id into v_id;
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------- seguro y siniestros (SA29, DF-21)
create table polizas_seguro (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  activo_id uuid not null references activos (id) on delete cascade,
  aseguradora text not null check (length(trim(aseguradora)) between 2 and 120),
  numero text check (numero is null or length(numero) <= 60),
  cobertura text check (cobertura is null or length(cobertura) <= 1000),
  vigente_desde date not null,
  vigente_hasta date not null,
  deducible numeric(14, 2) not null default 0 check (deducible >= 0),
  moneda char(3) not null check (moneda ~ '^[A-Z]{3}$'),
  creado_en timestamptz not null default now(),
  check (vigente_hasta >= vigente_desde)
);
create index polizas_activo_idx on polizas_seguro (activo_id, vigente_hasta desc);
create trigger polizas_auditar after insert or update or delete on polizas_seguro for each row execute function auditar();

create table siniestros (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  activo_id uuid not null references activos (id) on delete cascade,
  poliza_id uuid references polizas_seguro (id),
  operacion_id uuid references operaciones (id),
  fecha date not null default current_date,
  descripcion text not null check (length(trim(descripcion)) between 3 and 2000),
  estado text not null default 'abierto' check (estado in ('abierto', 'en_proceso', 'cerrado')),
  caso_dano_id uuid references danos_casos (id),
  creado_por uuid not null references miembros (id),
  creado_en timestamptz not null default now()
);
create index siniestros_grupo_idx on siniestros (grupo_id, estado);
create trigger siniestros_auditar after insert or update or delete on siniestros for each row execute function auditar();

create function poliza_guardar(
  p_grupo uuid, p_id uuid, p_activo uuid, p_aseguradora text, p_numero text, p_cobertura text,
  p_desde date, p_hasta date, p_deducible numeric, p_moneda text
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid;
begin
  if not es_socio(p_grupo) then raise exception 'solo_socios' using errcode = 'insufficient_privilege'; end if;
  if not exists (select 1 from activos where id = p_activo and grupo_id = p_grupo) then
    raise exception 'activo_no_existe' using errcode = 'no_data_found';
  end if;
  perform set_config('app.motivo', 'póliza de seguro', true);
  if p_id is null then
    insert into polizas_seguro (grupo_id, activo_id, aseguradora, numero, cobertura, vigente_desde, vigente_hasta, deducible, moneda)
    values (p_grupo, p_activo, trim(p_aseguradora), p_numero, left(p_cobertura, 1000), p_desde, p_hasta, coalesce(p_deducible, 0), upper(p_moneda))
    returning id into v_id;
  else
    update polizas_seguro set aseguradora = trim(p_aseguradora), numero = p_numero, cobertura = left(p_cobertura, 1000),
           vigente_desde = p_desde, vigente_hasta = p_hasta, deducible = coalesce(p_deducible, 0), moneda = upper(p_moneda)
     where id = p_id and grupo_id = p_grupo returning id into v_id;
  end if;
  return v_id;
end $$;

create function activo_poliza_vigente(p_activo uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from polizas_seguro p where p.activo_id = p_activo and current_date between p.vigente_desde and p.vigente_hasta
                   and es_miembro(p.grupo_id))
$$;

-- El deducible entra al flujo de daños (acuerdo entre socios, nunca automático).
create function siniestro_abrir(p_grupo uuid, p_activo uuid, p_descripcion text, p_operacion uuid default null)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_yo uuid := miembro_actual(p_grupo); v_pol polizas_seguro; v_id uuid; v_caso uuid;
begin
  if v_yo is null or not coalesce(rol_en(p_grupo) in ('socio', 'admin_operativo'), false) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  select * into v_pol from polizas_seguro
   where activo_id = p_activo and grupo_id = p_grupo and current_date between vigente_desde and vigente_hasta
   order by vigente_hasta desc limit 1;
  perform set_config('app.motivo', 'siniestro abierto', true);
  insert into siniestros (grupo_id, activo_id, poliza_id, operacion_id, descripcion, creado_por)
  values (p_grupo, p_activo, v_pol.id, p_operacion, trim(p_descripcion), v_yo) returning id into v_id;
  if v_pol.id is not null and v_pol.deducible > 0 then
    v_caso := dano_abrir(p_grupo, 'Deducible del siniestro', left(p_descripcion, 2000), null, null);
    update danos_casos set siniestro_id = v_id where id = v_caso;
    update siniestros set caso_dano_id = v_caso where id = v_id;
  end if;
  perform avisar_equipo(p_grupo, 'siniestro_abierto', 'Siniestro registrado', left(p_descripcion, 200), jsonb_build_object('siniestro_id', v_id), true);
  return v_id;
end $$;

create function siniestro_estado(p_siniestro uuid, p_estado text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare g uuid;
begin
  select grupo_id into g from siniestros where id = p_siniestro;
  if g is null or not es_socio(g) then raise exception 'solo_socios' using errcode = 'insufficient_privilege'; end if;
  if p_estado not in ('abierto', 'en_proceso', 'cerrado') then raise exception 'estado_invalido' using errcode = 'check_violation'; end if;
  perform set_config('app.motivo', 'cambio de estado del siniestro', true);
  update siniestros set estado = p_estado where id = p_siniestro;
end $$;

-- ---------------------------------------------------------------- mantenimiento (SA26, DF-13)
create table mantenimiento_planes (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  activo_id uuid not null references activos (id) on delete cascade,
  componente_id uuid references activo_componentes (id) on delete cascade,
  nombre text not null check (length(trim(nombre)) between 2 and 120),
  criterio text check (criterio is null or criterio in ('fecha', 'horas', 'primero')),   -- null = el de la política del grupo
  intervalo_dias int check (intervalo_dias is null or intervalo_dias > 0),
  intervalo_horas numeric(10, 1) check (intervalo_horas is null or intervalo_horas > 0),
  ultima_fecha date not null default current_date,
  ultima_lectura numeric(12, 1) not null default 0 check (ultima_lectura >= 0),
  alerta_dias int not null default 7 check (alerta_dias >= 0),
  alerta_horas numeric(10, 1) not null default 10 check (alerta_horas >= 0),
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  constraint plan_horas_con_componente check (intervalo_horas is null or componente_id is not null),
  constraint plan_con_intervalo check (intervalo_dias is not null or intervalo_horas is not null)
);
create index planes_grupo_idx on mantenimiento_planes (grupo_id, activo);
create trigger planes_auditar after insert or update or delete on mantenimiento_planes for each row execute function auditar();

create table mantenimiento_tareas (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  plan_id uuid references mantenimiento_planes (id) on delete set null,
  activo_id uuid not null references activos (id) on delete cascade,
  componente_id uuid references activo_componentes (id),
  titulo text not null check (length(trim(titulo)) between 2 and 160),
  estado text not null default 'pendiente' check (estado in ('pendiente', 'programada', 'hecha', 'cancelada')),
  vence_fecha date,
  vence_horas numeric(12, 1),
  proveedor text check (proveedor is null or length(proveedor) <= 120),
  notas text check (notas is null or length(notas) <= 1000),
  bloqueo_reserva_id uuid references reservas (id) on delete set null,
  creado_por uuid references miembros (id),
  creado_en timestamptz not null default now()
);
create index tareas_grupo_idx on mantenimiento_tareas (grupo_id, estado);
create trigger tareas_auditar after insert or update or delete on mantenimiento_tareas for each row execute function auditar();

create table servicios (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  activo_id uuid not null references activos (id) on delete cascade,
  componente_id uuid references activo_componentes (id),
  tarea_id uuid references mantenimiento_tareas (id) on delete set null,
  plan_id uuid references mantenimiento_planes (id) on delete set null,
  fecha date not null default current_date,
  lectura numeric(12, 1) check (lectura is null or lectura >= 0),
  proveedor text check (proveedor is null or length(proveedor) <= 120),
  descripcion text check (descripcion is null or length(descripcion) <= 1000),
  costo numeric(14, 2) check (costo is null or costo >= 0),
  moneda char(3),
  gasto_id uuid references gastos (id),
  registrado_por uuid not null references miembros (id),
  creado_en timestamptz not null default now()
);
create index servicios_grupo_idx on servicios (grupo_id, fecha desc);
create trigger servicios_auditar after insert on servicios for each row execute function auditar();

-- Lectura más reciente del componente (la mayor registrada; si no hay, la de partida).
create function lectura_actual(p_componente uuid) returns numeric
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select max(valor) from lecturas_vigentes where componente_id = p_componente),
                  (select lectura_inicial from activo_componentes where id = p_componente), 0)
$$;
revoke execute on function lectura_actual(uuid) from public, anon;
grant execute on function lectura_actual(uuid) to authenticated;

-- Vencimiento de un plan con las lecturas reales (lo que ocurra primero / solo fecha / solo horas).
create function plan_estado(p_plan uuid)
returns table (criterio text, vence_fecha date, vence_horas numeric, lectura numeric, dias_restantes int, horas_restantes numeric,
               vencido boolean, por_vencer boolean, disparador text)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare p mantenimiento_planes; v_crit text; v_f date; v_h numeric; v_lec numeric; v_d int; v_hr numeric; v_vf boolean := false; v_vh boolean := false; v_pf boolean := false; v_ph boolean := false;
begin
  select * into p from mantenimiento_planes where id = p_plan;
  if not found then return; end if;
  v_crit := coalesce(p.criterio, pol_txt(p.grupo_id, 'mantenimiento.criterio'), 'primero');
  if p.intervalo_dias is not null and v_crit in ('fecha', 'primero') then
    v_f := p.ultima_fecha + p.intervalo_dias;
    v_d := v_f - current_date;
    v_vf := v_d <= 0;
    v_pf := v_d <= p.alerta_dias;
  end if;
  if p.intervalo_horas is not null and p.componente_id is not null and v_crit in ('horas', 'primero') then
    v_h := p.ultima_lectura + p.intervalo_horas;
    v_lec := lectura_actual(p.componente_id);
    v_hr := v_h - v_lec;
    v_vh := v_hr <= 0;
    v_ph := v_hr <= p.alerta_horas;
  end if;
  return query select v_crit, v_f, v_h, v_lec, v_d, v_hr, (v_vf or v_vh), (v_pf or v_ph),
    case when v_vh and not v_vf then 'horas' when v_vf and not v_vh then 'fecha' when v_vf and v_vh then 'ambos'
         when v_ph and not v_pf then 'horas' when v_pf then 'fecha' else null end;
end $$;
revoke execute on function plan_estado(uuid) from public, anon;
grant execute on function plan_estado(uuid) to authenticated;

create function plan_guardar(
  p_grupo uuid, p_id uuid, p_activo uuid, p_componente uuid, p_nombre text, p_criterio text,
  p_dias int, p_horas numeric, p_alerta_dias int default 7, p_alerta_horas numeric default 10, p_activo_flag boolean default true
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid;
begin
  if not es_socio(p_grupo) then raise exception 'solo_socios' using errcode = 'insufficient_privilege'; end if;
  if not exists (select 1 from activos where id = p_activo and grupo_id = p_grupo) then
    raise exception 'activo_no_existe' using errcode = 'no_data_found';
  end if;
  perform set_config('app.motivo', 'plan de mantenimiento', true);
  if p_id is null then
    insert into mantenimiento_planes (grupo_id, activo_id, componente_id, nombre, criterio, intervalo_dias, intervalo_horas,
                                      ultima_lectura, alerta_dias, alerta_horas)
    values (p_grupo, p_activo, p_componente, trim(p_nombre), nullif(p_criterio, ''), p_dias, p_horas,
            case when p_componente is not null then lectura_actual(p_componente) else 0 end, p_alerta_dias, p_alerta_horas)
    returning id into v_id;
  else
    update mantenimiento_planes set nombre = trim(p_nombre), criterio = nullif(p_criterio, ''), intervalo_dias = p_dias,
           intervalo_horas = p_horas, alerta_dias = p_alerta_dias, alerta_horas = p_alerta_horas, activo = p_activo_flag
     where id = p_id and grupo_id = p_grupo returning id into v_id;
  end if;
  return v_id;
end $$;

create function tarea_crear(p_grupo uuid, p_activo uuid, p_titulo text, p_componente uuid, p_vence_fecha date, p_vence_horas numeric, p_proveedor text, p_notas text default null)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_yo uuid := miembro_actual(p_grupo); v_id uuid;
begin
  if v_yo is null or not coalesce(rol_en(p_grupo) in ('socio', 'admin_operativo'), false) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from activos where id = p_activo and grupo_id = p_grupo) then
    raise exception 'activo_no_existe' using errcode = 'no_data_found';
  end if;
  perform set_config('app.motivo', 'tarea de mantenimiento', true);
  insert into mantenimiento_tareas (grupo_id, activo_id, componente_id, titulo, vence_fecha, vence_horas, proveedor, notas, creado_por)
  values (p_grupo, p_activo, p_componente, trim(p_titulo), p_vence_fecha, p_vence_horas, p_proveedor, left(p_notas, 1000), v_yo)
  returning id into v_id;
  return v_id;
end $$;

-- Bloqueo del calendario por una tarea. Si choca con reservas confirmadas NO cancela nada: avisa y propone fecha.
create function tarea_programar(p_tarea uuid, p_inicio timestamptz, p_fin timestamptz, p_motivo text default null)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  t mantenimiento_tareas; v_conf jsonb; v_ini timestamptz := p_inicio; v_fin timestamptz := p_fin; v_dur interval := p_fin - p_inicio;
  v_sig timestamptz; v_id uuid; i int := 0; v_ini0 timestamptz := p_inicio;
begin
  select * into t from mantenimiento_tareas where id = p_tarea for update;
  if not found then raise exception 'tarea_no_existe' using errcode = 'no_data_found'; end if;
  if not coalesce(rol_en(t.grupo_id) in ('socio', 'admin_operativo'), false) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  if p_inicio is null or p_fin is null or p_inicio >= p_fin then
    raise exception 'bloqueo_invalido' using errcode = 'check_violation';
  end if;
  if t.estado in ('hecha', 'cancelada') then
    raise exception 'estado_invalido' using errcode = 'check_violation';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('reserva_id', r.id, 'orden', o.codigo, 'inicio', lower(r.rango), 'fin', upper(r.rango)) order by lower(r.rango)), '[]'::jsonb)
    into v_conf
    from reservas r left join ordenes o on o.reserva_id = r.id
   where r.activo_id = t.activo_id and r.estado in ('confirmada', 'en_curso', 'bloqueada_mantenimiento')
     and r.rango_bloqueo && tstzrange(p_inicio, p_fin, '[)') and r.id is distinct from t.bloqueo_reserva_id;
  if jsonb_array_length(v_conf) > 0 then
    -- propuesta: el siguiente hueco libre de la misma duración
    loop
      i := i + 1;
      select max(upper(r.rango_bloqueo)) into v_sig from reservas r
       where r.activo_id = t.activo_id and r.estado in ('confirmada', 'en_curso', 'bloqueada_mantenimiento')
         and r.rango_bloqueo && tstzrange(v_ini, v_ini + v_dur, '[)');
      exit when v_sig is null or i > 50;
      v_ini := v_sig;
    end loop;
    return jsonb_build_object('ok', false, 'conflictos', v_conf, 'sugerida', jsonb_build_object('inicio', v_ini, 'fin', v_ini + v_dur));
  end if;
  if t.bloqueo_reserva_id is not null then
    perform bloqueo_quitar(t.bloqueo_reserva_id);
  end if;
  v_id := bloqueo_crear(t.activo_id, v_ini0, p_fin, 'mantenimiento', coalesce(nullif(trim(p_motivo), ''), t.titulo));
  update mantenimiento_tareas set bloqueo_reserva_id = v_id, estado = 'programada' where id = t.id;
  return jsonb_build_object('ok', true, 'bloqueo_id', v_id);
end $$;

create function servicio_registrar(
  p_grupo uuid, p_activo uuid, p_componente uuid, p_tarea uuid, p_plan uuid, p_fecha date, p_lectura numeric,
  p_proveedor text, p_descripcion text, p_costo numeric, p_moneda text, p_categoria text default 'mantenimiento',
  p_vencimiento date default null, p_pagado_tipo text default 'miembro', p_pagado_miembro uuid default null
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_yo uuid := miembro_actual(p_grupo); v_id uuid; v_gasto uuid; v_plan uuid := p_plan; v_lec numeric := p_lectura; v_fecha date := coalesce(p_fecha, current_date); t mantenimiento_tareas;
begin
  if v_yo is null or not coalesce(rol_en(p_grupo) in ('socio', 'admin_operativo'), false) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from activos where id = p_activo and grupo_id = p_grupo) then
    raise exception 'activo_no_existe' using errcode = 'no_data_found';
  end if;
  if p_tarea is not null then
    select * into t from mantenimiento_tareas where id = p_tarea and grupo_id = p_grupo for update;
    if not found then raise exception 'tarea_no_existe' using errcode = 'no_data_found'; end if;
    v_plan := coalesce(v_plan, t.plan_id);
  end if;
  if v_lec is null and p_componente is not null then v_lec := lectura_actual(p_componente); end if;
  if v_lec is not null and v_lec < 0 then raise exception 'valor_negativo' using errcode = 'check_violation'; end if;
  perform set_config('app.motivo', 'servicio de mantenimiento', true);
  if coalesce(p_costo, 0) > 0 then
    -- SA10: la factura del servicio es un gasto común (la valida otro socio, DF-12)
    v_gasto := gasto_crear_interno(p_grupo, v_yo, 'comun', coalesce(p_categoria, 'mantenimiento'), p_costo, upper(p_moneda),
      p_pagado_tipo, p_pagado_miembro, p_proveedor, left(coalesce(p_descripcion, 'Servicio de mantenimiento'), 500), null, v_fecha, p_vencimiento, null);
  end if;
  insert into servicios (grupo_id, activo_id, componente_id, tarea_id, plan_id, fecha, lectura, proveedor, descripcion, costo, moneda, gasto_id, registrado_por)
  values (p_grupo, p_activo, p_componente, p_tarea, v_plan, v_fecha, v_lec, p_proveedor, left(p_descripcion, 1000), p_costo, upper(p_moneda), v_gasto, v_yo)
  returning id into v_id;
  if p_tarea is not null then
    update mantenimiento_tareas set estado = 'hecha' where id = p_tarea;
  end if;
  if v_plan is not null then
    update mantenimiento_planes set ultima_fecha = v_fecha, ultima_lectura = coalesce(v_lec, ultima_lectura) where id = v_plan and grupo_id = p_grupo;
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------- evaluación periódica: mantenimiento, seguro, licencias, facturas
create function mantenimiento_evaluar() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  p record; st record; n int := 0; v_nivel text; v_clave text; pol record; d int; c record; g record; v_dias jsonb; v_txt text; v_t uuid; v_umbral int;
begin
  for p in select * from mantenimiento_planes where activo loop
    select * into st from plan_estado(p.id);
    if st.vencido or st.por_vencer then
      v_nivel := case when st.vencido then 'vencido' else 'por_vencer' end;
      v_clave := 'plan:' || p.id || ':' || v_nivel || ':' || coalesce(st.vence_fecha::text, '') || ':' || coalesce(st.vence_horas::text, '');
      if alerta_una_vez(v_clave) then
        if not exists (select 1 from mantenimiento_tareas where plan_id = p.id and estado in ('pendiente', 'programada')) then
          insert into mantenimiento_tareas (grupo_id, plan_id, activo_id, componente_id, titulo, vence_fecha, vence_horas)
          values (p.grupo_id, p.id, p.activo_id, p.componente_id, p.nombre, st.vence_fecha, st.vence_horas);
        end if;
        v_txt := case st.disparador when 'horas' then 'por horas' when 'fecha' then 'por fecha' else 'por fecha y horas' end;
        perform avisar_equipo(p.grupo_id, 'mantenimiento_' || v_nivel,
          case when st.vencido then 'Mantenimiento vencido: ' else 'Mantenimiento próximo: ' end || p.nombre,
          'Criterio ' || v_txt || '.', jsonb_build_object('plan_id', p.id));
        n := n + 1;
      end if;
    end if;
  end loop;

  -- seguro: vigencia (alertas a N días, DF-21) y vencida
  for pol in select * from polizas_seguro where vigente_hasta >= current_date - 1 loop
    v_dias := politica_interna(pol.grupo_id, 'seguro.alerta_dias');
    d := pol.vigente_hasta - current_date;
    -- solo el umbral más cercano ya cruzado (30 → 7), una vez cada uno
    select min((value #>> '{}')::int) into v_umbral from jsonb_array_elements(v_dias) where d <= (value #>> '{}')::int;
    if v_umbral is not null and d >= 0 and alerta_una_vez('poliza:' || pol.id || ':' || v_umbral) then
      perform avisar_equipo(pol.grupo_id, 'seguro_por_vencer', 'El seguro vence en ' || d || ' día(s)', pol.aseguradora, jsonb_build_object('poliza_id', pol.id));
      n := n + 1;
    end if;
    if d < 0 and alerta_una_vez('poliza:' || pol.id || ':vencida') then
      perform avisar_equipo(pol.grupo_id, 'seguro_vencido', 'El seguro está vencido', pol.aseguradora, jsonb_build_object('poliza_id', pol.id));
      n := n + 1;
    end if;
  end loop;

  -- licencias de capitanes
  for c in select * from capitanes where estado = 'activo' and licencia_vence is not null loop
    d := c.licencia_vence - current_date;
    if d < 0 and alerta_una_vez('licencia:' || c.id || ':vencida') then
      perform avisar_equipo(c.grupo_id, 'licencia_vencida', 'Licencia vencida: ' || c.nombre, 'Sin licencia vigente no hay check-in.', jsonb_build_object('capitan_id', c.id));
      n := n + 1;
    elsif d between 0 and 7 and alerta_una_vez('licencia:' || c.id || ':7') then
      perform avisar_equipo(c.grupo_id, 'licencia_por_vencer', 'La licencia de ' || c.nombre || ' vence en ' || d || ' día(s)', null, jsonb_build_object('capitan_id', c.id));
      n := n + 1;
    elsif d between 8 and 30 and alerta_una_vez('licencia:' || c.id || ':30') then
      perform avisar_equipo(c.grupo_id, 'licencia_por_vencer', 'La licencia de ' || c.nombre || ' vence en ' || d || ' día(s)', null, jsonb_build_object('capitan_id', c.id));
      n := n + 1;
    end if;
  end loop;

  -- facturas por vencer (gastos con vencimiento a 7 días o menos)
  for g in select * from gastos where vencimiento is not null and estado <> 'anulado' and vencimiento <= current_date + 7 loop
    if alerta_una_vez('gasto:' || g.id || ':venc') then
      perform avisar_equipo(g.grupo_id, 'factura_por_vencer', 'Factura por vencer: ' || g.categoria,
        coalesce(g.proveedor, '') || ' · vence ' || g.vencimiento, jsonb_build_object('gasto_id', g.id), true);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke execute on function mantenimiento_evaluar() from public, anon, authenticated;

-- ---------------------------------------------------------------- RLS
alter table capitanes enable row level security;
alter table polizas_seguro enable row level security;
alter table siniestros enable row level security;
alter table mantenimiento_planes enable row level security;
alter table mantenimiento_tareas enable row level security;
alter table servicios enable row level security;
revoke all on capitanes, polizas_seguro, siniestros, mantenimiento_planes, mantenimiento_tareas, servicios from anon, authenticated;
grant select on capitanes, polizas_seguro, siniestros, mantenimiento_planes, mantenimiento_tareas, servicios to authenticated;
create policy capitanes_select on capitanes for select to authenticated using (es_miembro(grupo_id));
create policy polizas_select on polizas_seguro for select to authenticated using (es_miembro(grupo_id));
create policy siniestros_select on siniestros for select to authenticated using (es_miembro(grupo_id));
create policy planes_select on mantenimiento_planes for select to authenticated using (es_miembro(grupo_id));
create policy tareas_select on mantenimiento_tareas for select to authenticated using (es_miembro(grupo_id));
-- los costos de un servicio son finanzas: solo socios (y quien lo registró)
create policy servicios_select on servicios for select to authenticated using (es_socio(grupo_id) or es_miembro_id(registrado_por));

revoke execute on function capitan_guardar(uuid, uuid, text, uuid, text, date, numeric, text, text),
  poliza_guardar(uuid, uuid, uuid, text, text, text, date, date, numeric, text), activo_poliza_vigente(uuid),
  siniestro_abrir(uuid, uuid, text, uuid), siniestro_estado(uuid, text),
  plan_guardar(uuid, uuid, uuid, uuid, text, text, int, numeric, int, numeric, boolean),
  tarea_crear(uuid, uuid, text, uuid, date, numeric, text, text), tarea_programar(uuid, timestamptz, timestamptz, text),
  servicio_registrar(uuid, uuid, uuid, uuid, uuid, date, numeric, text, text, numeric, text, text, date, text, uuid) from public, anon;
grant execute on function capitan_guardar(uuid, uuid, text, uuid, text, date, numeric, text, text),
  poliza_guardar(uuid, uuid, uuid, text, text, text, date, date, numeric, text), activo_poliza_vigente(uuid),
  siniestro_abrir(uuid, uuid, text, uuid), siniestro_estado(uuid, text),
  plan_guardar(uuid, uuid, uuid, uuid, text, text, int, numeric, int, numeric, boolean),
  tarea_crear(uuid, uuid, text, uuid, date, numeric, text, text), tarea_programar(uuid, timestamptz, timestamptz, text),
  servicio_registrar(uuid, uuid, uuid, uuid, uuid, date, numeric, text, text, numeric, text, text, date, text, uuid) to authenticated;

-- ---------------------------------------------------------------- tarea periódica: ahora también evalúa mantenimiento y vencimientos
create or replace function cron_mantenimiento() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_rec int; v_lim int; v_exp int; v_fon int; v_man int; v_url text; v_key text; v_disparado boolean := false;
begin
  v_rec := recordatorios_acuse();
  v_lim := limpiar_borradores();
  v_exp := prioridad_911_expirar();
  v_fon := fondo_aportes_automaticos();
  v_man := mantenimiento_evaluar();
  if to_regclass('vault.decrypted_secrets') is not null and to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is not null
     and exists (select 1 from notificaciones where canal = 'correo' and estado_envio in ('pendiente', 'fallido') and reintentos < 2) then
    execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'shared_functions_url'$q$ into v_url;
    execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'shared_service_key'$q$ into v_key;
    if v_url is not null and v_key is not null then
      execute 'select net.http_post(url := $1, headers := $2, body := $3, timeout_milliseconds := 20000)'
        using v_url || '/enviar-notificaciones',
              jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key), '{}'::jsonb;
      v_disparado := true;
    end if;
  end if;
  return jsonb_build_object('recordatorios', v_rec, 'borradores_limpiados', v_lim, 'solicitudes_911_expiradas', v_exp,
                            'aportes_fondo', v_fon, 'alertas_mantenimiento', v_man, 'envio_disparado', v_disparado);
end $$;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table mantenimiento_tareas;
  end if;
end $$;
