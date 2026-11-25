-- 2026-11-25 · 31 · El administrador de plataforma ve y configura TODOS los grupos sin entrar como otro (DF-99..DF-103)
-- Idea: los tres predicados centrales de pertenencia también aceptan al administrador de plataforma.
--  * LECTURA: todas las políticas RLS que usan es_miembro/es_socio/comparte_grupo quedan abiertas para el admin.
--  * CONFIGURACIÓN (grupo, activo, destinos, tarifas, políticas, invitaciones, estatuto, pólizas, lanzamiento…): idem.
--  * ACTUAR COMO SOCIO (reservar, check-in/out, gastos, pagos, daños, votos, acuses): NO cambia. Esas funciones exigen
--    la identidad del miembro (miembro_actual / rol_en), que el admin no tiene → siguen fallando. Para eso: «Entrar como».
--  * El libro mayor no se toca: sin privilegios de escritura y sin políticas de escritura.

create or replace function es_miembro(g uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select es_admin_plataforma() or exists (
    select 1 from miembros
    where grupo_id = g and usuario_id = auth.uid() and estado = 'activo'
  )
$$;

create or replace function es_socio(g uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select es_admin_plataforma() or coalesce(rol_en(g) = 'socio', false)
$$;

create or replace function comparte_grupo(u uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select es_admin_plataforma() or exists (
    select 1 from miembros a join miembros b on a.grupo_id = b.grupo_id
    where a.usuario_id = auth.uid() and a.estado = 'activo'
      and b.usuario_id = u and b.estado = 'activo'
  )
$$;

-- El acuse del estatuto es un acto de socio: el admin (sin fila en miembros) no puede aceptar por nadie.
do $p$
declare d text; n text;
begin
  d := pg_get_functiondef('public.aceptar_version(uuid,boolean)'::regprocedure);
  n := replace(d,
    $a$  perform set_config('app.motivo', 'acuse de estatuto', true);$a$,
    $b$  if v_miembro is null then
    raise exception 'solo_miembros_aceptan' using errcode = 'insufficient_privilege';
  end if;
  perform set_config('app.motivo', 'acuse de estatuto', true);$b$);
  if n = d then raise exception 'parche_aceptar_version_no_aplicado'; end if;
  execute n;
end $p$;

-- Proponer un cambio de estatuto también es un acto de socio (lleva su acuse): el admin usa «Entrar como».
do $p$
declare d text; n text;
begin
  d := pg_get_functiondef('public.proponer_cambio_politica(uuid,jsonb,text)'::regprocedure);
  n := replace(d,
    $a$  insert into estatuto_acuses (grupo_id, version_id, miembro_id, acepta) values (p_grupo, v_id, v_miembro, true);$a$,
    $b$  if v_miembro is null then
    raise exception 'solo_miembros_proponen' using errcode = 'insufficient_privilege';
  end if;
  insert into estatuto_acuses (grupo_id, version_id, miembro_id, acepta) values (p_grupo, v_id, v_miembro, true);$b$);
  if n = d then raise exception 'parche_proponer_cambio_no_aplicado'; end if;
  execute n;
end $p$;

-- Registrar capitanes es configuración: el admin de plataforma también puede.
do $p$
declare d text; n text;
begin
  d := pg_get_functiondef('public.capitan_guardar(uuid,uuid,text,uuid,text,date,numeric,text,text)'::regprocedure);
  n := replace(d,
    $a$if not coalesce(rol_en(p_grupo) in ('socio', 'admin_operativo'), false) then$a$,
    $b$if not (coalesce(rol_en(p_grupo) in ('socio', 'admin_operativo'), false) or es_admin_plataforma()) then$b$);
  if n = d then raise exception 'parche_capitan_guardar_no_aplicado'; end if;
  execute n;
end $p$;

-- Tablas de propuestas/directorio no cuelgan de un grupo: lectura aditiva para el admin de plataforma.
create policy admin_ver on propuestas_compra for select to authenticated using (es_admin_plataforma());
create policy admin_ver on propuesta_participantes for select to authenticated using (es_admin_plataforma());
create policy admin_ver on propuesta_aportes for select to authenticated using (es_admin_plataforma());
create policy admin_ver on propuesta_mensajes for select to authenticated using (es_admin_plataforma());
create policy admin_ver on propuesta_evidencias for select to authenticated using (es_admin_plataforma());
create policy admin_ver on directorio_solicitudes for select to authenticated using (es_admin_plataforma());
create policy admin_ver on directorio_reportes for select to authenticated using (es_admin_plataforma());
