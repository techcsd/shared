-- Ciclo completo en un grupo de 10 socios al 10 %: reservar → check-in → gastos → check-out → liquidar → balances cuadran.
do $$
declare
  u uuid[] := '{}'; m uuid[] := '{}'; g uuid; t text; i int; bote uuid; act uuid; dest uuid; r uuid; j jsonb; lect jsonb; lfin jsonb; ck jsonb; ckr jsonb;
  d0 timestamptz := date_trunc('hour', now()) + interval '60 days'; s numeric; g1 uuid; g2 uuid; d1 numeric; total_socios numeric;
begin
  perform tests.admin();
  for i in 1..10 loop u := u || tests.crear_usuario('c10_' || i || '@test.local', 'C' || i); end loop;
  perform tests.como(u[1]);
  g := crear_grupo('Grupo Ciclo 10', 'DOP', 'America/Santo_Domingo', 'CIC', 10);
  for i in 2..10 loop
    perform tests.como(u[1]);
    t := invitar_miembro(g, 'c10_' || i || '@test.local', 'socio', 10);
    perform tests.como(u[i]); perform aceptar_invitacion(t);
  end loop;
  perform tests.admin();
  for i in 1..10 loop m := m || (select id from miembros where grupo_id = g and usuario_id = u[i]); end loop;

  perform tests.como(u[1]);
  select id into bote from tipos_activo where clave = 'bote' and es_sistema;
  act := crear_activo(g, bote, 'Bote Ciclo', 15);
  update activos set estado = 'activo' where id = act;
  insert into destinos (grupo_id, nombre) values (g, 'Cayo') returning id into dest;
  insert into tarifas (grupo_id, destino_id, tipo, monto, moneda) values (g, dest, 'fee_destino', 7000, 'DOP');

  perform capitan_guardar(g, null, 'Capitán Pedro', null, 'LIC-9', current_date + 100, 2, null);
  select jsonb_agg(jsonb_build_object('componente_id', id, 'valor', 10 * indice) order by indice) into lect from activo_componentes where activo_id = act;
  select jsonb_agg(jsonb_build_object('componente_id', id, 'valor', 10 * indice + 4.5) order by indice) into lfin from activo_componentes where activo_id = act;
  ck := jsonb_build_array(
    jsonb_build_object('clave', 'extintor', 'cumple', true), jsonb_build_object('clave', 'botiquin', 'cumple', true),
    jsonb_build_object('clave', 'capitan_sobrio', 'cumple', true), jsonb_build_object('clave', 'chalecos', 'cumple', true),
    jsonb_build_object('clave', 'menores', 'cumple', true), jsonb_build_object('clave', 'clima', 'cumple', true));
  ckr := jsonb_build_array(
    jsonb_build_object('clave', 'limpio', 'cumple', true), jsonb_build_object('clave', 'revisado', 'cumple', true),
    jsonb_build_object('clave', 'combustible', 'cumple', true));

  -- reservar (socio 1) con un invitado: el uso individual sigue siendo del socio 1
  r := reserva_crear_borrador(act, d0, d0 + interval '5 hours', 'invitado', dest, 7, null, 'Invitado Diez', 'inv10@test.local');
  perform reserva_confirmar(r);
  j := checkin_registrar(r, null, 'Capitán Pedro', dest, 80, lect, ck);
  perform tests.igual((j ->> 'ok')::boolean, true, 'check-in en grupo de 10');

  -- gastos del viaje: un individual pagado por el socio 2 y un común pagado por el socio 3
  perform tests.como(u[2]);
  g1 := gasto_registrar(g, 'individual', 'hielo', 1234.56, 'DOP', 'miembro', null, 'Hielera', null, r);
  perform tests.como(u[3]);
  g2 := gasto_registrar(g, 'comun', 'mantenimiento', 999.99, 'DOP');

  perform tests.como(u[1]);
  j := checkout_registrar(r, lfin, 30, 0, ckr, '[]'::jsonb);
  perform tests.igual((j ->> 'cerrada')::boolean, true, 'check-out cierra y liquida');

  perform tests.admin();
  perform tests.invariante(g, 'ciclo de 10 socios');
  select coalesce(sum(haber - debe), 0) into total_socios from libro_mayor where grupo_id = g and cuenta_tipo = 'miembro';
  perform tests.igual(total_socios, -7000::numeric, 'Σ socios = −fee (el fondo tiene +fee)');
  perform tests.igual(tests.bal_fondo(g), 7000::numeric, 'el fee entra al fondo');
  -- cuenta a mano del socio 1: −7000 (fee) −1234.56 (individual) − su parte del común (99,99 ó 100,00)
  d1 := tests.bal(m[1]) + 7000 + 1234.56;
  perform tests.igual(d1 in (-99.99, -100.00), true, 'socio 1: parte del común = 99,99 ó 100,00 (obtenido ' || d1 || ')');
  -- socio 2 adelantó el individual del socio 1: +1234.56 − su parte del común
  perform tests.igual(tests.bal(m[2]) - 1234.56 in (-99.99, -100.00), true, 'socio 2 recupera su adelanto');
  -- socio 3 adelantó el común: +999.99 − su parte
  perform tests.igual(tests.bal(m[3]) - 999.99 in (-99.99, -100.00), true, 'socio 3 recupera su adelanto');
  -- los otros 7 solo deben su parte del común
  select sum(tests.bal(m[k.n])) into s from generate_series(4, 10) as k(n);
  perform tests.igual(s <= -699.93 and s >= -700.00, true, 'los otros 7 solo deben su parte del común');
  -- las horas por componente salen de final − inicial
  perform tests.igual((select (resumen -> 'horas_por_componente' -> 0 ->> 'horas')::numeric from liquidaciones where reserva_id = r), 4.5::numeric, 'horas = 4,5');
  perform tests.igual((select (resumen ->> 'combustible_consumido')::numeric from liquidaciones where reserva_id = r), 50::numeric, 'consumido = 80 + 0 − 30');
end $$;
