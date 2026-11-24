-- 2026-11-24 · 24 · Reportes (SA18), salida o venta de un socio (SA33), desacuerdos y mediador (SA34) (P4·F5–F7)

-- ---------------------------------------------------------------- reportes: salen del MISMO libro mayor y operación (sin cálculo en el cliente)
-- Solo socios (finanzas): un admin operativo no puede pedirlos. Las estadísticas no limitan reservas: son solo lectura.
create function reporte_salidas(
  p_grupo uuid, p_desde date default null, p_hasta date default null, p_miembro uuid default null,
  p_destino uuid default null, p_uso text default null, p_estado text default null, p_limite int default 5000
) returns table (
  reserva_id uuid, orden text, fecha date, inicio timestamptz, fin timestamptz, miembro_id uuid, miembro text, destino text,
  uso text, estado text, personas int, duracion_horas numeric, horas_motor numeric, combustible_consumido numeric,
  fee numeric, gastos_individuales numeric, moneda char(3))
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not es_socio(p_grupo) then
    raise exception 'solo_socios' using errcode = 'insufficient_privilege';
  end if;
  return query
  select r.id, o.codigo, (lower(r.rango) at time zone coalesce((select gr.zona_horaria from grupos gr where gr.id = p_grupo), 'UTC'))::date,
         lower(r.rango), upper(r.rango), r.reservado_por, coalesce(pf.nombre, pf.correo::text), d.nombre,
         r.uso::text, r.estado::text, r.personas,
         round(extract(epoch from coalesce(op.regreso_real, upper(r.rango)) - coalesce(op.salida_real, lower(r.rango))) / 3600.0, 2),
         coalesce((select sum(f.valor - i.valor) from lecturas_vigentes i
                     join lecturas_vigentes f on f.operacion_id = i.operacion_id and f.componente_id = i.componente_id and f.momento = 'fin'
                    where i.operacion_id = op.id and i.momento = 'inicio'), 0),
         (select cantidad from combustible_registros cr where cr.operacion_id = op.id and cr.tipo = 'consumido' order by cr.creado_en desc limit 1),
         coalesce((select sum(lm.debe) from libro_mayor lm where lm.origen_tipo = 'fee' and lm.origen_id = l.id and lm.cuenta_tipo = 'miembro'), 0),
         coalesce((select sum(g.monto_grupo) from gastos g where g.reserva_id = r.id and g.alcance = 'individual' and g.estado <> 'anulado'), 0),
         (select gr.moneda from grupos gr where gr.id = p_grupo)
    from reservas r
    left join ordenes o on o.reserva_id = r.id
    left join operaciones op on op.reserva_id = r.id
    left join liquidaciones l on l.operacion_id = op.id
    left join destinos d on d.id = r.destino_id
    left join miembros m on m.id = r.reservado_por
    left join perfiles pf on pf.id = m.usuario_id
   where r.grupo_id = p_grupo and r.tipo_bloqueo is null and r.estado in ('confirmada', 'en_curso', 'finalizada', 'cancelada')
     and (p_desde is null or lower(r.rango)::date >= p_desde)
     and (p_hasta is null or lower(r.rango)::date <= p_hasta)
     and (p_miembro is null or r.reservado_por = p_miembro)
     and (p_destino is null or r.destino_id = p_destino)
     and (p_uso is null or r.uso::text = p_uso)
     and (p_estado is null or r.estado::text = p_estado)
   order by lower(r.rango) desc
   limit least(coalesce(p_limite, 5000), 5000);
end $$;

