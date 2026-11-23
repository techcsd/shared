-- 2026-11-23 · 06 · RPC de grupos e invitaciones (security definer, search_path fijo)

create function hash_token(p_token text) returns text
language sql immutable set search_path = public, pg_temp as $$
  select encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
$$;
revoke execute on function hash_token(text) from public, anon, authenticated;

-- Crea un grupo y al creador como socio. Con porcentaje 100 el grupo queda activo al instante.
create function crear_grupo(
  p_nombre text,
  p_moneda text default 'DOP',
  p_zona_horaria text default 'America/Santo_Domingo',
  p_prefijo text default 'ORD',
  p_porcentaje numeric default 100,
  p_modo_demo boolean default false
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_usuario uuid := auth.uid();
  v_grupo uuid;
begin
  if v_usuario is null then
    raise exception 'no_autenticado' using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from pg_timezone_names where name = p_zona_horaria) then
    raise exception 'zona_horaria_invalida: %', p_zona_horaria using errcode = 'invalid_parameter_value';
  end if;
  if p_porcentaje is null or p_porcentaje <= 0 or p_porcentaje > 100 then
    raise exception 'porcentaje_invalido' using errcode = 'invalid_parameter_value';
  end if;
  perform set_config('app.motivo', 'creación de grupo', true);
  insert into grupos (nombre, moneda, zona_horaria, prefijo, modo_demo, creado_por)
  values (trim(p_nombre), upper(p_moneda), p_zona_horaria, upper(p_prefijo), coalesce(p_modo_demo, false), v_usuario)
  returning id into v_grupo;
  insert into miembros (grupo_id, usuario_id, rol, porcentaje) values (v_grupo, v_usuario, 'socio', p_porcentaje);
  if p_porcentaje = 100 then
    update grupos set estado = 'activo' where id = v_grupo;
  end if;
  return v_grupo;
end $$;

-- Invita por correo. Devuelve el token en claro UNA vez (se guarda solo su hash).
create function invitar_miembro(
  p_grupo uuid,
  p_correo text,
  p_rol rol_miembro default 'socio',
  p_porcentaje numeric default 0
) returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_usuario uuid := auth.uid();
  v_grupo grupos;
  v_reservado numeric;
  v_token text;
begin
  if v_usuario is null or not es_socio(p_grupo) then
    raise exception 'solo_socios_invitan' using errcode = 'insufficient_privilege';
  end if;
  select * into v_grupo from grupos where id = p_grupo;
  if v_grupo.estado = 'archivado' then
    raise exception 'grupo_archivado' using errcode = 'check_violation';
  end if;
  if p_rol = 'socio' then
    if v_grupo.estado = 'activo' then
      -- Sumar un socio a un grupo activo cambia los porcentajes: requiere el flujo de estatuto (PROMPT-4).
      raise exception 'grupo_activo_requiere_estatuto' using errcode = 'check_violation';
    end if;
    if p_porcentaje is null or p_porcentaje <= 0 then
      raise exception 'porcentaje_invalido' using errcode = 'invalid_parameter_value';
    end if;
    select coalesce((select sum(porcentaje) from miembros
                      where grupo_id = p_grupo and rol = 'socio' and estado = 'activo'), 0)
         + coalesce((select sum(porcentaje) from invitaciones_miembro
                      where grupo_id = p_grupo and rol = 'socio' and estado = 'pendiente' and expira_en > now()), 0)
      into v_reservado;
    if v_reservado + p_porcentaje > 100 then
      raise exception 'porcentajes_invalidos: reservado % + % supera 100', v_reservado, p_porcentaje
        using errcode = 'check_violation';
    end if;
  else
    p_porcentaje := 0;
  end if;
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  perform set_config('app.motivo', 'invitación de miembro', true);
  insert into invitaciones_miembro (grupo_id, correo, rol, porcentaje, token_hash, invitado_por)
  values (p_grupo, trim(p_correo), p_rol, p_porcentaje, hash_token(v_token), v_usuario);
  return v_token;
end $$;

-- Vista previa para quien recibe el enlace (ya con sesión): nombre del grupo, rol y porcentaje.
create function previsualizar_invitacion(p_token text)
returns table (grupo_nombre text, rol rol_miembro, porcentaje numeric, estado estado_invitacion, expira_en timestamptz)
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then
    raise exception 'no_autenticado' using errcode = 'insufficient_privilege';
  end if;
  return query
    select g.nombre, i.rol, i.porcentaje,
           case when i.estado = 'pendiente' and i.expira_en <= now() then 'expirada'::estado_invitacion else i.estado end,
           i.expira_en
    from invitaciones_miembro i join grupos g on g.id = i.grupo_id
    where i.token_hash = hash_token(p_token)
      and lower(i.correo::text) = lower(coalesce(auth.jwt() ->> 'email', ''));
end $$;

create function aceptar_invitacion(p_token text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_usuario uuid := auth.uid();
  v_inv invitaciones_miembro;
  v_suma numeric;
begin
  if v_usuario is null then
    raise exception 'no_autenticado' using errcode = 'insufficient_privilege';
  end if;
  select * into v_inv from invitaciones_miembro
   where token_hash = hash_token(p_token) for update;
  if not found or lower(v_inv.correo::text) <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'invitacion_no_valida' using errcode = 'no_data_found';
  end if;
  if v_inv.estado <> 'pendiente' then
    raise exception 'invitacion_%', v_inv.estado using errcode = 'check_violation';
  end if;
  if v_inv.expira_en <= now() then
    update invitaciones_miembro set estado = 'expirada' where id = v_inv.id;
    return null; -- el cliente debe tratar null como «expirada»
  end if;
  perform set_config('app.motivo', 'aceptación de invitación', true);
  insert into miembros (grupo_id, usuario_id, rol, porcentaje)
  values (v_inv.grupo_id, v_usuario, v_inv.rol, v_inv.porcentaje);
  update invitaciones_miembro
     set estado = 'aceptada', aceptada_por = v_usuario, aceptada_en = now()
   where id = v_inv.id;
  -- Activación automática (DF-44): Σ socios = 100 y sin invitaciones de socio pendientes.
  select coalesce(sum(porcentaje), 0) into v_suma
    from miembros where grupo_id = v_inv.grupo_id and rol = 'socio' and estado = 'activo';
  if v_suma = 100 then
    update grupos set estado = 'activo' where id = v_inv.grupo_id and estado = 'formacion';
  end if;
  return v_inv.grupo_id;
end $$;

create function cancelar_invitacion(p_invitacion uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_grupo uuid;
begin
  select grupo_id into v_grupo from invitaciones_miembro where id = p_invitacion;
  if v_grupo is null or not es_socio(v_grupo) then
    raise exception 'solo_socios_cancelan' using errcode = 'insufficient_privilege';
  end if;
  perform set_config('app.motivo', 'cancelación de invitación', true);
  update invitaciones_miembro set estado = 'cancelada' where id = p_invitacion and estado = 'pendiente';
end $$;

revoke execute on function crear_grupo(text, text, text, text, numeric, boolean),
  invitar_miembro(uuid, text, rol_miembro, numeric), previsualizar_invitacion(text),
  aceptar_invitacion(text), cancelar_invitacion(uuid) from public, anon;
grant execute on function crear_grupo(text, text, text, text, numeric, boolean),
  invitar_miembro(uuid, text, rol_miembro, numeric), previsualizar_invitacion(text),
  aceptar_invitacion(text), cancelar_invitacion(uuid) to authenticated;
