-- 2026-11-24 · 18 · Operación: check-in, lecturas por componente, checklists, incidencias, evidencias (P3·F1)
-- Todo lo registrado es de solo adición: una corrección es una fila nueva con `motivo` (DF-39).

-- ---------------------------------------------------------------- operaciones (1 por orden)
create table operaciones (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  reserva_id uuid not null unique references reservas (id) on delete cascade,
  activo_id uuid not null references activos (id) on delete restrict,
  capitan_miembro uuid references miembros (id),
  capitan_nombre text check (capitan_nombre is null or length(trim(capitan_nombre)) between 2 and 120),
  destino_id uuid references destinos (id),
  salida_real timestamptz not null default now(),
  regreso_real timestamptz,
  combustible_inicial numeric(10, 2) not null check (combustible_inicial >= 0),
  combustible_final numeric(10, 2) check (combustible_final is null or combustible_final >= 0),
  combustible_unidad text not null default 'gal' check (length(combustible_unidad) between 1 and 10),
  observaciones text check (observaciones is null or length(observaciones) <= 1000),
  checkin_por uuid references miembros (id),
  checkout_por uuid references miembros (id),
  cerrada_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint operaciones_responsable check (capitan_miembro is not null or capitan_nombre is not null),
  constraint operaciones_regreso_despues check (regreso_real is null or regreso_real >= salida_real)
);
create index operaciones_grupo_idx on operaciones (grupo_id, salida_real desc);
create index operaciones_activo_idx on operaciones (activo_id, salida_real desc);
create trigger operaciones_actualizado before update on operaciones
  for each row execute function set_actualizado_en();
create trigger operaciones_auditar after insert or update or delete on operaciones
  for each row execute function auditar();

-- ---------------------------------------------------------------- lecturas (SA14: por componente, fin >= inicio, nunca negativas)
create table lecturas (
  id bigint generated always as identity primary key,
  grupo_id uuid not null references grupos (id) on delete cascade,
  operacion_id uuid not null references operaciones (id) on delete cascade,
  componente_id uuid not null references activo_componentes (id) on delete restrict,
  momento text not null check (momento in ('inicio', 'fin')),
  valor numeric(12, 1) not null check (valor >= 0),
  motivo text check (motivo is null or length(motivo) <= 300),
  creado_por uuid references miembros (id),
  creado_en timestamptz not null default now()
);
create index lecturas_clave_idx on lecturas (operacion_id, componente_id, momento, id desc);
create index lecturas_componente_idx on lecturas (componente_id, creado_en desc);

create function lecturas_validar() returns trigger
language plpgsql set search_path = public, pg_temp as $$
declare
  v_op operaciones; v_act uuid; v_previa numeric; v_otra numeric; v_ult numeric; v_base numeric;
begin
  select * into v_op from operaciones where id = new.operacion_id;
  select activo_id into v_act from activo_componentes where id = new.componente_id;
  if v_op.id is null or v_act is distinct from v_op.activo_id then
    raise exception 'componente_ajeno: el componente no pertenece al activo de la orden' using errcode = 'check_violation';
  end if;
  new.grupo_id := v_op.grupo_id;
  select valor into v_previa from lecturas
   where operacion_id = new.operacion_id and componente_id = new.componente_id and momento = new.momento
   order by id desc limit 1;
  if found and coalesce(length(trim(new.motivo)), 0) < 3 then
    raise exception 'motivo_requerido: corregir una lectura exige un motivo' using errcode = 'check_violation';
  end if;
  if new.momento = 'fin' then
    select valor into v_otra from lecturas
     where operacion_id = new.operacion_id and componente_id = new.componente_id and momento = 'inicio'
     order by id desc limit 1;
    if v_otra is null then
      raise exception 'falta_lectura_inicial' using errcode = 'check_violation';
    end if;
    if new.valor < v_otra then
      raise exception 'lectura_final_menor: la lectura final (%) no puede ser menor que la inicial (%)', new.valor, v_otra
        using errcode = 'check_violation';
    end if;
  else
    select valor into v_otra from lecturas
     where operacion_id = new.operacion_id and componente_id = new.componente_id and momento = 'fin'
     order by id desc limit 1;
    if v_otra is not null and new.valor > v_otra then
      raise exception 'lectura_inicial_mayor: la lectura inicial (%) no puede superar la final (%)', new.valor, v_otra
        using errcode = 'check_violation';
    end if;
    if v_previa is null then
      -- continuidad: no puede ser menor que la última lectura final de ese componente (o su lectura de partida)
      select l.valor into v_ult from lecturas l join operaciones o on o.id = l.operacion_id
       where l.componente_id = new.componente_id and l.momento = 'fin' and l.operacion_id <> new.operacion_id
       order by o.salida_real desc, l.id desc limit 1;
      select lectura_inicial into v_base from activo_componentes where id = new.componente_id;
      if new.valor < coalesce(v_ult, v_base) then
        raise exception 'lectura_menor_que_la_ultima: la lectura inicial (%) es menor que la última registrada (%)',
          new.valor, coalesce(v_ult, v_base) using errcode = 'check_violation';
      end if;
    end if;
  end if;
  return new;
