-- El administrador de plataforma ve y configura todos los grupos, pero NO actúa como socio ni toca el dinero (DF-99..DF-103).
do $$
declare
  adm uuid; a uuid; b uuid; ext uuid;
  g uuid; g2 uuid; n int; tok text; cap uuid; gasto uuid;
begin
  perform tests.admin();
  adm := tests.crear_usuario('ac_admin@test.local', 'Admin Total');
  a := tests.crear_usuario('ac_a@test.local', 'Socio A');
  b := tests.crear_usuario('ac_b@test.local', 'Socio B');
  ext := tests.crear_usuario('ac_ext@test.local', 'Ajeno');
  delete from plataforma_admins;
  insert into plataforma_admins (usuario_id) values (adm);

  perform tests.como(a);
  g := crear_grupo('Grupo Uno', 'DOP', 'America/Santo_Domingo', 'AAA', 100);
  perform tests.como(b);
  g2 := crear_grupo('Grupo Dos', 'DOP', 'America/Santo_Domingo', 'BBB', 100);

  -- control: el socio sí puede registrar un gasto en su grupo
  perform tests.como(a);
  gasto := (select gasto_registrar(g, 'comun', 'otros', 10, 'DOP'));
  perform tests.igual((select count(*) from gastos where grupo_id = g)::text, '1', 'control: el socio registra su gasto');

  perform tests.admin();
  n := (select count(*) from libro_mayor where grupo_id = g);

  -- ============ un ajeno NO ve nada de otros grupos (sin cambios)
  perform tests.como(ext);
  perform tests.igual((select count(*) from grupos where id in (g, g2))::text, '0', 'ajeno: no ve grupos');
  perform tests.igual((select count(*) from gastos)::text, '0', 'ajeno: no ve gastos');
  perform tests.falla(format($q$select balances_grupo(%L)$q$, g), 'solo_socios');
  -- un socio de un grupo no ve el otro
  perform tests.como(a);
  perform tests.igual((select count(*) from grupos where id = g2)::text, '0', 'socio: no ve el grupo ajeno');
  perform tests.falla(format($q$select balances_grupo(%L)$q$, g2), 'solo_socios');

  -- ============ el administrador de plataforma LEE todo, sin ser miembro
  perform tests.como(adm);
  perform tests.igual((select count(*) from grupos where id in (g, g2))::text, '2', 'admin: ve ambos grupos');
  perform tests.igual((select count(*) from miembros where grupo_id in (g, g2))::text, '2', 'admin: ve los miembros');
  perform tests.igual((select count(*) from gastos where grupo_id = g)::text, '1', 'admin: ve los gastos');
  perform tests.igual((select count(*) from perfiles where id in (a, b))::text, '2', 'admin: ve los perfiles de los socios');
  perform tests.igual((select count(*) from politicas_del_grupo(g))::text, (select count(*)::text from politicas_catalogo), 'admin: ve las políticas del grupo');
  perform tests.igual(((select count(*) from balances_grupo(g)) > 0)::text, 'true', 'admin: balances del grupo');

  -- ============ y CONFIGURA sin ser miembro
  perform actualizar_grupo(g, 'Grupo Uno (renombrado)', 'America/Santo_Domingo', 'AAA');
  perform tests.igual((select nombre from grupos where id = g), 'Grupo Uno (renombrado)', 'admin: edita el grupo');
  tok := invitar_miembro(g2, 'nuevo.operativo@test.local', 'admin_operativo', 0);
  perform tests.igual((tok is not null)::text, 'true', 'admin: gestiona invitaciones');
  cap := capitan_guardar(g, null, 'Capitán Admin', null, 'LIC-1', current_date + 365, 5, null);
  perform tests.igual((cap is not null)::text, 'true', 'admin: registra capitanes');

  -- ============ pero NO actúa como socio (identidad de miembro requerida)
  perform tests.falla(format($q$select gasto_registrar(%L, 'comun', 'otros', 5, 'DOP')$q$, g));
  perform tests.falla(format($q$select pago_registrar(%L, (select id from miembros where grupo_id = %L limit 1), 5, 'DOP')$q$, g, g));
  perform tests.falla(format($q$select gasto_validar(%L)$q$, gasto));
  perform tests.falla(format($q$select dano_abrir(%L, 'Daño de prueba')$q$, g));
  perform tests.falla(format($q$select proponer_cambio_politica(%L, '{"cancelacion.horas_sin_cargo": 72}'::jsonb, 'x')$q$, g), 'solo_miembros_proponen');
  perform tests.igual((select count(*) from estatuto_versiones where grupo_id = g)::text, '0', 'admin: no dejó versiones de estatuto');
  perform tests.igual((select count(*) from gastos where grupo_id = g)::text, '1', 'admin: no creó ni cambió gastos');

  -- el libro mayor sigue sin escritura directa, ni para el admin
  perform tests.falla(format($q$insert into libro_mayor (grupo_id, cuenta_tipo, moneda, debe, haber) values (%L, 'fondo', 'DOP', 1, 0)$q$, g));
  perform tests.falla(format($q$delete from libro_mayor where grupo_id = %L$q$, g));
  perform tests.falla(format($q$update gastos set estado = 'validado' where id = %L$q$, gasto));

  -- ============ anónimo sigue sin nada; los helpers fijan search_path
  perform tests.como_anonimo();
  perform tests.falla(format($q$select balances_grupo(%L)$q$, g));
  perform tests.igual((select count(*) from pg_proc p where p.proname in ('es_miembro', 'es_socio', 'comparte_grupo') and p.prosecdef
    and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'))::text, '3', 'helpers: security definer con search_path fijo');
  perform tests.admin();
  perform tests.igual((select count(*) from libro_mayor where grupo_id = g)::text, n::text, 'admin: el libro mayor no cambió');
end $$;
