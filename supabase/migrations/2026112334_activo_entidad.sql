-- 2026-11-25 · 34 · El activo como entidad real y editable (DF-109..DF-116)
-- Galería de fotos, documentos (privados, con vencimiento), equipamiento, ficha (condición/ubicación), valor e historial
-- de mejoras (solo informativo: NO toca el libro mayor), contactos, campos propios e historial visible de cambios.
-- Permiso de edición: admin del grupo (quien lo creó) + socios a quienes el admin se lo concede; el admin de plataforma también.
-- Leer: todo miembro (valor y mejoras solo socios; facturas y contratos solo socios).

-- ---------------------------------------------------------------- permiso «puede editar el activo»
alter table miembros add column puede_editar_activo boolean not null default false;

-- Admin del grupo = quien creó el grupo (si el grupo no tiene creador, los socios con permiso); más el admin de plataforma.
create function es_admin_grupo(g uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select es_admin_plataforma() or exists (
    select 1 from grupos gr join miembros m on m.grupo_id = gr.id
     where gr.id = g and m.usuario_id = auth.uid() and m.estado = 'activo' and m.rol = 'socio'
       and (gr.creado_por = auth.uid() or (gr.creado_por is null and m.puede_editar_activo)))
$$;

create function puede_editar_activo(g uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select es_admin_grupo(g) or exists (
    select 1 from miembros m
     where m.grupo_id = g and m.usuario_id = auth.uid() and m.estado = 'activo' and m.rol = 'socio'
       and m.puede_editar_activo)
$$;

-- Quien crea el grupo (o los socios de un grupo sin creador, como el de demostración) nace con el permiso.
create function miembros_permiso_inicial() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.rol = 'socio' and exists (
       select 1 from grupos where id = new.grupo_id and (creado_por = new.usuario_id or creado_por is null)) then
    new.puede_editar_activo := true;
  end if;
  return new;
end $$;
create trigger miembros_permiso_inicial before insert on miembros
  for each row execute function miembros_permiso_inicial();

update miembros m set puede_editar_activo = true
 where m.rol = 'socio' and exists (
   select 1 from grupos g where g.id = m.grupo_id and (g.creado_por = m.usuario_id or g.creado_por is null));

-- El admin del grupo concede o quita el permiso a un socio (el creador siempre edita).
create function activo_permiso_editar(p_grupo uuid, p_miembro uuid, p_permitir boolean) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_m miembros; v_creador uuid;
begin
  if auth.uid() is null then raise exception 'no_autenticado' using errcode = 'insufficient_privilege'; end if;
  if not es_admin_grupo(p_grupo) then raise exception 'sin_permiso' using errcode = 'insufficient_privilege'; end if;
  select * into v_m from miembros where id = p_miembro and grupo_id = p_grupo;
  if not found or v_m.estado <> 'activo' or v_m.rol <> 'socio' then
    raise exception 'miembro_invalido: solo un socio activo del grupo' using errcode = 'invalid_parameter_value';
  end if;
  select creado_por into v_creador from grupos where id = p_grupo;
  if v_creador = v_m.usuario_id and not p_permitir then
    raise exception 'creador_siempre_edita' using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'permiso de edición del activo', true);
  update miembros set puede_editar_activo = coalesce(p_permitir, false) where id = p_miembro;
end $$;

-- ---------------------------------------------------------------- el activo se edita con permiso (antes: cualquier socio)
alter table activos add constraint activos_id_grupo_unico unique (id, grupo_id);
drop policy activos_update on activos;
create policy activos_update on activos for update to authenticated
  using (puede_editar_activo(grupo_id)) with check (puede_editar_activo(grupo_id));

-- ---------------------------------------------------------------- tablas
-- Fotos (galería con portada). activos.imagen_path queda como copia de la portada para tarjetas y vistas previas.
create table activo_fotos (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null,
  activo_id uuid not null,
  foreign key (activo_id, grupo_id) references activos (id, grupo_id) on delete cascade,
  ruta text not null check (length(ruta) <= 300 and ruta like grupo_id::text || '/%'),
  descripcion text check (descripcion is null or length(descripcion) <= 200),
  orden int not null default 0 check (orden >= 0),
  es_portada boolean not null default false,
  creado_por uuid default auth.uid() references auth.users (id) on delete set null,
  creado_en timestamptz not null default now()
);
create index activo_fotos_activo_idx on activo_fotos (activo_id, orden);
create unique index activo_fotos_una_portada on activo_fotos (activo_id) where es_portada;

-- Documentos: archivo PRIVADO (bucket activo-documentos), tipo, vencimiento opcional.
create table activo_documentos (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null,
  activo_id uuid not null,
  foreign key (activo_id, grupo_id) references activos (id, grupo_id) on delete cascade,
  tipo text not null check (tipo in ('matricula', 'seguro', 'factura', 'manual', 'permiso', 'inspeccion', 'contrato', 'otro')),
  titulo text not null check (length(trim(titulo)) between 2 and 120),
  ruta text not null check (length(ruta) <= 300 and ruta like grupo_id::text || '/%'),
  mime text check (mime is null or length(mime) <= 100),
  tamano_bytes int check (tamano_bytes is null or tamano_bytes between 0 and 20971520),
  emitido_en date,
  vence_en date,
  notas text check (notas is null or length(notas) <= 500),
  creado_por uuid default auth.uid() references auth.users (id) on delete set null,
  creado_en timestamptz not null default now(),
  check (vence_en is null or emitido_en is null or vence_en >= emitido_en)
);
create index activo_documentos_activo_idx on activo_documentos (activo_id);
create index activo_documentos_vence_idx on activo_documentos (vence_en) where vence_en is not null;

-- Equipamiento y accesorios.
create table activo_equipo (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null,
  activo_id uuid not null,
  foreign key (activo_id, grupo_id) references activos (id, grupo_id) on delete cascade,
  nombre text not null check (length(trim(nombre)) between 1 and 80),
  cantidad int not null default 1 check (cantidad between 0 and 9999),
  condicion text not null default 'bueno' check (condicion in ('nuevo', 'bueno', 'regular', 'reparar', 'faltante')),
  notas text check (notas is null or length(notas) <= 300),
  orden int not null default 0 check (orden >= 0),
  actualizado_en timestamptz not null default now()
);
create index activo_equipo_activo_idx on activo_equipo (activo_id, orden);
create trigger activo_equipo_actualizado before update on activo_equipo
  for each row execute function set_actualizado_en();

-- Ficha: condición actual y ubicación (una fila por activo). Quién y cuándo se rellena solo.
create table activo_ficha (
  activo_id uuid primary key,
  grupo_id uuid not null,
  foreign key (activo_id, grupo_id) references activos (id, grupo_id) on delete cascade,
  condicion text check (condicion is null or condicion in ('excelente', 'buena', 'regular', 'atencion')),
  condicion_notas text check (condicion_notas is null or length(condicion_notas) <= 500),
  condicion_actualizada_en timestamptz,
  condicion_actualizada_por uuid references auth.users (id) on delete set null,
  ubicacion_texto text check (ubicacion_texto is null or length(ubicacion_texto) <= 200),
  ubicacion_url text check (ubicacion_url is null or (length(ubicacion_url) <= 500 and ubicacion_url ~* '^https://[^[:space:]]+$')),
  actualizado_en timestamptz not null default now()
);
create trigger activo_ficha_actualizado before update on activo_ficha
  for each row execute function set_actualizado_en();
create function activo_ficha_condicion() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' or new.condicion is distinct from old.condicion
     or new.condicion_notas is distinct from old.condicion_notas then
    new.condicion_actualizada_en := now();
    new.condicion_actualizada_por := auth.uid();
  end if;
  return new;
end $$;
create trigger activo_ficha_condicion before insert or update on activo_ficha
  for each row execute function activo_ficha_condicion();

-- Valor (INFORMATIVO, solo socios): no genera asientos ni afecta balances.
create table activo_valor (
  activo_id uuid primary key,
  grupo_id uuid not null,
  foreign key (activo_id, grupo_id) references activos (id, grupo_id) on delete cascade,
  precio_compra numeric(14, 2) check (precio_compra is null or precio_compra >= 0),
  moneda_compra char(3) check (moneda_compra is null or moneda_compra ~ '^[A-Z]{3}$'),
  fecha_compra date,
  valor_estimado numeric(14, 2) check (valor_estimado is null or valor_estimado >= 0),
  moneda_estimado char(3) check (moneda_estimado is null or moneda_estimado ~ '^[A-Z]{3}$'),
  fecha_estimado date,
  actualizado_en timestamptz not null default now()
);
create trigger activo_valor_actualizado before update on activo_valor
  for each row execute function set_actualizado_en();

-- Mejoras e inversiones (INFORMATIVO, solo socios).
create table activo_mejoras (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null,
  activo_id uuid not null,
  foreign key (activo_id, grupo_id) references activos (id, grupo_id) on delete cascade,
  fecha date not null default current_date,
  descripcion text not null check (length(trim(descripcion)) between 2 and 300),
  costo numeric(14, 2) not null default 0 check (costo >= 0),
  moneda char(3) not null default 'DOP' check (moneda ~ '^[A-Z]{3}$'),
  proveedor text check (proveedor is null or length(proveedor) <= 80),
  notas text check (notas is null or length(notas) <= 300),
  creado_por uuid default auth.uid() references auth.users (id) on delete set null,
  creado_en timestamptz not null default now()
);
create index activo_mejoras_activo_idx on activo_mejoras (activo_id, fecha desc);

-- Contactos y proveedores.
create table activo_contactos (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null,
  activo_id uuid not null,
  foreign key (activo_id, grupo_id) references activos (id, grupo_id) on delete cascade,
  categoria text not null default 'otro' check (categoria in ('marina', 'mecanico', 'aseguradora', 'emergencia', 'proveedor', 'otro')),
  nombre text not null check (length(trim(nombre)) between 2 and 80),
  telefono text check (telefono is null or telefono ~ '^[0-9+()\s.-]{5,30}$'),
  correo text check (correo is null or (length(correo) <= 120 and correo ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  notas text check (notas is null or length(notas) <= 300),
  orden int not null default 0 check (orden >= 0)
);
create index activo_contactos_activo_idx on activo_contactos (activo_id, orden);

-- Campos propios del grupo (la ficha del tipo sigue en activos.valores): etiqueta, tipo, unidad, opciones y valor.
create table activo_campos (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null,
  activo_id uuid not null,
  foreign key (activo_id, grupo_id) references activos (id, grupo_id) on delete cascade,
  etiqueta text not null check (length(trim(etiqueta)) between 1 and 60),
  tipo text not null default 'texto' check (tipo in ('texto', 'numero', 'fecha', 'si_no', 'seleccion')),
  unidad text check (unidad is null or length(unidad) <= 12),
  opciones jsonb check (opciones is null or (jsonb_typeof(opciones) = 'array' and jsonb_array_length(opciones) <= 20)),
  valor jsonb,
  orden int not null default 0 check (orden >= 0)
);
create index activo_campos_activo_idx on activo_campos (activo_id, orden);
create unique index activo_campos_etiqueta_unica on activo_campos (activo_id, lower(trim(etiqueta)));

create function activo_campos_validar() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' and (select count(*) from activo_campos where activo_id = new.activo_id) >= 40 then
    raise exception 'demasiados_campos: máximo 40 por activo' using errcode = 'check_violation';
  end if;
  new.etiqueta := trim(new.etiqueta);
  if new.tipo = 'seleccion' then
    if new.opciones is null or jsonb_array_length(new.opciones) = 0 then
      raise exception 'opciones_requeridas: una lista necesita al menos una opción' using errcode = 'check_violation';
    end if;
    if exists (select 1 from jsonb_array_elements(new.opciones) o
                where jsonb_typeof(o) <> 'string' or length(o #>> '{}') not between 1 and 60) then
      raise exception 'opciones_invalidas' using errcode = 'check_violation';
    end if;
  else
    new.opciones := null;
  end if;
  if new.valor is not null and jsonb_typeof(new.valor) <> 'null' then
    case new.tipo
      when 'texto' then
        if jsonb_typeof(new.valor) <> 'string' or length(new.valor #>> '{}') > 300 then
          raise exception 'valor_invalido: texto de hasta 300 caracteres' using errcode = 'check_violation';
        end if;
      when 'numero' then
        if jsonb_typeof(new.valor) <> 'number' then
          raise exception 'valor_invalido: se esperaba un número' using errcode = 'check_violation';
        end if;
      when 'fecha' then
        if jsonb_typeof(new.valor) <> 'string' or (new.valor #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$' then
          raise exception 'valor_invalido: se esperaba una fecha AAAA-MM-DD' using errcode = 'check_violation';
        end if;
      when 'si_no' then
        if jsonb_typeof(new.valor) <> 'boolean' then
          raise exception 'valor_invalido: se esperaba sí o no' using errcode = 'check_violation';
        end if;
      when 'seleccion' then
        if jsonb_typeof(new.valor) <> 'string' or not (new.opciones @> to_jsonb(new.valor #>> '{}')) then
          raise exception 'valor_invalido: no es una de las opciones' using errcode = 'check_violation';
        end if;
    end case;
  else
    new.valor := null;
  end if;
  return new;
end $$;
create trigger activo_campos_validar before insert or update on activo_campos
  for each row execute function activo_campos_validar();

-- Límites de la galería y de documentos (evita abuso de almacenamiento).
create function activo_limites() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_table_name = 'activo_fotos' and (select count(*) from activo_fotos where activo_id = new.activo_id) >= 30 then
    raise exception 'demasiadas_fotos: máximo 30 por activo' using errcode = 'check_violation';
  end if;
  if tg_table_name = 'activo_documentos' and (select count(*) from activo_documentos where activo_id = new.activo_id) >= 100 then
    raise exception 'demasiados_documentos: máximo 100 por activo' using errcode = 'check_violation';
  end if;
  if tg_table_name = 'activo_equipo' and (select count(*) from activo_equipo where activo_id = new.activo_id) >= 200 then
    raise exception 'demasiado_equipo: máximo 200 por activo' using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger activo_fotos_limite before insert on activo_fotos for each row execute function activo_limites();
create trigger activo_documentos_limite before insert on activo_documentos for each row execute function activo_limites();
create trigger activo_equipo_limite before insert on activo_equipo for each row execute function activo_limites();

-- La portada manda: activos.imagen_path la refleja (y si hay fotos pero ninguna es portada, la primera lo es).
create function activo_fotos_portada_sync() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_activo uuid := coalesce(new.activo_id, old.activo_id); v_ruta text;
begin
  if coalesce(current_setting('app.sin_portada_auto', true), '') = 'on' then return null; end if;   -- intercambio de portada en curso
  if not exists (select 1 from activo_fotos where activo_id = v_activo and es_portada)
     and exists (select 1 from activo_fotos where activo_id = v_activo) then
    update activo_fotos set es_portada = true
     where id = (select id from activo_fotos where activo_id = v_activo order by orden, creado_en limit 1);
  end if;
  select ruta into v_ruta from activo_fotos where activo_id = v_activo and es_portada;
  update activos set imagen_path = v_ruta where id = v_activo and imagen_path is distinct from v_ruta;
  return null;
end $$;
create trigger activo_fotos_portada_sync after insert or update or delete on activo_fotos
  for each row execute function activo_fotos_portada_sync();

-- La foto única de la migración 33 pasa a ser la portada de la galería.
insert into activo_fotos (grupo_id, activo_id, ruta, es_portada)
select grupo_id, id, imagen_path, true from activos where imagen_path is not null;

-- Auditoría de todo lo nuevo (alimenta el historial visible).
create trigger activo_fotos_auditar after insert or update or delete on activo_fotos for each row execute function auditar();
create trigger activo_documentos_auditar after insert or update or delete on activo_documentos for each row execute function auditar();
create trigger activo_equipo_auditar after insert or update or delete on activo_equipo for each row execute function auditar();
create trigger activo_ficha_auditar after insert or update or delete on activo_ficha for each row execute function auditar('activo_id');
create trigger activo_valor_auditar after insert or update or delete on activo_valor for each row execute function auditar('activo_id');
create trigger activo_mejoras_auditar after insert or update or delete on activo_mejoras for each row execute function auditar();
create trigger activo_contactos_auditar after insert or update or delete on activo_contactos for each row execute function auditar();
create trigger activo_campos_auditar after insert or update or delete on activo_campos for each row execute function auditar();

-- ---------------------------------------------------------------- RLS (leer: miembros; escribir: quien puede editar el activo)
alter table activo_fotos enable row level security;
alter table activo_documentos enable row level security;
alter table activo_equipo enable row level security;
alter table activo_ficha enable row level security;
alter table activo_valor enable row level security;
alter table activo_mejoras enable row level security;
alter table activo_contactos enable row level security;
alter table activo_campos enable row level security;
revoke all on activo_fotos, activo_documentos, activo_equipo, activo_ficha, activo_valor, activo_mejoras,
  activo_contactos, activo_campos from anon, authenticated;
grant select, insert, update, delete on activo_fotos, activo_documentos, activo_equipo, activo_ficha, activo_valor,
  activo_mejoras, activo_contactos, activo_campos to authenticated;

create policy activo_fotos_select on activo_fotos for select to authenticated using (es_miembro(grupo_id));
create policy activo_fotos_insert on activo_fotos for insert to authenticated with check (puede_editar_activo(grupo_id));
create policy activo_fotos_update on activo_fotos for update to authenticated
  using (puede_editar_activo(grupo_id)) with check (puede_editar_activo(grupo_id));
create policy activo_fotos_delete on activo_fotos for delete to authenticated using (puede_editar_activo(grupo_id));

-- facturas y contratos pueden mostrar montos: solo socios
create policy activo_documentos_select on activo_documentos for select to authenticated
  using (es_miembro(grupo_id) and (tipo not in ('factura', 'contrato') or es_socio(grupo_id)));
create policy activo_documentos_insert on activo_documentos for insert to authenticated with check (puede_editar_activo(grupo_id));
create policy activo_documentos_update on activo_documentos for update to authenticated
  using (puede_editar_activo(grupo_id)) with check (puede_editar_activo(grupo_id));
create policy activo_documentos_delete on activo_documentos for delete to authenticated using (puede_editar_activo(grupo_id));

create policy activo_equipo_select on activo_equipo for select to authenticated using (es_miembro(grupo_id));
create policy activo_equipo_insert on activo_equipo for insert to authenticated with check (puede_editar_activo(grupo_id));
create policy activo_equipo_update on activo_equipo for update to authenticated
  using (puede_editar_activo(grupo_id)) with check (puede_editar_activo(grupo_id));
create policy activo_equipo_delete on activo_equipo for delete to authenticated using (puede_editar_activo(grupo_id));

create policy activo_ficha_select on activo_ficha for select to authenticated using (es_miembro(grupo_id));
create policy activo_ficha_insert on activo_ficha for insert to authenticated with check (puede_editar_activo(grupo_id));
create policy activo_ficha_update on activo_ficha for update to authenticated
  using (puede_editar_activo(grupo_id)) with check (puede_editar_activo(grupo_id));
create policy activo_ficha_delete on activo_ficha for delete to authenticated using (puede_editar_activo(grupo_id));

create policy activo_valor_select on activo_valor for select to authenticated using (es_socio(grupo_id));
create policy activo_valor_insert on activo_valor for insert to authenticated with check (puede_editar_activo(grupo_id));
create policy activo_valor_update on activo_valor for update to authenticated
  using (puede_editar_activo(grupo_id)) with check (puede_editar_activo(grupo_id));
create policy activo_valor_delete on activo_valor for delete to authenticated using (puede_editar_activo(grupo_id));

create policy activo_mejoras_select on activo_mejoras for select to authenticated using (es_socio(grupo_id));
create policy activo_mejoras_insert on activo_mejoras for insert to authenticated with check (puede_editar_activo(grupo_id));
create policy activo_mejoras_update on activo_mejoras for update to authenticated
  using (puede_editar_activo(grupo_id)) with check (puede_editar_activo(grupo_id));
create policy activo_mejoras_delete on activo_mejoras for delete to authenticated using (puede_editar_activo(grupo_id));

create policy activo_contactos_select on activo_contactos for select to authenticated using (es_miembro(grupo_id));
create policy activo_contactos_insert on activo_contactos for insert to authenticated with check (puede_editar_activo(grupo_id));
create policy activo_contactos_update on activo_contactos for update to authenticated
  using (puede_editar_activo(grupo_id)) with check (puede_editar_activo(grupo_id));
create policy activo_contactos_delete on activo_contactos for delete to authenticated using (puede_editar_activo(grupo_id));

create policy activo_campos_select on activo_campos for select to authenticated using (es_miembro(grupo_id));
create policy activo_campos_insert on activo_campos for insert to authenticated with check (puede_editar_activo(grupo_id));
create policy activo_campos_update on activo_campos for update to authenticated
  using (puede_editar_activo(grupo_id)) with check (puede_editar_activo(grupo_id));
create policy activo_campos_delete on activo_campos for delete to authenticated using (puede_editar_activo(grupo_id));

-- ---------------------------------------------------------------- RPC
-- Portada: intercambio atómico (el índice único admite una sola portada por activo).
create function activo_foto_portada(p_foto uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_f activo_fotos;
begin
  if auth.uid() is null then raise exception 'no_autenticado' using errcode = 'insufficient_privilege'; end if;
  select * into v_f from activo_fotos where id = p_foto;
  if not found then raise exception 'foto_inexistente' using errcode = 'no_data_found'; end if;
  if not puede_editar_activo(v_f.grupo_id) then raise exception 'sin_permiso' using errcode = 'insufficient_privilege'; end if;
  perform set_config('app.motivo', 'portada del activo', true);
  perform set_config('app.sin_portada_auto', 'on', true);
  update activo_fotos set es_portada = false where activo_id = v_f.activo_id and es_portada and id <> p_foto;
  update activo_fotos set es_portada = true where id = p_foto;
  perform set_config('app.sin_portada_auto', 'off', true);
  update activos set imagen_path = v_f.ruta where id = v_f.activo_id and imagen_path is distinct from v_f.ruta;
end $$;

-- Reordenar listas (fotos, equipo, contactos, campos): el orden es la posición en el arreglo.
create function activo_reordenar(p_tabla text, p_ids uuid[]) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_grupo uuid; v_n int; v_activo uuid;
begin
  if auth.uid() is null then raise exception 'no_autenticado' using errcode = 'insufficient_privilege'; end if;
  if p_tabla not in ('activo_fotos', 'activo_equipo', 'activo_contactos', 'activo_campos') then
    raise exception 'tabla_invalida' using errcode = 'invalid_parameter_value';
  end if;
  if p_ids is null or coalesce(array_length(p_ids, 1), 0) = 0 or array_length(p_ids, 1) > 300 then
    raise exception 'ids_invalidos' using errcode = 'invalid_parameter_value';
  end if;
  execute format('select grupo_id, activo_id from %I where id = $1', p_tabla) into v_grupo, v_activo using p_ids[1];
  if v_grupo is null then raise exception 'registro_inexistente' using errcode = 'no_data_found'; end if;
  if not puede_editar_activo(v_grupo) then raise exception 'sin_permiso' using errcode = 'insufficient_privilege'; end if;
  execute format('select count(*) from %I where id = any($1) and grupo_id = $2 and activo_id = $3', p_tabla)
    into v_n using p_ids, v_grupo, v_activo;
  if v_n <> array_length(p_ids, 1) then raise exception 'ids_de_otro_activo' using errcode = 'check_violation'; end if;
  perform set_config('app.motivo', 'reordenar', true);
  execute format('update %I t set orden = x.pos - 1 from unnest($1) with ordinality as x(id, pos) where t.id = x.id', p_tabla)
    using p_ids;
end $$;

-- Todo el detalle de un activo en una llamada (valor y mejoras solo para socios; permisos para el cliente).
create function activo_detalle(p_activo uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_a activos; v_g uuid; v_socio boolean; v jsonb;
begin
  if auth.uid() is null then raise exception 'no_autenticado' using errcode = 'insufficient_privilege'; end if;
  select * into v_a from activos where id = p_activo;
  if not found or not es_miembro(v_a.grupo_id) then raise exception 'sin_permiso' using errcode = 'insufficient_privilege'; end if;
  v_g := v_a.grupo_id;
  v_socio := es_socio(v_g);
  select jsonb_build_object(
    'activo', jsonb_build_object('id', a.id, 'grupo_id', a.grupo_id, 'nombre', a.nombre, 'estado', a.estado,
       'descripcion', a.descripcion, 'imagen_path', a.imagen_path, 'capacidad_legal', a.capacidad_legal,
       'punto_encuentro', a.punto_encuentro, 'reglas_invitados', a.reglas_invitados, 'valores', a.valores,
       'tipo', jsonb_build_object('clave', t.clave, 'nombre', t.nombre, 'definicion', t.definicion)),
    'grupo', jsonb_build_object('id', g.id, 'nombre', g.nombre, 'moneda', g.moneda),
    'permisos', jsonb_build_object('editar', puede_editar_activo(v_g), 'admin', es_admin_grupo(v_g), 'socio', v_socio),
    'ficha', (select to_jsonb(f) - 'grupo_id' - 'actualizado_en' from activo_ficha f where f.activo_id = a.id),
    'condicion_por', (select p.nombre from activo_ficha f join perfiles p on p.id = f.condicion_actualizada_por where f.activo_id = a.id),
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'ruta', x.ruta, 'descripcion', x.descripcion,
        'orden', x.orden, 'es_portada', x.es_portada) order by x.orden, x.creado_en)
        from activo_fotos x where x.activo_id = a.id), '[]'::jsonb),
    'documentos', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'tipo', d.tipo, 'titulo', d.titulo,
        'ruta', d.ruta, 'mime', d.mime, 'tamano_bytes', d.tamano_bytes, 'emitido_en', d.emitido_en,
        'vence_en', d.vence_en, 'notas', d.notas) order by d.vence_en nulls last, d.creado_en)
        from activo_documentos d where d.activo_id = a.id
         and (d.tipo not in ('factura', 'contrato') or v_socio)), '[]'::jsonb),
    'equipo', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'nombre', e.nombre, 'cantidad', e.cantidad,
        'condicion', e.condicion, 'notas', e.notas, 'orden', e.orden) order by e.orden, e.nombre)
        from activo_equipo e where e.activo_id = a.id), '[]'::jsonb),
    'contactos', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'categoria', c.categoria, 'nombre', c.nombre,
        'telefono', c.telefono, 'correo', c.correo, 'notas', c.notas, 'orden', c.orden) order by c.orden, c.nombre)
        from activo_contactos c where c.activo_id = a.id), '[]'::jsonb),
    'campos', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'etiqueta', k.etiqueta, 'tipo', k.tipo,
        'unidad', k.unidad, 'opciones', k.opciones, 'valor', k.valor, 'orden', k.orden) order by k.orden, k.etiqueta)
        from activo_campos k where k.activo_id = a.id), '[]'::jsonb),
    'valor', case when v_socio then (select to_jsonb(vv) - 'grupo_id' - 'actualizado_en' from activo_valor vv where vv.activo_id = a.id) end,
    'mejoras', case when v_socio then coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'fecha', m.fecha,
        'descripcion', m.descripcion, 'costo', m.costo, 'moneda', m.moneda, 'proveedor', m.proveedor, 'notas', m.notas)
        order by m.fecha desc, m.creado_en desc) from activo_mejoras m where m.activo_id = a.id), '[]'::jsonb) end,
    'socios', case when es_admin_grupo(v_g) then coalesce((select jsonb_agg(jsonb_build_object('miembro_id', mi.id,
        'nombre', coalesce(nullif(p.nombre, ''), p.correo::text), 'puede_editar', (mi.puede_editar_activo or g.creado_por = mi.usuario_id),
        'es_creador', g.creado_por = mi.usuario_id) order by g.creado_por = mi.usuario_id desc, p.nombre)
        from miembros mi join perfiles p on p.id = mi.usuario_id
        where mi.grupo_id = v_g and mi.estado = 'activo' and mi.rol = 'socio'), '[]'::jsonb) end
  ) into v
  from activos a join tipos_activo t on t.id = a.tipo_id join grupos g on g.id = a.grupo_id where a.id = p_activo;
  return v;
