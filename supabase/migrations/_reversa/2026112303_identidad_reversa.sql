drop trigger if exists auth_usuario_crea_perfil on auth.users;
drop function if exists crear_perfil_para_usuario();
drop table if exists invitaciones_miembro, miembros, grupos, perfiles cascade;
drop function if exists validar_porcentajes();
drop function if exists set_actualizado_en();
