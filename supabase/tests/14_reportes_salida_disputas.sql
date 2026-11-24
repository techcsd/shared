-- Reportes (coinciden con el libro mayor), salida/venta de un socio y desacuerdos con mediador (solo lectura del caso).
do $$
declare
  a uuid; b uuid; adm uuid; g uuid; t text; bote uuid; act uuid; dest uuid; ma uuid; mb uuid; r1 uuid; j jsonb; lect jsonb; lfin jsonb; ck jsonb; ckr jsonb;
  d0 timestamptz := date_trunc('hour', now()) + interval '20 hours'; dash jsonb; v_fee numeric; v_costo numeric; v_sum numeric; n int;
begin
  perform tests.admin();
  a := tests.crear_usuario('rp_a@test.local', 'Ana');
  b := tests.crear_usuario('rp_b@test.local', 'Beto');
  adm := tests.crear_usuario('rp_adm@test.local', 'Operativo');
  perform tests.como(a);
  g := crear_grupo('Grupo RP', 'DOP', 'America/Santo_Domingo', 'RPP', 50);
  t := invitar_miembro(g, 'rp_b@test.local', 'socio', 50); perform tests.como(b); perform aceptar_invitacion(t);
  perform tests.como(a);
  t := invitar_miembro(g, 'rp_adm@test.local', 'admin_operativo', 0); perform tests.como(adm); perform aceptar_invitacion(t);
  perform tests.como(a);
  select id into bote from tipos_activo where clave = 'bote' and es_sistema;
  act := crear_activo(g, bote, 'Bote RP', 15);
  update activos set estado = 'activo' where id = act;
  insert into destinos (grupo_id, nombre) values (g, 'Cayo') returning id into dest;
  insert into tarifas (grupo_id, destino_id, tipo, monto, moneda) values (g, dest, 'fee_destino', 5000, 'DOP');
  select id into ma from miembros where grupo_id = g and usuario_id = a;
  select id into mb from miembros where grupo_id = g and usuario_id = b;
  perform capitan_guardar(g, null, 'Capitán RP', null, 'L1', current_date + 300, 5, null);
  select jsonb_agg(jsonb_build_object('componente_id', id, 'valor', 100 + indice) order by indice) into lect from activo_componentes where activo_id = act;
  select jsonb_agg(jsonb_build_object('componente_id', id, 'valor', 105 + indice) order by indice) into lfin from activo_componentes where activo_id = act;
  ck := jsonb_build_array(
    jsonb_build_object('clave', 'extintor', 'cumple', true), jsonb_build_object('clave', 'botiquin', 'cumple', true),
    jsonb_build_object('clave', 'capitan_sobrio', 'cumple', true), jsonb_build_object('clave', 'chalecos', 'cumple', true),
    jsonb_build_object('clave', 'menores', 'cumple', true), jsonb_build_object('clave', 'clima', 'cumple', true));
  ckr := jsonb_build_array(jsonb_build_object('clave', 'limpio', 'cumple', true), jsonb_build_object('clave', 'revisado', 'cumple', true), jsonb_build_object('clave', 'combustible', 'cumple', true));
  r1 := reserva_crear_borrador(act, d0, d0 + interval '5 hours', 'personal', dest, 6, ma);
  perform reserva_confirmar(r1);
  j := checkin_registrar(r1, null, 'Capitán RP', dest, 100, lect, ck);
  perform gasto_registrar(g, 'individual', 'hielo', 300, 'DOP', 'miembro', null, null, null, r1);
  j := checkout_registrar(r1, lfin, 70, 0, ckr, '[]'::jsonb);
  perform tests.igual((j ->> 'cerrada')::boolean, true, 'ciclo cerrado para el reporte');
  perform gasto_registrar(g, 'comun', 'mantenimiento', 800, 'DOP');

  -- ============ reportes: salen del mismo libro mayor
  perform tests.como(b);
  dash := reporte_dashboard(g, extract(year from now())::int);
  perform tests.admin();
  select coalesce(sum(case when origen_tipo = 'gasto_anulado' then -haber else debe end), 0) into v_costo
    from libro_mayor where grupo_id = g and cuenta_tipo = 'miembro' and origen_tipo <> 'pago';
  perform tests.igual((dash ->> 'costo_total')::numeric, v_costo, 'el total del dashboard = suma del libro mayor');
  select coalesce(sum((x ->> 'costo')::numeric), 0) into v_sum from jsonb_array_elements(dash -> 'por_miembro') x;
  perform tests.igual(v_sum, v_costo, 'Σ costo por socio = total del libro mayor');
  perform tests.igual((dash ->> 'fees')::numeric, 5000::numeric, 'fees del periodo');
  perform tests.igual((dash ->> 'salidas')::int, 1, 'una salida');
  perform tests.igual((dash -> 'horas_por_componente' -> 0 ->> 'horas')::numeric, 5::numeric, 'horas por motor = final − inicial');
  perform tests.igual((dash ->> 'combustible_consumido')::numeric, 30::numeric, 'combustible consumido 100 − 70');
  perform tests.igual(jsonb_array_length(dash -> 'por_mes') >= 1, true, 'tendencia mes a mes');
  -- el mismo reporte lo ven los dos socios: mismos números
  perform tests.como(a);
  perform tests.igual(reporte_dashboard(g, extract(year from now())::int), dash, 'los dos socios ven los mismos números');
  select sum(fee), count(*)::int into v_fee, n from reporte_salidas(g);
  perform tests.igual(v_fee, (dash ->> 'fees')::numeric, 'el reporte de salidas suma lo mismo que el dashboard');
  perform tests.igual(n, 1, 'una fila');
  perform tests.igual((select count(*)::int from reporte_salidas(g, null, null, mb)), 0, 'filtra por socio');
  perform tests.igual((select count(*)::int from reporte_salidas(g, null, null, ma, dest, 'personal', 'finalizada')), 1, 'filtra por socio, destino, tipo y estado');
  perform tests.igual((select count(*)::int from reporte_salidas(g, null, null, null, null, 'invitado')), 0, 'filtro por tipo de salida');
  -- los reportes no limitan nada: reservar sigue funcionando
  perform reserva_crear_borrador(act, d0 + interval '3 days', d0 + interval '3 days 2 hours', 'personal', dest, 3, ma);
  perform tests.como(adm);
  perform tests.falla(format($q$select reporte_dashboard(%L, 2026)$q$, g), 'solo_socios');

  -- ============ salida o venta de un socio (DF-25): los % se traspasan y siguen sumando 100
  declare c uuid; u3 uuid; m3 uuid; caso uuid; pg uuid;
  begin
    perform tests.admin();
    u3 := tests.crear_usuario('rp_c@test.local', 'Carla');
    perform tests.como(a);
    -- (en este grupo a=50, b=50): se vende la parte de a a b
    perform tests.falla(format($q$select salida_socio_ofertar(%L, 10, 100, 'DOP')$q$, gen_random_uuid()), 'caso_no_existe');
    caso := salida_socio_solicitar(g, 'Me retiro del negocio');
    perform tests.igual((select preferencia_hasta > now() + interval '29 days' from salida_socio_casos where id = caso), true, 'derecho de preferencia de 30 días');
    perform tests.falla(format($q$select salida_socio_ofertar(%L, 50, 1000, 'DOP')$q$, caso), 'solo_otros_socios');
    perform salida_socio_valorar(caso, 'Valoración del perito del 20/11: RD$ 4,000,000');
    perform tests.como(b);
    perform tests.falla(format($q$select salida_socio_ofertar(%L, 60, 1000, 'DOP')$q$, caso), 'oferta_excede');
    perform tests.falla(format($q$select salida_socio_responder(%L, true)$q$, caso), 'estado_invalido');
    perform salida_socio_ofertar(caso, 50, 2000000, 'DOP');
    perform tests.como(a);
    perform tests.falla(format($q$select salida_socio_cerrar(%L)$q$, caso), 'estado_invalido');   -- falta el acuerdo
    perform salida_socio_responder(caso, true);
    perform tests.como(b);
    perform salida_socio_responder(caso, true);
    perform tests.admin();
    perform tests.igual((select estado from salida_socio_casos where id = caso), 'aceptado', 'todos aceptaron');
    -- el saliente debe estar a mano con el grupo (la app no mueve dinero)
    perform tests.igual((select coalesce(sum(haber - debe), 0) from libro_mayor where miembro_id = ma) <> 0, true, 'a tiene saldo por liquidar');
    perform tests.como(a);
    perform tests.falla(format($q$select salida_socio_cerrar(%L)$q$, caso), 'saldo_pendiente');
    perform tests.admin();
    n := 0;
    select (select coalesce(sum(haber - debe), 0) from libro_mayor where miembro_id = ma) into v_sum;
    perform tests.como(a);
    if v_sum < 0 then
      pg := pago_registrar(g, mb, -v_sum, 'DOP', 'liquidación de salida');
      perform tests.como(b); perform pago_confirmar(pg);
    else
      pg := pago_registrar(g, mb, 1, 'DOP', 'x');   -- (no ocurre en este escenario)
    end if;
    perform tests.como(a);
    if v_sum > 0 then
      -- a es acreedor: b le paga y a confirma
      perform tests.como(b); pg := pago_registrar(g, ma, v_sum, 'DOP', 'liquidación de salida'); perform tests.como(a); perform pago_confirmar(pg);
    end if;
    perform tests.como(a);
    perform salida_socio_cerrar(caso);
    perform tests.admin();
    perform tests.igual((select porcentaje from miembros where id = mb), 100::numeric, 'b se queda con el 100 %');
    perform tests.igual((select porcentaje from miembros where id = ma), 0::numeric, 'a sale con 0 %');
    perform tests.igual((select estado::text from miembros where id = ma), 'salido', 'a queda como salido');
    perform tests.igual((select sum(porcentaje) from miembros where grupo_id = g and rol = 'socio' and estado = 'activo'), 100::numeric, 'los % siguen sumando 100');
    perform tests.igual((select count(*)::int from auditoria where tabla = 'miembros' and registro_id = ma::text and motivo like 'traspaso por salida%'), 1, 'auditoría del traspaso con motivo');
  end;
