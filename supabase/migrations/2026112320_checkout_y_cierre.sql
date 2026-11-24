-- 2026-11-24 · 20 · Check-out, cierre de la orden con datos completos, liquidación, cargo por cancelación tardía, aportes al fondo (P3·F2, F4, F6, F7)

-- Punto de extensión de DF-27: hoy todo es `registro` (nada bloquea). `estricto` queda reservado (sin pasarelas).
create function finanzas_modo(p_grupo uuid) returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(pol_txt(p_grupo, 'finanzas.modo'), 'registro')
$$;
revoke execute on function finanzas_modo(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- check-out (SA2 paso 4, SA14, SA31)
-- Guarda lo recibido (sin duplicar), calcula QUÉ falta y, solo si no falta nada, cierra la orden y liquida.
-- Los gastos del viaje se cargan antes con gasto_registrar (así reintentar no duplica nada).
create function checkout_registrar(
  p_reserva uuid,
  p_lecturas jsonb,
  p_combustible_final numeric,
  p_combustible_agregado numeric,
  p_checklist jsonb,
  p_incidencias jsonb,
  p_observaciones text default null,
  p_motivo text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r reservas; o operaciones; v_yo uuid; c record; it jsonb; v_resp jsonb; e jsonb; v_faltan jsonb := '[]'::jsonb;
  v_prev_agregado numeric; v_agregado numeric; v_cons numeric; v_resumen jsonb; s record; v_cod text; v_cumple boolean;
  v_motivo text := nullif(trim(coalesce(p_motivo, '')), '');
begin
  select * into r from reservas where id = p_reserva for update;
  if not found or r.tipo_bloqueo is not null then
    raise exception 'reserva_no_existe' using errcode = 'no_data_found';
  end if;
  if not operacion_puede(r) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  if r.estado <> 'en_curso' then
    raise exception 'transicion_invalida: solo una salida en curso puede regresar (estado %)', r.estado using errcode = 'check_violation';
  end if;
  select * into o from operaciones where reserva_id = r.id for update;
  if not found then
    raise exception 'sin_checkin: la salida no tiene check-in' using errcode = 'check_violation';
  end if;
  v_yo := miembro_actual(r.grupo_id);
  perform set_config('app.motivo', coalesce(v_motivo, 'check-out de la salida'), true);

  -- lecturas finales (negativas y «final < inicial» los rechaza la base)
  for e in select * from jsonb_array_elements(coalesce(p_lecturas, '[]'::jsonb)) loop
    perform lectura_guardar(o.id, (e ->> 'componente_id')::uuid, 'fin', (e ->> 'valor')::numeric, v_yo, v_motivo);
  end loop;

  -- combustible final y agregado
  if p_combustible_final is not null then
    if p_combustible_final < 0 then
      raise exception 'valor_negativo: el combustible final no puede ser negativo' using errcode = 'check_violation';
    end if;
    if o.combustible_final is not null and o.combustible_final <> p_combustible_final and v_motivo is null then
      raise exception 'motivo_requerido: corregir el combustible final exige un motivo' using errcode = 'check_violation';
    end if;
    update operaciones set combustible_final = p_combustible_final where id = o.id;
    o.combustible_final := p_combustible_final;
  end if;
  select cantidad into v_prev_agregado from combustible_registros
   where operacion_id = o.id and tipo = 'agregado' order by creado_en desc, id desc limit 1;
  if p_combustible_agregado is not null then
    if p_combustible_agregado < 0 then
      raise exception 'valor_negativo: el combustible agregado no puede ser negativo' using errcode = 'check_violation';
    end if;
    if v_prev_agregado is distinct from p_combustible_agregado then
      if v_prev_agregado is not null and v_motivo is null then
        raise exception 'motivo_requerido: corregir el combustible agregado exige un motivo' using errcode = 'check_violation';
      end if;
      insert into combustible_registros (grupo_id, operacion_id, tipo, cantidad, unidad, nota, creado_por)
      values (o.grupo_id, o.id, 'agregado', p_combustible_agregado, o.combustible_unidad, v_motivo, v_yo);
      v_prev_agregado := p_combustible_agregado;
    end if;
  end if;
  v_agregado := coalesce(v_prev_agregado, 0);

  -- checklist de regreso (DF-23)
  for it in select * from jsonb_array_elements(checklist_items(r.activo_id, 'regreso')) loop
    select x into v_resp from jsonb_array_elements(coalesce(p_checklist, '[]'::jsonb)) x where x ->> 'clave' = it ->> 'clave' limit 1;
    if v_resp is not null then
      v_cumple := coalesce((v_resp ->> 'cumple')::boolean, false);
      if not v_cumple and coalesce(length(trim(v_resp ->> 'nota')), 0) < 3 then
        raise exception 'nota_requerida: si «%» no se cumple, explica por qué', it ->> 'texto' using errcode = 'check_violation';
      end if;
      if not exists (select 1 from checklist_vigente where operacion_id = o.id and momento = 'regreso' and clave = it ->> 'clave' and cumple = v_cumple)
         and not v_cumple then
        insert into incidencias (grupo_id, operacion_id, tipo, descripcion, creado_por)
        values (o.grupo_id, o.id, 'incidencia', left('No se cumple: ' || (it ->> 'texto') || ' — ' || (v_resp ->> 'nota'), 1000), v_yo);
      end if;
      perform checklist_guardar(o.id, 'regreso', it, v_resp, v_yo, v_motivo);
    end if;
  end loop;

  -- incidencias y observaciones
  for e in select * from jsonb_array_elements(coalesce(p_incidencias, '[]'::jsonb)) loop
    if coalesce(length(trim(e ->> 'descripcion')), 0) > 0 then
      insert into incidencias (grupo_id, operacion_id, tipo, descripcion, creado_por)
      values (o.grupo_id, o.id, case when e ->> 'tipo' in ('observacion', 'incidencia', 'dano') then e ->> 'tipo' else 'incidencia' end,
              left(e ->> 'descripcion', 1000), v_yo);
    end if;
  end loop;
  if p_observaciones is not null and nullif(trim(p_observaciones), '') is not null then
    update operaciones set observaciones = left(p_observaciones, 1000) where id = o.id;
  end if;

  -- ¿qué falta?
  for c in select * from activo_componentes where activo_id = r.activo_id order by clave, indice loop
    if not exists (select 1 from lecturas_vigentes where operacion_id = o.id and componente_id = c.id and momento = 'fin') then
      v_faltan := v_faltan || jsonb_build_object('codigo', 'lectura_final', 'componente_id', c.id,
        'detalle', 'Lectura final de ' || c.etiqueta || ' (' || c.unidad || ')');
    end if;
  end loop;
  if o.combustible_final is null then
    v_faltan := v_faltan || jsonb_build_object('codigo', 'combustible_final', 'detalle', 'Combustible final');
  elsif o.combustible_inicial + v_agregado - o.combustible_final < 0 then
    raise exception 'combustible_inconsistente: el final (%) supera lo inicial (%) más lo agregado (%)',
      o.combustible_final, o.combustible_inicial, v_agregado using errcode = 'check_violation';
  end if;
  if coalesce(pol_txt(r.grupo_id, 'entrega.checklist_regreso_obligatorio')::boolean, true) then
    for it in select * from jsonb_array_elements(checklist_items(r.activo_id, 'regreso')) loop
      if coalesce((it ->> 'obligatorio')::boolean, true)
         and not exists (select 1 from checklist_vigente where operacion_id = o.id and momento = 'regreso' and clave = it ->> 'clave') then
        v_faltan := v_faltan || jsonb_build_object('codigo', 'checklist', 'momento', 'regreso', 'clave', it ->> 'clave', 'detalle', it ->> 'texto');
      end if;
    end loop;
  end if;

  if jsonb_array_length(v_faltan) > 0 then
    return jsonb_build_object('ok', true, 'cerrada', false, 'faltan', v_faltan);
  end if;

  -- datos completos: se cierra la orden y se liquida (SA2 paso 5)
  v_cons := o.combustible_inicial + v_agregado - o.combustible_final;
  insert into combustible_registros (grupo_id, operacion_id, tipo, cantidad, unidad, nota, creado_por)
  values (o.grupo_id, o.id, 'consumido', v_cons, o.combustible_unidad, 'calculado al cerrar', v_yo);
  if pol_txt(r.grupo_id, 'combustible.modelo') = 'devolver_lleno' and o.combustible_final < o.combustible_inicial then
    insert into incidencias (grupo_id, operacion_id, tipo, descripcion, creado_por)
    values (o.grupo_id, o.id, 'incidencia',
            'No se devolvió lleno: faltan ' || (o.combustible_inicial - o.combustible_final) || ' ' || o.combustible_unidad, v_yo);
  end if;
  update operaciones set regreso_real = greatest(now(), salida_real), checkout_por = v_yo, cerrada_en = now() where id = o.id;
  update reservas set estado = 'finalizada' where id = r.id;
  v_resumen := liquidar_operacion(o.id);

  select codigo into v_cod from ordenes where reserva_id = r.id;
  for s in select m.usuario_id from miembros m
            where m.grupo_id = r.grupo_id and m.rol = 'socio' and m.estado = 'activo' and m.id <> v_yo loop
    perform notificar(r.grupo_id, s.usuario_id, 'salida_cerrada', 'Salida cerrada y liquidada',
      coalesce(v_cod, '') || ' regresó. Revisa el estado de cuenta.', jsonb_build_object('reserva_id', r.id), false);
  end loop;
  return jsonb_build_object('ok', true, 'cerrada', true, 'faltan', '[]'::jsonb, 'resumen', v_resumen);
end $$;
revoke execute on function checkout_registrar(uuid, jsonb, numeric, numeric, jsonb, jsonb, text, text) from public, anon;
grant execute on function checkout_registrar(uuid, jsonb, numeric, numeric, jsonb, jsonb, text, text) to authenticated;

-- ---------------------------------------------------------------- la orden solo avanza por check-in / check-out (SA14)
-- Antes (P2) cualquiera con permiso operativo podía marcar iniciar/finalizar a mano; eso saltaba los datos completos.
create or replace function reserva_iniciar(p_reserva uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  raise exception 'usa_operacion: la salida se inicia con el check-in (combustible, lecturas y checklist)' using errcode = 'check_violation';
end $$;
create or replace function reserva_finalizar(p_reserva uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  raise exception 'usa_operacion: la orden se cierra con el check-out de datos completos' using errcode = 'check_violation';
end $$;

create function reservas_requiere_operacion() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if new.estado = 'en_curso' and old.estado <> 'en_curso'
     and not exists (select 1 from operaciones where reserva_id = new.id) then
    raise exception 'requiere_checkin: no hay check-in registrado' using errcode = 'check_violation';
  end if;
  if new.estado = 'finalizada' and old.estado <> 'finalizada'
     and not exists (select 1 from operaciones where reserva_id = new.id and cerrada_en is not null) then
    raise exception 'requiere_checkout_completo: la orden solo se cierra con check-in, check-out y checklists completos'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger reservas_requiere_operacion before update of estado on reservas
  for each row execute function reservas_requiere_operacion();

-- ---------------------------------------------------------------- cargo por cancelación tardía (DF-09 + DF-07)
create function reservas_cargo_cancelacion() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_mon char(3); v_cv record; v_cod text;
begin
  if new.estado = 'cancelada' and old.estado = 'confirmada' and coalesce(new.cargo_cancelacion, 0) > 0 then
    select moneda into v_mon from reserva_costos where reserva_id = new.id;
    if v_mon is null then
      select moneda into v_mon from grupos where id = new.grupo_id;
    end if;
    select * into v_cv from convertir_a_grupo(new.grupo_id, new.cargo_cancelacion, v_mon, null, current_date);
    select codigo into v_cod from ordenes where reserva_id = new.id;
    perform asentar_fee(new.grupo_id, new.reservado_por, v_cv.monto_grupo, v_cv.moneda_grupo, new.cargo_cancelacion, v_mon,
                        v_cv.tasa, 'cancelacion', new.id, 'Cancelación tardía ' || coalesce(v_cod, ''));
  end if;
  return new;
end $$;
create trigger reservas_cargo_cancelacion after update of estado on reservas
  for each row execute function reservas_cargo_cancelacion();

-- ---------------------------------------------------------------- tarea periódica: ahora también genera los aportes del fondo
create or replace function cron_mantenimiento() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_rec int; v_lim int; v_exp int; v_fon int; v_url text; v_key text; v_disparado boolean := false;
begin
  v_rec := recordatorios_acuse();
  v_lim := limpiar_borradores();
  v_exp := prioridad_911_expirar();
  v_fon := fondo_aportes_automaticos();

  if to_regclass('vault.decrypted_secrets') is not null and to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is not null
     and exists (select 1 from notificaciones where canal = 'correo' and estado_envio in ('pendiente', 'fallido') and reintentos < 2) then
    execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'shared_functions_url'$q$ into v_url;
    execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'shared_service_key'$q$ into v_key;
    if v_url is not null and v_key is not null then
      execute 'select net.http_post(url := $1, headers := $2, body := $3, timeout_milliseconds := 20000)'
        using v_url || '/enviar-notificaciones',
              jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
              '{}'::jsonb;
      v_disparado := true;
    end if;
  end if;
  return jsonb_build_object('recordatorios', v_rec, 'borradores_limpiados', v_lim,
                            'solicitudes_911_expiradas', v_exp, 'aportes_fondo', v_fon, 'envio_disparado', v_disparado);
end $$;
