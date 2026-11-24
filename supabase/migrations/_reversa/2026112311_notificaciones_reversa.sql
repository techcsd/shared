drop table if exists eventos_cliente;
drop function if exists notificar_correo(uuid, text, text, text, text, jsonb);
drop function if exists notificar(uuid, uuid, text, text, text, jsonb, boolean);
drop index if exists notificaciones_pendientes_idx;
alter table notificaciones drop constraint if exists notificaciones_destinatario;
alter table notificaciones drop column if exists destinatario_correo;
