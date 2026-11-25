-- 2026-11-25 · 29 · Panel de administración de la plataforma (DF-93…DF-98)
-- El administrador de plataforma (plataforma_admins) gestiona usuarios y grupos sin depender del correo
-- (Resend aún no tiene dominio verificado). Todo es RPC `security definer` con search_path fijo que exige
-- `es_admin_plataforma()`; las operaciones sobre Auth (crear, clave, bloquear, borrar) las hace la edge
-- function `admin-usuarios` con el JWT del admin (la base vuelve a verificar el permiso). Aditiva.

-- ---------------------------------------------------------------- bitácora de acciones del admin
create table admin_acciones (
  id bigint generated always as identity primary key,
  actor uuid,                                   -- sin FK a propósito: la bitácora sobrevive al borrado del usuario
  accion text not null check (length(accion) between 2 and 60),
  objetivo text check (objetivo is null or length(objetivo) <= 200),
  detalle jsonb not null default '{}'::jsonb,
  momento timestamptz not null default now()
);
create index admin_acciones_momento_idx on admin_acciones (momento desc);
alter table admin_acciones enable row level security;
revoke all on admin_acciones from anon, authenticated;
create trigger admin_acciones_sin_update before update on admin_acciones
  for each row execute function solo_adicion();
create trigger admin_acciones_sin_delete before delete on admin_acciones
  for each row execute function solo_adicion();

-- ---------------------------------------------------------------- ayudantes internos
create function admin_exigir() returns void
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not es_admin_plataforma() then
    raise exception 'solo_admin_plataforma' using errcode = 'insufficient_privilege';
  end if;
end $$;

create function admin_bitacora(p_accion text, p_objetivo text, p_detalle jsonb) returns void
language sql security definer set search_path = public, pg_temp as $$
  insert into admin_acciones (actor, accion, objetivo, detalle)
  values (auth.uid(), p_accion, p_objetivo, coalesce(p_detalle, '{}'::jsonb))
$$;

