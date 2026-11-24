-- Mantenimiento (fecha / horas / lo que ocurra primero), bloqueo sin cancelar reservas, servicio→gasto, seguro, capitanes y admin operativo.
do $$
declare
  a uuid; b uuid; adm uuid; cap uuid; g uuid; t text; bote uuid; act uuid; dest uuid; ma uuid; mb uuid; madm uuid; mc uuid;
  c1 uuid; p1 uuid; p2 uuid; p3 uuid; st record; n int; r1 uuid; j jsonb; tarea uuid; srv uuid; gs uuid; pol uuid; sin uuid; capi uuid; d1 timestamptz; r2 uuid;
  d0 timestamptz := date_trunc('hour', now()) + interval '70 days'; lect jsonb; ck jsonb; caso uuid;
begin
  perform tests.admin();
  a := tests.crear_usuario('mt_a@test.local', 'Ana');
  b := tests.crear_usuario('mt_b@test.local', 'Beto');
  adm := tests.crear_usuario('mt_adm@test.local', 'Operativo');
  cap := tests.crear_usuario('mt_cap@test.local', 'Capi');
  perform tests.como(a);
  g := crear_grupo('Grupo MT', 'DOP', 'America/Santo_Domingo', 'MTT', 50);
  t := invitar_miembro(g, 'mt_b@test.local', 'socio', 50); perform tests.como(b); perform aceptar_invitacion(t);
  perform tests.como(a);
  t := invitar_miembro(g, 'mt_adm@test.local', 'admin_operativo', 0); perform tests.como(adm); perform aceptar_invitacion(t);
  perform tests.como(a);
  t := invitar_miembro(g, 'mt_cap@test.local', 'capitan', 0); perform tests.como(cap); perform aceptar_invitacion(t);
  perform tests.como(a);
  select id into bote from tipos_activo where clave = 'bote' and es_sistema;
  act := crear_activo(g, bote, 'Bote MT', 15);
  update activos set estado = 'activo' where id = act;
  insert into destinos (grupo_id, nombre) values (g, 'Playa') returning id into dest;
  select id into ma from miembros where grupo_id = g and usuario_id = a;
  select id into mb from miembros where grupo_id = g and usuario_id = b;
  select id into madm from miembros where grupo_id = g and usuario_id = adm;
  select id into mc from miembros where grupo_id = g and usuario_id = cap;
  select id into c1 from activo_componentes where activo_id = act order by indice limit 1;

  -- ============ criterio «lo que ocurra primero» (DF-13)
  p1 := plan_guardar(g, null, act, c1, 'Aceite motor (50 h ó 1 año)', '', 365, 50);   -- política por defecto = primero
  perform tests.admin();
  update activo_componentes set lectura_inicial = 60 where id = c1;          -- el motor ya acumuló 60 h desde el plan
  perform tests.como(a);
  select * into st from plan_estado(p1);
  perform tests.igual(st.criterio, 'primero', 'criterio por defecto: lo que ocurra primero');
  perform tests.igual(st.vencido, true, 'vence por HORAS aunque la fecha no haya llegado');
  perform tests.igual(st.disparador, 'horas', 'disparador horas');
  perform tests.igual(st.dias_restantes > 300, true, 'a la fecha le quedan más de 300 días');

  p2 := plan_guardar(g, null, act, c1, 'Revisión anual (10 días ó 500 h)', '', 10, 500);
  perform tests.admin();
  update mantenimiento_planes set ultima_fecha = current_date - 20, ultima_lectura = 55 where id = p2;   -- 20 días atrás; horas lejos (55+500)
  select * into st from plan_estado(p2);
  perform tests.igual(st.vencido, true, 'vence por FECHA aunque las horas no lleguen');
  perform tests.igual(st.disparador, 'fecha', 'disparador fecha');
  perform tests.igual(st.horas_restantes > 400, true, 'a las horas les faltan más de 400');

  perform tests.como(a);
  p3 := plan_guardar(g, null, act, c1, 'Solo horas (500 h)', 'horas', 10, 500);
  perform tests.admin();
  update mantenimiento_planes set ultima_fecha = current_date - 400, ultima_lectura = 55 where id = p3;
  select * into st from plan_estado(p3);
  perform tests.igual(st.vencido, false, 'criterio solo-horas: la fecha vencida no cuenta');

  -- ============ alertas: tareas y avisos, una sola vez
  perform tests.admin();
  n := mantenimiento_evaluar();
  perform tests.igual(n >= 2, true, 'se emiten alertas de los planes vencidos');
  perform tests.igual((select count(*)::int from mantenimiento_tareas where grupo_id = g and plan_id in (p1, p2)), 2, 'se crean las tareas de los planes vencidos');
  perform tests.igual((select count(*)::int from notificaciones where usuario_id = b and tipo = 'mantenimiento_vencido' and canal = 'app'), 2, 'los socios reciben el aviso');
  perform tests.igual((select count(*)::int from notificaciones where usuario_id = adm and tipo = 'mantenimiento_vencido' and canal = 'app'), 2, 'y el admin operativo');
  perform tests.igual(mantenimiento_evaluar(), 0, 'la segunda evaluación no repite alertas');

  -- ============ bloqueo del calendario sin cancelar reservas
  perform tests.como(a);
  r1 := reserva_crear_borrador(act, d0, d0 + interval '6 hours', 'personal', dest, 4, ma);
  perform reserva_confirmar(r1);
  select id into tarea from mantenimiento_tareas where plan_id = p1;
  j := tarea_programar(tarea, d0 + interval '2 hours', d0 + interval '8 hours');
  perform tests.igual((j ->> 'ok')::boolean, false, 'choca con una reserva confirmada: no se programa');
  perform tests.igual(jsonb_array_length(j -> 'conflictos'), 1, 'lista el conflicto');
  perform tests.igual((j -> 'sugerida' ->> 'inicio')::timestamptz >= d0 + interval '6 hours', true, 'propone una fecha libre posterior');
  perform tests.admin();
  perform tests.igual((select estado from reservas where id = r1), 'confirmada'::estado_reserva, 'la reserva NO se cancela');
  perform tests.como(adm);
  j := tarea_programar(tarea, (j -> 'sugerida' ->> 'inicio')::timestamptz, (j -> 'sugerida' ->> 'fin')::timestamptz, 'Cambio de aceite');
  perform tests.igual((j ->> 'ok')::boolean, true, 'en la fecha sugerida se programa');
  perform tests.admin();
  perform tests.igual((select estado from mantenimiento_tareas where id = tarea), 'programada', 'tarea programada');
  perform tests.igual((select estado from reservas where id = (j ->> 'bloqueo_id')::uuid), 'bloqueada_mantenimiento'::estado_reserva, 'bloqueo de mantenimiento en el calendario');
  perform tests.como(b);
  d1 := (select lower(rango) from reservas where id = (j ->> 'bloqueo_id')::uuid);
  r2 := reserva_crear_borrador(act, d1 + interval '1 hour', d1 + interval '2 hours', 'personal', dest, 3, mb);
  perform tests.falla(format($q$select reserva_confirmar(%L)$q$, r2), 'horario_ocupado');

  -- ============ servicio → gasto común (SA10) + alerta del vencimiento de la factura
  perform tests.como(adm);
  srv := servicio_registrar(g, act, c1, tarea, null, current_date, null, 'Taller Naval', 'Cambio de aceite y filtros', 1500, 'DOP', 'mantenimiento', current_date + 3);
  perform tests.admin();
  perform tests.igual((select estado from mantenimiento_tareas where id = tarea), 'hecha', 'la tarea queda hecha');
  perform tests.igual((select gasto_id is not null from servicios where id = srv), true, 'el servicio registró su factura como gasto');
  select id into gs from gastos where id = (select gasto_id from servicios where id = srv);
  perform tests.igual((select alcance from gastos where id = gs), 'comun', 'gasto común');
  perform tests.igual((select cargado_por from gastos where id = gs), madm, 'cargado por el admin operativo');
  perform tests.igual((select estado from gastos where id = gs), 'registrado', 'sin validar: lo valida un socio');
  perform tests.igual((select ultima_lectura from mantenimiento_planes where id = p1), 60::numeric, 'el plan recomienza desde la lectura del servicio');
  select * into st from plan_estado(p1);
  perform tests.igual(st.vencido, false, 'tras el servicio el plan ya no está vencido');
  perform mantenimiento_evaluar();
  perform tests.igual((select count(*)::int from notificaciones where usuario_id = b and tipo = 'factura_por_vencer'), 1, 'alerta del vencimiento de la factura');

  -- ============ seguro y siniestros (DF-21)
  perform tests.como(a);
  perform tests.igual(activo_poliza_vigente(act), false, 'sin póliza vigente: aviso permanente (no bloquea)');
  pol := poliza_guardar(g, null, act, 'Aseguradora Mar', 'POL-1', 'Casco y motores', current_date - 300, current_date + 5, 1000, 'DOP');
  perform tests.igual(activo_poliza_vigente(act), true, 'con póliza vigente');
  perform tests.admin();
  perform mantenimiento_evaluar();
  perform tests.igual((select count(*)::int from notificaciones where usuario_id = b and tipo = 'seguro_por_vencer' and canal = 'app'), 1, 'alerta de vencimiento del seguro (30 y 7 días)');
  perform tests.como(a);
  n := (select count(*)::int from libro_mayor where grupo_id = g);
  sin := siniestro_abrir(g, act, 'Golpe en el espejo de popa');
  perform tests.admin();
  perform tests.igual((select count(*)::int from libro_mayor where grupo_id = g), n, 'el deducible NO genera cargos automáticos');
  perform tests.igual((select caso_dano_id is not null from siniestros where id = sin), true, 'el deducible entra al flujo de daños');
  perform tests.igual((select estado from danos_casos where id = (select caso_dano_id from siniestros where id = sin)), 'en_revision', 'en revisión: lo deciden los socios');
  perform tests.como(adm);
  perform tests.falla(format($q$select poliza_guardar(%L, null, %L, 'X Seguros', null, null, current_date, current_date + 10, 0, 'DOP')$q$, g, act), 'solo_socios');

  -- ============ capitanes y licencias (DF-20)
  perform tests.como(a);
  select jsonb_agg(jsonb_build_object('componente_id', id, 'valor', 70 + indice) order by indice) into lect from activo_componentes where activo_id = act;
  ck := jsonb_build_array(
    jsonb_build_object('clave', 'extintor', 'cumple', true), jsonb_build_object('clave', 'botiquin', 'cumple', true),
    jsonb_build_object('clave', 'capitan_sobrio', 'cumple', true), jsonb_build_object('clave', 'chalecos', 'cumple', true),
    jsonb_build_object('clave', 'menores', 'cumple', true), jsonb_build_object('clave', 'clima', 'cumple', true));
  capi := capitan_guardar(g, null, 'Capitán Vencido', null, 'LIC-X', current_date - 1, 4, null);
  r1 := reserva_crear_borrador(act, d0 + interval '3 days', d0 + interval '3 days 4 hours', 'personal', dest, 4, ma);
  perform reserva_confirmar(r1);
  j := checkin_registrar(r1, null, 'Capitán Vencido', dest, 50, lect, ck);
  perform tests.igual((j ->> 'ok')::boolean, false, 'licencia vencida: no hay check-in');
  perform tests.igual((select count(*)::int from jsonb_array_elements(j -> 'faltan') f where f ->> 'codigo' = 'capitan_sin_licencia'), 1, 'dice que el capitán no tiene licencia vigente');
  j := checkin_registrar(r1, null, 'Persona Desconocida', dest, 50, lect, ck);
  perform tests.igual((j ->> 'ok')::boolean, false, 'un capitán no registrado tampoco sirve');
  perform capitan_guardar(g, capi, 'Capitán Vencido', null, 'LIC-X', current_date + 90, 4, null);
  j := checkin_registrar(r1, null, 'Capitán Vencido', dest, 50, lect, ck);
  perform tests.igual((j ->> 'ok')::boolean, true, 'con licencia renovada sí sale');
  perform tests.admin();
  insert into capitanes (grupo_id, nombre, licencia_vence) values (g, 'Por vencer', current_date + 5);
  perform mantenimiento_evaluar();
  perform tests.igual((select count(*)::int from notificaciones where usuario_id = b and tipo = 'licencia_por_vencer' and canal = 'app'), 1, 'alerta de licencia por vencer');

  -- el rol capitán: ve la operación, nada de finanzas ni acuerdos
  perform tests.como(cap);
  perform tests.igual((select count(*)::int from operaciones where grupo_id = g), 1, 'el capitán ve la operación');
  perform tests.igual((select count(*)::int from libro_mayor), 0, 'sin libro mayor');
  perform tests.igual((select count(*)::int from gastos), 0, 'sin gastos');
  perform tests.falla(format($q$select * from balances_grupo(%L)$q$, g), 'solo_socios');
  perform tests.falla(format($q$select dano_responder(%L, true)$q$, (select id from danos_casos where grupo_id = g limit 1)));

  -- ============ admin operativo: no cambia acuerdos, políticas, estatuto, daños ni ve finanzas de los socios (SA16)
  perform tests.como(adm);
  perform tests.falla(format($q$select proponer_cambio_politica(%L, '{"reservas.dias_max_seguidos": 5}')$q$, g));
  perform tests.falla(format($q$select aceptar_version(%L)$q$, gen_random_uuid()));
  perform tests.falla(format($q$select dano_responder(%L, true)$q$, (select id from danos_casos where grupo_id = g limit 1)));
  perform tests.falla(format($q$select * from balances_grupo(%L)$q$, g), 'solo_socios');
  perform tests.falla(format($q$select reporte_dashboard(%L, 2026)$q$, g), 'solo_socios');
  perform tests.falla(format($q$select * from reporte_salidas(%L)$q$, g), 'solo_socios');
  perform tests.falla(format($q$select plan_guardar(%L, null, %L, null, 'Plan', '', 30, null)$q$, g, act), 'solo_socios');
  perform tests.falla(format($q$select salida_socio_solicitar(%L)$q$, g), 'solo_socios');
  perform tests.falla(format($q$select disputa_abrir(%L, 'Algo', null, null, 'x')$q$, g), 'solo_socios');
  perform tests.igual((select count(*)::int from libro_mayor), 0, 'no ve el libro mayor');
  perform tests.igual((select count(*)::int from pagos), 0, 'ni pagos');
  -- sí registra lecturas, combustible, facturas y reparaciones
  perform tarea_crear(g, act, 'Reparar defensa', null, current_date + 5, null, 'Taller');
end $$;
