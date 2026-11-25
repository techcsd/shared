-- 2026-11-25 · 32 · Invitaciones pendientes a MI correo (pantalla de bienvenida sin grupo)
-- Solo devuelve invitaciones cuyo correo coincide con el de la sesión: no hay forma de enumerar las de otros.
-- Aceptar por id reusa las mismas reglas que aceptar_invitacion (correo coincide, pendiente, no expirada).

create function invitaciones_pendientes_mias()
returns table (invitacion_id uuid, grupo_nombre text, rol rol_miembro, porcentaje numeric, expira_en timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then
    raise exception 'no_autenticado' using errcode = 'insufficient_privilege';
  end if;
  return query
    select i.id, g.nombre, i.rol, i.porcentaje, i.expira_en
      from invitaciones_miembro i join grupos g on g.id = i.grupo_id
     where i.estado = 'pendiente' and i.expira_en > now()
       and lower(i.correo::text) = lower(coalesce(auth.jwt() ->> 'email', ''))
     order by i.creado_en desc
     limit 20;
end $$;

create function aceptar_invitacion_por_id(p_invitacion uuid) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_usuario uuid := auth.uid();
  v_inv invitaciones_miembro;
  v_suma numeric;
begin
  if v_usuario is null then
    raise exception 'no_autenticado' using errcode = 'insufficient_privilege';
  end if;
  select * into v_inv from invitaciones_miembro where id = p_invitacion for update;
  if not found or lower(v_inv.correo::text) <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'invitacion_no_valida' using errcode = 'no_data_found';
  end if;
  if v_inv.estado <> 'pendiente' then
    raise exception 'invitacion_%', v_inv.estado using errcode = 'check_violation';
  end if;
  if v_inv.expira_en <= now() then
    update invitaciones_miembro set estado = 'expirada' where id = v_inv.id;
    return null;
  end if;
  perform set_config('app.motivo', 'aceptación de invitación', true);
  insert into miembros (grupo_id, usuario_id, rol, porcentaje)
  values (v_inv.grupo_id, v_usuario, v_inv.rol, v_inv.porcentaje);
  update invitaciones_miembro
     set estado = 'aceptada', aceptada_por = v_usuario, aceptada_en = now()
   where id = v_inv.id;
  select coalesce(sum(porcentaje), 0) into v_suma
    from miembros where grupo_id = v_inv.grupo_id and rol = 'socio' and estado = 'activo';
  if v_suma = 100 then
    update grupos set estado = 'activo' where id = v_inv.grupo_id and estado = 'formacion';
  end if;
  return v_inv.grupo_id;
end $$;

revoke execute on function invitaciones_pendientes_mias(), aceptar_invitacion_por_id(uuid) from public, anon;
grant execute on function invitaciones_pendientes_mias(), aceptar_invitacion_por_id(uuid) to authenticated;
