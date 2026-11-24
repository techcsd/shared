-- 2026-11-23 · 13 · RPC de reservas: validación, borrador, confirmar, cancelar, iniciar, finalizar, bloqueos, acuses, temporada

-- SA7: solo transiciones válidas, también contra SQL directo.
create function reservas_validar_transicion() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if new.estado = old.estado then return new; end if;
  if (old.estado, new.estado) in (
       ('borrador', 'confirmada'), ('borrador', 'cancelada'),
       ('confirmada', 'en_curso'), ('confirmada', 'cancelada'),
       ('en_curso', 'finalizada'), ('bloqueada_mantenimiento', 'cancelada')) then
    return new;
  end if;
  raise exception 'transicion_invalida: de % a %', old.estado, new.estado using errcode = 'check_violation';
end $$;
create trigger reservas_transicion before update of estado on reservas
  for each row execute function reservas_validar_transicion();

-- Validación central de políticas y límites (la usan borrador, confirmación y 911).
create function reserva_validar(
  p_grupo uuid, p_activo uuid, p_miembro uuid, p_inicio timestamptz, p_fin timestamptz,
  p_uso uso_reserva, p_personas int, p_excluir uuid default null
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_act activos; v_zona text; v_horas numeric; v_max text; v_cap int; v_derechos text;
  v_cuota numeric; v_usado numeric; v_mes_ini timestamptz; v_mes_fin timestamptz; t temporadas;
  v_pct numeric; v_dias_mes int;
begin
  select * into v_act from activos where id = p_activo and grupo_id = p_grupo;
  if not found or v_act.estado <> 'activo' then
    raise exception 'activo_no_disponible' using errcode = 'check_violation';
  end if;
  if p_inicio is null or p_fin is null or p_inicio >= p_fin then
    raise exception 'rango_invalido' using errcode = 'check_violation';
  end if;
  if p_inicio < now() - interval '5 minutes' then
    raise exception 'fecha_pasada' using errcode = 'check_violation';
  end if;
  if p_fin - p_inicio > interval '30 days' then
    raise exception 'rango_muy_largo' using errcode = 'check_violation';
  end if;
  select zona_horaria into v_zona from grupos where id = p_grupo;
  v_horas := extract(epoch from (p_fin - p_inicio)) / 3600;

  -- DF-10: varios días y tope de días seguidos
  if not coalesce(pol_txt(p_grupo, 'reservas.multi_dia_permitido')::boolean, true)
     and (p_inicio at time zone v_zona)::date <> ((p_fin - interval '1 second') at time zone v_zona)::date then
    raise exception 'multi_dia_no_permitido' using errcode = 'check_violation';
  end if;
  v_max := pol_txt(p_grupo, 'reservas.dias_max_seguidos');
  if v_max is not null and ceil(v_horas / 24) > v_max::int then
    raise exception 'dias_max_superados: máximo % días', v_max using errcode = 'check_violation';
  end if;

  -- SA9 / DF-17: capacidad (el límite legal manda)
  v_cap := capacidad_efectiva_interna(p_activo, p_uso);
  if p_personas is null or p_personas < 1 or p_personas > v_cap then
    raise exception 'capacidad_excedida: máximo % personas', v_cap using errcode = 'check_violation';
  end if;

  -- DF-16: derechos de uso (iguales = sin cuotas; cuota/proporcional si el grupo lo activó)
  v_derechos := pol_txt(p_grupo, 'derechos_uso');
  v_cuota := null;
  v_mes_ini := date_trunc('month', p_inicio at time zone v_zona) at time zone v_zona;
  v_mes_fin := v_mes_ini + interval '1 month';
  if v_derechos = 'cuota' then
    v_cuota := pol_txt(p_grupo, 'derechos_uso.cuota_horas_mes')::numeric;
  elsif v_derechos = 'proporcional' then
    select porcentaje into v_pct from miembros where id = p_miembro;
    v_dias_mes := extract(day from (v_mes_fin - v_mes_ini))::int;
    v_cuota := coalesce(v_pct, 0) / 100 * v_dias_mes * 24;
  end if;
  if v_cuota is not null then
    select coalesce(sum(extract(epoch from (upper(rango) - lower(rango))) / 3600), 0) into v_usado
      from reservas
     where grupo_id = p_grupo and reservado_por = p_miembro
       and estado in ('confirmada', 'en_curso', 'finalizada')
       and (p_excluir is null or id <> p_excluir)
       and lower(rango) >= v_mes_ini and lower(rango) < v_mes_fin;
    if v_usado + v_horas > v_cuota then
      raise exception 'cuota_excedida: usadas % h de % h', round(v_usado, 1), round(v_cuota, 1)
        using errcode = 'check_violation';
    end if;
  end if;

  -- DF-19 / SA27: temporada alta con prioridad rotativa (solo si la política está activa)
  if coalesce(pol_txt(p_grupo, 'temporada_alta.activa')::boolean, false) then
    for t in
      select * from temporadas
       where grupo_id = p_grupo and libre_desde > now()
         and daterange(desde, hasta + 1) && daterange(
               (p_inicio at time zone v_zona)::date,
               ((p_fin - interval '1 second') at time zone v_zona)::date + 1)
    loop
      if t.miembro_prioridad is distinct from p_miembro then
        raise exception 'temporada_alta_prioridad: % %, le toca a otro socio', t.periodo, t.anio
          using errcode = 'check_violation';
      end if;
    end loop;
  end if;
end $$;
revoke execute on function reserva_validar(uuid, uuid, uuid, timestamptz, timestamptz, uso_reserva, int, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------- borrador (SC6, DF-14)
create function reserva_crear_borrador(
  p_activo uuid, p_inicio timestamptz, p_fin timestamptz, p_uso uso_reserva, p_destino uuid,
  p_personas int, p_responsable_miembro uuid default null,
  p_invitado_nombre text default null, p_invitado_correo text default null,
  p_anfitrion uuid default null, p_notas text default null
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_grupo uuid; v_yo uuid; v_inv uuid; v_resp_m uuid; v_id uuid; v_horas int;
begin
  select grupo_id into v_grupo from activos where id = p_activo;
  if v_grupo is null then
    raise exception 'activo_no_existe' using errcode = 'no_data_found';
  end if;
  v_yo := miembro_actual(v_grupo);
  if v_yo is null or not es_socio(v_grupo) then
    raise exception 'solo_socios_reservan' using errcode = 'insufficient_privilege';
  end if;
  if p_destino is not null and not exists (select 1 from destinos where id = p_destino and grupo_id = v_grupo and activo) then
    raise exception 'destino_invalido' using errcode = 'check_violation';
  end if;
  perform reserva_validar(v_grupo, p_activo, v_yo, p_inicio, p_fin, p_uso, p_personas, null);

  if p_uso = 'invitado' then
    if coalesce(trim(p_invitado_nombre), '') = '' or coalesce(trim(p_invitado_correo), '') = '' then
      raise exception 'invitado_requiere_nombre_y_correo' using errcode = 'check_violation';
    end if;
    if p_anfitrion is not null and not exists (
         select 1 from miembros where id = p_anfitrion and grupo_id = v_grupo and rol = 'socio' and estado = 'activo') then
      raise exception 'anfitrion_invalido' using errcode = 'check_violation';
    end if;
    insert into invitados (grupo_id, nombre, correo, anfitrion_id)
    values (v_grupo, trim(p_invitado_nombre), trim(p_invitado_correo), coalesce(p_anfitrion, v_yo))
    returning id into v_inv;
  else
    v_resp_m := coalesce(p_responsable_miembro, v_yo);
    if not exists (select 1 from miembros where id = v_resp_m and grupo_id = v_grupo and estado = 'activo') then
      raise exception 'responsable_invalido' using errcode = 'check_violation';
    end if;
  end if;

  v_horas := coalesce(pol_txt(v_grupo, 'reservas.borrador_horas')::int, 24);
  perform set_config('app.motivo', 'borrador de reserva', true);
  insert into reservas (grupo_id, activo_id, rango, rango_bloqueo, estado, uso, destino_id, personas,
                        reservado_por, responsable_miembro, responsable_invitado, notas, borrador_expira_en)
  values (v_grupo, p_activo, tstzrange(p_inicio, p_fin, '[)'), tstzrange(p_inicio, p_fin, '[)'), 'borrador',
          p_uso, p_destino, p_personas, v_yo, v_resp_m, v_inv, left(p_notas, 1000),
          now() + make_interval(hours => v_horas))
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------- confirmar (SA3, SA5, DF-32)
-- Interna: la usan la confirmación normal y la aceptación de 911. No mira auth.uid().
create function reserva_confirmar_interna(p_reserva uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r reservas; v_buffer numeric; v_zona text; v_anio int; v_n int; v_prefijo text; v_codigo text;
  v_fee numeric; v_mon char(3); v_token text; v_inv invitados; v_horas int; v_act activos;
  v_yo_usuario uuid; s record; v_nombre text;
begin
  select * into r from reservas where id = p_reserva for update;
  if not found or r.estado <> 'borrador' then
    raise exception 'transicion_invalida: solo un borrador se confirma' using errcode = 'check_violation';
  end if;
  if r.borrador_expira_en is not null and r.borrador_expira_en < now() then
    raise exception 'borrador_expirado' using errcode = 'check_violation';
  end if;
  perform reserva_validar(r.grupo_id, r.activo_id, r.reservado_por, lower(r.rango), upper(r.rango), r.uso, r.personas, r.id);

  v_buffer := coalesce(pol_txt(r.grupo_id, 'reservas.buffer_horas')::numeric, 0);
  begin
    update reservas
       set estado = 'confirmada', borrador_expira_en = null,
           rango_bloqueo = tstzrange(lower(rango) - make_interval(secs => v_buffer * 1800),
                                     upper(rango) + make_interval(secs => v_buffer * 1800), '[)')
     where id = r.id;
  exception when exclusion_violation then
    raise exception 'horario_ocupado' using errcode = '23P01';
  end;

  -- número de orden {PREFIJO}-{AAAA}-{NNNN}, atómico por grupo y año
  select zona_horaria into v_zona from grupos where id = r.grupo_id;
  v_anio := extract(year from now() at time zone v_zona)::int;
  insert into orden_contadores (grupo_id, anio, ultimo) values (r.grupo_id, v_anio, 1)
  on conflict (grupo_id, anio) do update set ultimo = orden_contadores.ultimo + 1
  returning ultimo into v_n;
  select t.prefijo_orden into v_prefijo from tipos_activo t join activos a on a.tipo_id = t.id where a.id = r.activo_id;
  v_codigo := v_prefijo || '-' || v_anio || '-' || lpad(v_n::text, 4, '0');
  insert into ordenes (grupo_id, reserva_id, anio, numero, codigo) values (r.grupo_id, r.id, v_anio, v_n, v_codigo);

  -- fee estimado (solo socios lo ven)
  select monto, moneda into v_fee, v_mon from fee_calc(r.grupo_id, r.destino_id, lower(r.rango), upper(r.rango));
  if v_fee is not null and v_fee > 0 then
    insert into reserva_costos (reserva_id, grupo_id, fee, moneda) values (r.id, r.grupo_id, v_fee, v_mon);
  end if;

  -- aviso a los demás socios (SA3: aviso, no permiso)
  select a.nombre into v_nombre from activos a where a.id = r.activo_id;
  select m.usuario_id into v_yo_usuario from miembros m where m.id = r.reservado_por;
  for s in select m.usuario_id from miembros m
            where m.grupo_id = r.grupo_id and m.rol = 'socio' and m.estado = 'activo' and m.id <> r.reservado_por loop
    perform notificar(r.grupo_id, s.usuario_id, 'reserva_confirmada', 'Nueva reserva ' || v_codigo,
      v_nombre || ': ' || to_char(lower(r.rango) at time zone v_zona, 'DD/MM/YYYY HH24:MI') || ' a '
        || to_char(upper(r.rango) at time zone v_zona, 'DD/MM/YYYY HH24:MI') || '. Marca «Leído y enterado» (no es una aprobación).',
      jsonb_build_object('reserva_id', r.id, 'orden', v_codigo), coalesce(pol_txt(r.grupo_id, 'reservas.acuse_requerido')::boolean, true));
  end loop;

  -- invitado sin cuenta (SC8, DF-31): enlace de un solo propósito, hasheado, expira tras el regreso
  if r.uso = 'invitado' then
    select * into v_inv from invitados where id = r.responsable_invitado;
    select * into v_act from activos where id = r.activo_id;
    v_horas := coalesce(pol_txt(r.grupo_id, 'invitados.enlace_horas_tras_regreso')::int, 24);
    v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    insert into invitado_enlaces (grupo_id, reserva_id, invitado_id, token_hash, expira_en)
    values (r.grupo_id, r.id, v_inv.id, hash_token(v_token), upper(r.rango) + make_interval(hours => v_horas));
    perform notificar_correo(r.grupo_id, v_inv.correo::text, 'invitado_enlace', 'Tu salida en ' || v_act.nombre,
      'Fecha y horario: ' || to_char(lower(r.rango) at time zone v_zona, 'DD/MM/YYYY HH24:MI') || ' a '
        || to_char(upper(r.rango) at time zone v_zona, 'DD/MM/YYYY HH24:MI'),
      jsonb_build_object('token', v_token, 'reserva_id', r.id, 'orden', v_codigo));
  end if;
  return v_codigo;
end $$;
revoke execute on function reserva_confirmar_interna(uuid) from public, anon, authenticated;

create function reserva_confirmar(p_reserva uuid) returns table (reserva_id uuid, orden text)
language plpgsql security definer set search_path = public, pg_temp as $$
declare r reservas; v_codigo text;
begin
  select * into r from reservas where id = p_reserva;
  if not found or r.reservado_por is distinct from miembro_actual(r.grupo_id) then
    raise exception 'solo_quien_reserva' using errcode = 'insufficient_privilege';
  end if;
  perform set_config('app.motivo', 'confirmación de reserva', true);
  v_codigo := reserva_confirmar_interna(p_reserva);
  return query select p_reserva, v_codigo;
end $$;

-- ---------------------------------------------------------------- cancelar (SA22, DF-09)
create function reserva_cancelar(p_reserva uuid, p_motivo text default null)
returns table (tardia boolean, cargo numeric)
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r reservas; v_horas int; v_pct numeric; v_tardia boolean := false; v_cargo numeric := 0; v_fee numeric;
  v_codigo text; s record;
begin
  select * into r from reservas where id = p_reserva for update;
  if not found or r.tipo_bloqueo is not null or r.reservado_por is distinct from miembro_actual(r.grupo_id) then
    raise exception 'solo_quien_reserva' using errcode = 'insufficient_privilege';
  end if;
  if r.estado not in ('borrador', 'confirmada') then
    raise exception 'transicion_invalida: no se puede cancelar una reserva %', r.estado using errcode = 'check_violation';
  end if;
  if r.estado = 'confirmada' then
    v_horas := coalesce(pol_txt(r.grupo_id, 'cancelacion.horas_sin_cargo')::int, 48);
    v_pct := coalesce(pol_txt(r.grupo_id, 'cancelacion.cargo_tardio_pct')::numeric, 0);
    if now() > lower(r.rango) - make_interval(hours => v_horas) then
      v_tardia := true;
      select fee into v_fee from reserva_costos where reserva_id = r.id;
      v_cargo := round(coalesce(v_fee, 0) * v_pct / 100, 2);
    end if;
  end if;
  perform set_config('app.motivo', coalesce(nullif(trim(p_motivo), ''), 'cancelación de reserva'), true);
  update reservas
     set estado = 'cancelada', cancelada_en = now(), cancelada_por = miembro_actual(r.grupo_id),
         motivo_cancelacion = left(p_motivo, 300), cancelacion_tardia = v_tardia,
         cargo_cancelacion = case when v_tardia then v_cargo else null end
   where id = r.id;
  if r.estado = 'confirmada' then
    select codigo into v_codigo from ordenes where reserva_id = r.id;
    for s in select m.usuario_id from miembros m
              where m.grupo_id = r.grupo_id and m.rol = 'socio' and m.estado = 'activo' and m.id <> r.reservado_por loop
      perform notificar(r.grupo_id, s.usuario_id, 'reserva_cancelada', 'Reserva ' || v_codigo || ' cancelada',
        case when v_tardia then 'Cancelación tardía.' else 'Cancelación sin cargo.' end,
        jsonb_build_object('reserva_id', r.id, 'orden', v_codigo));
    end loop;
  end if;
  return query select v_tardia, v_cargo;
end $$;

-- ---------------------------------------------------------------- iniciar / finalizar (SA7)
create function reserva_cambiar_estado_operativo(p_reserva uuid, p_desde estado_reserva, p_hasta estado_reserva)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare r reservas; v_rol rol_miembro;
begin
  select * into r from reservas where id = p_reserva for update;
  if not found or r.tipo_bloqueo is not null then
    raise exception 'reserva_no_existe' using errcode = 'no_data_found';
  end if;
  v_rol := rol_en(r.grupo_id);
  if not coalesce(r.reservado_por = miembro_actual(r.grupo_id) or v_rol in ('admin_operativo', 'capitan'), false) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  if r.estado <> p_desde then
    raise exception 'transicion_invalida: de % a %', r.estado, p_hasta using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'cambio de estado a ' || p_hasta, true);
  update reservas set estado = p_hasta where id = r.id;
end $$;
revoke execute on function reserva_cambiar_estado_operativo(uuid, estado_reserva, estado_reserva)
  from public, anon, authenticated;

create function reserva_iniciar(p_reserva uuid) returns void
language sql security definer set search_path = public, pg_temp as $$
  select reserva_cambiar_estado_operativo(p_reserva, 'confirmada', 'en_curso')
$$;
create function reserva_finalizar(p_reserva uuid) returns void
language sql security definer set search_path = public, pg_temp as $$
  select reserva_cambiar_estado_operativo(p_reserva, 'en_curso', 'finalizada')
$$;

-- ---------------------------------------------------------------- bloqueos (SA5, F7)
create function bloqueo_crear(p_activo uuid, p_inicio timestamptz, p_fin timestamptz, p_tipo text, p_motivo text default null)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_grupo uuid; v_id uuid;
begin
  select grupo_id into v_grupo from activos where id = p_activo;
  if v_grupo is null or not coalesce(rol_en(v_grupo) in ('socio', 'admin_operativo'), false) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  if p_tipo not in ('mantenimiento', 'preparacion') or p_inicio is null or p_fin is null or p_inicio >= p_fin then
    raise exception 'bloqueo_invalido' using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', coalesce(nullif(trim(p_motivo), ''), 'bloqueo de ' || p_tipo), true);
  begin
    insert into reservas (grupo_id, activo_id, rango, rango_bloqueo, estado, tipo_bloqueo, motivo_bloqueo)
    values (v_grupo, p_activo, tstzrange(p_inicio, p_fin, '[)'), tstzrange(p_inicio, p_fin, '[)'),
            'bloqueada_mantenimiento', p_tipo, left(p_motivo, 300))
    returning id into v_id;
  exception when exclusion_violation then
    raise exception 'horario_ocupado' using errcode = '23P01';
  end;
  return v_id;
end $$;

create function bloqueo_quitar(p_bloqueo uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare r reservas;
begin
  select * into r from reservas where id = p_bloqueo and tipo_bloqueo is not null for update;
  if not found or not coalesce(rol_en(r.grupo_id) in ('socio', 'admin_operativo'), false) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  perform set_config('app.motivo', 'bloqueo retirado', true);
  update reservas set estado = 'cancelada', cancelada_en = now(), cancelada_por = miembro_actual(r.grupo_id) where id = r.id;
end $$;

-- ---------------------------------------------------------------- acuse «Leído y enterado» (SA3, DF-15)
create function reserva_marcar_enterado(p_reserva uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare r reservas; v_yo uuid;
begin
  select * into r from reservas where id = p_reserva;
  v_yo := case when r.id is null then null else miembro_actual(r.grupo_id) end;
  if v_yo is null or not es_socio(r.grupo_id) or r.tipo_bloqueo is not null then
    raise exception 'solo_socios' using errcode = 'insufficient_privilege';
  end if;
  if v_yo = r.reservado_por then
    raise exception 'el_titular_no_marca_enterado' using errcode = 'check_violation';
  end if;
  if r.estado not in ('confirmada', 'en_curso') then
    raise exception 'reserva_no_vigente' using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'leído y enterado', true);
  insert into reserva_acuses (grupo_id, reserva_id, miembro_id) values (r.grupo_id, r.id, v_yo)
  on conflict (reserva_id, miembro_id) do nothing;
end $$;

-- ---------------------------------------------------------------- temporada alta (SA27, DF-19)
create function temporada_generar(p_grupo uuid, p_periodo text, p_anio int, p_desde date, p_hasta date)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_ids uuid[]; v_n int; v_idx int; v_id uuid; v_rot text;
begin
  if not es_socio(p_grupo) then
    raise exception 'solo_socios' using errcode = 'insufficient_privilege';
  end if;
  select array_agg(id order by desde, id) into v_ids from miembros
   where grupo_id = p_grupo and rol = 'socio' and estado = 'activo';
  v_n := coalesce(array_length(v_ids, 1), 0);
  if v_n = 0 then
    raise exception 'sin_socios' using errcode = 'check_violation';
  end if;
  v_rot := pol_txt(p_grupo, 'temporada_alta.rotacion');
  -- rotación anual: cada año cambia el socio que elige primero; el periodo desplaza el orden
  v_idx := case when v_rot = 'anual'
                then (p_anio + array_position(array['semana_santa', 'navidad', 'ano_nuevo', 'verano', 'otro'], p_periodo)) % v_n
                else 0 end;
  perform set_config('app.motivo', 'temporada alta ' || p_periodo || ' ' || p_anio, true);
  insert into temporadas (grupo_id, periodo, anio, desde, hasta, miembro_prioridad, libre_desde)
  values (p_grupo, p_periodo, p_anio, p_desde, p_hasta, v_ids[v_idx + 1], (p_desde - 14)::timestamptz)
  returning id into v_id;
  return v_id;
end $$;

create function temporada_quitar(p_temporada uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare g uuid;
begin
  select grupo_id into g from temporadas where id = p_temporada;
  if g is null or not es_socio(g) then
    raise exception 'solo_socios' using errcode = 'insufficient_privilege';
  end if;
  delete from temporadas where id = p_temporada;
end $$;

-- ---------------------------------------------------------------- vista pública de invitado (SC8)
create function invitado_ver(p_token text, p_ip_hash text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare e invitado_enlaces; r reservas; a activos; g grupos; i invitados; d destinos;
begin
  if p_ip_hash is not null and (select count(*) from invitado_intentos
       where ip_hash = p_ip_hash and momento > now() - interval '10 minutes') >= 20 then
    raise exception 'demasiados_intentos' using errcode = 'check_violation';
  end if;
  select * into e from invitado_enlaces where token_hash = hash_token(p_token) and expira_en > now();
  if not found then
    if p_ip_hash is not null then insert into invitado_intentos (ip_hash) values (p_ip_hash); end if;
    return null;
  end if;
  select * into r from reservas where id = e.reserva_id and estado in ('confirmada', 'en_curso');
  if not found then
    if p_ip_hash is not null then insert into invitado_intentos (ip_hash) values (p_ip_hash); end if;
    return null;
  end if;
  select * into a from activos where id = r.activo_id;
  select * into g from grupos where id = r.grupo_id;
  select * into i from invitados where id = e.invitado_id;
  select * into d from destinos where id = r.destino_id;
  -- SOLO lo que el invitado puede ver: nunca tarifas, finanzas ni datos de otros socios
  return jsonb_build_object(
    'activo', a.nombre, 'invitado', i.nombre, 'personas', r.personas,
    'inicio', lower(r.rango), 'fin', upper(r.rango), 'zona_horaria', g.zona_horaria,
    'destino', d.nombre, 'punto_encuentro', a.punto_encuentro,
    'reglas', a.reglas_invitados, 'contacto', a.contacto_invitados);
end $$;
revoke execute on function invitado_ver(text, text) from public, anon, authenticated;
grant execute on function invitado_ver(text, text) to service_role;

-- ---------------------------------------------------------------- mantenimiento programado
create function recordatorios_acuse() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; v_horas jsonb; h int; n int := 0;
begin
  for r in
    select re.id, re.grupo_id, lower(re.rango) as ini, o.codigo, m.usuario_id
      from reservas re
      join ordenes o on o.reserva_id = re.id
      join miembros m on m.grupo_id = re.grupo_id and m.rol = 'socio' and m.estado = 'activo' and m.id <> re.reservado_por
     where re.estado = 'confirmada' and lower(re.rango) > now()
       and not exists (select 1 from reserva_acuses a where a.reserva_id = re.id and a.miembro_id = m.id)
  loop
    if not coalesce(pol_txt(r.grupo_id, 'reservas.acuse_requerido')::boolean, true) then continue; end if;
    v_horas := politica_interna(r.grupo_id, 'reservas.acuse_recordatorio_horas');
    -- se envía el recordatorio más cercano ya vencido (24 h, luego 2 h), una sola vez cada uno
    select min((value #>> '{}')::int) into h
      from jsonb_array_elements(v_horas)
     where r.ini - make_interval(hours => (value #>> '{}')::int) <= now();
    if h is not null and not exists (
         select 1 from notificaciones x
          where x.usuario_id = r.usuario_id and x.tipo = 'recordatorio_acuse'
            and x.datos ->> 'reserva_id' = r.id::text and (x.datos ->> 'horas')::int = h) then
      perform notificar(r.grupo_id, r.usuario_id, 'recordatorio_acuse', 'Recordatorio: reserva ' || r.codigo,
        'Falta marcar «Leído y enterado» (no es una aprobación).',
        jsonb_build_object('reserva_id', r.id, 'orden', r.codigo, 'horas', h));
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

create function limpiar_borradores() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  delete from reservas where estado = 'borrador' and borrador_expira_en < now();
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function recordatorios_acuse(), limpiar_borradores() from public, anon, authenticated;

-- ---------------------------------------------------------------- RLS y privilegios
alter table invitados enable row level security;
alter table reservas enable row level security;
alter table orden_contadores enable row level security;
alter table ordenes enable row level security;
alter table reserva_costos enable row level security;
alter table reserva_acuses enable row level security;
alter table invitado_enlaces enable row level security;
alter table invitado_intentos enable row level security;
alter table temporadas enable row level security;

revoke all on invitados, reservas, orden_contadores, ordenes, reserva_costos, reserva_acuses,
  invitado_enlaces, invitado_intentos, temporadas from anon, authenticated;
grant select on invitados, reservas, ordenes, reserva_costos, reserva_acuses, temporadas to authenticated;

create policy invitados_select on invitados for select to authenticated using (es_miembro(grupo_id));
create policy reservas_select on reservas for select to authenticated using (es_miembro(grupo_id));
create policy ordenes_select on ordenes for select to authenticated using (es_miembro(grupo_id));
create policy reserva_costos_select on reserva_costos for select to authenticated using (es_socio(grupo_id));
create policy reserva_acuses_select on reserva_acuses for select to authenticated using (es_miembro(grupo_id));
create policy temporadas_select on temporadas for select to authenticated using (es_miembro(grupo_id));

-- Escrituras de negocio: solo por RPC. invitado_enlaces / invitado_intentos / orden_contadores: nadie desde el cliente.
revoke execute on function reserva_crear_borrador(uuid, timestamptz, timestamptz, uso_reserva, uuid, int, uuid, text, text, uuid, text),
  reserva_confirmar(uuid), reserva_cancelar(uuid, text), reserva_iniciar(uuid), reserva_finalizar(uuid),
  bloqueo_crear(uuid, timestamptz, timestamptz, text, text), bloqueo_quitar(uuid),
  reserva_marcar_enterado(uuid), temporada_generar(uuid, text, int, date, date), temporada_quitar(uuid)
  from public, anon;
grant execute on function reserva_crear_borrador(uuid, timestamptz, timestamptz, uso_reserva, uuid, int, uuid, text, text, uuid, text),
  reserva_confirmar(uuid), reserva_cancelar(uuid, text), reserva_iniciar(uuid), reserva_finalizar(uuid),
  bloqueo_crear(uuid, timestamptz, timestamptz, text, text), bloqueo_quitar(uuid),
  reserva_marcar_enterado(uuid), temporada_generar(uuid, text, int, date, date), temporada_quitar(uuid)
  to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table reservas, reserva_acuses;
  end if;
end $$;
