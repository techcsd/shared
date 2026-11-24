-- Finanzas: libro mayor, INVARIANTES de dinero, validación de facturas, pagos, daños, fee, combustible, multi-moneda, fondo.
-- Invariante: suma de balances de miembros + saldo del fondo = 0 por moneda (y con «externo»: la suma de TODAS las cuentas = 0).
create function tests.bal(p_miembro uuid) returns numeric language sql as $$
  select coalesce(sum(haber - debe), 0) from libro_mayor where cuenta_tipo = 'miembro' and miembro_id = p_miembro
$$;
create function tests.bal_fondo(p_grupo uuid) returns numeric language sql as $$
  select coalesce(sum(haber - debe), 0) from libro_mayor where grupo_id = p_grupo and cuenta_tipo = 'fondo'
$$;
create function tests.bal_externo(p_grupo uuid) returns numeric language sql as $$
  select coalesce(sum(haber - debe), 0) from libro_mayor where grupo_id = p_grupo and cuenta_tipo = 'externo'
$$;
-- Σ miembros + fondo por moneda; debe ser 0 si no hay «externo»
create function tests.invariante(p_grupo uuid, p_msg text) returns void language plpgsql as $$
declare x record;
begin
  for x in select moneda, sum(haber - debe) as total from libro_mayor
            where grupo_id = p_grupo and cuenta_tipo in ('miembro', 'fondo') group by moneda loop
    if x.total <> -tests.bal_externo(p_grupo) then
      raise exception 'INVARIANTE ROTO % [%]: miembros+fondo=% , externo=%', p_msg, x.moneda, x.total, tests.bal_externo(p_grupo);
    end if;
  end loop;
  -- cada asiento cuadra
  if exists (select 1 from libro_mayor where grupo_id = p_grupo group by asiento_id having sum(debe) <> sum(haber)) then
    raise exception 'INVARIANTE ROTO % : hay un asiento descuadrado', p_msg;
  end if;
end $$;

create function tests.descuadre(p_grupo uuid) returns void language plpgsql as $f$
begin
  insert into libro_mayor (grupo_id, asiento_id, cuenta_tipo, debe, moneda, origen_tipo, origen_id)
  values (p_grupo, gen_random_uuid(), 'fondo', 10, 'DOP', 'aporte', gen_random_uuid());
  set constraints all immediate;
end $f$;

do $$
declare
  a uuid; b uuid; adm uuid; ext uuid; g uuid; t text; bote uuid; act uuid; dest uuid; ma uuid; mb uuid; madm uuid;
  r1 uuid; r2 uuid; r3 uuid; gs uuid; gs2 uuid; pg uuid; d0 timestamptz := date_trunc('hour', now()) + interval '40 days';
  n int; v_res record; caso uuid; cargo numeric; tard boolean;
