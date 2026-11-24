-- Operación: check-in, lecturas por componente, checklists, check-out, cierre con datos completos, correcciones y permisos.
do $$
declare
  a uuid; b uuid; adm uuid; ext uuid; g uuid; t text; bote uuid; act uuid; dest uuid;
  r1 uuid; r2 uuid; j jsonb; lect jsonb; lect_fin jsonb; ck jsonb; ck_reg jsonb; op uuid; n int;
  d0 timestamptz := date_trunc('hour', now()) + interval '20 days'; c1 uuid; ma uuid; mb uuid;
  v_fee numeric;
begin
  a := tests.crear_usuario('op_a@test.local', 'Ana');
  b := tests.crear_usuario('op_b@test.local', 'Beto');
  adm := tests.crear_usuario('op_adm@test.local', 'Operativo');
  ext := tests.crear_usuario('op_ext@test.local', 'Externo');

  perform tests.como(a);
  g := crear_grupo('Grupo OP', 'DOP', 'America/Santo_Domingo', 'OPP', 50);
  t := invitar_miembro(g, 'op_b@test.local', 'socio', 50);
  perform tests.como(b); perform aceptar_invitacion(t);
  perform tests.como(a);
  t := invitar_miembro(g, 'op_adm@test.local', 'admin_operativo', 0);
  perform tests.como(adm); perform aceptar_invitacion(t);
  perform tests.como(ext); perform crear_grupo('Otro OP', 'DOP', 'America/Santo_Domingo', 'OTX', 100);

  perform tests.como(a);
  select id into bote from tipos_activo where clave = 'bote' and es_sistema;
  act := crear_activo(g, bote, 'Bote OP', 15);
  update activos set estado = 'activo' where id = act;
  insert into destinos (grupo_id, nombre) values (g, 'Playa') returning id into dest;
  insert into tarifas (grupo_id, destino_id, tipo, monto, moneda) values (g, dest, 'fee_destino', 5000, 'DOP');
  select id into ma from miembros where grupo_id = g and usuario_id = a;
  select id into mb from miembros where grupo_id = g and usuario_id = b;

  perform tests.igual((select count(*)::int from activo_componentes where activo_id = act), 2, 'el bote tiene 2 motores');
  select jsonb_agg(jsonb_build_object('componente_id', id, 'valor', 100 + indice * 10) order by indice) into lect
    from activo_componentes where activo_id = act;
  select jsonb_agg(jsonb_build_object('componente_id', id, 'valor', 105 + indice * 10) order by indice) into lect_fin
    from activo_componentes where activo_id = act;
  ck := jsonb_build_array(
    jsonb_build_object('clave', 'extintor', 'cumple', true), jsonb_build_object('clave', 'botiquin', 'cumple', true),
    jsonb_build_object('clave', 'capitan_sobrio', 'cumple', true), jsonb_build_object('clave', 'chalecos', 'cumple', true),
    jsonb_build_object('clave', 'menores', 'cumple', true), jsonb_build_object('clave', 'clima', 'cumple', true));
  ck_reg := jsonb_build_array(
    jsonb_build_object('clave', 'limpio', 'cumple', true), jsonb_build_object('clave', 'revisado', 'cumple', true),
    jsonb_build_object('clave', 'combustible', 'cumple', true));

  r1 := reserva_crear_borrador(act, d0, d0 + interval '6 hours', 'personal', dest, 8);
  perform reserva_confirmar(r1);

  -- ============ check-in: dice QUÉ falta y no escribe nada
  perform tests.como(a);
  j := checkin_registrar(r1, null, null, dest, null, '[]'::jsonb, '[]'::jsonb);
  perform tests.igual((j ->> 'ok')::boolean, false, 'sin datos no hay check-in');
  perform tests.igual((select count(*)::int from jsonb_array_elements(j -> 'faltan') f where f ->> 'codigo' = 'lectura_inicial'), 2, 'falta la lectura de CADA motor');
  perform tests.igual((select count(*)::int from jsonb_array_elements(j -> 'faltan') f where f ->> 'codigo' = 'capitan'), 1, 'falta capitán');
  perform tests.igual((select count(*)::int from jsonb_array_elements(j -> 'faltan') f where f ->> 'codigo' = 'combustible_inicial'), 1, 'falta combustible inicial');
  perform tests.igual((select count(*)::int from jsonb_array_elements(j -> 'faltan') f where f ->> 'codigo' = 'checklist'), 6, 'faltan los 6 ítems obligatorios (bengalas es opcional)');
  perform tests.admin();
  perform tests.igual((select count(*)::int from operaciones where reserva_id = r1), 0, 'no se escribió nada');
  perform tests.igual((select estado from reservas where id = r1), 'confirmada'::estado_reserva, 'sigue confirmada');

  -- una lectura inicial que va solo para un motor sigue faltando el otro; el negativo se rechaza
  perform tests.como(a);
  perform tests.falla(format($q$select checkin_registrar(%L, %L, null, %L, 50, %L::jsonb, %L::jsonb)$q$,
    r1, ma, dest, jsonb_build_array(jsonb_build_object('componente_id', (lect -> 0 ->> 'componente_id'), 'valor', -1)), ck), 'valor_negativo');
  -- un checklist de seguridad incumplido bloquea la salida
  j := checkin_registrar(r1, ma, null, dest, 50, lect,
    (select jsonb_agg(case when e ->> 'clave' = 'chalecos' then jsonb_build_object('clave', 'chalecos', 'cumple', false) else e end) from jsonb_array_elements(ck) e));
  perform tests.igual((j ->> 'ok')::boolean, false, 'sin chalecos no se sale');
  perform tests.igual((select count(*)::int from jsonb_array_elements(j -> 'faltan') f where f ->> 'codigo' = 'checklist_no_cumple'), 1, 'incumplimiento listado');

  -- permisos: el otro socio y un extraño no operan la salida de Ana
  perform tests.como(b);
  perform tests.falla(format($q$select checkin_registrar(%L, %L, null, %L, 50, %L::jsonb, %L::jsonb)$q$, r1, ma, dest, lect, ck), 'sin_permiso');
  perform tests.como(ext);
  perform tests.falla(format($q$select checkin_registrar(%L, null, 'Capi', %L, 50, %L::jsonb, %L::jsonb)$q$, r1, dest, lect, ck), 'sin_permiso');

  -- check-in correcto: capitán externo por nombre
  perform tests.como(a);
  j := checkin_registrar(r1, null, 'Capitán Juan', dest, 50, lect, ck, 'salida de prueba');
  perform tests.igual((j ->> 'ok')::boolean, true, 'check-in correcto');
  op := (j ->> 'operacion_id')::uuid;
  perform tests.igual((select estado from reservas where id = r1), 'en_curso'::estado_reserva, 'la reserva pasa a en_curso');
  perform tests.igual((select count(*)::int from lecturas where operacion_id = op and momento = 'inicio'), 2, 'una lectura inicial por motor');
  perform tests.igual((select count(*)::int from checklist_vigente where operacion_id = op), 6, 'checklist guardado');
  perform tests.falla(format($q$select checkin_registrar(%L, null, 'Capi', %L, 50, %L::jsonb, %L::jsonb)$q$, r1, dest, lect, ck), 'transicion_invalida');

  -- ============ check-out: parcial → lista de faltantes; la orden NO se cierra
  j := checkout_registrar(r1, '[]'::jsonb, null, null, '[]'::jsonb, '[]'::jsonb);
  perform tests.igual((j ->> 'cerrada')::boolean, false, 'sin datos no se cierra');
  perform tests.igual((select count(*)::int from jsonb_array_elements(j -> 'faltan') f where f ->> 'codigo' = 'lectura_final'), 2, 'faltan 2 lecturas finales');
  perform tests.igual((select count(*)::int from jsonb_array_elements(j -> 'faltan') f where f ->> 'codigo' = 'combustible_final'), 1, 'falta combustible final');
  perform tests.igual((select count(*)::int from jsonb_array_elements(j -> 'faltan') f where f ->> 'codigo' = 'checklist'), 3, 'faltan los 3 ítems de entrega');
  perform tests.igual((select estado from reservas where id = r1), 'en_curso'::estado_reserva, 'sigue en curso');
  -- valores inválidos: final menor que inicial, negativo, combustible imposible
  perform tests.falla(format($q$select checkout_registrar(%L, %L::jsonb, 10, null, '[]'::jsonb, '[]'::jsonb)$q$, r1,
    jsonb_build_array(jsonb_build_object('componente_id', lect -> 0 ->> 'componente_id', 'valor', 50))), 'lectura_final_menor');
  perform tests.falla(format($q$select checkout_registrar(%L, %L::jsonb, 10, null, '[]'::jsonb, '[]'::jsonb)$q$, r1,
    jsonb_build_array(jsonb_build_object('componente_id', lect -> 0 ->> 'componente_id', 'valor', -3))), 'valor_negativo');
  perform tests.falla(format($q$select checkout_registrar(%L, %L::jsonb, 80, 0, %L::jsonb, '[]'::jsonb)$q$, r1, lect_fin, ck_reg), 'combustible_inconsistente');
  perform tests.falla(format($q$select checkout_registrar(%L, '[]'::jsonb, -1, null, '[]'::jsonb, '[]'::jsonb)$q$, r1), 'valor_negativo');
  -- el estado quedó intacto tras los rechazos
  perform tests.igual((select estado from reservas where id = r1), 'en_curso'::estado_reserva, 'los rechazos no cerraron la orden');
  -- un checklist de regreso incumplido exige explicación
  perform tests.falla(format($q$select checkout_registrar(%L, '[]'::jsonb, null, null, %L::jsonb, '[]'::jsonb)$q$, r1,
    jsonb_build_array(jsonb_build_object('clave', 'limpio', 'cumple', false))), 'nota_requerida');

  -- cierre completo
  j := checkout_registrar(r1, lect_fin, 30, 5, ck_reg,
    jsonb_build_array(jsonb_build_object('tipo', 'observacion', 'descripcion', 'Todo bien')), 'regreso de prueba');
  perform tests.igual((j ->> 'cerrada')::boolean, true, 'con datos completos se cierra');
  perform tests.igual((select estado from reservas where id = r1), 'finalizada'::estado_reserva, 'finalizada');
  perform tests.igual((select cantidad from combustible_registros where operacion_id = op and tipo = 'consumido'), 25::numeric, 'consumido = inicial + agregado − final');
  perform tests.igual(((j -> 'resumen' -> 'horas_por_componente' -> 0 ->> 'horas'))::numeric, 5::numeric, 'horas = final − inicial');
  perform tests.igual((select count(*)::int from liquidaciones where operacion_id = op), 1, 'liquidada');
  perform tests.igual((select fee_monto from liquidaciones where operacion_id = op), 5000::numeric, 'fee liquidado');
  -- liquidar dos veces no duplica
  perform tests.admin();
  perform liquidar_operacion(op);
  perform tests.igual((select count(*)::int from libro_mayor where origen_tipo = 'fee'), 2, 'el fee asienta una sola vez (débito socio + crédito fondo)');
  perform tests.igual((select debe from libro_mayor where origen_tipo = 'fee' and miembro_id = ma), 5000::numeric, 'el fee se carga a quien reservó');
  perform tests.igual((select haber from libro_mayor where origen_tipo = 'fee' and cuenta_tipo = 'fondo'), 5000::numeric, 'y entra al fondo común');

  -- ============ correcciones: nunca se edita; fila nueva con motivo, la anterior queda
  perform tests.como(a);
  perform tests.falla(format($q$select lectura_corregir(%L, %L, 'fin', 120, '')$q$, op, lect -> 0 ->> 'componente_id'), 'motivo_requerido');
  perform tests.falla(format($q$select lectura_corregir(%L, %L, 'fin', 1, 'error de digitación')$q$, op, lect -> 0 ->> 'componente_id'), 'lectura_final_menor');
  perform lectura_corregir(op, (lect -> 0 ->> 'componente_id')::uuid, 'fin', 120, 'error de digitación');
  perform tests.igual((select valor from lecturas_vigentes where operacion_id = op and componente_id = (lect -> 0 ->> 'componente_id')::uuid and momento = 'fin'), 120::numeric, 'la corrección es la vigente');
  perform tests.admin();
  perform tests.igual((select count(*)::int from lecturas where operacion_id = op and componente_id = (lect -> 0 ->> 'componente_id')::uuid and momento = 'fin'), 2, 'la lectura anterior se conserva');
  perform tests.falla(format($q$update lecturas set valor = 1 where operacion_id = %L$q$, op), 'solo_adicion');
  perform tests.igual((select count(*)::int from auditoria where tabla = 'lecturas' and motivo = 'error de digitación'), 1, 'la auditoría guarda el motivo');

  -- ============ continuidad: la siguiente salida no puede arrancar por debajo de la última lectura final
  perform tests.como(a);
  r2 := reserva_crear_borrador(act, d0 + interval '1 day', d0 + interval '1 day 4 hours', 'familiar', dest, 6);
  perform reserva_confirmar(r2);
  perform tests.falla(format($q$select checkin_registrar(%L, %L, null, %L, 40, %L::jsonb, %L::jsonb)$q$, r2, ma, dest, lect, ck), 'lectura_menor_que_la_ultima');

  -- ============ permisos de lectura (RLS)
  perform tests.como(ext);
  perform tests.igual((select count(*)::int from operaciones), 0, 'un extraño no ve operaciones');
  perform tests.igual((select count(*)::int from lecturas), 0, 'ni lecturas');
  perform tests.como(adm);
  perform tests.igual((select count(*)::int from operaciones where grupo_id = g), 1, 'el admin operativo ve la operación');
  perform tests.igual((select count(*)::int from libro_mayor), 0, 'pero no el libro mayor');
  perform tests.igual((select count(*)::int from liquidaciones), 0, 'ni liquidaciones');
  perform tests.como(b);
  perform tests.igual((select count(*)::int from libro_mayor where grupo_id = g) > 0, true, 'el otro socio sí ve el libro mayor');
end $$;
