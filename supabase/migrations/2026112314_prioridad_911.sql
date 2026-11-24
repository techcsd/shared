-- 2026-11-23 · 14 · Prioridad 911: pedir, nunca quitar (SA8)

create type motivo_911 as enum ('cumpleanos', 'evento_familiar', 'cliente', 'negocio');
create type urgencia_911 as enum ('baja', 'media', 'alta');
create type estado_911 as enum ('pendiente', 'aceptada', 'rechazada', 'contrapropuesta', 'aceptada_contra', 'rechazada_contra', 'expirada');

create table solicitudes_911 (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  reserva_id uuid not null references reservas (id) on delete cascade,
  titular_id uuid not null references miembros (id),
  solicitante_id uuid not null references miembros (id),
  motivo motivo_911 not null,
  urgencia urgencia_911 not null default 'media',
  alternativa text check (alternativa is null or length(alternativa) <= 500),
  rango tstzrange not null,
  uso uso_reserva not null default 'personal',
  destino_id uuid references destinos (id),
  personas int not null check (personas between 1 and 1000),
  estado estado_911 not null default 'pendiente',
  contra_rango tstzrange,
  expira_en timestamptz not null,
  reserva_resultante_id uuid references reservas (id),
  creado_en timestamptz not null default now(),
  resuelta_en timestamptz,
  check (titular_id <> solicitante_id),
  check (uso <> 'invitado')   -- una 911 la hace un socio; el invitado se agrega después en su propia reserva
);
create index solicitudes_911_grupo_idx on solicitudes_911 (grupo_id, estado);
create unique index solicitudes_911_una_pendiente on solicitudes_911 (reserva_id, solicitante_id)
  where estado in ('pendiente', 'contrapropuesta');
create trigger solicitudes_911_auditar after insert or update or delete on solicitudes_911
  for each row execute function auditar();

create table solicitudes_911_mensajes (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  solicitud_id uuid not null references solicitudes_911 (id) on delete cascade,
  autor_id uuid references miembros (id),
  tipo text not null check (tipo in ('solicitud', 'acepta', 'rechaza', 'contrapropone', 'acepta_contra', 'rechaza_contra', 'expiracion')),
  texto text check (texto is null or length(texto) <= 1000),
  creado_en timestamptz not null default now()
);
create index solicitudes_911_mensajes_idx on solicitudes_911_mensajes (solicitud_id, creado_en);

-- Crea una reserva confirmada para el solicitante (misma vía que una reserva normal: validaciones, orden, avisos).
create function p911_reservar_para(p_sol solicitudes_911, p_rango tstzrange) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_res reservas; v_id uuid;
begin
  select * into v_res from reservas where id = p_sol.reserva_id;
  insert into reservas (grupo_id, activo_id, rango, rango_bloqueo, estado, uso, destino_id, personas,
                        reservado_por, responsable_miembro, borrador_expira_en)
  values (p_sol.grupo_id, v_res.activo_id, p_rango, p_rango, 'borrador', p_sol.uso, p_sol.destino_id, p_sol.personas,
          p_sol.solicitante_id, p_sol.solicitante_id, now() + interval '1 hour')
  returning id into v_id;
  perform reserva_confirmar_interna(v_id);
  return v_id;
end $$;
revoke execute on function p911_reservar_para(solicitudes_911, tstzrange) from public, anon, authenticated;

create function p911_mensaje(p_sol uuid, p_grupo uuid, p_autor uuid, p_tipo text, p_texto text) returns void
language sql security definer set search_path = public, pg_temp as $$
  insert into solicitudes_911_mensajes (grupo_id, solicitud_id, autor_id, tipo, texto)
  values (p_grupo, p_sol, p_autor, p_tipo, left(p_texto, 1000))
$$;
revoke execute on function p911_mensaje(uuid, uuid, uuid, text, text) from public, anon, authenticated;

