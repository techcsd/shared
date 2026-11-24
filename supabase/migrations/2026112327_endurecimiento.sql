-- 2026-11-24 · 27 · Endurecimiento (P5·F5): ningún rol anónimo ejecuta funciones de negocio
revoke execute on function tipo_activo_validar(jsonb), activo_valores_validar(uuid, jsonb, boolean),
  es_miembro_id(uuid), es_mediador_de(uuid) from public, anon;
grant execute on function es_miembro_id(uuid), es_mediador_de(uuid) to authenticated;
