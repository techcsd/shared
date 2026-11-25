-- 2026-11-25 · 33 · Vitrina del activo: descripción, foto y resúmenes seguros (DF-105..DF-108)
-- Un usuario debe ver QUÉ activo comparte el grupo (foto o ícono, descripción y datos clave), también antes de entrar.

alter table activos
  add column descripcion text check (descripcion is null or length(descripcion) <= 2000),
  add column imagen_path text check (imagen_path is null or length(imagen_path) <= 300);

-- La foto vive en Storage bajo «<grupo_id>/…»: no se puede apuntar a la carpeta de otro grupo.
alter table activos add constraint activos_imagen_del_grupo
  check (imagen_path is null or imagen_path like grupo_id::text || '/%');

-- ---------------------------------------------------------------- Storage (solo si el esquema existe)
-- Bucket de lectura pública por URL con ruta no adivinable (uuid): las vistas previas de invitación se ven sin ser
-- miembro. Solo socios del grupo (y el admin de plataforma, vía es_socio) suben, reemplazan o borran.
do $$
begin
  if to_regclass('storage.buckets') is not null and to_regclass('storage.objects') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('activos', 'activos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
    on conflict (id) do update set public = true, file_size_limit = 5242880,
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];
    execute $p$
      create policy activos_ver on storage.objects for select to authenticated using (
        bucket_id = 'activos'
        and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                 then es_miembro(((storage.foldername(name))[1])::uuid) else false end)$p$;
    execute $p$
      create policy activos_subir on storage.objects for insert to authenticated with check (
        bucket_id = 'activos'
        and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                 then es_socio(((storage.foldername(name))[1])::uuid) else false end)$p$;
    execute $p$
      create policy activos_reemplazar on storage.objects for update to authenticated
      using (bucket_id = 'activos'
        and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                 then es_socio(((storage.foldername(name))[1])::uuid) else false end)
      with check (bucket_id = 'activos'
        and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                 then es_socio(((storage.foldername(name))[1])::uuid) else false end)$p$;
    execute $p$
      create policy activos_borrar on storage.objects for delete to authenticated using (
        bucket_id = 'activos'
        and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                 then es_socio(((storage.foldername(name))[1])::uuid) else false end)$p$;
  end if;
end $$;

-- ---------------------------------------------------------------- Vitrina completa (miembros y admin de plataforma)
create function activo_vitrina(p_grupo uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v jsonb;
begin
  if auth.uid() is null then raise exception 'no_autenticado' using errcode = 'insufficient_privilege'; end if;
  if not es_miembro(p_grupo) then raise exception 'sin_permiso' using errcode = 'insufficient_privilege'; end if;
  select jsonb_build_object(
    'grupo', jsonb_build_object('id', g.id, 'nombre', g.nombre, 'moneda', g.moneda),
    'activos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'nombre', a.nombre, 'estado', a.estado, 'descripcion', a.descripcion,
        'imagen_path', a.imagen_path, 'capacidad_legal', a.capacidad_legal,
        'punto_encuentro', a.punto_encuentro, 'reglas_invitados', a.reglas_invitados, 'valores', a.valores,
        'tipo', jsonb_build_object('clave', t.clave, 'nombre', t.nombre, 'definicion', t.definicion),
        'componentes', coalesce((
          select jsonb_agg(jsonb_build_object('etiqueta', c.etiqueta, 'unidad', c.unidad, 'indice', c.indice)
                           order by c.clave, c.indice)
            from activo_componentes c where c.activo_id = a.id), '[]'::jsonb),
        'poliza_vigente', activo_poliza_vigente(a.id)
      ) order by a.creado_en)
      from activos a join tipos_activo t on t.id = a.tipo_id where a.grupo_id = p_grupo), '[]'::jsonb),
    'destinos', coalesce((
      select jsonb_agg(jsonb_build_object('nombre', d.nombre,
        'fee', (select tf.monto from tarifas tf
                 where tf.destino_id = d.id and tf.tipo = 'fee_destino' and tf.vigente_desde <= current_date
                   and (tf.vigente_hasta is null or tf.vigente_hasta >= current_date)
                 order by tf.vigente_desde desc limit 1)) order by d.orden, d.nombre)
      from destinos d where d.grupo_id = p_grupo and d.activo), '[]'::jsonb),
    'tarifa_hora', (select jsonb_build_object('monto', tf.monto, 'moneda', tf.moneda) from tarifas tf
                     where tf.grupo_id = p_grupo and tf.tipo = 'hora' and tf.vigente_desde <= current_date
                       and (tf.vigente_hasta is null or tf.vigente_hasta >= current_date)
                     order by tf.vigente_desde desc limit 1),
    'capitanes', (select count(*) from capitanes where grupo_id = p_grupo and estado = 'activo')
  ) into v
  from grupos g where g.id = p_grupo;
  return v;
end $$;

-- ---------------------------------------------------------------- Subconjunto no sensible (vista previa de invitación)
-- Interna: no se concede a nadie; la usan las dos funciones de abajo después de validar la invitación.
create function activo_resumen_publico(p_grupo uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'grupo_nombre', g.nombre,
    'activos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nombre', a.nombre, 'descripcion', a.descripcion, 'imagen_path', a.imagen_path,
        'capacidad_legal', a.capacidad_legal, 'punto_encuentro', a.punto_encuentro,
        'tipo', jsonb_build_object('clave', t.clave, 'nombre', t.nombre)) order by a.creado_en)
      from activos a join tipos_activo t on t.id = a.tipo_id
      where a.grupo_id = g.id and a.estado <> 'inactivo'), '[]'::jsonb))
  from grupos g where g.id = p_grupo
$$;

-- Por token: solo quien tiene el enlace Y la sesión con el correo invitado; si no, null (sin pistas).
create function activo_vista_por_token(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_grupo uuid;
begin
  if auth.uid() is null then raise exception 'no_autenticado' using errcode = 'insufficient_privilege'; end if;
  select i.grupo_id into v_grupo from invitaciones_miembro i
   where i.token_hash = hash_token(p_token) and i.estado = 'pendiente' and i.expira_en > now()
     and lower(i.correo::text) = lower(coalesce(auth.jwt() ->> 'email', ''));
  if v_grupo is null then return null; end if;
  return activo_resumen_publico(v_grupo);
end $$;

-- Por id de invitación pendiente dirigida al propio correo (lista de invitaciones de la pantalla de bienvenida).
create function activo_vista_por_invitacion(p_invitacion uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_grupo uuid;
begin
  if auth.uid() is null then raise exception 'no_autenticado' using errcode = 'insufficient_privilege'; end if;
  select i.grupo_id into v_grupo from invitaciones_miembro i
   where i.id = p_invitacion and i.estado = 'pendiente' and i.expira_en > now()
     and lower(i.correo::text) = lower(coalesce(auth.jwt() ->> 'email', ''));
  if v_grupo is null then return null; end if;
  return activo_resumen_publico(v_grupo);
end $$;

revoke execute on function activo_vitrina(uuid), activo_resumen_publico(uuid),
  activo_vista_por_token(text), activo_vista_por_invitacion(uuid) from public, anon, authenticated;
grant execute on function activo_vitrina(uuid), activo_vista_por_token(text),
  activo_vista_por_invitacion(uuid) to authenticated;