end $$;
create trigger lecturas_validar before insert on lecturas
  for each row execute function lecturas_validar();

create function solo_adicion() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  raise exception 'solo_adicion: % no permitido en %; las correcciones son filas nuevas con motivo', tg_op, tg_table_name
    using errcode = 'insufficient_privilege';
end $$;
create trigger lecturas_sin_update before update on lecturas for each row execute function solo_adicion();
create trigger lecturas_auditar after insert on lecturas for each row execute function auditar();

-- Valor vigente = la última fila de cada clave.
create view lecturas_vigentes with (security_invoker = true) as
select distinct on (operacion_id, componente_id, momento) *
  from lecturas order by operacion_id, componente_id, momento, id desc;

-- ---------------------------------------------------------------- checklists (seguridad / salida / regreso)
create table checklist_respuestas (
  id bigint generated always as identity primary key,
  grupo_id uuid not null references grupos (id) on delete cascade,
  operacion_id uuid not null references operaciones (id) on delete cascade,
  momento text not null check (momento in ('seguridad', 'salida', 'regreso')),
  clave text not null check (clave ~ '^[a-z][a-z0-9_]{0,39}$'),
  texto text not null check (length(texto) between 1 and 200),
  obligatorio boolean not null default true,
  cumple boolean not null,
  nota text check (nota is null or length(nota) <= 300),
  motivo text check (motivo is null or length(motivo) <= 300),
  creado_por uuid references miembros (id),
  creado_en timestamptz not null default now()
);
create index checklist_clave_idx on checklist_respuestas (operacion_id, momento, clave, id desc);
create function checklist_validar() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  select grupo_id into new.grupo_id from operaciones where id = new.operacion_id;
  if exists (select 1 from checklist_respuestas
              where operacion_id = new.operacion_id and momento = new.momento and clave = new.clave)
     and coalesce(length(trim(new.motivo)), 0) < 3 then
    raise exception 'motivo_requerido: corregir una respuesta exige un motivo' using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger checklist_validar before insert on checklist_respuestas
  for each row execute function checklist_validar();
create trigger checklist_sin_update before update on checklist_respuestas for each row execute function solo_adicion();
create trigger checklist_auditar after insert on checklist_respuestas for each row execute function auditar();
create view checklist_vigente with (security_invoker = true) as
select distinct on (operacion_id, momento, clave) *
  from checklist_respuestas order by operacion_id, momento, clave, id desc;

-- ---------------------------------------------------------------- combustible, incidencias, evidencias
create table combustible_registros (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  operacion_id uuid not null references operaciones (id) on delete cascade,
  tipo text not null check (tipo in ('agregado', 'consumido')),
  cantidad numeric(10, 2) not null check (cantidad >= 0),
  unidad text not null default 'gal',
  costo numeric(14, 2) check (costo is null or costo >= 0),
  moneda char(3) check (moneda is null or moneda ~ '^[A-Z]{3}$'),
  gasto_id uuid,
  nota text check (nota is null or length(nota) <= 300),
  creado_por uuid references miembros (id),
  creado_en timestamptz not null default now()
);
create index combustible_op_idx on combustible_registros (operacion_id);
create trigger combustible_auditar after insert on combustible_registros for each row execute function auditar();
create trigger combustible_sin_update before update on combustible_registros for each row execute function solo_adicion();