begin
  a := tests.crear_usuario('fi_a@test.local', 'Ana');
  b := tests.crear_usuario('fi_b@test.local', 'Beto');
  adm := tests.crear_usuario('fi_adm@test.local', 'Operativo');
  ext := tests.crear_usuario('fi_ext@test.local', 'Externo');

  perform tests.como(a);
  g := crear_grupo('Grupo FI', 'DOP', 'America/Santo_Domingo', 'FIN', 50);
  t := invitar_miembro(g, 'fi_b@test.local', 'socio', 50);
  perform tests.como(b); perform aceptar_invitacion(t);
  perform tests.como(a);
  t := invitar_miembro(g, 'fi_adm@test.local', 'admin_operativo', 0);
  perform tests.como(adm); perform aceptar_invitacion(t);
  perform tests.como(ext); perform crear_grupo('Otro FI', 'DOP', 'America/Santo_Domingo', 'OTF', 100);

  perform tests.como(a);
  select id into bote from tipos_activo where clave = 'bote' and es_sistema;
  act := crear_activo(g, bote, 'Bote FI', 15);
  update activos set estado = 'activo' where id = act;
  insert into destinos (grupo_id, nombre) values (g, 'Playa') returning id into dest;
  insert into tarifas (grupo_id, destino_id, tipo, monto, moneda) values (g, dest, 'fee_destino', 5000, 'DOP');
  select id into ma from miembros where grupo_id = g and usuario_id = a;
  select id into mb from miembros where grupo_id = g and usuario_id = b;
  select id into madm from miembros where grupo_id = g and usuario_id = adm;
  r1 := reserva_crear_borrador(act, d0, d0 + interval '6 hours', 'invitado', dest, 6, null, 'Pedro Invitado', 'pedro@test.local');
  perform reserva_confirmar(r1);

  -- ============ (b) gasto común de 100 pagado por A, 50/50 → A +50, B −50
  gs := gasto_registrar(g, 'comun', 'mantenimiento', 100, 'DOP', 'miembro', null, 'Taller Mar');
  perform tests.admin();
  perform tests.igual(tests.bal(ma), 50::numeric, '(b) A queda en +50');
  perform tests.igual(tests.bal(mb), -50::numeric, '(b) B queda en −50');
  perform tests.invariante(g, 'tras gasto común');

  -- ============ (c) individual: a quien reservó (A), aunque el uso sea de un invitado
  perform tests.como(b);
  gs2 := gasto_registrar(g, 'individual', 'hielo', 300, 'DOP', 'miembro', null, 'Hielera', null, r1);   -- B lo pagó para la salida de A
  perform tests.admin();
  perform tests.igual(tests.bal(ma), 50::numeric - 300, '(c) el individual lo debe A (quien reservó), no B');
  perform tests.igual(tests.bal(mb), -50::numeric + 300, '(c) B, que lo pagó, recupera 300');
  perform tests.invariante(g, 'tras gasto individual');

  -- categoría inválida y monto inválido
  perform tests.como(a);
  perform tests.falla(format($q$select gasto_registrar(%L, 'comun', 'inventada', 10, 'DOP')$q$, g), 'categoria_invalida');
  perform tests.falla(format($q$select gasto_registrar(%L, 'comun', 'otros', 0, 'DOP')$q$, g), 'monto_invalido');
  perform tests.falla(format($q$select gasto_registrar(%L, 'dano', 'otros', 10, 'DOP')$q$, g), 'alcance_invalido');
  perform tests.falla(format($q$select gasto_registrar(%L, 'individual', 'hielo', 10, 'DOP')$q$, g), 'reserva_invalida');   -- sin reserva

  -- ============ DF-12: validación de facturas
  perform tests.como(a);
  perform tests.falla(format($q$select gasto_validar(%L)$q$, gs), 'otro_socio');                       -- no valida lo que cargó
  perform tests.como(adm);
  gs := gasto_registrar(g, 'comun', 'reparacion', 200, 'DOP');                                          -- el admin operativo carga
  perform tests.falla(format($q$select gasto_validar(%L)$q$, gs), 'solo_socios');                       -- y NUNCA valida
  perform tests.como(b);
  perform gasto_validar(gs);
  perform tests.admin();
  perform tests.igual((select estado from gastos where id = gs), 'validado', 'otro socio validó');
  perform tests.invariante(g, 'tras cargar el admin operativo');
  -- el admin operativo: crédito a él (adelantó 200), débitos 50/50
  perform tests.igual(tests.bal(madm), 200::numeric, 'el admin operativo adelantó 200');

  -- provisional vs confirmado en el balance (SA: sin validar se ve y se suma como provisional)
  perform tests.como(a);
  select * into v_res from balances_grupo(g) where miembro_id = ma;
  perform tests.igual(v_res.provisional <> 0, true, 'hay montos provisionales sin validar');
  perform tests.igual(v_res.balance, v_res.confirmado + v_res.provisional, 'balance = confirmado + provisional');

  -- disputa y anulación (asiento inverso, nada se borra)
  perform tests.como(b);
  gs := gasto_registrar(g, 'comun', 'seguro', 500, 'DOP');
  perform tests.como(a);
  perform gasto_disputar(gs, 'No reconozco este seguro');
  perform tests.admin();
  perform tests.igual((select estado from gastos where id = gs), 'disputado', 'disputado');
  perform tests.como(a);
  perform tests.falla(format($q$select gasto_anular(%L, '')$q$, gs), 'motivo_requerido');
  perform gasto_anular(gs, 'Era un duplicado');
  perform tests.admin();
  perform tests.igual((select estado from gastos where id = gs), 'anulado', 'anulado');
  perform tests.igual((select coalesce(sum(haber - debe), 0) from libro_mayor where origen_id = gs and cuenta_tipo = 'miembro'), 0::numeric, 'el gasto anulado neto = 0');
  perform tests.invariante(g, 'tras anular');
  perform tests.igual((select count(*)::int from libro_mayor where origen_id = gs) >= 4, true, 'las líneas originales se conservan');

  -- ============ (d) pagos: sin confirmar no reduce la deuda; solo confirma el receptor
  perform tests.admin();
  n := (select count(*)::int from libro_mayor where origen_tipo = 'pago');
  perform tests.como(a);                                   -- A debe 250 neto a B; paga 250
  pg := pago_registrar(g, mb, 250, 'DOP', 'transferencia');
  perform tests.admin();
  perform tests.igual((select count(*)::int from libro_mayor where origen_tipo = 'pago'), n, '(d) un pago sin confirmar NO toca los balances');
  perform tests.como(a);
  perform tests.falla(format($q$select pago_confirmar(%L)$q$, pg), 'solo_el_receptor');              -- el que paga no confirma
  perform tests.como(b);
  perform pago_confirmar(pg);
  perform tests.admin();
  perform tests.igual((select count(*)::int from libro_mayor where origen_tipo = 'pago'), n + 2, '(d) confirmado: asiento doble');
  perform tests.invariante(g, 'tras pago confirmado');
  perform tests.como(b);
  perform tests.falla(format($q$select pago_confirmar(%L)$q$, pg), 'estado_invalido');
  -- rechazo no mueve balances
  perform tests.como(a);
  pg := pago_registrar(g, mb, 10, 'DOP');
  perform tests.como(b);
  perform pago_rechazar(pg, 'no llegó');
  perform tests.admin();
  perform tests.igual((select estado from pagos where id = pg), 'rechazado', 'rechazado');
  perform tests.invariante(g, 'tras pago rechazado');

  -- ============ daños: nunca cargan hasta que TODOS acuerdan (DF-11)
  perform tests.como(b);
  caso := dano_abrir(g, 'Rayón en el casco', 'Se rayó al atracar', r1);
  perform tests.admin();
  n := (select count(*)::int from libro_mayor);
  perform tests.como(a);
  perform dano_proponer(caso, 1000, 'DOP', 'miembro', ma, jsonb_build_array(
    jsonb_build_object('miembro_id', ma, 'monto', 200), jsonb_build_object('miembro_id', mb, 'monto', 800)));
  perform tests.admin();
  perform tests.igual((select count(*)::int from libro_mayor), n, 'con acuerdo incompleto NO hay cargos');
  perform tests.igual((select estado from danos_casos where id = caso), 'en_revision', 'sigue en revisión');
  perform tests.como(a);
  perform tests.falla(format($q$select dano_proponer(%L, 1000, 'DOP', 'miembro', %L, %L::jsonb)$q$, caso, ma,
    jsonb_build_array(jsonb_build_object('miembro_id', ma, 'monto', 100))), 'propuesta_descuadrada');
  perform tests.como(b);
  perform dano_responder(caso, true, 'De acuerdo');
  perform tests.admin();
  perform tests.igual((select estado from danos_casos where id = caso), 'acordado', 'todos aceptaron: acordado');
  perform tests.igual((select count(*)::int from libro_mayor where origen_tipo = 'dano' and cuenta_tipo = 'miembro' and debe > 0), 2, 'cargos según lo acordado');
  perform tests.invariante(g, 'tras acuerdo de daño');
  -- un rechazo frena todo
  perform tests.como(b);
  caso := dano_abrir(g, 'Defensa rota', null, r1);
  perform tests.como(a);
  perform dano_proponer(caso, 300, 'DOP', 'fondo', null, jsonb_build_array(jsonb_build_object('miembro_id', mb, 'monto', 300)));
  perform tests.como(b);
  perform dano_responder(caso, false, 'No me corresponde');
  perform tests.admin();
  perform tests.igual((select estado from danos_casos where id = caso), 'rechazado', 'rechazado, sin cargos');
  perform tests.igual((select count(*)::int from libro_mayor where origen_id = caso), 0, 'ninguna línea');
  -- el admin operativo no decide acuerdos
  perform tests.como(adm);
  perform tests.falla(format($q$select dano_responder(%L, true)$q$, caso), 'solo_socios');
  perform tests.falla(format($q$select pago_registrar(%L, null, 10, 'DOP')$q$, g), 'solo_socios');

  -- ============ RLS de finanzas: solo socios; el admin operativo ve solo lo que cargó; extraños nada
  perform tests.como(ext);
  perform tests.igual((select count(*)::int from gastos), 0, 'extraño: sin gastos');
  perform tests.igual((select count(*)::int from libro_mayor), 0, 'extraño: sin libro');
  perform tests.falla(format($q$select * from balances_grupo(%L)$q$, g), 'solo_socios');
  perform tests.como(adm);
  perform tests.igual((select count(*)::int from gastos where cargado_por <> madm), 0, 'el admin operativo solo ve lo que cargó');
  perform tests.igual((select count(*)::int from gastos) >= 1, true, 'y sí ve lo suyo');
  perform tests.falla(format($q$select * from balances_grupo(%L)$q$, g), 'solo_socios');
  perform tests.falla(format($q$insert into libro_mayor (grupo_id, asiento_id, cuenta_tipo, debe, moneda, origen_tipo, origen_id) values (%L, gen_random_uuid(), 'fondo', 1, 'DOP', 'pago', gen_random_uuid())$q$, g), 'permission');
  perform tests.como(a);
  perform tests.falla(format($q$update libro_mayor set debe = 0 where grupo_id = %L$q$, g), 'permission');

  -- ============ asiento descuadrado: lo rechaza la base al cerrar la transacción
  perform tests.admin();
  perform tests.falla(format($q$select tests.descuadre(%L)$q$, g), 'asiento_descuadrado');
  perform tests.falla(format($q$update libro_mayor set debe = debe where grupo_id = %L$q$, g), 'solo_adicion');
  perform tests.falla(format($q$delete from libro_mayor where grupo_id = %L$q$, g), 'solo_adicion');
  perform tests.invariante(g, 'tras intentos de alterar el libro');

  -- ============ estado de cuenta: saldo acumulado y comprobantes
  perform tests.como(a);
  select count(*)::int into n from estado_cuenta(ma);
  perform tests.igual(n > 0, true, 'el estado de cuenta lista movimientos');
  perform tests.igual((select saldo from estado_cuenta(ma) order by id desc limit 1), (select coalesce(sum(haber - debe), 0) from estado_cuenta(ma)), 'saldo final = Σ(haber − debe)');
  perform tests.como(ext);
  perform tests.falla(format($q$select * from estado_cuenta(%L)$q$, ma), 'solo_socios');

  -- ============ fee: destino configurable (DF-07) y cargo de cancelación tardía (DF-09)
  perform tests.como(a);
  perform tests.admin();
  insert into grupo_politicas (grupo_id, clave, valor) values (g, 'tarifa.destino_fee_a', '"socios_proporcional"'::jsonb)
    on conflict (grupo_id, clave) do update set valor = excluded.valor;
  perform tests.como(a);
  cargo := 0;
  r2 := reserva_crear_borrador(act, date_trunc('hour', now()) + interval '30 hours', date_trunc('hour', now()) + interval '34 hours', 'personal', dest, 4, ma);
  perform reserva_confirmar(r2);
  perform tests.admin();
  insert into grupo_politicas (grupo_id, clave, valor) values (g, 'cancelacion.cargo_tardio_pct', '50'::jsonb)
    on conflict (grupo_id, clave) do update set valor = excluded.valor;
  perform tests.como(a);
  select * into v_res from reserva_cancelar(r2);
  perform tests.admin();
  perform tests.igual(v_res.cargo, 2500::numeric, 'cancelación tardía al 50 % del fee');
  perform tests.igual((select count(*)::int from libro_mayor where origen_tipo = 'cancelacion' and miembro_id = ma and debe = 2500), 1, 'cargo a quien canceló');
  perform tests.igual((select haber from libro_mayor where origen_tipo = 'cancelacion' and miembro_id = mb), 2500::numeric, 'socios_proporcional: lo recibe el otro socio');
  perform tests.invariante(g, 'tras cancelación tardía con fee a socios');

  -- ============ multi-moneda (DF-05): sin tasa se exige; con tasa se guarda moneda original + tasa
  perform tests.como(a);
  perform tests.falla(format($q$select gasto_registrar(%L, 'comun', 'otros', 10, 'USD')$q$, g), 'tasa_requerida');
  gs := gasto_registrar(g, 'comun', 'otros', 100, 'USD', 'miembro', null, 'Marina US', null, null, null, null, 60.5);
  perform tests.admin();
  perform tests.igual((select monto_grupo from gastos where id = gs), 6050::numeric, 'convertido a la moneda del grupo');
  perform tests.igual((select tasa from gastos where id = gs), 60.5::numeric, 'tasa guardada');
  perform tests.igual((select moneda from gastos where id = gs), 'USD'::bpchar, 'moneda original guardada');
  perform tests.igual((select count(*)::int from libro_mayor where origen_id = gs and moneda_original = 'USD' and tasa = 60.5), 3, 'cada línea guarda moneda original y tasa');
  perform tests.invariante(g, 'tras gasto en USD');
  -- con tasa del día registrada, no hace falta indicarla
  insert into tasas_cambio (grupo_id, fecha, de, a, tasa) values (g, current_date, 'EUR', 'DOP', 65);
  perform tests.como(a);
  gs := gasto_registrar(g, 'comun', 'otros', 10, 'EUR');
  perform tests.admin();
  perform tests.igual((select monto_grupo from gastos where id = gs), 650::numeric, 'usa la tasa del día');

  -- ============ combustible «incluido en el fee»: lo absorbe el fondo (DF-08)
  insert into grupo_politicas (grupo_id, clave, valor) values (g, 'combustible.modelo', '"incluido"'::jsonb)
    on conflict (grupo_id, clave) do update set valor = excluded.valor;
  perform tests.como(a);
  gs := gasto_registrar(g, 'individual', 'combustible', 400, 'DOP', 'miembro', null, 'Gasolinera', null, r1);
  perform tests.admin();
  perform tests.igual((select debe from libro_mayor where origen_id = gs and cuenta_tipo = 'fondo'), 400::numeric, 'el fondo asume el combustible');
  perform tests.igual((select count(*)::int from libro_mayor where origen_id = gs and cuenta_tipo = 'miembro' and debe > 0), 0, 'nadie más lo debe');
  perform tests.invariante(g, 'tras combustible incluido');

  -- ============ fondo: aporte mensual configurable, apagado por defecto (DF-24)
  perform tests.igual(fondo_aportes_automaticos(), 0, 'el aporte mensual está apagado (0)');
  insert into grupo_politicas (grupo_id, clave, valor) values (g, 'fondo.aporte_mensual', '1000'::jsonb)
    on conflict (grupo_id, clave) do update set valor = excluded.valor;
  perform tests.igual(fondo_aportes_automaticos(), 2, 'con aporte 1000 se generan 2 (uno por socio)');
  perform tests.igual(fondo_aportes_automaticos(), 0, 'idempotente por mes');
  perform tests.igual((select sum(monto) from fondo_aportes where grupo_id = g), 1000::numeric, 'el aporte se reparte por porcentaje');
  perform tests.invariante(g, 'tras aportes');

  -- ============ modo registro: nada bloquea (ni reservar con deuda)
  perform tests.igual(finanzas_modo(g), 'registro', 'modo registro por defecto');
  perform tests.como(a);
  r3 := reserva_crear_borrador(act, d0 + interval '9 days', d0 + interval '9 days 4 hours', 'personal', dest, 4, ma);
  perform reserva_confirmar(r3);
  perform tests.igual(tests.bal(ma) is not null, true, 'reservar con deuda pendiente funciona');
