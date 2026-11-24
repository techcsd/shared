-- Reservas: choques, capacidad, transiciones, cancelación, acuses, bloqueos, invitados, temporada, permisos.
do $$
declare
  a uuid; b uuid; adm uuid; ext uuid; g uuid; t text; bote uuid; act uuid; dest uuid;
  r1 uuid; r2 uuid; r3 uuid; r4 uuid; bl uuid; cod text; n int; v_tardia boolean; v_cargo numeric;
  d0 timestamptz := date_trunc('hour', now()) + interval '10 days'; v_ver uuid; v_tok text; j jsonb;
  ver uuid; ma uuid; est estado_reserva;
begin
  a := tests.crear_usuario('rv_a@test.local', 'Ana');
  b := tests.crear_usuario('rv_b@test.local', 'Beto');
  adm := tests.crear_usuario('rv_adm@test.local', 'Operativo');
  ext := tests.crear_usuario('rv_ext@test.local', 'Externo');

  perform tests.como(a);
  g := crear_grupo('Grupo RV', 'DOP', 'America/Santo_Domingo', 'RVV', 50);
  t := invitar_miembro(g, 'rv_b@test.local', 'socio', 50);
  perform tests.como(b); perform aceptar_invitacion(t);
  perform tests.como(a);
  t := invitar_miembro(g, 'rv_adm@test.local', 'admin_operativo', 0);
  perform tests.como(adm); perform aceptar_invitacion(t);
  perform tests.como(ext); perform crear_grupo('Otro grupo', 'DOP', 'America/Santo_Domingo', 'OTR', 100);

  -- Activo Bote (cap. legal 15) y destino con fee 5000
  perform tests.como(a);
  select id into bote from tipos_activo where clave = 'bote' and es_sistema;
  act := crear_activo(g, bote, 'Bote RV', 15);
  update activos set estado = 'activo', punto_encuentro = 'Marina X', reglas_invitados = 'Chaleco puesto', contacto_invitados = 'Ana 809-555-0000' where id = act;
  insert into destinos (grupo_id, nombre) values (g, 'Playa') returning id into dest;
  insert into tarifas (grupo_id, destino_id, tipo, monto, moneda) values (g, dest, 'fee_destino', 5000, 'DOP');

  -- ============ F1: borrador → confirmar, orden atómica, aviso al otro socio
  perform tests.como(a);
  r1 := reserva_crear_borrador(act, d0, d0 + interval '6 hours', 'personal', dest, 10);
  perform tests.igual((select estado from reservas where id = r1), 'borrador'::estado_reserva, 'nace borrador');
  select orden into cod from reserva_confirmar(r1);
  perform tests.igual(cod, 'BOT-' || extract(year from now())::int || '-0001', 'primera orden');
  perform tests.igual((select estado from reservas where id = r1), 'confirmada'::estado_reserva, 'confirmada');
  perform tests.admin();
  perform tests.igual((select count(*)::int from notificaciones where usuario_id = b and tipo = 'reserva_confirmada' and canal = 'app'), 1, 'aviso in-app al otro socio');
  perform tests.igual((select count(*)::int from notificaciones where usuario_id = b and tipo = 'reserva_confirmada' and canal = 'correo' and estado_envio = 'pendiente'), 1, 'correo en cola');
  perform tests.igual((select count(*)::int from notificaciones where usuario_id = a and tipo = 'reserva_confirmada'), 0, 'el titular no se avisa a sí mismo');
  perform tests.igual((select fee from reserva_costos where reserva_id = r1), 5000::numeric, 'fee estimado guardado');

  -- ============ SA5: sin choques
  perform tests.como(b);
  r2 := reserva_crear_borrador(act, d0 + interval '2 hours', d0 + interval '4 hours', 'personal', dest, 5);
  perform tests.falla(format($q$select reserva_confirmar(%L)$q$, r2), 'horario_ocupado');
  -- el borrador no ocupa calendario; ajustar a continuación exacta (fin == inicio) sí pasa
  perform reserva_cancelar(r2);
  r2 := reserva_crear_borrador(act, d0 + interval '6 hours', d0 + interval '8 hours', 'familiar', dest, 5);
  select orden into cod from reserva_confirmar(r2);
  perform tests.igual(cod, 'BOT-' || extract(year from now())::int || '-0002', 'segunda orden consecutiva');

  -- carrera: dos borradores del mismo rango; el primero que confirma gana, el segundo falla
  r3 := reserva_crear_borrador(act, d0 + interval '1 day', d0 + interval '1 day 3 hours', 'personal', dest, 3);
  perform tests.como(a);
  r4 := reserva_crear_borrador(act, d0 + interval '1 day', d0 + interval '1 day 3 hours', 'personal', dest, 3);
  perform reserva_confirmar(r4);
  perform tests.como(b);
  perform tests.falla(format($q$select reserva_confirmar(%L)$q$, r3), 'horario_ocupado');
  perform tests.admin();
  perform tests.igual((select count(*)::int from reservas where activo_id = act and estado = 'confirmada'
                         and rango && tstzrange(d0 + interval '1 day', d0 + interval '1 day 3 hours')), 1, 'solo una gana la carrera');
  -- la base lo impide aunque se intente forzar por SQL directo
  perform tests.falla(format($q$insert into reservas (grupo_id, activo_id, rango, rango_bloqueo, estado, tipo_bloqueo)
     values (%L, %L, tstzrange(%L::timestamptz, %L::timestamptz), tstzrange(%L::timestamptz, %L::timestamptz), 'bloqueada_mantenimiento', 'mantenimiento')$q$,
     g, act, d0 + interval '1 day 1 hour', d0 + interval '1 day 2 hours', d0 + interval '1 day 1 hour', d0 + interval '1 day 2 hours'), 'reservas_sin_solapamiento');

  -- ============ bloqueos de mantenimiento (socio o admin operativo)
  perform tests.como(adm);
  bl := bloqueo_crear(act, d0 + interval '3 days', d0 + interval '4 days', 'mantenimiento', 'Cambio de aceite');
  perform tests.falla(format($q$select bloqueo_crear(%L, %L, %L, 'preparacion')$q$, act, d0 + interval '3 days 2 hours', d0 + interval '3 days 5 hours'), 'horario_ocupado');
  perform tests.como(b);
  r3 := reserva_crear_borrador(act, d0 + interval '3 days 5 hours', d0 + interval '3 days 8 hours', 'personal', dest, 2);
  perform tests.falla(format($q$select reserva_confirmar(%L)$q$, r3), 'horario_ocupado');
  perform tests.como(ext);
  perform tests.falla(format($q$select bloqueo_crear(%L, %L, %L, 'mantenimiento')$q$, act, d0 + interval '9 days', d0 + interval '9 days 2 hours'), 'sin_permiso');
  perform tests.como(adm);
  perform bloqueo_quitar(bl);
  perform tests.como(b);
  perform reserva_confirmar(r3);   -- ahora el hueco está libre

  -- ============ SA9: capacidad (socio 15 / invitado 8, el límite legal manda)
  perform tests.como(a);
  perform tests.falla(format($q$select reserva_crear_borrador(%L, %L, %L, 'personal', null, 16)$q$, act, d0 + interval '5 days', d0 + interval '5 days 2 hours'), 'capacidad_excedida');
  r3 := reserva_crear_borrador(act, d0 + interval '5 days', d0 + interval '5 days 2 hours', 'personal', null, 15);
  perform reserva_cancelar(r3);
  perform tests.falla(format($q$select reserva_crear_borrador(%L, %L, %L, 'invitado', null, 9, null, 'Invitado Uno', 'inv@test.local')$q$, act, d0 + interval '5 days', d0 + interval '5 days 2 hours'), 'capacidad_excedida');
  perform tests.falla(format($q$select reserva_crear_borrador(%L, %L, %L, 'invitado', null, 3)$q$, act, d0 + interval '5 days', d0 + interval '5 days 2 hours'), 'invitado_requiere_nombre_y_correo');
  -- el límite legal manda: bajar la capacidad certificada a 6 limita el uso de socio
  update activos set capacidad_legal = 6 where id = act;
  perform tests.falla(format($q$select reserva_crear_borrador(%L, %L, %L, 'personal', null, 7)$q$, act, d0 + interval '5 days', d0 + interval '5 days 2 hours'), 'capacidad_excedida: máximo 6');
  perform tests.igual(capacidad_efectiva(act, 'personal'), 6, 'capacidad efectiva = min(15, legal 6)');
  update activos set capacidad_legal = 15 where id = act;
  perform tests.igual(capacidad_efectiva(act, 'invitado'), 8, 'capacidad invitado 8');

  -- ============ SC8 / SA16: invitado sin cuenta
  r3 := reserva_crear_borrador(act, d0 + interval '5 days', d0 + interval '5 days 4 hours', 'invitado', dest, 8, null, 'Pedro Invitado', 'pedro@test.local');
  perform reserva_confirmar(r3);
  perform tests.admin();
  select datos ->> 'token' into v_tok from notificaciones where destinatario_correo = 'pedro@test.local' and tipo = 'invitado_enlace';
  perform tests.igual(length(v_tok), 64, 'token de invitado generado');
  perform tests.igual((select count(*)::int from invitado_enlaces where token_hash = v_tok), 0, 'el token NO se guarda en claro');
  j := invitado_ver(v_tok);
  perform tests.igual(j ->> 'punto_encuentro', 'Marina X', 'invitado ve punto de encuentro');
  perform tests.igual(j ->> 'reglas', 'Chaleco puesto', 'invitado ve reglas');
  perform tests.igual(j ->> 'contacto', 'Ana 809-555-0000', 'invitado ve contacto');
  perform tests.igual((j ? 'fee') or (j ? 'tarifa') or (j ? 'monto') or (j ? 'socios') or (j ? 'anfitrion'), false, 'invitado NO ve tarifas ni datos de socios');
  perform tests.igual(invitado_ver(v_tok || 'x'), null::jsonb, 'token alterado no devuelve nada');
  perform tests.igual(invitado_ver(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')), null::jsonb, 'token ajeno no devuelve nada');
  update invitado_enlaces set expira_en = now() - interval '1 minute' where reserva_id = r3;
  perform tests.igual(invitado_ver(v_tok), null::jsonb, 'token expirado no devuelve nada');
  update invitado_enlaces set expira_en = now() + interval '1 day' where reserva_id = r3;
  -- límite de intentos por IP
  for n in 1..20 loop perform invitado_ver('basura' || n, 'iphash1'); end loop;
  perform tests.falla($q$select invitado_ver('otra', 'iphash1')$q$, 'demasiados_intentos');
  -- los clientes autenticados no pueden llamar la vista de invitado ni leer enlaces
  perform tests.como(a);
  perform tests.falla(format($q$select invitado_ver(%L)$q$, v_tok), 'permission denied');
  perform tests.falla($q$select * from invitado_enlaces$q$, 'permission denied');

  -- ============ transiciones (SA7)
  r3 := reserva_crear_borrador(act, d0 + interval '6 days', d0 + interval '6 days 2 hours', 'personal', null, 4);
  perform tests.falla(format($q$select reserva_iniciar(%L)$q$, r3), 'transicion_invalida');
  perform tests.falla(format($q$select reserva_finalizar(%L)$q$, r3), 'transicion_invalida');
  perform reserva_confirmar(r3);
  perform tests.falla(format($q$select reserva_confirmar(%L)$q$, r3), 'transicion_invalida');
  perform tests.falla(format($q$select reserva_finalizar(%L)$q$, r3), 'transicion_invalida');
  perform reserva_iniciar(r3);
  perform tests.falla(format($q$select reserva_cancelar(%L)$q$, r3), 'transicion_invalida');
  perform tests.falla(format($q$select reserva_iniciar(%L)$q$, r3), 'transicion_invalida');
  perform reserva_finalizar(r3);
  perform tests.admin();
  perform tests.igual((select estado from reservas where id = r3), 'finalizada'::estado_reserva, 'finalizada');
  perform tests.falla(format($q$update reservas set estado = 'confirmada' where id = %L$q$, r3));  -- ni siquiera el dueño: sin trigger de vuelta atrás
  -- otro socio no maneja la reserva ajena
  perform tests.como(b);
  r4 := reserva_crear_borrador(act, d0 + interval '7 days', d0 + interval '7 days 2 hours', 'personal', null, 4);
  perform tests.como(a);
  perform tests.falla(format($q$select reserva_confirmar(%L)$q$, r4), 'solo_quien_reserva');
  perform tests.falla(format($q$select reserva_cancelar(%L)$q$, r4), 'solo_quien_reserva');

  -- ============ SA22 / DF-09: cancelación tardía y cargo
  perform tests.como(a);
  perform proponer_cambio_politica(g, '{"cancelacion.cargo_tardio_pct": 10}');
  perform tests.como(b); perform aceptar_version((select id from estatuto_versiones where grupo_id = g and estado = 'pendiente'));
  perform tests.como(a);
  r3 := reserva_crear_borrador(act, now() + interval '10 hours', now() + interval '12 hours', 'personal', dest, 4);
  perform reserva_confirmar(r3);
  select tardia, cargo into v_tardia, v_cargo from reserva_cancelar(r3, 'imprevisto');
  perform tests.igual(v_tardia, true, 'cancelación tardía (< 48 h)');
  perform tests.igual(v_cargo, 500::numeric, 'cargo tardío 10 % de 5000');
  perform tests.admin();
  perform tests.igual((select cancelacion_tardia from reservas where id = r3), true, 'queda registrada la cancelación tardía');
  perform tests.como(a);
  r3 := reserva_crear_borrador(act, d0 + interval '20 days', d0 + interval '20 days 2 hours', 'personal', dest, 4);
  perform reserva_confirmar(r3);
  select tardia, cargo into v_tardia, v_cargo from reserva_cancelar(r3);
  perform tests.igual(v_tardia, false, 'cancelación a tiempo sin cargo');
  perform tests.igual(v_cargo, 0::numeric, 'sin cargo');

  -- ============ DF-10: días seguidos (default 3) y varios días
  perform tests.falla(format($q$select reserva_crear_borrador(%L, %L, %L, 'personal', null, 2)$q$, act, d0 + interval '30 days', d0 + interval '34 days'), 'dias_max_superados');
  perform tests.falla(format($q$select reserva_crear_borrador(%L, %L, %L, 'personal', null, 2)$q$, act, d0 + interval '30 days', d0 + interval '29 days'), 'rango_invalido');
  perform tests.falla(format($q$select reserva_crear_borrador(%L, %L, %L, 'personal', null, 2)$q$, act, now() - interval '3 days', now() - interval '3 days' + interval '2 hours'), 'fecha_pasada');
  r3 := reserva_crear_borrador(act, d0 + interval '30 days', d0 + interval '32 days 12 hours', 'personal', null, 2);  -- 2.5 días → 3
  perform reserva_cancelar(r3);

  -- ============ SA3: acuse «Leído y enterado» (no es aprobación)
  perform tests.como(b);
  perform reserva_marcar_enterado(r1);
  perform reserva_marcar_enterado(r1);   -- idempotente
  perform tests.igual((select count(*)::int from reserva_acuses where reserva_id = r1), 1, 'un acuse por socio');
  perform tests.como(a);
  perform tests.falla(format($q$select reserva_marcar_enterado(%L)$q$, r1), 'el_titular_no_marca_enterado');
  perform tests.como(adm);
  perform tests.falla(format($q$select reserva_marcar_enterado(%L)$q$, r1), 'solo_socios');
  perform tests.como(b);
  perform tests.igual((select estado from reservas where id = r1), 'confirmada'::estado_reserva, 'el acuse no cambia la reserva');

  -- recordatorios: reserva que empieza en 1 h y el otro socio no marcó
  perform tests.como(a);
  r3 := reserva_crear_borrador(act, now() + interval '1 hour', now() + interval '3 hours', 'personal', null, 3);
  perform reserva_confirmar(r3);
  perform tests.admin();
  perform tests.igual(recordatorios_acuse(), 1, 'un recordatorio (2 h)');
  perform tests.igual(recordatorios_acuse(), 0, 'no se repite');
  perform tests.igual((select (datos ->> 'horas')::int from notificaciones where tipo = 'recordatorio_acuse' and usuario_id = b limit 1), 2, 'recordatorio de 2 h');

  -- ============ SA16 / finanzas: el admin operativo no ve tarifas ni costos, y no reserva
  perform tests.como(adm);
  perform tests.igual((select count(*)::int from fee_estimado(g, dest, d0, d0 + interval '2 hours')), 0, 'admin no obtiene fee estimado');
  perform tests.igual((select count(*)::int from reserva_costos), 0, 'admin no ve costos');
  perform tests.igual((select count(*)::int from reservas where grupo_id = g) > 0, true, 'admin ve el calendario');
  perform tests.falla(format($q$select reserva_crear_borrador(%L, %L, %L, 'personal', null, 2)$q$, act, d0 + interval '12 days', d0 + interval '12 days 2 hours'), 'solo_socios_reservan');
  perform tests.como(a);
  perform tests.igual((select monto from fee_estimado(g, dest, d0, d0 + interval '2 hours')), 5000::numeric, 'socio ve el fee estimado');

  -- ============ aislamiento y escritura directa
  perform tests.como(ext);
  perform tests.igual((select count(*)::int from reservas), 0, 'otro grupo no ve reservas');
  perform tests.igual((select count(*)::int from ordenes), 0, 'otro grupo no ve órdenes');
  perform tests.falla(format($q$select reserva_crear_borrador(%L, %L, %L, 'personal', null, 2)$q$, act, d0 + interval '13 days', d0 + interval '13 days 2 hours'), 'solo_socios_reservan');
  perform tests.como(a);
  perform tests.falla(format($q$insert into reservas (grupo_id, activo_id, rango, rango_bloqueo, estado, tipo_bloqueo) values (%L, %L, tstzrange(now(), now() + interval '1 hour'), tstzrange(now(), now() + interval '1 hour'), 'bloqueada_mantenimiento', 'mantenimiento')$q$, g, act), 'permission denied');
  perform tests.falla(format($q$update reservas set estado = 'cancelada' where id = %L$q$, r1), 'permission denied');
  perform tests.falla($q$select reserva_confirmar_interna(gen_random_uuid())$q$, 'permission denied');

  -- ============ borradores caducan (DF-14)
  r3 := reserva_crear_borrador(act, d0 + interval '14 days', d0 + interval '14 days 2 hours', 'personal', null, 2);
  perform tests.admin();
  perform tests.igual(limpiar_borradores(), 0, 'borrador vigente no se limpia');
  update reservas set borrador_expira_en = now() - interval '1 minute' where id = r3;
  perform tests.como(a);
  perform tests.falla(format($q$select reserva_confirmar(%L)$q$, r3), 'borrador_expirado');
  perform tests.admin();
  perform tests.igual(limpiar_borradores(), 1, 'borrador vencido se limpia');

  -- ============ DF-18: buffer de preparación bloquea alrededor de cada salida
  perform tests.como(a);
  perform proponer_cambio_politica(g, '{"reservas.buffer_horas": 2}');
  perform tests.como(b); perform aceptar_version((select id from estatuto_versiones where grupo_id = g and estado = 'pendiente'));
  perform tests.como(a);
  r3 := reserva_crear_borrador(act, d0 + interval '40 days', d0 + interval '40 days 2 hours', 'personal', null, 2);
  perform reserva_confirmar(r3);
  perform tests.como(b);
  r4 := reserva_crear_borrador(act, d0 + interval '40 days 3 hours', d0 + interval '40 days 5 hours', 'personal', null, 2);
  perform tests.falla(format($q$select reserva_confirmar(%L)$q$, r4), 'horario_ocupado');   -- hueco de 1 h < buffer de 2 h
  perform reserva_cancelar(r4);
  r4 := reserva_crear_borrador(act, d0 + interval '40 days 4 hours', d0 + interval '40 days 6 hours', 'personal', null, 2);
  perform reserva_confirmar(r4);   -- hueco de 2 h = buffer: pasa

  -- ============ DF-19 / SA27: temporada alta (apagada por defecto; con rotación si se activa)
  perform tests.como(a);
  perform proponer_cambio_politica(g, '{"temporada_alta.activa": true}');
  perform tests.como(b); perform aceptar_version((select id from estatuto_versiones where grupo_id = g and estado = 'pendiente'));
  perform tests.como(a);
  perform temporada_generar(g, 'navidad', 2100, (current_date + 400)::date, (current_date + 405)::date);
  perform tests.admin();
  select miembro_prioridad into ver from temporadas where grupo_id = g and periodo = 'navidad';
  select id into ma from miembros where grupo_id = g and usuario_id = a;
  perform tests.como(case when ver = ma then b else a end);
  perform tests.falla(format($q$select reserva_crear_borrador(%L, %L, %L, 'personal', null, 2)$q$, act,
     ((current_date + 401)::timestamptz + interval '10 hours'), ((current_date + 401)::timestamptz + interval '12 hours')), 'temporada_alta_prioridad');
  perform tests.como(case when ver = ma then a else b end);
  r3 := reserva_crear_borrador(act, ((current_date + 401)::timestamptz + interval '10 hours'), ((current_date + 401)::timestamptz + interval '12 hours'), 'personal', null, 2);
  perform reserva_confirmar(r3);
  perform tests.admin();
  perform tests.igual((select count(*)::int from temporadas where grupo_id = g), 1, 'temporada registrada');
end $$;
