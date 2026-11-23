drop trigger if exists grupo_politicas_validar on grupo_politicas;
drop function if exists grupo_politicas_validar();
drop function if exists politicas_del_grupo(uuid);
drop function if exists politica(uuid, text);
drop function if exists politica_validar(text, jsonb);
delete from politicas_catalogo;