end $$;

-- ============ (e) redondeo y N socios: el centavo sobrante es determinista y la suma siempre cuadra
do $$
declare
  u uuid[] := '{}'; g uuid; t text; i int; miembros uuid[] := '{}'; ids uuid[]; gs uuid; s numeric; x numeric; m uuid;
  r record; esperado text; obtenido text;
begin
  perform tests.admin();
  -- 3 socios 33,33 / 33,33 / 33,34 y un gasto de 100,01
  for i in 1..3 loop u := u || tests.crear_usuario('rd' || i || '@test.local', 'R' || i); end loop;
  perform tests.como(u[1]);
  g := crear_grupo('Grupo Redondeo', 'DOP', 'America/Santo_Domingo', 'RDD', 33.33);
  t := invitar_miembro(g, 'rd2@test.local', 'socio', 33.33); perform tests.como(u[2]); perform aceptar_invitacion(t);
  perform tests.como(u[1]);
  t := invitar_miembro(g, 'rd3@test.local', 'socio', 33.34); perform tests.como(u[3]); perform aceptar_invitacion(t);
  perform tests.como(u[1]);
  gs := gasto_registrar(g, 'comun', 'otros', 100.01, 'DOP');
  perform tests.admin();
  select sum(debe) into s from libro_mayor where origen_id = gs and cuenta_tipo = 'miembro';
  perform tests.igual(s, 100.01::numeric, '(e) los débitos suman exactamente el gasto');
  perform tests.igual((select count(distinct debe)::int from libro_mayor where origen_id = gs and debe > 0) <= 2, true, '(e) solo difiere en 1 centavo');
  perform tests.invariante(g, '(e) 3 socios');
  -- determinismo: repetir con el mismo monto da el mismo reparto por miembro
  perform tests.como(u[1]);
  gs := gasto_registrar(g, 'comun', 'otros', 100.01, 'DOP');
  perform tests.admin();
  select string_agg(miembro_id::text || ':' || debe::text, ',' order by miembro_id) into obtenido from libro_mayor where origen_id = gs and debe > 0;
  select string_agg(miembro_id::text || ':' || debe::text, ',' order by miembro_id) into esperado
    from libro_mayor where origen_id = (select id from gastos where grupo_id = g order by creado_en limit 1) and debe > 0;
  perform tests.igual(obtenido, esperado, '(e) el redondeo es determinista');

  -- 10 socios al 10 %: una tanda de montos «incómodos»; el invariante se mantiene
  u := '{}';
  for i in 1..10 loop u := u || tests.crear_usuario('d10_' || i || '@test.local', 'S' || i); end loop;
  perform tests.como(u[1]);
  g := crear_grupo('Grupo Diez', 'DOP', 'America/Santo_Domingo', 'DIE', 10);
  for i in 2..10 loop
    perform tests.como(u[1]);
    t := invitar_miembro(g, 'd10_' || i || '@test.local', 'socio', 10);
    perform tests.como(u[i]); perform aceptar_invitacion(t);
  end loop;
  perform tests.como(u[1]);
  foreach x in array array[0.01, 0.05, 1.00, 33.33, 99.99, 100.05, 12345.67, 0.09] loop
    gs := gasto_registrar(g, 'comun', 'otros', x, 'DOP');
    perform tests.admin();
    select sum(debe) into s from libro_mayor where origen_id = gs and cuenta_tipo = 'miembro';
    perform tests.igual(s, x, '(e) 10 socios: Σ débitos = gasto (' || x || ')');
    perform tests.como(u[1]);
  end loop;
  perform tests.admin();
  perform tests.invariante(g, '(a) 10 socios tras montos con redondeo');
  perform tests.igual(tests.bal_fondo(g), 0::numeric, '(a) el fondo sigue en 0 sin fees');
  select coalesce(sum(haber - debe), 0) into s from libro_mayor where grupo_id = g and cuenta_tipo = 'miembro';
  perform tests.igual(s, 0::numeric, '(a) Σ balances de los 10 socios = 0');
end $$;
