-- 2026-11-23 · 11 · Infraestructura de notificaciones (outbox) y eventos de cliente (P2·F4)

-- Destinatarios sin cuenta (invitados): solo correo.
alter table notificaciones alter column usuario_id drop not null;
alter table notificaciones add column destinatario_correo citext;
alter table notificaciones add constraint notificaciones_destinatario
  check (usuario_id is not null or destinatario_correo is not null);
create index notificaciones_pendientes_idx on notificaciones (estado_envio, reintentos)
  where canal = 'correo' and estado_envio in ('pendiente', 'fallido');

-- Encola una notificación in-app y (opcional) una por correo para un usuario con cuenta.
create function notificar(
  p_grupo uuid, p_usuario uuid, p_tipo text, p_titulo text, p_cuerpo text,
  p_datos jsonb default '{}'::jsonb, p_correo boolean default true
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into notificaciones (grupo_id, usuario_id, tipo, titulo, cuerpo, datos, canal, estado_envio)
  values (p_grupo, p_usuario, p_tipo, p_titulo, p_cuerpo, p_datos, 'app', 'enviado');
  if p_correo then
    insert into notificaciones (grupo_id, usuario_id, tipo, titulo, cuerpo, datos, canal, estado_envio)
    values (p_grupo, p_usuario, p_tipo, p_titulo, p_cuerpo, p_datos, 'correo', 'pendiente');
  end if;
end $$;

-- Correo a alguien sin cuenta (invitado).
create function notificar_correo(
  p_grupo uuid, p_correo text, p_tipo text, p_titulo text, p_cuerpo text, p_datos jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into notificaciones (grupo_id, destinatario_correo, tipo, titulo, cuerpo, datos, canal, estado_envio)
  values (p_grupo, p_correo, p_tipo, p_titulo, p_cuerpo, p_datos, 'correo', 'pendiente');
end $$;

revoke execute on function notificar(uuid, uuid, text, text, text, jsonb, boolean),
  notificar_correo(uuid, text, text, text, text, jsonb) from public, anon, authenticated;

-- Métricas de cliente (p. ej. tiempo del asistente de reserva, meta «< 1 min»).
create table eventos_cliente (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid references auth.users (id) on delete set null,
  grupo_id uuid references grupos (id) on delete set null,
  tipo text not null check (length(tipo) <= 60),
  valor_ms integer check (valor_ms is null or valor_ms >= 0),
  meta jsonb not null default '{}'::jsonb,
  momento timestamptz not null default now()
);
create index eventos_cliente_tipo_idx on eventos_cliente (tipo, momento desc);
alter table eventos_cliente enable row level security;
revoke all on eventos_cliente from anon, authenticated;
grant insert on eventos_cliente to authenticated;
create policy eventos_cliente_insert on eventos_cliente for insert to authenticated
  with check (usuario_id = auth.uid() and (grupo_id is null or es_miembro(grupo_id)));

-- Realtime (solo existe en Supabase; en PGlite se omite).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table notificaciones;
  end if;
end $$;