end $$;

-- ============ desacuerdos y mediador: solo lectura del caso; nada más del grupo
do $$
declare
  a uuid; b uuid; med uuid; ext uuid; g uuid; t text; dis uuid; tok text; n int; ma uuid;
begin
  perform tests.admin();
  a := tests.crear_usuario('ds_a@test.local', 'Ana');
  b := tests.crear_usuario('ds_b@test.local', 'Beto');
  med := tests.crear_usuario('ds_med@test.local', 'Mediador');
  ext := tests.crear_usuario('ds_ext@test.local', 'Otro');
  perform tests.como(a);
  g := crear_grupo('Grupo DS', 'DOP', 'America/Santo_Domingo', 'DSP', 50);
  t := invitar_miembro(g, 'ds_b@test.local', 'socio', 50); perform tests.como(b); perform aceptar_invitacion(t);
  perform tests.como(a);
  perform gasto_registrar(g, 'comun', 'otros', 100, 'DOP');
  dis := disputa_abrir(g, 'No reconozco esta factura', 'gasto', null, 'No estoy de acuerdo con el monto');
  perform tests.como(b);
  perform disputa_mensaje(dis, 'Fue lo que cobró el taller');
  perform tests.como(a);
  -- a los 7 días (DF-26), no antes
  perform tests.falla(format($q$select disputa_invitar_mediador(%L, 'ds_med@test.local')$q$, dis), 'mediador_aun_no');
  perform tests.admin();
  update disputas set creado_en = now() - interval '8 days' where id = dis;
  perform tests.como(a);
  tok := disputa_invitar_mediador(dis, 'ds_med@test.local');
  -- otro usuario no puede usar el token; el correo debe coincidir
  perform tests.como(ext);
  perform tests.falla(format($q$select disputa_aceptar_mediacion(%L)$q$, tok), 'invitacion_no_valida');
  perform tests.igual((select count(*)::int from disputas), 0, 'un extraño no ve la disputa');
  -- antes de aceptar, el mediador no ve nada
  perform tests.como(med);
  perform tests.igual((select count(*)::int from disputas), 0, 'sin aceptar no ve el caso');
  perform disputa_aceptar_mediacion(tok);
  perform tests.igual((select count(*)::int from disputas), 1, 'el mediador ve SU caso');
  perform tests.igual((select count(*)::int from disputa_mensajes), 3, 'y su hilo (2 mensajes + aviso)');
  -- ...y nada más del grupo
  perform tests.igual((select count(*)::int from gastos), 0, 'sin gastos');
  perform tests.igual((select count(*)::int from libro_mayor), 0, 'sin libro mayor');
  perform tests.igual((select count(*)::int from miembros where grupo_id = g), 0, 'sin ver a los socios');
  perform tests.igual((select count(*)::int from reservas where grupo_id = g), 0, 'sin reservas');
  perform tests.igual((select count(*)::int from operaciones), 0, 'sin operaciones');
  perform tests.igual((select count(*)::int from notificaciones where grupo_id = g), 0, 'sin notificaciones del grupo');
  perform tests.falla(format($q$select * from balances_grupo(%L)$q$, g), 'solo_socios');
  perform tests.falla(format($q$select reporte_dashboard(%L, 2026)$q$, g), 'solo_socios');
  perform tests.falla(format($q$select disputa_cerrar(%L, 'acuerdo')$q$, dis), 'solo_socios');
  perform tests.falla(format($q$select disputa_invitar_mediador(%L, 'otro@test.local')$q$, dis), 'solo_socios');
  perform tests.falla(format($q$insert into disputa_mensajes (grupo_id, disputa_id, rol, texto) values (%L, %L, 'mediador', 'directo')$q$, g, dis), 'permission');
  perform disputa_mensaje(dis, 'Propongo repartir el costo entre los dos');
  perform tests.como(a);
  perform tests.igual((select count(*)::int from disputa_mensajes where disputa_id = dis and rol = 'mediador'), 1, 'los socios ven el mensaje del mediador');
  perform disputa_cerrar(dis, 'acuerdo', 'Se repartió');
  -- al cerrarse el caso, el mediador pierde todo acceso
  perform tests.como(med);
  perform tests.igual((select count(*)::int from disputas), 0, 'cerrado: el mediador ya no ve el caso');
  perform tests.falla(format($q$select disputa_mensaje(%L, 'ya cerrado')$q$, dis), 'estado_invalido');
  perform tests.admin();
  perform tests.igual((select resultado from disputas where id = dis), 'acuerdo', 'el resultado queda registrado');
  perform tests.igual((select estado from disputa_mediadores where disputa_id = dis), 'finalizado', 'el mediador expira al cerrarse');
  perform tests.igual((select count(*)::int from auditoria where tabla = 'disputas' and grupo_id = g) >= 2, true, 'auditoría completa');
end $$;
