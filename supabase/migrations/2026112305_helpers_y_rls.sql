-- 2026-11-23 · 05 · Helpers de pertenencia y RLS en TODAS las tablas
-- Los helpers son security definer (evitan recursión de RLS sobre `miembros`).

create function es_miembro(g uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from miembros
    where grupo_id = g and usuario_id = auth.uid() and estado = 'activo'
  )
$$;

create function rol_en(g uuid) returns rol_miembro
language sql stable security definer set search_path = public, pg_temp as $$
  select rol from miembros
  where grupo_id = g and usuario_id = auth.uid() and estado = 'activo'
$$;

create function es_socio(g uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(rol_en(g) = 'socio', false)
$$;

create function comparte_grupo(u uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from miembros a join miembros b on a.grupo_id = b.grupo_id
    where a.usuario_id = auth.uid() and a.estado = 'activo'
      and b.usuario_id = u and b.estado = 'activo'
  )
$$;

revoke execute on function es_miembro(uuid), rol_en(uuid), es_socio(uuid), comparte_grupo(uuid)
  from public, anon;
grant execute on function es_miembro(uuid), rol_en(uuid), es_socio(uuid), comparte_grupo(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------- RLS
alter table perfiles enable row level security;
alter table grupos enable row level security;
alter table miembros enable row level security;
alter table invitaciones_miembro enable row level security;
alter table politicas_catalogo enable row level security;
alter table grupo_politicas enable row level security;
alter table estatuto_versiones enable row level security;
alter table estatuto_acuses enable row level security;
alter table errores_cliente enable row level security;
alter table notificaciones enable row level security;
alter table auditoria enable row level security;

-- Privilegios mínimos (RLS decide las filas). Escrituras de negocio: solo vía RPC security definer.
revoke all on perfiles, grupos, miembros, invitaciones_miembro, politicas_catalogo, grupo_politicas,
  estatuto_versiones, estatuto_acuses, errores_cliente, notificaciones, auditoria
  from anon, authenticated;

grant select on perfiles, grupos, miembros, invitaciones_miembro, politicas_catalogo, grupo_politicas,
  estatuto_versiones, estatuto_acuses, errores_cliente, notificaciones, auditoria to authenticated;
grant update (nombre, telefono, idioma) on perfiles to authenticated;
grant insert on errores_cliente to authenticated;
grant update (leida_en) on notificaciones to authenticated;

-- perfiles: yo y quienes comparten grupo conmigo
create policy perfiles_select on perfiles for select to authenticated
  using (id = auth.uid() or comparte_grupo(id));
create policy perfiles_update on perfiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- grupos / miembros: cualquier miembro activo ve su grupo y sus compañeros
create policy grupos_select on grupos for select to authenticated using (es_miembro(id));
create policy miembros_select on miembros for select to authenticated
  using (usuario_id = auth.uid() or es_miembro(grupo_id));

-- invitaciones: los socios del grupo las ven; el invitado ve la suya por correo
create policy invitaciones_select on invitaciones_miembro for select to authenticated
  using (es_socio(grupo_id)
         or lower(correo::text) = lower(coalesce(auth.jwt() ->> 'email', '')));

-- catálogo: legible por cualquier autenticado
create policy politicas_catalogo_select on politicas_catalogo for select to authenticated using (true);

-- políticas, estatuto: miembros leen; escritura solo por RPC
create policy grupo_politicas_select on grupo_politicas for select to authenticated
  using (es_miembro(grupo_id));
create policy estatuto_versiones_select on estatuto_versiones for select to authenticated
  using (es_miembro(grupo_id));
create policy estatuto_acuses_select on estatuto_acuses for select to authenticated
  using (es_miembro(grupo_id));

-- errores del cliente: solo propios
create policy errores_cliente_insert on errores_cliente for insert to authenticated
  with check (usuario_id = auth.uid());
create policy errores_cliente_select on errores_cliente for select to authenticated
  using (usuario_id = auth.uid());

-- notificaciones: solo el destinatario
create policy notificaciones_select on notificaciones for select to authenticated
  using (usuario_id = auth.uid());
create policy notificaciones_update on notificaciones for update to authenticated
  using (usuario_id = auth.uid()) with check (usuario_id = auth.uid());

-- auditoría: solo socios del grupo; jamás escritura directa
create policy auditoria_select on auditoria for select to authenticated using (es_socio(grupo_id));
