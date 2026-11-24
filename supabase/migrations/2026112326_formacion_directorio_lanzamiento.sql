-- 2026-11-24 · 26 · Formación de grupos (propuestas de compra), directorio opcional, plataforma, salud del sistema, lanzamiento (P5)
-- SIN CUSTODIA DE DINERO: los aportes se declaran y confirman a mano entre participantes; la app solo registra.

-- ---------------------------------------------------------------- el libro mayor se puede borrar solo al borrar el grupo entero
drop trigger libro_sin_delete on libro_mayor;
create function libro_sin_borrado() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  -- borrado en cascada al eliminar el grupo (el grupo ya no existe) o reinicio demo autorizado
  if current_setting('app.permitir_borrado', true) = 'on' or not exists (select 1 from grupos where id = old.grupo_id) then
    return old;
  end if;
  raise exception 'solo_adicion: DELETE no permitido en libro_mayor; las correcciones son asientos nuevos con motivo'
    using errcode = 'insufficient_privilege';
end $$;
create trigger libro_sin_delete before delete on libro_mayor for each row execute function libro_sin_borrado();

-- ---------------------------------------------------------------- plataforma: configuración global y administradores
create table plataforma_config (
  clave text primary key,
  valor jsonb not null,
  actualizado_en timestamptz not null default now()
);
insert into plataforma_config (clave, valor) values ('directorio_habilitado', 'false'::jsonb);
create table plataforma_admins (
  usuario_id uuid primary key references auth.users (id) on delete cascade,
  creado_en timestamptz not null default now()
);
alter table plataforma_config enable row level security;
alter table plataforma_admins enable row level security;
revoke all on plataforma_config, plataforma_admins from anon, authenticated;

