-- Prioridad 911: pedir, nunca quitar. Atomicidad, permisos, contrapropuesta, expiración.
do $$
declare
  a uuid; b uuid; c uuid; adm uuid; g uuid; t text; bote uuid; act uuid; ra uuid; rb uuid; s1 uuid; s2 uuid; s3 uuid;
  d0 timestamptz := date_trunc('hour', now()) + interval '15 days'; est estado_911; n int; nueva uuid; cod_a text; cod_n text;
begin
  a := tests.crear_usuario('n_a@test.local', 'Ana');
  b := tests.crear_usuario('n_b@test.local', 'Beto');
  c := tests.crear_usuario('n_c@test.local', 'Carla');
  adm := tests.crear_usuario('n_adm@test.local', 'Operativo');

  perform tests.como(a);
  g := crear_grupo('Grupo 911', 'DOP', 'America/Santo_Domingo', 'NNN', 40);
  t := invitar_miembro(g, 'n_b@test.local', 'socio', 30);
  perform tests.como(b); perform aceptar_invitacion(t);
  perform tests.como(a);
  t := invitar_miembro(g, 'n_c@test.local', 'socio', 30);
  perform tests.como(c); perform aceptar_invitacion(t);
  perform tests.como(a);
  t := invitar_miembro(g, 'n_adm@test.local', 'admin_operativo', 0);
  perform tests.como(adm); perform aceptar_invitacion(t);
  perform tests.como(a);
  select id into bote from tipos_activo where clave = 'bote' and es_sistema;
  act := crear_activo(g, bote, 'Bote 911', 15);
  update activos set estado = 'activo' where id = act;

  -- A reserva el sábado
  ra := reserva_crear_borrador(act, d0, d0 + interval '8 hours', 'personal', null, 10);
  perform reserva_confirmar(ra);
  select codigo into cod_a from ordenes where reserva_id = ra;

  -- B solicita 911: la reserva de A sigue vigente
  perform tests.como(b);
  s1 := prioridad_911_solicitar(ra, 'cumpleanos', 'alta', 'Puedo el domingo', 'familiar', null, 12, 'Es el cumple de mi hijo');
  perform tests.admin();
  perform tests.igual((select estado from solicitudes_911 where id = s1), 'pendiente'::estado_911, 'solicitud pendiente');
  perform tests.igual((select estado from reservas where id = ra), 'confirmada'::estado_reserva, 'la reserva de A sigue vigente mientras no acepte');
  perform tests.igual((select count(*)::int from notificaciones where tipo = 'prioridad_911_solicitud' and canal = 'app'), 3, 'aviso a todos los socios (con N socios)');
  perform tests.igual((select count(*)::int from solicitudes_911_mensajes where solicitud_id = s1 and tipo = 'solicitud'), 1, 'historial con el primer mensaje');

  -- nadie más que el titular decide
  perform tests.como(c);
  perform tests.falla(format($q$select prioridad_911_responder(%L, 'acepta')$q$, s1), 'solo_titular_decide');
  perform tests.como(b);
  perform tests.falla(format($q$select prioridad_911_responder(%L, 'acepta')$q$, s1), 'solo_titular_decide');
  perform tests.como(adm);
  perform tests.falla(format($q$select prioridad_911_responder(%L, 'acepta')$q$, s1), 'solo_titular_decide');
  perform tests.igual((select count(*)::int from solicitudes_911), 0, 'el admin operativo no ve solicitudes 911');

  -- no hay forma de quitar una reserva sin la aceptación: ni cancelar ni editar
  perform tests.como(b);
  perform tests.falla(format($q$select reserva_cancelar(%L)$q$, ra), 'solo_quien_reserva');
  perform tests.falla(format($q$update reservas set estado = 'cancelada' where id = %L$q$, ra), 'permission denied');
  perform tests.falla(format($q$delete from reservas where id = %L$q$, ra), 'permission denied');
  perform tests.falla(format($q$update solicitudes_911 set estado = 'aceptada' where id = %L$q$, s1), 'permission denied');
  perform tests.falla(format($q$select prioridad_911_solicitar(%L, 'negocio', 'baja')$q$, ra), 'duplicate key');  -- no duplica la solicitud pendiente
  perform tests.como(a);
  perform tests.falla(format($q$select prioridad_911_solicitar(%L, 'negocio', 'baja')$q$, ra), 'es_tu_reserva');

  -- rechazar: no cambia nada
  est := prioridad_911_responder(s1, 'rechaza', 'No puedo, tengo cliente');
  perform tests.igual(est, 'rechazada'::estado_911, 'rechazada');
  perform tests.admin();
  perform tests.igual((select estado from reservas where id = ra), 'confirmada'::estado_reserva, 'rechazar mantiene la reserva');
  perform tests.igual((select count(*)::int from reservas where activo_id = act and estado = 'confirmada'), 1, 'sigue una sola reserva');
  perform tests.como(a);
  perform tests.falla(format($q$select prioridad_911_responder(%L, 'acepta')$q$, s1), 'solicitud_rechazada');

  -- aceptar: atómico (cede, crea la nueva con su orden, avisa a todos)
  perform tests.como(b);
  s2 := prioridad_911_solicitar(ra, 'evento_familiar', 'media', null, 'familiar', null, 12);
  perform tests.como(a);
  est := prioridad_911_responder(s2, 'acepta', 'Va, es tuyo');
  perform tests.igual(est, 'aceptada'::estado_911, 'aceptada');
  perform tests.admin();
  perform tests.igual((select estado from reservas where id = ra), 'cancelada'::estado_reserva, 'la de A queda cancelada (cedida)');
  select reserva_resultante_id into nueva from solicitudes_911 where id = s2;
  perform tests.igual((select estado from reservas where id = nueva), 'confirmada'::estado_reserva, 'B tiene la reserva confirmada');
  perform tests.igual((select reservado_por from reservas where id = nueva), (select id from miembros where grupo_id = g and usuario_id = b), 'a nombre de B');
  perform tests.igual((select count(*)::int from reservas where activo_id = act and estado = 'confirmada'), 1, 'nunca dos a la vez');
  select codigo into cod_n from ordenes where reserva_id = nueva;
  perform tests.igual(cod_n, 'BOT-' || extract(year from now())::int || '-0002', 'nueva orden');
  perform tests.igual((select cancelacion_tardia from reservas where id = ra), false, 'ceder no es cancelación tardía');
  perform tests.igual((select count(*)::int from notificaciones where tipo = 'prioridad_911_aceptada' and canal = 'app'), 3, 'aviso a todos');
  perform tests.igual((select count(*)::int from solicitudes_911_mensajes where solicitud_id = s2), 2, 'historial: solicitud + decisión');

  -- contrapropuesta: el titular ofrece otro horario; el solicitante acepta; el titular conserva su reserva
  perform tests.como(c);
  s3 := prioridad_911_solicitar(nueva, 'negocio', 'baja', null, 'negocios', null, 4);
  perform tests.como(b);
  est := prioridad_911_responder(s3, 'contrapropone', 'Mejor el lunes', d0 + interval '2 days', d0 + interval '2 days 6 hours');
  perform tests.igual(est, 'contrapropuesta'::estado_911, 'contrapropuesta');
  perform tests.como(a);
  perform tests.falla(format($q$select prioridad_911_responder_contra(%L, true)$q$, s3), 'solo_solicitante_responde');
  perform tests.como(c);
  est := prioridad_911_responder_contra(s3, true, 'Acepto el lunes');
  perform tests.igual(est, 'aceptada_contra'::estado_911, 'contrapropuesta aceptada');
  perform tests.admin();
  perform tests.igual((select estado from reservas where id = nueva), 'confirmada'::estado_reserva, 'el titular conserva su reserva');
  perform tests.igual((select count(*)::int from reservas where activo_id = act and estado = 'confirmada'), 2, 'ahora hay dos, en horarios distintos');
  perform tests.igual((select count(*)::int from reservas r1 join reservas r2 on r1.id < r2.id and r1.activo_id = r2.activo_id
     where r1.estado = 'confirmada' and r2.estado = 'confirmada' and r1.rango_bloqueo && r2.rango_bloqueo), 0, 'ningún solape');

  -- contrapropuesta rechazada: nada cambia
  perform tests.como(c);
  s3 := prioridad_911_solicitar(nueva, 'cliente', 'baja', null, 'negocios', null, 4);
  perform tests.como(b);
  perform prioridad_911_responder(s3, 'contrapropone', null, d0 + interval '4 days', d0 + interval '4 days 6 hours');
  perform tests.como(c);
  est := prioridad_911_responder_contra(s3, false);
  perform tests.igual(est, 'rechazada_contra'::estado_911, 'contrapropuesta rechazada');
  perform tests.admin();
  perform tests.igual((select count(*)::int from reservas where activo_id = act and estado = 'confirmada'), 2, 'sin cambios');

  -- contrapropuesta inválida
  perform tests.como(c);
  s3 := prioridad_911_solicitar(nueva, 'cliente', 'baja', null, 'negocios', null, 4);
  perform tests.como(b);
  perform tests.falla(format($q$select prioridad_911_responder(%L, 'contrapropone', null, now() - interval '1 day', now())$q$, s3), 'contrapropuesta_invalida');
  perform tests.falla(format($q$select prioridad_911_responder(%L, 'borrar')$q$, s3), 'accion_invalida');

  -- expiración: no toca la reserva; después de expirar el titular ya no puede aceptar
  perform tests.admin();
  update solicitudes_911 set expira_en = now() - interval '1 minute' where id = s3;
  perform tests.igual(cron_mantenimiento() ->> 'solicitudes_911_expiradas', '1', 'el cron expira la solicitud');
  perform tests.igual((select estado from solicitudes_911 where id = s3), 'expirada'::estado_911, 'expirada');
  perform tests.igual((select estado from reservas where id = nueva), 'confirmada'::estado_reserva, 'expirar no altera la reserva');
  perform tests.como(b);
  perform tests.falla(format($q$select prioridad_911_responder(%L, 'acepta')$q$, s3), 'solicitud_expirada');

  -- solicitud sobre reserva que ya empezó o no confirmada
  perform tests.como(c);
  perform tests.falla(format($q$select prioridad_911_solicitar(%L, 'cliente', 'baja')$q$, ra), 'la_reserva_no_admite_911');
end $$;