end $$;

-- Historial legible: quién cambió qué y cuándo (desde la auditoría inmutable). Solo miembros; valor/mejoras solo socios.
create function activo_historial(p_activo uuid, p_limite int default 100) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_g uuid; v_socio boolean; v jsonb;
begin
  if auth.uid() is null then raise exception 'no_autenticado' using errcode = 'insufficient_privilege'; end if;
  select grupo_id into v_g from activos where id = p_activo;
  if v_g is null or not es_miembro(v_g) then raise exception 'sin_permiso' using errcode = 'insufficient_privilege'; end if;
  v_socio := es_socio(v_g);
  select coalesce(jsonb_agg(f order by f.momento desc, f.id desc), '[]'::jsonb) into v from (
    select au.id, au.momento, au.tabla, au.accion,
      coalesce(nullif(p.nombre, ''), 'Sistema') as actor,
      coalesce(au.despues ->> 'nombre', au.antes ->> 'nombre', au.despues ->> 'titulo', au.antes ->> 'titulo',
               au.despues ->> 'etiqueta', au.antes ->> 'etiqueta', au.despues ->> 'descripcion', au.antes ->> 'descripcion') as titulo,
      case when au.accion = 'UPDATE' then (
        select coalesce(jsonb_agg(jsonb_build_object('campo', k.key, 'antes', au.antes -> k.key, 'despues', k.value)), '[]'::jsonb)
          from jsonb_each(au.despues) k
         where au.antes -> k.key is distinct from k.value
           and k.key not in ('actualizado_en', 'creado_en', 'id', 'grupo_id', 'activo_id', 'creado_por', 'ruta', 'imagen_path',
                             'condicion_actualizada_en', 'condicion_actualizada_por', 'orden', 'es_portada', 'valores_internos')
      ) else '[]'::jsonb end as cambios
    from auditoria au left join perfiles p on p.id = au.actor
    where au.grupo_id = v_g
      and ((au.tabla = 'activos' and au.registro_id = p_activo::text)
        or (au.tabla in ('activo_fotos', 'activo_documentos', 'activo_equipo', 'activo_ficha', 'activo_valor',
                         'activo_mejoras', 'activo_contactos', 'activo_campos')
            and coalesce(au.despues, au.antes) ->> 'activo_id' = p_activo::text))
      and (v_socio or au.tabla not in ('activo_valor', 'activo_mejoras'))
      and (v_socio or coalesce(coalesce(au.despues, au.antes) ->> 'tipo', '') not in ('factura', 'contrato'))
      and not (au.accion = 'UPDATE' and au.tabla = 'activos'
               and not exists (select 1 from jsonb_each(au.despues) k
                                where au.antes -> k.key is distinct from k.value
                                  and k.key not in ('actualizado_en', 'imagen_path')))
    order by au.momento desc, au.id desc
    limit greatest(1, least(coalesce(p_limite, 100), 300))
  ) f;
  return v;
