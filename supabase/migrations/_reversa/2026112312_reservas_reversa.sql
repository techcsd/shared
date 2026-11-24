drop table if exists temporadas, invitado_intentos, invitado_enlaces, reserva_acuses, reserva_costos, ordenes, orden_contadores, reservas, invitados cascade;
drop function if exists fee_estimado(uuid, uuid, timestamptz, timestamptz);
drop function if exists fee_calc(uuid, uuid, timestamptz, timestamptz);
drop function if exists capacidad_efectiva(uuid, uso_reserva);
drop function if exists capacidad_efectiva_interna(uuid, uso_reserva);
drop function if exists miembro_actual(uuid);
drop function if exists pol_txt(uuid, text);
drop function if exists politica_interna(uuid, text);
drop type if exists uso_reserva, estado_reserva;