-- La edge function registra aquí lo que hace sobre Auth (con el JWT del admin; nunca claves).
create function admin_accion_registrar(p_accion text, p_objetivo text, p_detalle jsonb default '{}'::jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform admin_exigir();
  perform admin_bitacora(p_accion, p_objetivo, p_detalle);
end $$;

-- Activación automática igual que en `aceptar_invitacion` (DF-44): Σ socios = 100.
create function admin_activar_si_completo(p_grupo uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_suma numeric;
begin
  select coalesce(sum(porcentaje), 0) into v_suma
    from miembros where grupo_id = p_grupo and rol = 'socio' and estado = 'activo';
  if v_suma = 100 then
    update grupos set estado = 'activo' where id = p_grupo and estado = 'formacion';
  end if;
end $$;

-- ---------------------------------------------------------------- usuarios
create function admin_usuarios_listar() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform admin_exigir();
  return coalesce((
    select jsonb_agg(t.x order by t.ord desc)
      from (
        select u.created_at as ord,
               jsonb_build_object(
                 'id', u.id,
                 'correo', u.email,
                 'nombre', coalesce(p.nombre, ''),
                 'creado_en', u.created_at,
                 'ultimo_acceso', u.last_sign_in_at,
                 'bloqueado', coalesce(u.banned_until > now(), false),
                 'es_admin', exists (select 1 from plataforma_admins a where a.usuario_id = u.id),
                 'grupos', coalesce((
                   select jsonb_agg(jsonb_build_object('grupo_id', g.id, 'nombre', g.nombre,
                                                       'rol', m.rol, 'porcentaje', m.porcentaje) order by g.nombre)
                     from miembros m join grupos g on g.id = m.grupo_id
                    where m.usuario_id = u.id and m.estado = 'activo'), '[]'::jsonb)
               ) as x
          from auth.users u left join perfiles p on p.id = u.id
      ) t), '[]'::jsonb);
end $$;

-- ¿Se puede borrar a este usuario sin dejar un grupo roto o perder historial? (DF-95)
create function admin_usuario_borrable(p_usuario uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_motivos text[] := '{}';
begin
  perform admin_exigir();
  if not exists (select 1 from auth.users where id = p_usuario) then
    raise exception 'usuario_no_existe' using errcode = 'no_data_found';
  end if;
  if p_usuario = auth.uid() then v_motivos := array_append(v_motivos, 'es_el_mismo'::text); end if;
  if exists (select 1 from plataforma_admins where usuario_id = p_usuario)
     and (select count(*) from plataforma_admins) <= 1 then
    v_motivos := array_append(v_motivos, 'ultimo_admin_plataforma'::text);
  end if;
  if exists (select 1 from libro_mayor l join miembros m on m.id = l.miembro_id where m.usuario_id = p_usuario) then
    v_motivos := array_append(v_motivos, 'tiene_movimientos'::text);
  end if;
  if exists (select 1 from miembros m join grupos g on g.id = m.grupo_id
              where m.usuario_id = p_usuario and m.rol = 'socio' and m.estado = 'activo'
                and m.porcentaje > 0 and g.estado = 'activo') then
    v_motivos := array_append(v_motivos, 'socio_en_grupo_activo'::text);
  end if;
  if exists (select 1 from propuestas_compra where organizador_id = p_usuario) then
    v_motivos := array_append(v_motivos, 'organiza_propuestas'::text);
  end if;
  return jsonb_build_object('ok', cardinality(v_motivos) = 0, 'motivos', to_jsonb(v_motivos));
end $$;

create function admin_plataforma_asignar(p_usuario uuid, p_admin boolean) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform admin_exigir();
  if not exists (select 1 from auth.users where id = p_usuario) then
    raise exception 'usuario_no_existe' using errcode = 'no_data_found';
  end if;
  if p_admin then
    insert into plataforma_admins (usuario_id) values (p_usuario) on conflict do nothing;
  else
    if (select count(*) from plataforma_admins where usuario_id <> p_usuario) = 0 then
      raise exception 'ultimo_admin_plataforma: debe quedar al menos un administrador' using errcode = 'check_violation';
    end if;
    delete from plataforma_admins where usuario_id = p_usuario;
  end if;
  perform admin_bitacora(case when p_admin then 'admin_otorgar' else 'admin_quitar' end, p_usuario::text, '{}'::jsonb);
end $$;

create function admin_directorio_set(p_habilitado boolean) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform admin_exigir();
  update plataforma_config set valor = to_jsonb(p_habilitado), actualizado_en = now() where clave = 'directorio_habilitado';
  perform admin_bitacora('directorio_set', 'directorio_habilitado', jsonb_build_object('valor', p_habilitado));
end $$;

create function admin_bitacora_listar(p_limite int default 50) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform admin_exigir();
  return coalesce((select jsonb_agg(jsonb_build_object('momento', momento, 'accion', accion, 'objetivo', objetivo,
                                                       'actor', actor, 'detalle', detalle) order by momento desc, id desc)
                     from (select * from admin_acciones order by momento desc, id desc
                            limit least(greatest(coalesce(p_limite, 50), 1), 200)) a), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------- grupos
create function admin_grupos_listar() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform admin_exigir();
  return coalesce((
    select jsonb_agg(t.x order by t.ord desc)
      from (
        select g.creado_en as ord,
               jsonb_build_object(
                 'id', g.id, 'nombre', g.nombre, 'moneda', g.moneda, 'estado', g.estado,
                 'modo_demo', g.modo_demo, 'creado_en', g.creado_en,
                 'activo', (select a.nombre from activos a where a.grupo_id = g.id order by a.creado_en limit 1),
                 'miembros', (select count(*) from miembros m where m.grupo_id = g.id and m.estado = 'activo'),
                 'suma_porcentajes', (select coalesce(sum(m.porcentaje), 0) from miembros m
                                       where m.grupo_id = g.id and m.rol = 'socio' and m.estado = 'activo'),
                 'movimientos', (select count(*) from libro_mayor l where l.grupo_id = g.id)
               ) as x
          from grupos g
      ) t), '[]'::jsonb);
end $$;

create function admin_grupo_miembros(p_grupo uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform admin_exigir();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'miembro_id', m.id, 'usuario_id', m.usuario_id, 'correo', u.email,
             'nombre', coalesce(p.nombre, ''), 'rol', m.rol, 'porcentaje', m.porcentaje,
             'estado', m.estado, 'desde', m.desde)
           order by (m.estado = 'activo') desc, m.rol, m.desde)
      from miembros m
      join auth.users u on u.id = m.usuario_id
      left join perfiles p on p.id = m.usuario_id
     where m.grupo_id = p_grupo), '[]'::jsonb);
end $$;

-- Agrega (o reactiva / cambia de rol) a un usuario existente SIN invitación por correo.
-- La suma de porcentajes de socios sigue rigiéndose por `validar_porcentajes` (≤ 100; = 100 si el grupo está activo).
create function admin_miembro_guardar(p_grupo uuid, p_usuario uuid, p_rol rol_miembro, p_porcentaje numeric default 0)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_estado estado_grupo;
  v_otros numeric;
  v_nuevo numeric;
  v_id uuid;
begin
  perform admin_exigir();
  select estado into v_estado from grupos where id = p_grupo for update;
  if not found then raise exception 'grupo_no_existe' using errcode = 'no_data_found'; end if;
  if v_estado = 'archivado' then raise exception 'grupo_archivado' using errcode = 'check_violation'; end if;
  if not exists (select 1 from auth.users where id = p_usuario) then
    raise exception 'usuario_no_existe' using errcode = 'no_data_found';
  end if;
  p_porcentaje := coalesce(p_porcentaje, 0);
  if p_porcentaje < 0 or p_porcentaje > 100 or (p_rol <> 'socio' and p_porcentaje <> 0) then
    raise exception 'porcentaje_invalido' using errcode = 'invalid_parameter_value';
  end if;
  select coalesce(sum(porcentaje), 0) into v_otros
    from miembros where grupo_id = p_grupo and rol = 'socio' and estado = 'activo' and usuario_id <> p_usuario;
  v_nuevo := v_otros + case when p_rol = 'socio' then p_porcentaje else 0 end;
  if v_nuevo > 100 then
    raise exception 'porcentajes_invalidos: la suma de socios (%) supera 100', v_nuevo using errcode = 'check_violation';
  end if;
  if v_estado = 'activo' and v_nuevo <> 100 then
    raise exception 'porcentajes_invalidos: un grupo activo exige suma 100 (resultaría %); agrega con 0 y reparte después', v_nuevo
      using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'administración de plataforma', true);
  insert into miembros (grupo_id, usuario_id, rol, porcentaje)
  values (p_grupo, p_usuario, p_rol, p_porcentaje)
  on conflict (grupo_id, usuario_id) do update
     set rol = excluded.rol, porcentaje = excluded.porcentaje, estado = 'activo', hasta = null
  returning id into v_id;
  perform admin_activar_si_completo(p_grupo);
  perform admin_bitacora('miembro_guardar', p_grupo::text,
          jsonb_build_object('usuario_id', p_usuario, 'rol', p_rol, 'porcentaje', p_porcentaje));
  return v_id;