create table incidencias (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  operacion_id uuid not null references operaciones (id) on delete cascade,
  tipo text not null check (tipo in ('observacion', 'incidencia', 'dano')),
  descripcion text not null check (length(trim(descripcion)) between 1 and 1000),
  creado_por uuid references miembros (id),
  creado_en timestamptz not null default now()
);
create index incidencias_op_idx on incidencias (operacion_id);
create trigger incidencias_auditar after insert on incidencias for each row execute function auditar();
create trigger incidencias_sin_update before update on incidencias for each row execute function solo_adicion();

create table evidencias (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  ref_tipo text not null check (ref_tipo in ('operacion', 'incidencia', 'gasto', 'pago', 'dano')),
  ref_id uuid not null,
  tipo text not null default 'foto' check (tipo in ('foto', 'factura', 'comprobante', 'otro')),
  ruta text not null check (length(ruta) between 5 and 400),
  mime text check (mime is null or length(mime) <= 100),
  creado_por uuid not null references miembros (id),
  creado_en timestamptz not null default now()
);
create index evidencias_ref_idx on evidencias (ref_tipo, ref_id);
create trigger evidencias_auditar after insert or delete on evidencias for each row execute function auditar();

-- ---------------------------------------------------------------- helpers
create function es_miembro_id(p_miembro uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from miembros where id = p_miembro and usuario_id = auth.uid() and estado = 'activo')
$$;

-- Gancho de DF-20: el registro de capitanes llega en el PROMPT-4, que reemplaza esta función.
-- Mientras no exista, no se bloquea nada (tolerancia pedida en el PROMPT-3).
create function capitan_licencia_ok(p_grupo uuid, p_miembro uuid, p_nombre text, p_fecha date) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$ select true $$;
revoke execute on function capitan_licencia_ok(uuid, uuid, text, date) from public, anon, authenticated;