-- Costo neto de un miembro = cargos (débitos que no son pagos) − reversas de gastos anulados.
create function reporte_dashboard(p_grupo uuid, p_anio int, p_mes int default null)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_desde timestamptz; v_hasta timestamptz; v_res jsonb; v_zona text;
begin
  if not es_socio(p_grupo) then
    raise exception 'solo_socios' using errcode = 'insufficient_privilege';
  end if;
  select zona_horaria into v_zona from grupos where id = p_grupo;
  if p_mes is null then
    v_desde := make_timestamptz(p_anio, 1, 1, 0, 0, 0, v_zona);
    v_hasta := make_timestamptz(p_anio + 1, 1, 1, 0, 0, 0, v_zona);
  else
    v_desde := make_timestamptz(p_anio, p_mes, 1, 0, 0, 0, v_zona);
    v_hasta := v_desde + interval '1 month';
  end if;
  select jsonb_build_object(
    'periodo', jsonb_build_object('desde', v_desde, 'hasta', v_hasta),
    'salidas', (select count(*) from reservas r where r.grupo_id = p_grupo and r.tipo_bloqueo is null
                  and r.estado in ('en_curso', 'finalizada') and lower(r.rango) >= v_desde and lower(r.rango) < v_hasta),
    'dias_usados', (select count(distinct dia::date) from reservas r,
                      lateral generate_series(lower(r.rango) at time zone v_zona, (upper(r.rango) - interval '1 second') at time zone v_zona, interval '1 day') dia
                     where r.grupo_id = p_grupo and r.tipo_bloqueo is null and r.estado in ('en_curso', 'finalizada')
                       and lower(r.rango) >= v_desde and lower(r.rango) < v_hasta),
    'horas_duracion', coalesce((select round(sum(extract(epoch from op.regreso_real - op.salida_real)) / 3600.0, 2) from operaciones op
                        where op.grupo_id = p_grupo and op.cerrada_en is not null and op.salida_real >= v_desde and op.salida_real < v_hasta), 0),
    'horas_por_componente', coalesce((select jsonb_agg(jsonb_build_object('etiqueta', x.etiqueta, 'unidad', x.unidad, 'horas', x.h) order by x.etiqueta)
        from (select c.etiqueta, c.unidad, sum(f.valor - i.valor) as h
                from operaciones op
                join lecturas_vigentes i on i.operacion_id = op.id and i.momento = 'inicio'
                join lecturas_vigentes f on f.operacion_id = op.id and f.componente_id = i.componente_id and f.momento = 'fin'
                join activo_componentes c on c.id = i.componente_id
               where op.grupo_id = p_grupo and op.cerrada_en is not null and op.salida_real >= v_desde and op.salida_real < v_hasta
               group by c.etiqueta, c.unidad) x), '[]'::jsonb),
    'combustible_consumido', coalesce((select sum(cr.cantidad) from combustible_registros cr join operaciones op on op.id = cr.operacion_id
                        where cr.grupo_id = p_grupo and cr.tipo = 'consumido' and op.salida_real >= v_desde and op.salida_real < v_hasta), 0),
    'fees', coalesce((select sum(lm.debe) from libro_mayor lm where lm.grupo_id = p_grupo and lm.origen_tipo = 'fee' and lm.cuenta_tipo = 'miembro'
                        and lm.momento >= v_desde and lm.momento < v_hasta), 0),
    'danos', coalesce((select sum(lm.debe) from libro_mayor lm where lm.grupo_id = p_grupo and lm.origen_tipo = 'dano' and lm.cuenta_tipo = 'miembro'
                        and lm.momento >= v_desde and lm.momento < v_hasta), 0),
    'gastos_comunes', coalesce((select sum(g.monto_grupo) from gastos g where g.grupo_id = p_grupo and g.alcance = 'comun' and g.estado <> 'anulado'
                        and g.creado_en >= v_desde and g.creado_en < v_hasta), 0),
    'costo_total', coalesce((select sum(case when lm.origen_tipo = 'gasto_anulado' then -lm.haber else lm.debe end) from libro_mayor lm
                        where lm.grupo_id = p_grupo and lm.cuenta_tipo = 'miembro' and lm.origen_tipo <> 'pago'
                          and lm.momento >= v_desde and lm.momento < v_hasta), 0),
    'por_miembro', coalesce((select jsonb_agg(jsonb_build_object('miembro_id', mm.id, 'nombre', coalesce(pf.nombre, pf.correo::text),
          'porcentaje', mm.porcentaje,
          'salidas', (select count(*) from reservas r where r.reservado_por = mm.id and r.tipo_bloqueo is null and r.estado in ('en_curso', 'finalizada')
                        and lower(r.rango) >= v_desde and lower(r.rango) < v_hasta),
          'horas', coalesce((select round(sum(extract(epoch from op.regreso_real - op.salida_real)) / 3600.0, 2) from operaciones op
                              join reservas r on r.id = op.reserva_id
                             where r.reservado_por = mm.id and op.cerrada_en is not null and op.salida_real >= v_desde and op.salida_real < v_hasta), 0),
          'costo', coalesce((select sum(case when lm.origen_tipo = 'gasto_anulado' then -lm.haber else lm.debe end) from libro_mayor lm
                        where lm.miembro_id = mm.id and lm.origen_tipo <> 'pago' and lm.momento >= v_desde and lm.momento < v_hasta), 0))
          order by coalesce(pf.nombre, pf.correo::text))
        from miembros mm join perfiles pf on pf.id = mm.usuario_id
       where mm.grupo_id = p_grupo and mm.rol = 'socio' and mm.estado = 'activo'), '[]'::jsonb),
    'por_mes', coalesce((select jsonb_agg(jsonb_build_object('mes', to_char(x.mes, 'YYYY-MM'), 'salidas', x.salidas, 'costo', x.costo) order by x.mes)
        from (select date_trunc('month', s.t at time zone v_zona) as mes, sum(s.n) as salidas, sum(s.c) as costo
                from (select lower(r.rango) as t, 1 as n, 0::numeric as c from reservas r
                       where r.grupo_id = p_grupo and r.tipo_bloqueo is null and r.estado in ('en_curso', 'finalizada')
                         and lower(r.rango) >= v_desde and lower(r.rango) < v_hasta
                      union all
                      select lm.momento, 0, case when lm.origen_tipo = 'gasto_anulado' then -lm.haber else lm.debe end from libro_mayor lm
                       where lm.grupo_id = p_grupo and lm.cuenta_tipo = 'miembro' and lm.origen_tipo <> 'pago'
                         and lm.momento >= v_desde and lm.momento < v_hasta) s
               group by 1) x), '[]'::jsonb)
  ) into v_res;
  return v_res;
