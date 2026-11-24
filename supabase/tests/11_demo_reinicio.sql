-- Reinicio de datos demo: solo en grupos de demostración, solo socios.
do $$
declare a uuid; b uuid; gd uuid; gr uuid; ma uuid; gs uuid;
begin
  perform tests.admin();
  a := tests.crear_usuario('dm_a@test.local', 'Ana');
  b := tests.crear_usuario('dm_b@test.local', 'Beto');
  perform tests.como(a);
  gd := crear_grupo('Demo', 'DOP', 'America/Santo_Domingo', 'DMO', 100, true);
  gr := crear_grupo('Real', 'DOP', 'America/Santo_Domingo', 'REA', 100, false);
  perform tests.admin();
  insert into activos (grupo_id, tipo_id, nombre) values (gd, (select id from tipos_activo where clave = 'otro' and es_sistema), 'Activo demo');
  perform tests.como(a);
  gs := gasto_registrar(gd, 'comun', 'otros', 100, 'DOP');
  perform dano_abrir(gd, 'Daño demo');
  perform dano_proponer((select id from danos_casos where grupo_id = gd), 50, 'DOP', 'miembro', (select id from miembros where grupo_id = gd and usuario_id = a), jsonb_build_array(jsonb_build_object('miembro_id', (select id from miembros where grupo_id = gd and usuario_id = a), 'monto', 50)));
  perform tests.admin();
  perform tests.igual((select count(*)::int from gastos where grupo_id = gd and alcance = 'dano'), 1, 'un gasto de daño referencia el caso');
  perform tests.igual((select count(*)::int from libro_mayor where grupo_id = gd) > 0, true, 'hay asientos antes del reinicio');
  perform tests.como(b);
  perform tests.falla(format($q$select demo_reiniciar_operacion(%L)$q$, gd), 'solo_socios');
  perform tests.como(a);
  perform tests.falla(format($q$select demo_reiniciar_operacion(%L)$q$, gr), 'solo_demo');
  perform demo_reiniciar_operacion(gd);
  perform tests.admin();
  perform tests.igual((select count(*)::int from libro_mayor where grupo_id = gd), 0, 'el libro del grupo demo queda vacío');
  perform tests.igual((select count(*)::int from gastos where grupo_id = gd), 0, 'sin gastos');
  -- el borrado directo sigue prohibido fuera del reinicio
  perform tests.como(a);
  gs := gasto_registrar(gd, 'comun', 'otros', 10, 'DOP');
  perform tests.admin();
  perform set_config('app.permitir_borrado', '', true);   -- (el permiso es local a la transacción del reinicio)
  perform tests.falla(format($q$delete from libro_mayor where grupo_id = %L$q$, gd), 'solo_adicion');
end $$;