create function checklist_items(p_activo uuid, p_momento text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(t.definicion -> 'checklists' -> p_momento, '[]'::jsonb)
    from activos a join tipos_activo t on t.id = a.tipo_id where a.id = p_activo
$$;
revoke execute on function checklist_items(uuid, text) from public, anon, authenticated;

-- Permiso operativo sobre una reserva: quien reservó, admin operativo o capitán (igual que iniciar/finalizar).
create function operacion_puede(r reservas) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(r.reservado_por = miembro_actual(r.grupo_id) or rol_en(r.grupo_id) in ('admin_operativo', 'capitan'), false)
$$;
revoke execute on function operacion_puede(reservas) from public, anon, authenticated;

-- Guarda una respuesta de checklist solo si cambia (evita filas duplicadas); corrige con motivo si ya existía.
create function checklist_guardar(p_op uuid, p_momento text, p_item jsonb, p_resp jsonb, p_actor uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_cumple boolean := coalesce((p_resp ->> 'cumple')::boolean, false); v_prev boolean; v_nota text := left(p_resp ->> 'nota', 300);
begin
  select cumple into v_prev from checklist_vigente where operacion_id = p_op and momento = p_momento and clave = p_item ->> 'clave';
  if found and v_prev = v_cumple then return; end if;
  insert into checklist_respuestas (operacion_id, momento, clave, texto, obligatorio, cumple, nota, motivo, creado_por)
  values (p_op, p_momento, p_item ->> 'clave', left(p_item ->> 'texto', 200),
          coalesce((p_item ->> 'obligatorio')::boolean, true), v_cumple, v_nota,
          case when found then p_motivo end, p_actor);
end $$;
revoke execute on function checklist_guardar(uuid, text, jsonb, jsonb, uuid, text) from public, anon, authenticated;

-- Guarda una lectura solo si cambia; corrige con motivo si ya existía.
create function lectura_guardar(p_op uuid, p_componente uuid, p_momento text, p_valor numeric, p_actor uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_prev numeric;
begin
  if p_valor is null then return; end if;
  if p_valor < 0 then
    raise exception 'valor_negativo: las lecturas no pueden ser negativas' using errcode = 'check_violation';
  end if;
  select valor into v_prev from lecturas_vigentes where operacion_id = p_op and componente_id = p_componente and momento = p_momento;
  if found and v_prev = p_valor then return; end if;
  insert into lecturas (operacion_id, componente_id, momento, valor, motivo, creado_por)
  values (p_op, p_componente, p_momento, p_valor, case when found then p_motivo end, p_actor);
end $$;
revoke execute on function lectura_guardar(uuid, uuid, text, numeric, uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------- check-in (SA2 paso 3, SA14, SA30)
-- Devuelve {ok, faltan[]}: si falta algo no se escribe nada y se dice QUÉ falta.
create function checkin_registrar(
  p_reserva uuid,
  p_capitan_miembro uuid,
  p_capitan_nombre text,
  p_destino uuid,
  p_combustible numeric,
  p_lecturas jsonb,
  p_checklist jsonb,
  p_nota text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r reservas; v_yo uuid; v_faltan jsonb := '[]'::jsonb; c record; it jsonb; v_resp jsonb; v_val numeric;
  v_ult numeric; v_cap text := nullif(trim(coalesce(p_capitan_nombre, '')), ''); v_op uuid; v_oblig boolean;
  v_unidad text := 'gal'; m text; s record;
begin
  select * into r from reservas where id = p_reserva for update;
  if not found or r.tipo_bloqueo is not null then
    raise exception 'reserva_no_existe' using errcode = 'no_data_found';
  end if;
  if not operacion_puede(r) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  if r.estado <> 'confirmada' then
    raise exception 'transicion_invalida: solo una reserva confirmada puede salir (estado %)', r.estado using errcode = 'check_violation';
  end if;
  v_yo := miembro_actual(r.grupo_id);
  if p_combustible is not null and p_combustible < 0 then
    raise exception 'valor_negativo: el combustible no puede ser negativo' using errcode = 'check_violation';
  end if;

  -- capitán o responsable a bordo
  if p_capitan_miembro is not null and not exists (
       select 1 from miembros where id = p_capitan_miembro and grupo_id = r.grupo_id and estado = 'activo') then
    raise exception 'capitan_invalido' using errcode = 'check_violation';
  end if;
  if p_capitan_miembro is null and v_cap is null then
    v_faltan := v_faltan || jsonb_build_object('codigo', 'capitan', 'detalle', 'Capitán o responsable a bordo');
  elsif coalesce(pol_txt(r.grupo_id, 'capitanes.licencia_vigente_requerida')::boolean, false)
        and not capitan_licencia_ok(r.grupo_id, p_capitan_miembro, v_cap, current_date) then
    v_faltan := v_faltan || jsonb_build_object('codigo', 'capitan_sin_licencia', 'detalle', 'El capitán no tiene licencia vigente');
  end if;
  if p_combustible is null then
    v_faltan := v_faltan || jsonb_build_object('codigo', 'combustible_inicial', 'detalle', 'Combustible inicial');
  end if;

  -- lectura inicial de CADA componente con medidor
  for c in select * from activo_componentes where activo_id = r.activo_id order by clave, indice loop
    select (e ->> 'valor')::numeric into v_val
      from jsonb_array_elements(coalesce(p_lecturas, '[]'::jsonb)) e where e ->> 'componente_id' = c.id::text limit 1;
    if v_val is null then
      v_faltan := v_faltan || jsonb_build_object('codigo', 'lectura_inicial', 'componente_id', c.id,
        'detalle', 'Lectura inicial de ' || c.etiqueta || ' (' || c.unidad || ')');
    else
      if v_val < 0 then
        raise exception 'valor_negativo: la lectura de % no puede ser negativa', c.etiqueta using errcode = 'check_violation';
      end if;
      select l.valor into v_ult from lecturas l join operaciones o on o.id = l.operacion_id
       where l.componente_id = c.id and l.momento = 'fin'
       order by o.salida_real desc, l.id desc limit 1;
      if v_val < coalesce(v_ult, c.lectura_inicial) then
        raise exception 'lectura_menor_que_la_ultima: % no puede iniciar en % (última lectura: %)',
          c.etiqueta, v_val, coalesce(v_ult, c.lectura_inicial) using errcode = 'check_violation';
      end if;
    end if;
  end loop;

  -- checklist de seguridad y de salida (DF-22): obligatorios y cumplidos
  if coalesce(pol_txt(r.grupo_id, 'seguridad.checklist_salida_obligatorio')::boolean, true) then
    foreach m in array array['seguridad', 'salida'] loop
      for it in select * from jsonb_array_elements(checklist_items(r.activo_id, m)) loop
        v_oblig := coalesce((it ->> 'obligatorio')::boolean, true);
        select e into v_resp from jsonb_array_elements(coalesce(p_checklist, '[]'::jsonb)) e
         where e ->> 'clave' = it ->> 'clave' and coalesce(e ->> 'momento', m) = m limit 1;
        if v_oblig and v_resp is null then
          v_faltan := v_faltan || jsonb_build_object('codigo', 'checklist', 'momento', m, 'clave', it ->> 'clave', 'detalle', it ->> 'texto');
        elsif v_oblig and not coalesce((v_resp ->> 'cumple')::boolean, false) then
          v_faltan := v_faltan || jsonb_build_object('codigo', 'checklist_no_cumple', 'momento', m, 'clave', it ->> 'clave',
            'detalle', 'No se cumple: ' || (it ->> 'texto'));
        end if;
      end loop;
    end loop;
  end if;

  if jsonb_array_length(v_faltan) > 0 then
    return jsonb_build_object('ok', false, 'faltan', v_faltan);
  end if;

  perform set_config('app.motivo', 'check-in de la salida', true);
  insert into operaciones (grupo_id, reserva_id, activo_id, capitan_miembro, capitan_nombre, destino_id,
                           combustible_inicial, observaciones, checkin_por)
  values (r.grupo_id, r.id, r.activo_id, p_capitan_miembro, v_cap, coalesce(p_destino, r.destino_id),
          p_combustible, left(p_nota, 1000), v_yo)
  returning id into v_op;

  for c in select * from activo_componentes where activo_id = r.activo_id loop
    select (e ->> 'valor')::numeric into v_val
      from jsonb_array_elements(p_lecturas) e where e ->> 'componente_id' = c.id::text limit 1;
    insert into lecturas (operacion_id, componente_id, momento, valor, creado_por) values (v_op, c.id, 'inicio', v_val, v_yo);
  end loop;
  foreach m in array array['seguridad', 'salida'] loop
    for it in select * from jsonb_array_elements(checklist_items(r.activo_id, m)) loop
      select e into v_resp from jsonb_array_elements(coalesce(p_checklist, '[]'::jsonb)) e
       where e ->> 'clave' = it ->> 'clave' and coalesce(e ->> 'momento', m) = m limit 1;
      if v_resp is not null then
        perform checklist_guardar(v_op, m, it, v_resp, v_yo, null);
      end if;
    end loop;
  end loop;

  update reservas set estado = 'en_curso' where id = r.id;

  for s in select m2.usuario_id from miembros m2
            where m2.grupo_id = r.grupo_id and m2.rol = 'socio' and m2.estado = 'activo' and m2.id <> v_yo loop
    perform notificar(r.grupo_id, s.usuario_id, 'salida_iniciada', 'Salida iniciada',
      (select codigo from ordenes where reserva_id = r.id) || ' salió.',
      jsonb_build_object('reserva_id', r.id), false);
  end loop;
  return jsonb_build_object('ok', true, 'operacion_id', v_op);
end $$;

-- Corrección explícita de una lectura (después del cierre o antes): fila nueva con motivo obligatorio.
create function lectura_corregir(p_operacion uuid, p_componente uuid, p_momento text, p_valor numeric, p_motivo text)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare o operaciones; v_yo uuid;
begin
  select * into o from operaciones where id = p_operacion;
  if not found then raise exception 'operacion_no_existe' using errcode = 'no_data_found'; end if;
  v_yo := miembro_actual(o.grupo_id);
  if not coalesce(rol_en(o.grupo_id) in ('socio', 'admin_operativo'), false) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(length(trim(p_motivo)), 0) < 3 then
    raise exception 'motivo_requerido' using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', p_motivo, true);
  insert into lecturas (operacion_id, componente_id, momento, valor, motivo, creado_por)
  values (p_operacion, p_componente, p_momento, p_valor, p_motivo, v_yo);
end $$;

-- ---------------------------------------------------------------- evidencias (fotos / facturas / comprobantes en Storage privado)
-- Ruta: {grupo_id}/op/{operacion}/archivo  ·  {grupo_id}/fin/{usuario}/archivo (finanzas: solo socios y quien lo subió)
create function evidencia_registrar(p_grupo uuid, p_ref_tipo text, p_ref_id uuid, p_ruta text, p_tipo text default 'foto', p_mime text default null)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_yo uuid := miembro_actual(p_grupo); v_id uuid;
begin
  if v_yo is null then raise exception 'sin_permiso' using errcode = 'insufficient_privilege'; end if;
  if p_ref_tipo in ('gasto', 'pago', 'dano') and not coalesce(rol_en(p_grupo) in ('socio', 'admin_operativo'), false) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  if position(p_grupo::text || '/' in p_ruta) <> 1 then
    raise exception 'ruta_invalida: la ruta debe empezar por el grupo' using errcode = 'check_violation';
  end if;
  insert into evidencias (grupo_id, ref_tipo, ref_id, tipo, ruta, mime, creado_por)
  values (p_grupo, p_ref_tipo, p_ref_id, p_tipo, p_ruta, p_mime, v_yo) returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------- RLS
alter table operaciones enable row level security;
alter table lecturas enable row level security;
alter table checklist_respuestas enable row level security;
alter table combustible_registros enable row level security;
alter table incidencias enable row level security;
alter table evidencias enable row level security;
revoke all on operaciones, lecturas, checklist_respuestas, combustible_registros, incidencias, evidencias from anon, authenticated;
grant select on operaciones, lecturas, checklist_respuestas, combustible_registros, incidencias, evidencias to authenticated;
grant select on lecturas_vigentes, checklist_vigente to authenticated;

create policy operaciones_select on operaciones for select to authenticated using (es_miembro(grupo_id));
create policy lecturas_select on lecturas for select to authenticated using (es_miembro(grupo_id));
create policy checklist_select on checklist_respuestas for select to authenticated using (es_miembro(grupo_id));
create policy combustible_select on combustible_registros for select to authenticated using (es_miembro(grupo_id));
create policy incidencias_select on incidencias for select to authenticated using (es_miembro(grupo_id));
-- Evidencias de operación: todos los miembros. De gastos/pagos/daños: socios y quien las subió.
create policy evidencias_select on evidencias for select to authenticated using (
  case when ref_tipo in ('operacion', 'incidencia') then es_miembro(grupo_id)
       else es_socio(grupo_id) or es_miembro_id(creado_por) end);

revoke execute on function checkin_registrar(uuid, uuid, text, uuid, numeric, jsonb, jsonb, text),
  lectura_corregir(uuid, uuid, text, numeric, text),
  evidencia_registrar(uuid, text, uuid, text, text, text) from public, anon;
grant execute on function checkin_registrar(uuid, uuid, text, uuid, numeric, jsonb, jsonb, text),
  lectura_corregir(uuid, uuid, text, numeric, text),
  evidencia_registrar(uuid, text, uuid, text, text, text) to authenticated;
grant execute on function es_miembro_id(uuid) to authenticated;

-- ---------------------------------------------------------------- Storage privado (solo si el esquema existe)
do $$
begin
  if to_regclass('storage.buckets') is not null and to_regclass('storage.objects') is not null then
    insert into storage.buckets (id, name, public) values ('evidencias', 'evidencias', false) on conflict (id) do nothing;
    execute $p$
      create policy evidencias_leer on storage.objects for select to authenticated using (
        bucket_id = 'evidencias'
        and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                 then es_miembro(((storage.foldername(name))[1])::uuid)
                      and ((storage.foldername(name))[2] = 'op'
                           or es_socio(((storage.foldername(name))[1])::uuid)
                           or (storage.foldername(name))[3] = auth.uid()::text)
                 else false end)$p$;
    execute $p$
      create policy evidencias_subir on storage.objects for insert to authenticated with check (
        bucket_id = 'evidencias'
        and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                 then es_miembro(((storage.foldername(name))[1])::uuid)
                      and ((storage.foldername(name))[2] = 'op'
                           or ((storage.foldername(name))[2] = 'fin' and (storage.foldername(name))[3] = auth.uid()::text))
                 else false end)$p$;
  end if;
end $$;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table operaciones;
  end if;
end $$;