end $$;

revoke execute on function reporte_salidas(uuid, date, date, uuid, uuid, text, text, int), reporte_dashboard(uuid, int, int) from public, anon;
grant execute on function reporte_salidas(uuid, date, date, uuid, uuid, text, text, int), reporte_dashboard(uuid, int, int) to authenticated;

-- ---------------------------------------------------------------- salida o venta de un socio (SA33, DF-25)
create table salida_socio_casos (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  miembro_id uuid not null references miembros (id),
  porcentaje numeric(5, 2) not null check (porcentaje > 0),
  estado text not null default 'abierto' check (estado in ('abierto', 'oferta', 'aceptado', 'cerrado', 'cancelado')),
  preferencia_hasta timestamptz not null,
  valoracion_nota text check (valoracion_nota is null or length(valoracion_nota) <= 2000),
  nota text check (nota is null or length(nota) <= 1000),
  creado_en timestamptz not null default now(),
  cerrado_en timestamptz
);
create unique index salida_socio_uno_abierto on salida_socio_casos (miembro_id) where estado in ('abierto', 'oferta', 'aceptado');
create trigger salida_socio_auditar after insert or update on salida_socio_casos for each row execute function auditar();

create table salida_socio_ofertas (
  id uuid primary key default gen_random_uuid(),
  caso_id uuid not null references salida_socio_casos (id) on delete cascade,
  grupo_id uuid not null references grupos (id) on delete cascade,
  miembro_id uuid not null references miembros (id),
  porcentaje numeric(5, 2) not null check (porcentaje > 0),
  valor numeric(14, 2) not null check (valor >= 0),
  moneda char(3) not null check (moneda ~ '^[A-Z]{3}$'),
  estado text not null default 'vigente' check (estado in ('vigente', 'retirada')),
  creado_en timestamptz not null default now()
);
create unique index salida_oferta_unica on salida_socio_ofertas (caso_id, miembro_id) where estado = 'vigente';
create trigger salida_ofertas_auditar after insert or update on salida_socio_ofertas for each row execute function auditar();

