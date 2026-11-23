drop function if exists cancelar_invitacion(uuid);
drop function if exists aceptar_invitacion(text);
drop function if exists previsualizar_invitacion(text);
drop function if exists invitar_miembro(uuid, text, rol_miembro, numeric);
drop function if exists crear_grupo(text, text, text, text, numeric, boolean);
drop function if exists hash_token(text);