create function es_admin_plataforma() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from plataforma_admins where usuario_id = auth.uid())
$$;
create function directorio_habilitado() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select (valor #>> '{}')::boolean from plataforma_config where clave = 'directorio_habilitado'), false)
$$;
grant execute on function es_admin_plataforma(), directorio_habilitado() to authenticated;
revoke execute on function es_admin_plataforma(), directorio_habilitado() from anon, public;

-- ---------------------------------------------------------------- propuestas de compra (SB9, SC10)
create table propuestas_compra (
  id uuid primary key default gen_random_uuid(),
  organizador_id uuid not null references auth.users (id),
  titulo text not null check (length(trim(titulo)) between 3 and 120),
  tipo_activo_id uuid not null references tipos_activo (id),
  descripcion text check (descripcion is null or length(descripcion) <= 2000),
  precio_objetivo numeric(14, 2) not null check (precio_objetivo > 0),
  moneda char(3) not null check (moneda ~ '^[A-Z]{3}$'),
  fecha_limite date,
  estado text not null default 'borrador'
    check (estado in ('borrador', 'abierta', 'fondeada', 'adquirida', 'convertida', 'cancelada', 'expirada')),
  token_hash text not null,
  cupos int check (cupos is null or cupos between 2 and 200),
  directorio_visible boolean not null default false,
  directorio_oculto boolean not null default false,
  adquisicion_nota text check (adquisicion_nota is null or length(adquisicion_nota) <= 1000),
  adquisicion_registrada_en timestamptz,
  motivo_cancelacion text check (motivo_cancelacion is null or length(motivo_cancelacion) <= 500),
  grupo_id uuid references grupos (id) on delete set null,
  creado_en timestamptz not null default now()
);
create index propuestas_estado_idx on propuestas_compra (estado);
create unique index propuestas_token_idx on propuestas_compra (token_hash);
create trigger propuestas_auditar after insert or update on propuestas_compra for each row execute function auditar();

create table propuesta_participantes (
  id uuid primary key default gen_random_uuid(),
  propuesta_id uuid not null references propuestas_compra (id) on delete cascade,
  usuario_id uuid not null references auth.users (id) on delete cascade,
  estado text not null default 'acepto' check (estado in ('acepto', 'salio')),
  compromiso numeric(14, 2) not null default 0 check (compromiso >= 0),
  acuse_adquisicion_en timestamptz,
  creado_en timestamptz not null default now(),
  unique (propuesta_id, usuario_id)
);
create trigger propuesta_participantes_auditar after insert or update on propuesta_participantes for each row execute function auditar();

create table propuesta_aportes (
  id uuid primary key default gen_random_uuid(),
  propuesta_id uuid not null references propuestas_compra (id) on delete cascade,
  participante_id uuid not null references propuesta_participantes (id) on delete cascade,
  monto numeric(14, 2) not null check (monto > 0),
  nota text check (nota is null or length(nota) <= 300),
  estado text not null default 'declarado' check (estado in ('declarado', 'confirmado', 'rechazado')),
  confirmado_en timestamptz,
  acuse_aportante_en timestamptz,
  reembolsado_en timestamptz,
  reembolso_nota text check (reembolso_nota is null or length(reembolso_nota) <= 300),
  creado_en timestamptz not null default now()
);
create index propuesta_aportes_idx on propuesta_aportes (propuesta_id, estado);
create trigger propuesta_aportes_auditar after insert or update on propuesta_aportes for each row execute function auditar();

create table propuesta_mensajes (
  id uuid primary key default gen_random_uuid(),
  propuesta_id uuid not null references propuestas_compra (id) on delete cascade,
  autor_id uuid references auth.users (id) on delete set null,
  texto text not null check (length(trim(texto)) between 1 and 1000),
  creado_en timestamptz not null default now()
);

create table propuesta_evidencias (
  id uuid primary key default gen_random_uuid(),
  propuesta_id uuid not null references propuestas_compra (id) on delete cascade,
  tipo text not null default 'contrato' check (tipo in ('contrato', 'factura', 'comprobante', 'otro')),
  ruta text not null check (length(ruta) between 5 and 400),
  subida_por uuid not null references auth.users (id),
  creado_en timestamptz not null default now()
);

create function es_participante(p_prop uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from propuesta_participantes where propuesta_id = p_prop and usuario_id = auth.uid() and estado = 'acepto')
$$;
create function es_organizador(p_prop uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from propuestas_compra where id = p_prop and organizador_id = auth.uid())
$$;
grant execute on function es_participante(uuid), es_organizador(uuid) to authenticated;
revoke execute on function es_participante(uuid), es_organizador(uuid) from anon, public;

-- Totales calculados en la base: comprometido y CONFIRMADO (lo confirmado manda; nada de dinero real se mueve aquí).
create function propuesta_totales(p_prop uuid)
returns table (precio numeric, comprometido numeric, confirmado numeric, declarado numeric, porcentaje_fondeado numeric, participantes int)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not (es_participante(p_prop) or es_organizador(p_prop)) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  return query
  select p.precio_objetivo,
         coalesce((select sum(compromiso) from propuesta_participantes x where x.propuesta_id = p.id and x.estado = 'acepto'), 0),
         coalesce((select sum(a.monto) from propuesta_aportes a where a.propuesta_id = p.id and a.estado = 'confirmado' and a.reembolsado_en is null), 0),
         coalesce((select sum(a.monto) from propuesta_aportes a where a.propuesta_id = p.id and a.estado = 'declarado'), 0),
         round(coalesce((select sum(a.monto) from propuesta_aportes a where a.propuesta_id = p.id and a.estado = 'confirmado' and a.reembolsado_en is null), 0) * 100 / p.precio_objetivo, 2),
         (select count(*)::int from propuesta_participantes x where x.propuesta_id = p.id and x.estado = 'acepto')
    from propuestas_compra p where p.id = p_prop;
end $$;

create function propuesta_crear(
  p_titulo text, p_tipo uuid, p_descripcion text, p_precio numeric, p_moneda text, p_fecha_limite date, p_cupos int default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid; v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  if auth.uid() is null then raise exception 'no_autenticado' using errcode = 'insufficient_privilege'; end if;
  if not exists (select 1 from tipos_activo where id = p_tipo and (es_sistema or grupo_id is null)) then
    raise exception 'tipo_no_permitido' using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'propuesta de compra creada', true);
  insert into propuestas_compra (organizador_id, titulo, tipo_activo_id, descripcion, precio_objetivo, moneda, fecha_limite, token_hash, cupos)
  values (auth.uid(), trim(p_titulo), p_tipo, left(p_descripcion, 2000), p_precio, upper(p_moneda), p_fecha_limite, hash_token(v_token), p_cupos)
  returning id into v_id;
  insert into propuesta_participantes (propuesta_id, usuario_id) values (v_id, auth.uid());
  return jsonb_build_object('id', v_id, 'token', v_token);
end $$;

create function propuesta_abrir(p_prop uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not es_organizador(p_prop) then raise exception 'solo_organizador' using errcode = 'insufficient_privilege'; end if;
  perform set_config('app.motivo', 'propuesta abierta', true);
  update propuestas_compra set estado = 'abierta' where id = p_prop and estado = 'borrador';
  if not found then raise exception 'estado_invalido' using errcode = 'check_violation'; end if;
end $$;

-- Vista previa para quien recibe el enlace (datos mínimos).
create function propuesta_vista_previa(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare p propuestas_compra;
begin
  if auth.uid() is null then raise exception 'no_autenticado' using errcode = 'insufficient_privilege'; end if;
  select * into p from propuestas_compra where token_hash = hash_token(p_token) and estado in ('abierta', 'fondeada');
  if not found then return null; end if;
  return jsonb_build_object('id', p.id, 'titulo', p.titulo, 'precio_objetivo', p.precio_objetivo, 'moneda', p.moneda,
    'estado', p.estado, 'fecha_limite', p.fecha_limite,
    'organizador', (select coalesce(nombre, correo::text) from perfiles where id = p.organizador_id));
end $$;

create function propuesta_unirse(p_token text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare p propuestas_compra; v_n int;
begin
  if auth.uid() is null then raise exception 'no_autenticado' using errcode = 'insufficient_privilege'; end if;
  select * into p from propuestas_compra where token_hash = hash_token(p_token) for update;
  if not found or p.estado <> 'abierta' then raise exception 'propuesta_no_disponible' using errcode = 'no_data_found'; end if;
  select count(*) into v_n from propuesta_participantes where propuesta_id = p.id and estado = 'acepto';
  if p.cupos is not null and v_n >= p.cupos then raise exception 'sin_cupos' using errcode = 'check_violation'; end if;
  perform set_config('app.motivo', 'se une a una propuesta', true);
  insert into propuesta_participantes (propuesta_id, usuario_id) values (p.id, auth.uid())
  on conflict (propuesta_id, usuario_id) do update set estado = 'acepto';
  return p.id;
end $$;

create function propuesta_comprometer(p_prop uuid, p_monto numeric) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare p propuestas_compra;
begin
  select * into p from propuestas_compra where id = p_prop;
  if not found or not es_participante(p_prop) then raise exception 'sin_permiso' using errcode = 'insufficient_privilege'; end if;
  if p.estado not in ('abierta', 'fondeada') or p_monto is null or p_monto < 0 then raise exception 'estado_invalido' using errcode = 'check_violation'; end if;
  perform set_config('app.motivo', 'compromiso de aporte', true);
  update propuesta_participantes set compromiso = round(p_monto, 2) where propuesta_id = p_prop and usuario_id = auth.uid();
end $$;

create function propuesta_salir(p_prop uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not es_participante(p_prop) or es_organizador(p_prop) then raise exception 'sin_permiso' using errcode = 'insufficient_privilege'; end if;
  if exists (select 1 from propuesta_aportes a join propuesta_participantes x on x.id = a.participante_id
              where a.propuesta_id = p_prop and x.usuario_id = auth.uid() and a.estado = 'confirmado' and a.reembolsado_en is null) then
    raise exception 'aporte_confirmado: pide al organizador registrar el reembolso antes de salir' using errcode = 'check_violation';
  end if;
  update propuesta_participantes set estado = 'salio', compromiso = 0 where propuesta_id = p_prop and usuario_id = auth.uid();
end $$;

create function propuesta_aporte_declarar(p_prop uuid, p_monto numeric, p_nota text default null) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare p propuestas_compra; v_part uuid; v_id uuid;
begin
  select * into p from propuestas_compra where id = p_prop;
  if not found or not es_participante(p_prop) then raise exception 'sin_permiso' using errcode = 'insufficient_privilege'; end if;
  if p.estado not in ('abierta', 'fondeada') then raise exception 'estado_invalido' using errcode = 'check_violation'; end if;
  if p_monto is null or p_monto <= 0 then raise exception 'monto_invalido' using errcode = 'check_violation'; end if;
  select id into v_part from propuesta_participantes where propuesta_id = p_prop and usuario_id = auth.uid();
  perform set_config('app.motivo', 'aporte declarado (sin custodia)', true);
  insert into propuesta_aportes (propuesta_id, participante_id, monto, nota) values (p_prop, v_part, round(p_monto, 2), left(p_nota, 300))
  returning id into v_id;
  return v_id;
end $$;

-- Confirmación MANUAL del organizador (la app no ve ni mueve dinero). Al llegar al precio objetivo la propuesta queda fondeada.
create function propuesta_aporte_confirmar(p_aporte uuid, p_confirmar boolean default true) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare a propuesta_aportes; p propuestas_compra; v_conf numeric;
begin
  select * into a from propuesta_aportes where id = p_aporte for update;
  if not found then raise exception 'aporte_no_existe' using errcode = 'no_data_found'; end if;
  select * into p from propuestas_compra where id = a.propuesta_id for update;
  if not es_organizador(p.id) then raise exception 'solo_organizador' using errcode = 'insufficient_privilege'; end if;
  if a.estado <> 'declarado' or p.estado not in ('abierta', 'fondeada') then raise exception 'estado_invalido' using errcode = 'check_violation'; end if;
  perform set_config('app.motivo', case when p_confirmar then 'aporte confirmado' else 'aporte rechazado' end, true);
  update propuesta_aportes set estado = case when p_confirmar then 'confirmado' else 'rechazado' end,
         confirmado_en = case when p_confirmar then now() end where id = a.id;
  select coalesce(sum(monto), 0) into v_conf from propuesta_aportes where propuesta_id = p.id and estado = 'confirmado' and reembolsado_en is null;
  if v_conf >= p.precio_objetivo and p.estado = 'abierta' then
    update propuestas_compra set estado = 'fondeada' where id = p.id;
  end if;
end $$;

create function propuesta_aporte_acusar(p_aporte uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare a propuesta_aportes;
begin
  select * into a from propuesta_aportes where id = p_aporte for update;
  if not found or not exists (select 1 from propuesta_participantes x where x.id = a.participante_id and x.usuario_id = auth.uid()) then
    raise exception 'sin_permiso' using errcode = 'insufficient_privilege';
  end if;
  if a.estado <> 'confirmado' then raise exception 'estado_invalido' using errcode = 'check_violation'; end if;
  update propuesta_aportes set acuse_aportante_en = now() where id = a.id;
end $$;

create function propuesta_evidencia_registrar(p_prop uuid, p_ruta text, p_tipo text default 'contrato') returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid;
begin
  if not es_participante(p_prop) then raise exception 'sin_permiso' using errcode = 'insufficient_privilege'; end if;
  if position('propuestas/' || p_prop::text || '/' in p_ruta) <> 1 then raise exception 'ruta_invalida' using errcode = 'check_violation'; end if;
  insert into propuesta_evidencias (propuesta_id, tipo, ruta, subida_por) values (p_prop, p_tipo, p_ruta, auth.uid()) returning id into v_id;
  return v_id;
end $$;

-- Adquisición: registro manual del organizador (con el contrato o la factura adjuntos) y acuse de los participantes con aporte.
create function propuesta_registrar_adquisicion(p_prop uuid, p_nota text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare p propuestas_compra;
begin
  select * into p from propuestas_compra where id = p_prop for update;
  if not found or not es_organizador(p_prop) then raise exception 'solo_organizador' using errcode = 'insufficient_privilege'; end if;
  if p.estado <> 'fondeada' then raise exception 'estado_invalido: la propuesta debe estar fondeada' using errcode = 'check_violation'; end if;
  if not exists (select 1 from propuesta_evidencias where propuesta_id = p_prop and tipo in ('contrato', 'factura')) then
    raise exception 'falta_contrato: adjunta el contrato o la factura de compra' using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'adquisición registrada', true);
  update propuestas_compra set adquisicion_nota = left(p_nota, 1000), adquisicion_registrada_en = now() where id = p.id;
  update propuesta_participantes set acuse_adquisicion_en = now() where propuesta_id = p.id and usuario_id = p.organizador_id;
end $$;

create function propuesta_acusar_adquisicion(p_prop uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare p propuestas_compra; v_falta int;
begin
  select * into p from propuestas_compra where id = p_prop for update;
  if not found or not es_participante(p_prop) then raise exception 'sin_permiso' using errcode = 'insufficient_privilege'; end if;
  if p.estado <> 'fondeada' or p.adquisicion_registrada_en is null then raise exception 'estado_invalido' using errcode = 'check_violation'; end if;
  update propuesta_participantes set acuse_adquisicion_en = now() where propuesta_id = p_prop and usuario_id = auth.uid() and acuse_adquisicion_en is null;
  -- adquirida cuando todos los participantes con aporte confirmado acusaron
  select count(*) into v_falta from propuesta_participantes x
   where x.propuesta_id = p.id and x.estado = 'acepto' and x.acuse_adquisicion_en is null
     and exists (select 1 from propuesta_aportes a where a.participante_id = x.id and a.estado = 'confirmado' and a.reembolsado_en is null);
  if v_falta = 0 then
    perform set_config('app.motivo', 'adquisición acusada por todos', true);
    update propuestas_compra set estado = 'adquirida' where id = p.id;
  end if;
end $$;

-- Conversión en UNA transacción: grupo + activo + miembros con porcentaje = aporte confirmado / total + estatuto inicial.
create function propuesta_convertir(p_prop uuid, p_nombre_grupo text, p_prefijo text, p_zona text default 'America/Santo_Domingo') returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  p propuestas_compra; v_ids uuid[]; v_pesos numeric[]; r record; v_g uuid; v_org_pct numeric; v_n int; v_miembro uuid;
begin
  select * into p from propuestas_compra where id = p_prop for update;
  if not found or not es_organizador(p_prop) then raise exception 'solo_organizador' using errcode = 'insufficient_privilege'; end if;
  if p.estado <> 'adquirida' then raise exception 'estado_invalido: solo se convierte una propuesta adquirida' using errcode = 'check_violation'; end if;
  select array_agg(x.usuario_id order by x.usuario_id), array_agg(x.suma order by x.usuario_id) into v_ids, v_pesos
    from (select pp.usuario_id, sum(a.monto) as suma
            from propuesta_participantes pp join propuesta_aportes a on a.participante_id = pp.id
           where pp.propuesta_id = p.id and pp.estado = 'acepto' and a.estado = 'confirmado' and a.reembolsado_en is null
           group by pp.usuario_id) x;
  if v_ids is null then raise exception 'sin_aportes_confirmados: no hay aportes confirmados' using errcode = 'check_violation'; end if;
  if not (p.organizador_id = any (v_ids)) then raise exception 'organizador_sin_aporte: el organizador debe tener aporte confirmado' using errcode = 'check_violation'; end if;
  perform set_config('app.motivo', 'conversión de propuesta en grupo', true);
  v_g := crear_grupo(p_nombre_grupo, p.moneda, p_zona, p_prefijo, 1);
  -- porcentajes exactos (centésimas), regla determinista de redondeo: mayor resto, luego mayor aporte, luego id
  for r in select * from repartir_pesos(100, v_ids, v_pesos) loop
    if r.id = p.organizador_id then
      update miembros set porcentaje = r.monto where grupo_id = v_g and usuario_id = p.organizador_id;
    else
      insert into miembros (grupo_id, usuario_id, rol, porcentaje) values (v_g, r.id, 'socio', r.monto);
    end if;
  end loop;
  update grupos set estado = 'activo' where id = v_g;
  perform crear_activo(v_g, p.tipo_activo_id, p.titulo, null);
  -- estatuto inicial con los defaults: rige cuando todos los socios lo acepten (SC9: no es firma legal)
  insert into estatuto_versiones (grupo_id, numero, estado, cambios, motivo, propuesta_por)
  values (v_g, 1, 'pendiente', '{}'::jsonb, 'Versión inicial con los valores por defecto (desde la propuesta de compra)', p.organizador_id);
  select id into v_miembro from miembros where grupo_id = v_g and usuario_id = p.organizador_id;
  insert into estatuto_acuses (grupo_id, version_id, miembro_id, acepta)
  select v_g, id, v_miembro, true from estatuto_versiones where grupo_id = v_g and numero = 1;
  update propuestas_compra set estado = 'convertida', grupo_id = v_g where id = p.id;
  for r in select usuario_id from miembros where grupo_id = v_g and usuario_id <> auth.uid() loop
    perform notificar(v_g, r.usuario_id, 'grupo_creado', 'Se creó el grupo «' || p_nombre_grupo || '»',
      'Revisa el estatuto inicial y acéptalo.', jsonb_build_object('grupo_id', v_g), false);
  end loop;
  select count(*) into v_n from miembros where grupo_id = v_g;
  return v_g;
end $$;

create function propuesta_cancelar(p_prop uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare p propuestas_compra;
begin
  select * into p from propuestas_compra where id = p_prop for update;
  if not found or not es_organizador(p_prop) then raise exception 'solo_organizador' using errcode = 'insufficient_privilege'; end if;
  if p.estado in ('convertida', 'cancelada', 'expirada') then raise exception 'estado_invalido' using errcode = 'check_violation'; end if;
  if coalesce(length(trim(p_motivo)), 0) < 3 then raise exception 'motivo_requerido' using errcode = 'check_violation'; end if;
  perform set_config('app.motivo', 'propuesta cancelada: ' || p_motivo, true);
  update propuestas_compra set estado = 'cancelada', motivo_cancelacion = left(p_motivo, 500), directorio_visible = false where id = p.id;
end $$;

-- Reembolso: SOLO registro (la app no mueve dinero).
create function propuesta_reembolsar(p_aporte uuid, p_nota text default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare a propuesta_aportes;
begin
  select * into a from propuesta_aportes where id = p_aporte for update;
  if not found or not es_organizador(a.propuesta_id) then raise exception 'solo_organizador' using errcode = 'insufficient_privilege'; end if;
  if a.estado <> 'confirmado' or a.reembolsado_en is not null then raise exception 'estado_invalido' using errcode = 'check_violation'; end if;
  update propuesta_aportes set reembolsado_en = now(), reembolso_nota = left(p_nota, 300) where id = a.id;
end $$;

create function propuesta_mensaje(p_prop uuid, p_texto text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not es_participante(p_prop) then raise exception 'sin_permiso' using errcode = 'insufficient_privilege'; end if;
  insert into propuesta_mensajes (propuesta_id, autor_id, texto) values (p_prop, auth.uid(), left(trim(p_texto), 1000));
end $$;

create function propuestas_expirar() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  perform set_config('app.motivo', 'propuesta expirada', true);
  update propuestas_compra set estado = 'expirada', directorio_visible = false
   where estado = 'abierta' and fecha_limite is not null and fecha_limite < current_date;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function propuestas_expirar() from public, anon, authenticated;

-- ---------------------------------------------------------------- directorio opcional (SB3, DF-28): apagado por defecto
create table directorio_solicitudes (
  id uuid primary key default gen_random_uuid(),
  propuesta_id uuid not null references propuestas_compra (id) on delete cascade,
  usuario_id uuid not null references auth.users (id) on delete cascade,
  mensaje text check (mensaje is null or length(mensaje) <= 500),
  estado text not null default 'pendiente' check (estado in ('pendiente', 'aprobada', 'rechazada')),
  creado_en timestamptz not null default now()
);
create unique index directorio_solicitud_unica on directorio_solicitudes (propuesta_id, usuario_id) where estado = 'pendiente';
create table directorio_reportes (
  id uuid primary key default gen_random_uuid(),
  propuesta_id uuid not null references propuestas_compra (id) on delete cascade,
  usuario_id uuid not null references auth.users (id) on delete cascade,
  motivo text not null check (length(motivo) between 3 and 500),
  creado_en timestamptz not null default now()
);

create function propuesta_directorio_visible(p_prop uuid, p_visible boolean) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not es_organizador(p_prop) then raise exception 'solo_organizador' using errcode = 'insufficient_privilege'; end if;
  update propuestas_compra set directorio_visible = p_visible where id = p_prop and estado = 'abierta';
  if not found then raise exception 'estado_invalido' using errcode = 'check_violation'; end if;
end $$;

-- Datos mínimos: tipo, precio objetivo, % fondeado, cupos. Sin nombres, sin correos, sin finanzas de nadie.
create function directorio_listar()
returns table (id uuid, tipo text, precio_objetivo numeric, moneda char(3), porcentaje_fondeado numeric, cupos_libres int, fecha_limite date)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not directorio_habilitado() then return; end if;
  return query
  select p.id, t.nombre, p.precio_objetivo, p.moneda,
         round(coalesce((select sum(a.monto) from propuesta_aportes a where a.propuesta_id = p.id and a.estado = 'confirmado' and a.reembolsado_en is null), 0) * 100 / p.precio_objetivo, 0),
         case when p.cupos is null then null else greatest(p.cupos - (select count(*)::int from propuesta_participantes x where x.propuesta_id = p.id and x.estado = 'acepto'), 0) end,
         p.fecha_limite
    from propuestas_compra p join tipos_activo t on t.id = p.tipo_activo_id
   where p.estado = 'abierta' and p.directorio_visible and not p.directorio_oculto
   order by p.creado_en desc limit 100;
end $$;

create function directorio_solicitar(p_prop uuid, p_mensaje text default null) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid;
begin
  if auth.uid() is null or not directorio_habilitado() then raise exception 'directorio_apagado' using errcode = 'insufficient_privilege'; end if;
  if not exists (select 1 from propuestas_compra where id = p_prop and estado = 'abierta' and directorio_visible and not directorio_oculto) then
    raise exception 'propuesta_no_disponible' using errcode = 'no_data_found';
  end if;
  if es_participante(p_prop) then raise exception 'ya_participa' using errcode = 'check_violation'; end if;
  if (select count(*) from directorio_solicitudes where usuario_id = auth.uid() and creado_en > now() - interval '1 hour') >= 5 then
    raise exception 'demasiadas_solicitudes: espera antes de solicitar más' using errcode = 'check_violation';
  end if;
  insert into directorio_solicitudes (propuesta_id, usuario_id, mensaje) values (p_prop, auth.uid(), left(p_mensaje, 500)) returning id into v_id;
  return v_id;
end $$;

create function directorio_responder(p_solicitud uuid, p_aprobar boolean) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare s directorio_solicitudes;
begin
  select * into s from directorio_solicitudes where id = p_solicitud for update;
  if not found or not es_organizador(s.propuesta_id) then raise exception 'solo_organizador' using errcode = 'insufficient_privilege'; end if;
  if s.estado <> 'pendiente' then raise exception 'estado_invalido' using errcode = 'check_violation'; end if;
  update directorio_solicitudes set estado = case when p_aprobar then 'aprobada' else 'rechazada' end where id = s.id;
  if p_aprobar then
    insert into propuesta_participantes (propuesta_id, usuario_id) values (s.propuesta_id, s.usuario_id)
    on conflict (propuesta_id, usuario_id) do update set estado = 'acepto';
  end if;
end $$;

create function directorio_reportar(p_prop uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not directorio_habilitado() then raise exception 'directorio_apagado' using errcode = 'insufficient_privilege'; end if;
  if (select count(*) from directorio_reportes where usuario_id = auth.uid() and creado_en > now() - interval '1 hour') >= 5 then
    raise exception 'demasiadas_solicitudes' using errcode = 'check_violation';
  end if;
  insert into directorio_reportes (propuesta_id, usuario_id, motivo) values (p_prop, auth.uid(), left(p_motivo, 500));
end $$;

create function directorio_ocultar(p_prop uuid, p_ocultar boolean default true) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not es_admin_plataforma() then raise exception 'solo_admin_plataforma' using errcode = 'insufficient_privilege'; end if;
  perform set_config('app.motivo', 'moderación del directorio', true);
  update propuestas_compra set directorio_oculto = p_ocultar where id = p_prop;
end $$;

-- ---------------------------------------------------------------- salud del sistema (solo admin de plataforma) (F6)
create function salud_sistema() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not es_admin_plataforma() then raise exception 'solo_admin_plataforma' using errcode = 'insufficient_privilege'; end if;
  return jsonb_build_object(
    'errores_24h', (select count(*) from errores_cliente where momento > now() - interval '24 hours'),
    'errores_recientes', coalesce((select jsonb_agg(jsonb_build_object('momento', momento, 'mensaje', left(mensaje, 200), 'ruta', ruta) order by momento desc)
                                     from (select * from errores_cliente order by momento desc limit 20) e), '[]'::jsonb),
    'notificaciones', coalesce((select jsonb_object_agg(estado_envio, n) from (select estado_envio, count(*) n from notificaciones where canal = 'correo' group by 1) x), '{}'::jsonb),
    'fallos_correo', coalesce((select jsonb_agg(jsonb_build_object('momento', creado_en, 'tipo', tipo, 'motivo', left(motivo_fallo, 200), 'reintentos', reintentos) order by creado_en desc)
                                from (select * from notificaciones where canal = 'correo' and estado_envio = 'fallido' order by creado_en desc limit 20) f), '[]'::jsonb),
    'reservas_por_dia', coalesce((select jsonb_agg(jsonb_build_object('dia', d, 'n', n) order by d) from
                                   (select creado_en::date d, count(*) n from reservas where tipo_bloqueo is null and creado_en > now() - interval '14 days' group by 1) r), '[]'::jsonb),
    'asistente_ms', (select jsonb_build_object('n', count(*), 'promedio', round(avg(valor_ms)), 'mediana', round((percentile_cont(0.5) within group (order by valor_ms))::numeric))
                       from eventos_cliente where tipo = 'reserva_asistente_ms' and momento > now() - interval '30 days'),
    'grupos', (select count(*) from grupos), 'grupos_demo', (select count(*) from grupos where modo_demo),
    'propuestas_abiertas', (select count(*) from propuestas_compra where estado = 'abierta'),
    'directorio_habilitado', directorio_habilitado()
  );
end $$;

-- ---------------------------------------------------------------- modo demo → real (SA35)
create function grupo_checklist_lanzamiento(p_grupo uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v jsonb := '[]'::jsonb;
begin
  if not es_socio(p_grupo) then raise exception 'solo_socios' using errcode = 'insufficient_privilege'; end if;
  v := v || jsonb_build_array(jsonb_build_object('clave', 'activo', 'ok', exists (select 1 from activos where grupo_id = p_grupo and estado = 'activo')));
  v := v || jsonb_build_array(jsonb_build_object('clave', 'capacidad_legal',
        'ok', exists (select 1 from activos where grupo_id = p_grupo and estado = 'activo') and not exists (select 1 from activos where grupo_id = p_grupo and estado = 'activo' and coalesce(capacidad_legal, 0) <= 0)));
  v := v || jsonb_build_array(jsonb_build_object('clave', 'componentes',
        'ok', not exists (select 1 from activos a where a.grupo_id = p_grupo and a.estado = 'activo'
                           and exists (select 1 from tipos_activo t where t.id = a.tipo_id and jsonb_array_length(coalesce(t.definicion -> 'componentes', '[]'::jsonb)) > 0)
                           and not exists (select 1 from activo_componentes c where c.activo_id = a.id))));
  v := v || jsonb_build_array(jsonb_build_object('clave', 'destinos', 'ok', exists (select 1 from destinos where grupo_id = p_grupo and activo)));
  v := v || jsonb_build_array(jsonb_build_object('clave', 'tarifas', 'ok', exists (select 1 from tarifas where grupo_id = p_grupo and monto > 0)));
  v := v || jsonb_build_array(jsonb_build_object('clave', 'correos', 'ok', exists (select 1 from grupo_correos where grupo_id = p_grupo and activo)));
  v := v || jsonb_build_array(jsonb_build_object('clave', 'capitanes',
        'ok', exists (select 1 from capitanes where grupo_id = p_grupo and estado = 'activo' and licencia_vence >= current_date)));
  v := v || jsonb_build_array(jsonb_build_object('clave', 'seguro',
        'ok', exists (select 1 from polizas_seguro where grupo_id = p_grupo and current_date between vigente_desde and vigente_hasta)));
  v := v || jsonb_build_array(jsonb_build_object('clave', 'estatuto',
        'ok', exists (select 1 from estatuto_versiones where grupo_id = p_grupo and estado = 'vigente')
              or not exists (select 1 from estatuto_versiones where grupo_id = p_grupo)));
  return v;
end $$;

-- Pasa un grupo demo a real: exige lo esencial y BORRA los datos demo de operación y finanzas (nunca se mezclan con los reales).
create function grupo_pasar_a_real(p_grupo uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_lista jsonb; v_faltan jsonb;
begin
  if not es_socio(p_grupo) then raise exception 'solo_socios' using errcode = 'insufficient_privilege'; end if;
  if not exists (select 1 from grupos where id = p_grupo and modo_demo) then raise exception 'no_es_demo' using errcode = 'check_violation'; end if;
  v_lista := grupo_checklist_lanzamiento(p_grupo);
  select coalesce(jsonb_agg(x -> 'clave'), '[]'::jsonb) into v_faltan
    from jsonb_array_elements(v_lista) x
   where (x ->> 'clave') in ('activo', 'capacidad_legal', 'componentes', 'destinos', 'tarifas', 'correos') and not (x ->> 'ok')::boolean;
  if jsonb_array_length(v_faltan) > 0 then
    return jsonb_build_object('ok', false, 'faltan', v_faltan, 'lista', v_lista);
  end if;
  perform demo_reiniciar_operacion(p_grupo);
  delete from reservas where grupo_id = p_grupo and estado in ('confirmada', 'finalizada', 'cancelada', 'borrador') and tipo_bloqueo is null;
  perform set_config('app.motivo', 'el grupo pasa de demo a real', true);
  update grupos set modo_demo = false where id = p_grupo;
  return jsonb_build_object('ok', true, 'faltan', '[]'::jsonb, 'lista', v_lista);
end $$;

-- ---------------------------------------------------------------- cron: ahora también expira propuestas
create or replace function cron_mantenimiento() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_rec int; v_lim int; v_exp int; v_fon int; v_man int; v_prop int; v_url text; v_key text; v_disparado boolean := false;
begin
  v_rec := recordatorios_acuse();
  v_lim := limpiar_borradores();
  v_exp := prioridad_911_expirar();
  v_fon := fondo_aportes_automaticos();
  v_man := mantenimiento_evaluar();
  v_prop := propuestas_expirar();
  if to_regclass('vault.decrypted_secrets') is not null and to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is not null
     and exists (select 1 from notificaciones where canal = 'correo' and estado_envio in ('pendiente', 'fallido') and reintentos < 2) then
    execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'shared_functions_url'$q$ into v_url;
    execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'shared_service_key'$q$ into v_key;
    if v_url is not null and v_key is not null then
      execute 'select net.http_post(url := $1, headers := $2, body := $3, timeout_milliseconds := 20000)'
        using v_url || '/enviar-notificaciones',
              jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key), '{}'::jsonb;
      v_disparado := true;
    end if;
  end if;
  return jsonb_build_object('recordatorios', v_rec, 'borradores_limpiados', v_lim, 'solicitudes_911_expiradas', v_exp,
                            'aportes_fondo', v_fon, 'alertas_mantenimiento', v_man, 'propuestas_expiradas', v_prop, 'envio_disparado', v_disparado);
end $$;

-- ---------------------------------------------------------------- RLS
alter table propuestas_compra enable row level security;
alter table propuesta_participantes enable row level security;
alter table propuesta_aportes enable row level security;
alter table propuesta_mensajes enable row level security;
alter table propuesta_evidencias enable row level security;
alter table directorio_solicitudes enable row level security;
alter table directorio_reportes enable row level security;
revoke all on propuestas_compra, propuesta_participantes, propuesta_aportes, propuesta_mensajes, propuesta_evidencias,
  directorio_solicitudes, directorio_reportes from anon, authenticated;
grant select on propuestas_compra, propuesta_participantes, propuesta_aportes, propuesta_mensajes, propuesta_evidencias,
  directorio_solicitudes to authenticated;

-- un tercero NO ve la propuesta: solo organizador y participantes (el enlace da una vista previa mínima por RPC)
create policy propuestas_select on propuestas_compra for select to authenticated using (organizador_id = auth.uid() or es_participante(id));
create policy participantes_select on propuesta_participantes for select to authenticated using (es_participante(propuesta_id) or es_organizador(propuesta_id));
create policy aportes_select on propuesta_aportes for select to authenticated using (es_participante(propuesta_id) or es_organizador(propuesta_id));
create policy pmensajes_select on propuesta_mensajes for select to authenticated using (es_participante(propuesta_id) or es_organizador(propuesta_id));
create policy pevidencias_select on propuesta_evidencias for select to authenticated using (es_participante(propuesta_id) or es_organizador(propuesta_id));
create policy dsolicitudes_select on directorio_solicitudes for select to authenticated using (usuario_id = auth.uid() or es_organizador(propuesta_id));

revoke execute on function propuesta_totales(uuid), propuesta_crear(text, uuid, text, numeric, text, date, int), propuesta_abrir(uuid),
  propuesta_vista_previa(text), propuesta_unirse(text), propuesta_comprometer(uuid, numeric), propuesta_salir(uuid),
  propuesta_aporte_declarar(uuid, numeric, text), propuesta_aporte_confirmar(uuid, boolean), propuesta_aporte_acusar(uuid),
  propuesta_evidencia_registrar(uuid, text, text), propuesta_registrar_adquisicion(uuid, text), propuesta_acusar_adquisicion(uuid),
  propuesta_convertir(uuid, text, text, text), propuesta_cancelar(uuid, text), propuesta_reembolsar(uuid, text), propuesta_mensaje(uuid, text),
  propuesta_directorio_visible(uuid, boolean), directorio_listar(), directorio_solicitar(uuid, text), directorio_responder(uuid, boolean),
  directorio_reportar(uuid, text), directorio_ocultar(uuid, boolean), salud_sistema(), grupo_checklist_lanzamiento(uuid), grupo_pasar_a_real(uuid)
  from public, anon;
grant execute on function propuesta_totales(uuid), propuesta_crear(text, uuid, text, numeric, text, date, int), propuesta_abrir(uuid),
  propuesta_vista_previa(text), propuesta_unirse(text), propuesta_comprometer(uuid, numeric), propuesta_salir(uuid),
  propuesta_aporte_declarar(uuid, numeric, text), propuesta_aporte_confirmar(uuid, boolean), propuesta_aporte_acusar(uuid),
  propuesta_evidencia_registrar(uuid, text, text), propuesta_registrar_adquisicion(uuid, text), propuesta_acusar_adquisicion(uuid),
  propuesta_convertir(uuid, text, text, text), propuesta_cancelar(uuid, text), propuesta_reembolsar(uuid, text), propuesta_mensaje(uuid, text),
  propuesta_directorio_visible(uuid, boolean), directorio_listar(), directorio_solicitar(uuid, text), directorio_responder(uuid, boolean),
  directorio_reportar(uuid, text), directorio_ocultar(uuid, boolean), salud_sistema(), grupo_checklist_lanzamiento(uuid), grupo_pasar_a_real(uuid)
  to authenticated;

-- ---------------------------------------------------------------- Storage: límites de tamaño y tipos; carpeta de propuestas
do $$
begin
  if to_regclass('storage.buckets') is not null then
    update storage.buckets set file_size_limit = 10485760,
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf']
     where id = 'evidencias';
  end if;
  if to_regclass('storage.objects') is not null then
    execute $p$
      create policy evidencias_propuestas_leer on storage.objects for select to authenticated using (
        bucket_id = 'evidencias' and (storage.foldername(name))[1] = 'propuestas'
        and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
        and (es_participante(((storage.foldername(name))[2])::uuid) or es_organizador(((storage.foldername(name))[2])::uuid)))$p$;
    execute $p$
      create policy evidencias_propuestas_subir on storage.objects for insert to authenticated with check (
        bucket_id = 'evidencias' and (storage.foldername(name))[1] = 'propuestas'
        and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
        and es_participante(((storage.foldername(name))[2])::uuid))$p$;
  end if;
end $$;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table propuesta_aportes, propuesta_mensajes;
  end if;
end $$;