create table salida_socio_acuses (
  caso_id uuid not null references salida_socio_casos (id) on delete cascade,
  ronda int not null,
  miembro_id uuid not null references miembros (id),
  grupo_id uuid not null references grupos (id) on delete cascade,
  acepta boolean not null,
  creado_en timestamptz not null default now(),
  primary key (caso_id, ronda, miembro_id)
);

alter table salida_socio_casos add column ronda int not null default 1;

create function salida_socio_solicitar(p_grupo uuid, p_nota text default null) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_yo uuid := miembro_actual(p_grupo); m miembros; v_id uuid; v_dias int;
begin
  if v_yo is null or not es_socio(p_grupo) then raise exception 'solo_socios' using errcode = 'insufficient_privilege'; end if;
  select * into m from miembros where id = v_yo;
  v_dias := coalesce(pol_txt(p_grupo, 'salida_socio.preferencia_dias')::int, 30);
  perform set_config('app.motivo', 'solicitud de salida de socio', true);
  insert into salida_socio_casos (grupo_id, miembro_id, porcentaje, preferencia_hasta, nota)
  values (p_grupo, v_yo, m.porcentaje, now() + make_interval(days => v_dias), left(p_nota, 1000)) returning id into v_id;
  perform avisar_equipo(p_grupo, 'salida_socio', 'Un socio quiere salir o vender su parte',
    'Tienen ' || v_dias || ' días de derecho de preferencia.', jsonb_build_object('caso_id', v_id), true);
  return v_id;
end $$;

