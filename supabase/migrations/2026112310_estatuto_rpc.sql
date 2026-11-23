-- 2026-11-23 · 10 · Estatuto versionado: proponer, aceptar, aplicar (DF-30, DF-45)

-- Interna: pone la versión como vigente y copia sus cambios a grupo_politicas.
create function aplicar_version(p_version uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v estatuto_versiones; k text;
begin
  select * into v from estatuto_versiones where id = p_version for update;
  if not found or v.estado <> 'pendiente' then
    raise exception 'version_no_aplicable' using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'estatuto v' || v.numero, true);
  update estatuto_versiones set estado = 'reemplazada' where grupo_id = v.grupo_id and estado = 'vigente';
  update estatuto_versiones set estado = 'vigente', vigente_desde = now() where id = v.id;
  for k in select jsonb_object_keys(v.cambios) loop
    insert into grupo_politicas (grupo_id, clave, valor, version_id)
    values (v.grupo_id, k, v.cambios -> k, v.id)
    on conflict (grupo_id, clave) do update
      set valor = excluded.valor, version_id = excluded.version_id, actualizado_en = now();
  end loop;
end $$;
revoke execute on function aplicar_version(uuid) from public, anon, authenticated;

-- Evalúa si todos los socios activos aceptaron; si sí, aplica.
create function estatuto_evaluar(p_version uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v estatuto_versiones; v_faltan int;
begin
  select * into v from estatuto_versiones where id = p_version;
  select count(*) into v_faltan
    from miembros m
   where m.grupo_id = v.grupo_id and m.rol = 'socio' and m.estado = 'activo'
     and not exists (select 1 from estatuto_acuses a
                      where a.version_id = v.id and a.miembro_id = m.id and a.acepta);
  if v_faltan = 0 then
    perform aplicar_version(p_version);
  end if;
end $$;
revoke execute on function estatuto_evaluar(uuid) from public, anon, authenticated;

create function proponer_cambio_politica(p_grupo uuid, p_cambios jsonb, p_motivo text default null) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_usuario uuid := auth.uid();
  v_miembro uuid;
  v_num int;
  v_id uuid;
  k text;
  v_hay_diferencia boolean := false;
begin
  if v_usuario is null or not es_socio(p_grupo) then
    raise exception 'solo_socios_proponen' using errcode = 'insufficient_privilege';
  end if;
  if p_cambios is null or jsonb_typeof(p_cambios) <> 'object' or p_cambios = '{}'::jsonb then
    raise exception 'sin_cambios' using errcode = 'invalid_parameter_value';
  end if;
  if exists (select 1 from estatuto_versiones where grupo_id = p_grupo and estado = 'pendiente') then
    raise exception 'ya_hay_version_pendiente' using errcode = 'check_violation';
  end if;
  for k in select jsonb_object_keys(p_cambios) loop
    perform politica_validar(k, p_cambios -> k);
    if politica(p_grupo, k) is distinct from (p_cambios -> k) then
      v_hay_diferencia := true;
    end if;
  end loop;
  if not v_hay_diferencia then
    raise exception 'sin_cambios' using errcode = 'invalid_parameter_value';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_grupo::text, 0));
  select coalesce(max(numero), 0) + 1 into v_num from estatuto_versiones where grupo_id = p_grupo;
  perform set_config('app.motivo', coalesce(nullif(trim(p_motivo), ''), 'propuesta de estatuto'), true);
  insert into estatuto_versiones (grupo_id, numero, cambios, motivo, propuesta_por)
  values (p_grupo, v_num, p_cambios, left(p_motivo, 500), v_usuario)
  returning id into v_id;
  select id into v_miembro from miembros
   where grupo_id = p_grupo and usuario_id = v_usuario and estado = 'activo';
  insert into estatuto_acuses (grupo_id, version_id, miembro_id, acepta) values (p_grupo, v_id, v_miembro, true);
  perform estatuto_evaluar(v_id); -- con un solo socio activo rige al instante (DF-45)
  return v_id;
end $$;

create function aceptar_version(p_version uuid, p_acepta boolean default true) returns estado_version
language plpgsql security definer set search_path = public, pg_temp as $$
declare v estatuto_versiones; v_miembro uuid; v_estado estado_version;
begin
  select * into v from estatuto_versiones where id = p_version for update;
  if not found or not es_socio(v.grupo_id) then
    raise exception 'solo_socios_aceptan' using errcode = 'insufficient_privilege';
  end if;
  if v.estado <> 'pendiente' then
    raise exception 'version_%', v.estado using errcode = 'check_violation';
  end if;
  select id into v_miembro from miembros
   where grupo_id = v.grupo_id and usuario_id = auth.uid() and estado = 'activo';
  perform set_config('app.motivo', 'acuse de estatuto', true);
  insert into estatuto_acuses (grupo_id, version_id, miembro_id, acepta)
  values (v.grupo_id, v.id, v_miembro, coalesce(p_acepta, true));
  if not coalesce(p_acepta, true) then
    update estatuto_versiones set estado = 'rechazada' where id = v.id;
  else
    perform estatuto_evaluar(v.id);
  end if;
  select estado into v_estado from estatuto_versiones where id = v.id;
  return v_estado;
end $$;

-- El proponente retira su propuesta pendiente.
create function cancelar_version(p_version uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v estatuto_versiones;
begin
  select * into v from estatuto_versiones where id = p_version for update;
  if not found or v.propuesta_por is distinct from auth.uid() or not es_socio(v.grupo_id) then
    raise exception 'solo_el_proponente' using errcode = 'insufficient_privilege';
  end if;
  if v.estado <> 'pendiente' then
    raise exception 'version_%', v.estado using errcode = 'check_violation';
  end if;
  perform set_config('app.motivo', 'propuesta retirada', true);
  update estatuto_versiones set estado = 'rechazada' where id = v.id;
end $$;

revoke execute on function proponer_cambio_politica(uuid, jsonb, text), aceptar_version(uuid, boolean),
  cancelar_version(uuid) from public, anon;
grant execute on function proponer_cambio_politica(uuid, jsonb, text), aceptar_version(uuid, boolean),
  cancelar_version(uuid) to authenticated;