end $$;

-- Quién coincide: Vitrina con condición (tarjeta del activo); misma firma, se añade 'condicion'.
create or replace function activo_vitrina(p_grupo uuid) returns jsonb
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
        'condicion', (select f.condicion from activo_ficha f where f.activo_id = a.id),
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

revoke execute on function es_admin_grupo(uuid), puede_editar_activo(uuid), activo_permiso_editar(uuid, uuid, boolean),
  activo_foto_portada(uuid), activo_reordenar(text, uuid[]), activo_detalle(uuid), activo_historial(uuid, int),
  activo_vitrina(uuid) from public, anon, authenticated;
grant execute on function es_admin_grupo(uuid), puede_editar_activo(uuid), activo_permiso_editar(uuid, uuid, boolean),
  activo_foto_portada(uuid), activo_reordenar(text, uuid[]), activo_detalle(uuid), activo_historial(uuid, int),
  activo_vitrina(uuid) to authenticated;
revoke execute on function miembros_permiso_inicial(), activo_fotos_portada_sync(), activo_limites(),
  activo_campos_validar(), activo_ficha_condicion() from public, anon, authenticated;

-- ---------------------------------------------------------------- alertas de vencimiento de documentos
create function activo_documentos_evaluar() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare d record; n int := 0; dias int; v_umbral int;
begin
  for d in select dd.*, a.nombre as activo_nombre from activo_documentos dd join activos a on a.id = dd.activo_id
            where dd.vence_en is not null and dd.vence_en <= current_date + 30 and dd.vence_en >= current_date - 365 loop
    dias := d.vence_en - current_date;
    if dias < 0 then
      if alerta_una_vez('adoc:' || d.id || ':vencido:' || d.vence_en) then
        perform avisar_equipo(d.grupo_id, 'documento_vencido', 'Documento vencido: ' || d.titulo, d.activo_nombre,
          jsonb_build_object('activo_id', d.activo_id, 'documento_id', d.id), d.tipo in ('factura', 'contrato'));
        n := n + 1;
      end if;
    else
      -- solo el umbral más cercano ya cruzado (30 → 7), una vez cada uno
      v_umbral := case when dias <= 7 then 7 else 30 end;
      if alerta_una_vez('adoc:' || d.id || ':' || v_umbral || ':' || d.vence_en) then
        perform avisar_equipo(d.grupo_id, 'documento_por_vencer', d.titulo || ' vence en ' || dias || ' día(s)', d.activo_nombre,
          jsonb_build_object('activo_id', d.activo_id, 'documento_id', d.id), d.tipo in ('factura', 'contrato'));
        n := n + 1;
      end if;
    end if;
  end loop;
  return n;
