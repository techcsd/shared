drop function if exists prioridad_911_expirar();
drop function if exists prioridad_911_responder_contra(uuid, boolean, text);
drop function if exists prioridad_911_responder(uuid, text, text, timestamptz, timestamptz);
drop function if exists prioridad_911_solicitar(uuid, motivo_911, urgencia_911, text, uso_reserva, uuid, int, text);
drop function if exists p911_avisar_socios(uuid, text, text, text, jsonb);
drop function if exists p911_mensaje(uuid, uuid, uuid, text, text);
drop function if exists p911_reservar_para(solicitudes_911, tstzrange);
drop table if exists solicitudes_911_mensajes, solicitudes_911 cascade;
drop type if exists estado_911, urgencia_911, motivo_911;