end $$;

-- Fija los porcentajes de TODOS los socios activos a la vez (atómico; el reparto debe sumar 100 en un grupo activo).
create function admin_porcentajes_fijar(p_grupo uuid, p_items jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_estado estado_grupo;
  it jsonb;
  v_suma numeric := 0;
  v_n int;
  v_distintos int;
  v_pct numeric;
begin
  perform admin_exigir();
  select estado into v_estado from grupos where id = p_grupo for update;
  if not found then raise exception 'grupo_no_existe' using errcode = 'no_data_found'; end if;
  if v_estado = 'archivado' then raise exception 'grupo_archivado' using errcode = 'check_violation'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'items_invalidos' using errcode = 'invalid_parameter_value';
  end if;
  select count(*), count(distinct e ->> 'usuario_id') into v_n, v_distintos from jsonb_array_elements(p_items) e;
  if v_n <> v_distintos
     or v_n <> (select count(*) from miembros where grupo_id = p_grupo and rol = 'socio' and estado = 'activo') then
    raise exception 'porcentajes_invalidos: incluye una sola vez a cada socio activo' using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'administración de plataforma', true);
  for it in select * from jsonb_array_elements(p_items) loop
    v_pct := (it ->> 'porcentaje')::numeric;
    update miembros set porcentaje = v_pct
     where grupo_id = p_grupo and usuario_id = (it ->> 'usuario_id')::uuid and rol = 'socio' and estado = 'activo';
    if not found then raise exception 'miembro_no_encontrado' using errcode = 'no_data_found'; end if;
    v_suma := v_suma + v_pct;
  end loop;
  if v_suma > 100 or (v_estado = 'activo' and v_suma <> 100) then
    raise exception 'porcentajes_invalidos: la suma debe ser 100 (es %)', v_suma using errcode = 'check_violation';
  end if;
  perform admin_activar_si_completo(p_grupo);
  perform admin_bitacora('porcentajes_fijar', p_grupo::text, jsonb_build_object('items', p_items, 'suma', v_suma));
