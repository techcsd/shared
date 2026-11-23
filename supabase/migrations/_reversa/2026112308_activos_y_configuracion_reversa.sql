drop function if exists actualizar_grupo(uuid, text, text, text);
drop function if exists crear_activo(uuid, uuid, text, int, jsonb, jsonb);
drop function if exists clonar_tipo_activo(uuid, uuid, text, text);
drop table if exists grupo_correos, tasas_cambio, tarifas, destinos, activo_componentes, activos cascade;
drop function if exists activo_componentes_grupo();
drop function if exists activos_validar();
drop function if exists activo_valores_validar(uuid, jsonb, boolean);