create function p911_avisar_socios(p_grupo uuid, p_tipo text, p_titulo text, p_cuerpo text, p_datos jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare s record;
begin
  for s in select usuario_id from miembros where grupo_id = p_grupo and rol = 'socio' and estado = 'activo' loop
    perform notificar(p_grupo, s.usuario_id, p_tipo, p_titulo, p_cuerpo, p_datos);
  end loop;
end $$;
revoke execute on function p911_avisar_socios(uuid, text, text, text, jsonb) from public, anon, authenticated;

-- Solicitar: no toca la reserva de nadie.
create function prioridad_911_solicitar(
  p_reserva uuid, p_motivo motivo_911, p_urgencia urgencia_911, p_alternativa text default null,
  p_uso uso_reserva default 'personal', p_destino uuid default null, p_personas int default 1,
  p_mensaje text default null
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare r reservas; v_yo uuid; v_id uuid; v_horas int; v_cod text; s solicitudes_911;
begin
  select * into r from reservas where id = p_reserva;
  v_yo := case when r.id is null then null else miembro_actual(r.grupo_id) end;
  if v_yo is null or not es_socio(r.grupo_id) then
    raise exception 'solo_socios' using errcode = 'insufficient_privilege';
  end if;
  if r.tipo_bloqueo is not null or r.estado <> 'confirmada' then
    raise exception 'la_reserva_no_admite_911: solo una reserva confirmada' using errcode = 'check_violation';
  end if;
  if r.reservado_por = v_yo then
    raise exception 'es_tu_reserva' using errcode = 'check_violation';
  end if;
  if lower(r.rango) < now() then
    raise exception 'la_reserva_ya_empezo' using errcode = 'check_violation';
  end if;
  v_horas := coalesce(pol_txt(r.grupo_id, 'prioridad_911.expira_horas')::int, 72);
  perform set_config('app.motivo', 'prioridad 911', true);
  insert into solicitudes_911 (grupo_id, reserva_id, titular_id, solicitante_id, motivo, urgencia, alternativa,
                               rango, uso, destino_id, personas, expira_en)
  values (r.grupo_id, r.id, r.reservado_por, v_yo, p_motivo, p_urgencia, left(p_alternativa, 500),
          r.rango, p_uso, p_destino, p_personas, now() + make_interval(hours => v_horas))
  returning id into v_id;
  perform p911_mensaje(v_id, r.grupo_id, v_yo, 'solicitud', coalesce(p_mensaje, p_alternativa));
  select codigo into v_cod from ordenes where reserva_id = r.id;
  -- el aviso va al titular y a todos los demás socios
  perform p911_avisar_socios(r.grupo_id, 'prioridad_911_solicitud', 'Prioridad 911 sobre ' || v_cod,
    'Un socio pide tu fecha (motivo: ' || p_motivo || ', urgencia: ' || p_urgencia || '). Tu reserva sigue vigente hasta que decidas.',
    jsonb_build_object('solicitud_id', v_id, 'reserva_id', r.id, 'orden', v_cod));
  return v_id;
end $$;

-- Responder (solo el titular): acepta | rechaza | contrapropone
create function prioridad_911_responder(
  p_solicitud uuid, p_accion text, p_mensaje text default null,
  p_contra_inicio timestamptz default null, p_contra_fin timestamptz default null
) returns estado_911
language plpgsql security definer set search_path = public, pg_temp as $$
declare s solicitudes_911; v_yo uuid; v_nueva uuid; v_cod text; v_cod_nuevo text;
begin
  select * into s from solicitudes_911 where id = p_solicitud for update;
  v_yo := case when s.id is null then null else miembro_actual(s.grupo_id) end;
  if v_yo is null or v_yo is distinct from s.titular_id then
    raise exception 'solo_titular_decide' using errcode = 'insufficient_privilege';
  end if;
  if s.estado <> 'pendiente' then
    raise exception 'solicitud_%', s.estado using errcode = 'check_violation';
  end if;
  if s.expira_en < now() then
    update solicitudes_911 set estado = 'expirada', resuelta_en = now() where id = s.id;
    perform p911_mensaje(s.id, s.grupo_id, null, 'expiracion', 'La solicitud expiró sin respuesta; la reserva no cambió.');
    return 'expirada';
  end if;
  select codigo into v_cod from ordenes where reserva_id = s.reserva_id;
  perform set_config('app.motivo', 'respuesta 911: ' || p_accion, true);

  if p_accion = 'acepta' then
    -- todo en una sola transacción: cede la reserva, crea la nueva (con su orden) y avisa a todos
    update reservas set estado = 'cancelada', cancelada_en = now(), cancelada_por = v_yo,
           motivo_cancelacion = 'Cedida por Prioridad 911', cancelacion_tardia = false
     where id = s.reserva_id and estado = 'confirmada';
    if not found then
      raise exception 'la_reserva_ya_no_esta_confirmada' using errcode = 'check_violation';
    end if;
    v_nueva := p911_reservar_para(s, s.rango);
    select codigo into v_cod_nuevo from ordenes where reserva_id = v_nueva;
    update solicitudes_911 set estado = 'aceptada', resuelta_en = now(), reserva_resultante_id = v_nueva where id = s.id;
    perform p911_mensaje(s.id, s.grupo_id, v_yo, 'acepta', p_mensaje);
    perform p911_avisar_socios(s.grupo_id, 'prioridad_911_aceptada', 'Prioridad 911 aceptada',
      'La reserva ' || v_cod || ' fue cedida. Nueva orden: ' || v_cod_nuevo || '.',
      jsonb_build_object('solicitud_id', s.id, 'orden', v_cod_nuevo, 'reserva_id', v_nueva));
    return 'aceptada';
  elsif p_accion = 'rechaza' then
    update solicitudes_911 set estado = 'rechazada', resuelta_en = now() where id = s.id;
    perform p911_mensaje(s.id, s.grupo_id, v_yo, 'rechaza', p_mensaje);
    perform p911_avisar_socios(s.grupo_id, 'prioridad_911_rechazada', 'Prioridad 911 rechazada',
      'Se mantiene la reserva ' || v_cod || '.', jsonb_build_object('solicitud_id', s.id, 'orden', v_cod));
    return 'rechazada';
  elsif p_accion = 'contrapropone' then
    if p_contra_inicio is null or p_contra_fin is null or p_contra_inicio >= p_contra_fin or p_contra_inicio < now() then
      raise exception 'contrapropuesta_invalida' using errcode = 'check_violation';
    end if;
    update solicitudes_911 set estado = 'contrapropuesta', contra_rango = tstzrange(p_contra_inicio, p_contra_fin, '[)') where id = s.id;
    perform p911_mensaje(s.id, s.grupo_id, v_yo, 'contrapropone',
      coalesce(p_mensaje, '') || ' [' || p_contra_inicio || ' → ' || p_contra_fin || ']');
    perform p911_avisar_socios(s.grupo_id, 'prioridad_911_contrapropuesta', 'Prioridad 911: contrapropuesta',
      'El titular de ' || v_cod || ' ofrece otra fecha u horario.', jsonb_build_object('solicitud_id', s.id, 'orden', v_cod));
    return 'contrapropuesta';
  end if;
  raise exception 'accion_invalida' using errcode = 'invalid_parameter_value';
end $$;

-- El solicitante responde a la contrapropuesta.
create function prioridad_911_responder_contra(p_solicitud uuid, p_acepta boolean, p_mensaje text default null)
returns estado_911
language plpgsql security definer set search_path = public, pg_temp as $$
declare s solicitudes_911; v_yo uuid; v_nueva uuid; v_cod_nuevo text; v_cod text;
begin
  select * into s from solicitudes_911 where id = p_solicitud for update;
  v_yo := case when s.id is null then null else miembro_actual(s.grupo_id) end;
  if v_yo is null or v_yo is distinct from s.solicitante_id then
    raise exception 'solo_solicitante_responde' using errcode = 'insufficient_privilege';
  end if;
  if s.estado <> 'contrapropuesta' then
    raise exception 'solicitud_%', s.estado using errcode = 'check_violation';
  end if;
  select codigo into v_cod from ordenes where reserva_id = s.reserva_id;
  perform set_config('app.motivo', 'respuesta a contrapropuesta 911', true);
  if p_acepta then
    -- el titular conserva su reserva; el solicitante recibe la reserva en el horario ofrecido
    v_nueva := p911_reservar_para(s, s.contra_rango);
    select codigo into v_cod_nuevo from ordenes where reserva_id = v_nueva;
    update solicitudes_911 set estado = 'aceptada_contra', resuelta_en = now(), reserva_resultante_id = v_nueva where id = s.id;
    perform p911_mensaje(s.id, s.grupo_id, v_yo, 'acepta_contra', p_mensaje);
    perform p911_avisar_socios(s.grupo_id, 'prioridad_911_aceptada', 'Prioridad 911: contrapropuesta aceptada',
      'Nueva orden ' || v_cod_nuevo || '. La reserva ' || v_cod || ' no cambia.',
      jsonb_build_object('solicitud_id', s.id, 'orden', v_cod_nuevo, 'reserva_id', v_nueva));
    return 'aceptada_contra';
  end if;
  update solicitudes_911 set estado = 'rechazada_contra', resuelta_en = now() where id = s.id;
  perform p911_mensaje(s.id, s.grupo_id, v_yo, 'rechaza_contra', p_mensaje);
  perform p911_avisar_socios(s.grupo_id, 'prioridad_911_rechazada', 'Prioridad 911: contrapropuesta rechazada',
    'Se mantiene la reserva ' || v_cod || '.', jsonb_build_object('solicitud_id', s.id, 'orden', v_cod));
  return 'rechazada_contra';
end $$;

-- Expira solicitudes sin respuesta; NUNCA toca la reserva.
create function prioridad_911_expirar() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare s record; n int := 0;
begin
  for s in select id, grupo_id from solicitudes_911 where estado in ('pendiente', 'contrapropuesta') and expira_en < now() loop
    update solicitudes_911 set estado = 'expirada', resuelta_en = now() where id = s.id;
    perform p911_mensaje(s.id, s.grupo_id, null, 'expiracion', 'La solicitud expiró sin respuesta; la reserva no cambió.');
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function prioridad_911_expirar() from public, anon, authenticated;

alter table solicitudes_911 enable row level security;
alter table solicitudes_911_mensajes enable row level security;
revoke all on solicitudes_911, solicitudes_911_mensajes from anon, authenticated;
grant select on solicitudes_911, solicitudes_911_mensajes to authenticated;
create policy solicitudes_911_select on solicitudes_911 for select to authenticated using (es_socio(grupo_id));
create policy solicitudes_911_mensajes_select on solicitudes_911_mensajes for select to authenticated using (es_socio(grupo_id));

revoke execute on function prioridad_911_solicitar(uuid, motivo_911, urgencia_911, text, uso_reserva, uuid, int, text),
  prioridad_911_responder(uuid, text, text, timestamptz, timestamptz),
  prioridad_911_responder_contra(uuid, boolean, text) from public, anon;
grant execute on function prioridad_911_solicitar(uuid, motivo_911, urgencia_911, text, uso_reserva, uuid, int, text),
  prioridad_911_responder(uuid, text, text, timestamptz, timestamptz),
  prioridad_911_responder_contra(uuid, boolean, text) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table solicitudes_911, solicitudes_911_mensajes;
  end if;
end $$;