end $$;

-- Saca a un miembro del grupo (queda como «salido»: el historial y el libro mayor no se tocan).
create function admin_miembro_quitar(p_grupo uuid, p_usuario uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_m miembros; v_estado estado_grupo;
begin
  perform admin_exigir();
  select estado into v_estado from grupos where id = p_grupo for update;
  if not found then raise exception 'grupo_no_existe' using errcode = 'no_data_found'; end if;
  select * into v_m from miembros where grupo_id = p_grupo and usuario_id = p_usuario and estado <> 'salido';
  if not found then raise exception 'miembro_no_encontrado' using errcode = 'no_data_found'; end if;
  if v_m.rol = 'socio' and v_m.porcentaje > 0 and v_estado = 'activo' then
    raise exception 'porcentaje_pendiente: reparte primero el % %% de este socio', v_m.porcentaje using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'administración de plataforma', true);
  update miembros set estado = 'salido', hasta = now() where id = v_m.id;
  perform admin_bitacora('miembro_quitar', p_grupo::text, jsonb_build_object('usuario_id', p_usuario));
end $$;

-- ---------------------------------------------------------------- permisos: solo usuarios con sesión; el resto lo exige la función
revoke execute on function admin_exigir(), admin_bitacora(text, text, jsonb), admin_activar_si_completo(uuid)
  from public, anon, authenticated;
revoke execute on function admin_accion_registrar(text, text, jsonb), admin_usuarios_listar(), admin_usuario_borrable(uuid),
  admin_plataforma_asignar(uuid, boolean), admin_directorio_set(boolean), admin_bitacora_listar(int),
  admin_grupos_listar(), admin_grupo_miembros(uuid), admin_miembro_guardar(uuid, uuid, rol_miembro, numeric),
  admin_porcentajes_fijar(uuid, jsonb), admin_miembro_quitar(uuid, uuid)
  from public, anon;
grant execute on function admin_accion_registrar(text, text, jsonb), admin_usuarios_listar(), admin_usuario_borrable(uuid),
  admin_plataforma_asignar(uuid, boolean), admin_directorio_set(boolean), admin_bitacora_listar(int),
  admin_grupos_listar(), admin_grupo_miembros(uuid), admin_miembro_guardar(uuid, uuid, rol_miembro, numeric),
  admin_porcentajes_fijar(uuid, jsonb), admin_miembro_quitar(uuid, uuid) to authenticated;