create function salida_socio_valorar(p_caso uuid, p_valoracion text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare c salida_socio_casos;
begin
  select * into c from salida_socio_casos where id = p_caso for update;
  if not found or not es_socio(c.grupo_id) then raise exception 'solo_socios' using errcode = 'insufficient_privilege'; end if;
  if c.estado not in ('abierto', 'oferta') then raise exception 'estado_invalido' using errcode = 'check_violation'; end if;
  perform set_config('app.motivo', 'valoración registrada', true);
  update salida_socio_casos set valoracion_nota = left(p_valoracion, 2000) where id = c.id;
end $$;

create function salida_socio_ofertar(p_caso uuid, p_porcentaje numeric, p_valor numeric, p_moneda text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare c salida_socio_casos; v_yo uuid; v_suma numeric; v_id uuid;
begin
  select * into c from salida_socio_casos where id = p_caso for update;
  if not found then raise exception 'caso_no_existe' using errcode = 'no_data_found'; end if;
  v_yo := miembro_actual(c.grupo_id);
  if v_yo is null or not es_socio(c.grupo_id) or v_yo = c.miembro_id then
    raise exception 'solo_otros_socios: lo ofertan los demás socios' using errcode = 'insufficient_privilege';
  end if;
  if c.estado not in ('abierto', 'oferta') then raise exception 'estado_invalido' using errcode = 'check_violation'; end if;
  if p_porcentaje is null or p_porcentaje <= 0 or p_valor is null or p_valor < 0 then
    raise exception 'oferta_invalida' using errcode = 'check_violation';
  end if;
  select coalesce(sum(porcentaje), 0) into v_suma from salida_socio_ofertas where caso_id = c.id and estado = 'vigente' and miembro_id <> v_yo;
  if v_suma + p_porcentaje > c.porcentaje then
    raise exception 'oferta_excede: lo ofertado superaría el % que se vende', c.porcentaje using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'oferta por la parte de un socio', true);
  update salida_socio_ofertas set estado = 'retirada' where caso_id = c.id and miembro_id = v_yo and estado = 'vigente';
  insert into salida_socio_ofertas (caso_id, grupo_id, miembro_id, porcentaje, valor, moneda)
  values (c.id, c.grupo_id, v_yo, p_porcentaje, p_valor, upper(p_moneda)) returning id into v_id;
  update salida_socio_casos set estado = 'oferta', ronda = ronda + 1 where id = c.id;   -- una oferta nueva reinicia las aceptaciones
  return v_id;
end $$;

create function salida_socio_responder(p_caso uuid, p_acepta boolean) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare c salida_socio_casos; v_yo uuid; v_suma numeric; v_falta int;
begin
  select * into c from salida_socio_casos where id = p_caso for update;
  if not found then raise exception 'caso_no_existe' using errcode = 'no_data_found'; end if;
  v_yo := miembro_actual(c.grupo_id);
  if v_yo is null or not es_socio(c.grupo_id) then raise exception 'solo_socios' using errcode = 'insufficient_privilege'; end if;
  if c.estado <> 'oferta' then raise exception 'estado_invalido: no hay una oferta completa para aceptar' using errcode = 'check_violation'; end if;
  select coalesce(sum(porcentaje), 0) into v_suma from salida_socio_ofertas where caso_id = c.id and estado = 'vigente';
  if v_suma <> c.porcentaje then raise exception 'oferta_incompleta: las ofertas suman % de %', v_suma, c.porcentaje using errcode = 'check_violation'; end if;
  perform set_config('app.motivo', 'respuesta a la salida de un socio', true);
  insert into salida_socio_acuses (caso_id, ronda, miembro_id, grupo_id, acepta) values (c.id, c.ronda, v_yo, c.grupo_id, p_acepta)
  on conflict (caso_id, ronda, miembro_id) do update set acepta = excluded.acepta, creado_en = now();
  if not p_acepta then
    update salida_socio_casos set estado = 'abierto', ronda = ronda + 1 where id = c.id;
    return;
  end if;
  select count(*) into v_falta from miembros m
   where m.grupo_id = c.grupo_id and m.rol = 'socio' and m.estado = 'activo'
     and not exists (select 1 from salida_socio_acuses a where a.caso_id = c.id and a.ronda = c.ronda and a.miembro_id = m.id and a.acepta);
  if v_falta = 0 then
    update salida_socio_casos set estado = 'aceptado' where id = c.id;
  end if;
end $$;

-- Cierre: traspasa los porcentajes (suma sigue en 100, auditado). La app NO mueve dinero: el saldo del saliente debe estar en 0.
create function salida_socio_cerrar(p_caso uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare c salida_socio_casos; o record; v_saldo numeric;
begin
  select * into c from salida_socio_casos where id = p_caso for update;
  if not found or not es_socio(c.grupo_id) then raise exception 'solo_socios' using errcode = 'insufficient_privilege'; end if;
  if c.estado <> 'aceptado' then raise exception 'estado_invalido: todos los socios deben aceptar antes de cerrar' using errcode = 'check_violation'; end if;
  select coalesce(sum(haber - debe), 0) into v_saldo from libro_mayor where cuenta_tipo = 'miembro' and miembro_id = c.miembro_id;
  if v_saldo <> 0 then
    raise exception 'saldo_pendiente: el saliente tiene un saldo de % por liquidar entre socios', v_saldo using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'traspaso por salida de socio (caso ' || c.id || ')', true);
  for o in select * from salida_socio_ofertas where caso_id = c.id and estado = 'vigente' loop
    update miembros set porcentaje = porcentaje + o.porcentaje where id = o.miembro_id;
  end loop;
  update miembros set porcentaje = 0, estado = 'salido', hasta = now() where id = c.miembro_id;
  update salida_socio_casos set estado = 'cerrado', cerrado_en = now() where id = c.id;
  perform avisar_equipo(c.grupo_id, 'salida_socio_cerrada', 'Salida de socio cerrada', 'Los porcentajes se actualizaron.', jsonb_build_object('caso_id', c.id), true);
end $$;

create function salida_socio_cancelar(p_caso uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare c salida_socio_casos;
begin
  select * into c from salida_socio_casos where id = p_caso for update;
  if not found or not es_socio(c.grupo_id) then raise exception 'solo_socios' using errcode = 'insufficient_privilege'; end if;
  if c.estado in ('cerrado', 'cancelado') then raise exception 'estado_invalido' using errcode = 'check_violation'; end if;
  if c.miembro_id <> miembro_actual(c.grupo_id) then raise exception 'solo_el_saliente' using errcode = 'insufficient_privilege'; end if;
  perform set_config('app.motivo', 'salida de socio cancelada', true);
  update salida_socio_casos set estado = 'cancelado', cerrado_en = now() where id = c.id;
end $$;

-- ---------------------------------------------------------------- desacuerdos y mediador (SA34, DF-26)
create table disputas (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  titulo text not null check (length(trim(titulo)) between 3 and 160),
  ref_tipo text check (ref_tipo is null or ref_tipo in ('gasto', 'dano', '911', 'orden', 'otro')),
  ref_id uuid,
  estado text not null default 'abierta' check (estado in ('abierta', 'cerrada')),
  resultado text check (resultado is null or resultado in ('acuerdo', 'sin_acuerdo')),
  nota_cierre text check (nota_cierre is null or length(nota_cierre) <= 1000),
  abierta_por uuid not null references miembros (id),
  creado_en timestamptz not null default now(),
  cerrada_en timestamptz
);
create index disputas_grupo_idx on disputas (grupo_id, estado);
create trigger disputas_auditar after insert or update on disputas for each row execute function auditar();

create table disputa_mensajes (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  disputa_id uuid not null references disputas (id) on delete cascade,
  autor_usuario uuid,
  autor_nombre text,
  rol text not null check (rol in ('socio', 'mediador', 'sistema')),
  texto text not null check (length(trim(texto)) between 1 and 2000),
  creado_en timestamptz not null default now()
);
create index disputa_mensajes_idx on disputa_mensajes (disputa_id, creado_en);

create table disputa_mediadores (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  disputa_id uuid not null references disputas (id) on delete cascade,
  correo citext not null,
  token_hash text not null,
  usuario_id uuid references auth.users (id),
  estado text not null default 'invitado' check (estado in ('invitado', 'activo', 'finalizado')),
  invitado_por uuid not null references miembros (id),
  creado_en timestamptz not null default now()
);
create unique index disputa_mediador_unico on disputa_mediadores (disputa_id, correo) where estado <> 'finalizado';
create trigger disputa_mediadores_auditar after insert or update on disputa_mediadores for each row execute function auditar();

create function es_mediador_de(p_disputa uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from disputa_mediadores x join disputas d on d.id = x.disputa_id
                  where x.disputa_id = p_disputa and x.usuario_id = auth.uid() and x.estado = 'activo' and d.estado = 'abierta')
$$;
grant execute on function es_mediador_de(uuid) to authenticated;

create function disputa_abrir(p_grupo uuid, p_titulo text, p_ref_tipo text, p_ref_id uuid, p_texto text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_yo uuid := miembro_actual(p_grupo); v_id uuid; v_nom text;
begin
  if v_yo is null or not es_socio(p_grupo) then raise exception 'solo_socios' using errcode = 'insufficient_privilege'; end if;
  select coalesce(pf.nombre, pf.correo::text) into v_nom from miembros m join perfiles pf on pf.id = m.usuario_id where m.id = v_yo;
  perform set_config('app.motivo', 'disputa abierta', true);
  insert into disputas (grupo_id, titulo, ref_tipo, ref_id, abierta_por) values (p_grupo, trim(p_titulo), nullif(p_ref_tipo, ''), p_ref_id, v_yo)
  returning id into v_id;
  insert into disputa_mensajes (grupo_id, disputa_id, autor_usuario, autor_nombre, rol, texto)
  values (p_grupo, v_id, auth.uid(), v_nom, 'socio', coalesce(nullif(trim(p_texto), ''), trim(p_titulo)));
  perform avisar_equipo(p_grupo, 'disputa_abierta', 'Nuevo desacuerdo', trim(p_titulo), jsonb_build_object('disputa_id', v_id), true);
  return v_id;
end $$;

create function disputa_mensaje(p_disputa uuid, p_texto text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare d disputas; v_rol text; v_nom text;
begin
  select * into d from disputas where id = p_disputa;
  if not found then raise exception 'disputa_no_existe' using errcode = 'no_data_found'; end if;
  if d.estado <> 'abierta' then raise exception 'estado_invalido: la disputa está cerrada' using errcode = 'check_violation'; end if;
  if es_socio(d.grupo_id) then v_rol := 'socio';
  elsif es_mediador_de(d.id) then v_rol := 'mediador';
  else raise exception 'sin_permiso' using errcode = 'insufficient_privilege'; end if;
  select coalesce(nombre, correo::text) into v_nom from perfiles where id = auth.uid();
  insert into disputa_mensajes (grupo_id, disputa_id, autor_usuario, autor_nombre, rol, texto)
  values (d.grupo_id, d.id, auth.uid(), v_nom, v_rol, left(trim(p_texto), 2000));
end $$;

-- A los N días sin acuerdo (política) se puede invitar a un mediador. Devuelve el token (enlace /mediar/<token>).
create function disputa_invitar_mediador(p_disputa uuid, p_correo text) returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare d disputas; v_yo uuid; v_dias int; v_token text;
begin
  select * into d from disputas where id = p_disputa for update;
  if not found then raise exception 'disputa_no_existe' using errcode = 'no_data_found'; end if;
  v_yo := miembro_actual(d.grupo_id);
  if v_yo is null or not es_socio(d.grupo_id) then raise exception 'solo_socios' using errcode = 'insufficient_privilege'; end if;
  if d.estado <> 'abierta' then raise exception 'estado_invalido' using errcode = 'check_violation'; end if;
  v_dias := coalesce(pol_txt(d.grupo_id, 'desacuerdos.dias_mediador')::int, 7);
  if now() < d.creado_en + make_interval(days => v_dias) then
    raise exception 'mediador_aun_no: el mediador se puede invitar a los % días sin acuerdo', v_dias using errcode = 'check_violation';
  end if;
  if p_correo !~ '^[^@\s]+@[^@\s]+$' then raise exception 'correo_invalido' using errcode = 'check_violation'; end if;
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  perform set_config('app.motivo', 'mediador invitado', true);
  insert into disputa_mediadores (grupo_id, disputa_id, correo, token_hash, invitado_por)
  values (d.grupo_id, d.id, lower(trim(p_correo)), hash_token(v_token), v_yo);
  insert into disputa_mensajes (grupo_id, disputa_id, rol, texto) values (d.grupo_id, d.id, 'sistema', 'Se invitó a un mediador.');
  return v_token;
end $$;

create function disputa_aceptar_mediacion(p_token text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare x disputa_mediadores; v_estado text;
begin
  if auth.uid() is null then raise exception 'no_autenticado' using errcode = 'insufficient_privilege'; end if;
  select * into x from disputa_mediadores where token_hash = hash_token(p_token) for update;
  if not found or lower(x.correo::text) <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'invitacion_no_valida' using errcode = 'no_data_found';
  end if;
  select estado into v_estado from disputas where id = x.disputa_id;
  if x.estado = 'finalizado' or v_estado <> 'abierta' then raise exception 'mediacion_cerrada' using errcode = 'check_violation'; end if;
  perform set_config('app.motivo', 'mediación aceptada', true);
  update disputa_mediadores set usuario_id = auth.uid(), estado = 'activo' where id = x.id;
  return x.disputa_id;
end $$;

create function disputa_cerrar(p_disputa uuid, p_resultado text, p_nota text default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare d disputas;
begin
  select * into d from disputas where id = p_disputa for update;
  if not found or not es_socio(d.grupo_id) then raise exception 'solo_socios' using errcode = 'insufficient_privilege'; end if;
  if d.estado <> 'abierta' or p_resultado not in ('acuerdo', 'sin_acuerdo') then raise exception 'estado_invalido' using errcode = 'check_violation'; end if;
  perform set_config('app.motivo', 'disputa cerrada: ' || p_resultado, true);
  update disputas set estado = 'cerrada', resultado = p_resultado, nota_cierre = left(p_nota, 1000), cerrada_en = now() where id = d.id;
  update disputa_mediadores set estado = 'finalizado' where disputa_id = d.id and estado <> 'finalizado';
  insert into disputa_mensajes (grupo_id, disputa_id, rol, texto)
  values (d.grupo_id, d.id, 'sistema', 'Disputa cerrada: ' || case p_resultado when 'acuerdo' then 'con acuerdo' else 'sin acuerdo' end);
end $$;

-- ---------------------------------------------------------------- RLS
alter table salida_socio_casos enable row level security;
alter table salida_socio_ofertas enable row level security;
alter table salida_socio_acuses enable row level security;
alter table disputas enable row level security;
alter table disputa_mensajes enable row level security;
alter table disputa_mediadores enable row level security;
revoke all on salida_socio_casos, salida_socio_ofertas, salida_socio_acuses, disputas, disputa_mensajes, disputa_mediadores from anon, authenticated;
grant select on salida_socio_casos, salida_socio_ofertas, salida_socio_acuses, disputas, disputa_mensajes, disputa_mediadores to authenticated;
create policy salida_casos_select on salida_socio_casos for select to authenticated using (es_socio(grupo_id));
create policy salida_ofertas_select on salida_socio_ofertas for select to authenticated using (es_socio(grupo_id));
create policy salida_acuses_select on salida_socio_acuses for select to authenticated using (es_socio(grupo_id));
-- el mediador ve SOLO su caso y sus mensajes; nada más del grupo
create policy disputas_select on disputas for select to authenticated using (es_socio(grupo_id) or es_mediador_de(id));
create policy disputa_mensajes_select on disputa_mensajes for select to authenticated using (es_socio(grupo_id) or es_mediador_de(disputa_id));
create policy disputa_mediadores_select on disputa_mediadores for select to authenticated using (es_socio(grupo_id));

revoke execute on function salida_socio_solicitar(uuid, text), salida_socio_valorar(uuid, text), salida_socio_ofertar(uuid, numeric, numeric, text),
  salida_socio_responder(uuid, boolean), salida_socio_cerrar(uuid), salida_socio_cancelar(uuid),
  disputa_abrir(uuid, text, text, uuid, text), disputa_mensaje(uuid, text), disputa_invitar_mediador(uuid, text),
  disputa_aceptar_mediacion(text), disputa_cerrar(uuid, text, text) from public, anon;
grant execute on function salida_socio_solicitar(uuid, text), salida_socio_valorar(uuid, text), salida_socio_ofertar(uuid, numeric, numeric, text),
  salida_socio_responder(uuid, boolean), salida_socio_cerrar(uuid), salida_socio_cancelar(uuid),
  disputa_abrir(uuid, text, text, uuid, text), disputa_mensaje(uuid, text), disputa_invitar_mediador(uuid, text),
  disputa_aceptar_mediacion(text), disputa_cerrar(uuid, text, text) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table disputa_mensajes;
  end if;
end $$;