end $$;
revoke execute on function activo_documentos_evaluar() from public, anon, authenticated;

-- El cron periódico también evalúa documentos (misma tarea de mantenimiento; se parchea su definición vigente).
do $p$
declare d text; n text;
begin
  d := pg_get_functiondef('public.cron_mantenimiento()'::regprocedure);
  n := replace(d, 'v_man := mantenimiento_evaluar();', 'v_man := mantenimiento_evaluar() + activo_documentos_evaluar();');
  if n = d then raise exception 'parche_cron_mantenimiento_no_aplicado'; end if;
  execute n;
end $p$;

-- ---------------------------------------------------------------- Storage
do $$
begin
  if to_regclass('storage.buckets') is not null and to_regclass('storage.objects') is not null then
    -- Fotos: ahora suben/borran quienes pueden editar el activo (antes: cualquier socio).
    execute 'drop policy if exists activos_subir on storage.objects';
    execute 'drop policy if exists activos_reemplazar on storage.objects';
    execute 'drop policy if exists activos_borrar on storage.objects';
    execute $p$
      create policy activos_subir on storage.objects for insert to authenticated with check (
        bucket_id = 'activos'
        and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                 then puede_editar_activo(((storage.foldername(name))[1])::uuid) else false end)$p$;
    execute $p$
      create policy activos_reemplazar on storage.objects for update to authenticated
      using (bucket_id = 'activos'
        and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                 then puede_editar_activo(((storage.foldername(name))[1])::uuid) else false end)
      with check (bucket_id = 'activos'
        and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                 then puede_editar_activo(((storage.foldername(name))[1])::uuid) else false end)$p$;
    execute $p$
      create policy activos_borrar on storage.objects for delete to authenticated using (
        bucket_id = 'activos'
        and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                 then puede_editar_activo(((storage.foldername(name))[1])::uuid) else false end)$p$;

    -- Documentos: bucket PRIVADO; se leen con URL firmada solo si eres miembro del grupo de la carpeta.
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('activo-documentos', 'activo-documentos', false, 15728640,
            array['application/pdf', 'image/jpeg', 'image/png', 'image/webp'])
    on conflict (id) do update set public = false, file_size_limit = 15728640,
      allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png', 'image/webp'];
    execute $p$
      create policy activo_docs_ver on storage.objects for select to authenticated using (
        bucket_id = 'activo-documentos'
        and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                 then es_miembro(((storage.foldername(name))[1])::uuid) else false end)$p$;
    execute $p$
      create policy activo_docs_subir on storage.objects for insert to authenticated with check (
        bucket_id = 'activo-documentos'
        and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                 then puede_editar_activo(((storage.foldername(name))[1])::uuid) else false end)$p$;
    execute $p$
      create policy activo_docs_reemplazar on storage.objects for update to authenticated
      using (bucket_id = 'activo-documentos'
        and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                 then puede_editar_activo(((storage.foldername(name))[1])::uuid) else false end)
      with check (bucket_id = 'activo-documentos'
        and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                 then puede_editar_activo(((storage.foldername(name))[1])::uuid) else false end)$p$;
    execute $p$
      create policy activo_docs_borrar on storage.objects for delete to authenticated using (
        bucket_id = 'activo-documentos'
        and case when (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
                 then puede_editar_activo(((storage.foldername(name))[1])::uuid) else false end)$p$;
  end if;
end $$;
