-- 2026-11-23 · 02 · Auditoría inmutable (DF-39)
create table auditoria (
  id bigint generated always as identity primary key,
  tabla text not null,
  registro_id text,
  grupo_id uuid,
  accion text not null check (accion in ('INSERT', 'UPDATE', 'DELETE')),
  antes jsonb,
  despues jsonb,
  actor uuid,
  momento timestamptz not null default now(),
  motivo text
);
create index auditoria_grupo_momento_idx on auditoria (grupo_id, momento desc);
create index auditoria_tabla_registro_idx on auditoria (tabla, registro_id);

-- Nadie (ni service_role ni dueño) puede alterar la auditoría.
create function auditoria_inmutable() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  raise exception 'auditoria es inmutable (% no permitido)', tg_op using errcode = 'insufficient_privilege';
end $$;

create trigger auditoria_sin_update_delete before update or delete on auditoria
  for each row execute function auditoria_inmutable();
create trigger auditoria_sin_truncate before truncate on auditoria
  for each statement execute function auditoria_inmutable();

-- Trigger genérico. Motivo opcional: set_config('app.motivo', '...', true) desde el RPC.
-- Argumento opcional: nombre de la columna clave (por defecto 'id').
create function auditar() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_antes jsonb;
  v_desp jsonb;
  v_base jsonb;
  v_pk text := coalesce(tg_argv[0], 'id');
  v_grupo uuid;
begin
  if tg_op = 'INSERT' then
    v_desp := to_jsonb(new);
  elsif tg_op = 'UPDATE' then
    v_antes := to_jsonb(old);
    v_desp := to_jsonb(new);
  else
    v_antes := to_jsonb(old);
  end if;
  v_base := coalesce(v_desp, v_antes);
  begin
    if tg_table_name = 'grupos' then
      v_grupo := (v_base ->> 'id')::uuid;
    else
      v_grupo := (v_base ->> 'grupo_id')::uuid;
    end if;
  exception when others then
    v_grupo := null;
  end;
  insert into auditoria (tabla, registro_id, grupo_id, accion, antes, despues, actor, motivo)
  values (tg_table_name, v_base ->> v_pk, v_grupo, tg_op, v_antes, v_desp, auth.uid(),
          nullif(current_setting('app.motivo', true), ''));
  return null;
end $$;

alter table auditoria enable row level security;
revoke all on auditoria from anon, authenticated;
-- La política de lectura (solo socios del grupo) se crea en 2026112305, cuando existan los helpers.
