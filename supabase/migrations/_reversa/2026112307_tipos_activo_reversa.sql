select set_config('app.permitir_sistema', 'on', true);
drop table if exists tipos_activo cascade;
drop function if exists tipos_activo_proteger_sistema();
drop function if exists tipo_activo_validar(jsonb);
