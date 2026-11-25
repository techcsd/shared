-- Invitaciones pendientes a mi correo: solo las mías, aceptar por id con las mismas reglas.
do $$
declare a uuid; b uuid; ext uuid; g uuid; tok text; inv uuid; r uuid; n int;
begin
  perform tests.admin();
  a := tests.crear_usuario('ip_a@test.local', 'Dueño');
  b := tests.crear_usuario('ip_b@test.local', 'Invitado');
  ext := tests.crear_usuario('ip_ext@test.local', 'Otro');
  perform tests.como(a);
  g := crear_grupo('Grupo Inv', 'DOP', 'America/Santo_Domingo', 'INV', 60);
  tok := invitar_miembro(g, 'ip_b@test.local', 'socio', 40);

  perform tests.como(b);
  perform tests.igual((select count(*) from invitaciones_pendientes_mias())::text, '1', 'el invitado ve su invitación');
  inv := (select invitacion_id from invitaciones_pendientes_mias());

  perform tests.como(ext);
  perform tests.igual((select count(*) from invitaciones_pendientes_mias())::text, '0', 'otro usuario no ve invitaciones ajenas');
  perform tests.falla(format($q$select aceptar_invitacion_por_id(%L)$q$, inv), 'invitacion_no_valida');
  perform tests.como_anonimo();
  perform tests.falla($q$select * from invitaciones_pendientes_mias()$q$);
  perform tests.falla(format($q$select aceptar_invitacion_por_id(%L)$q$, inv));

  perform tests.como(b);
  r := aceptar_invitacion_por_id(inv);
  perform tests.igual((r = g)::text, 'true', 'aceptar por id devuelve el grupo');
  perform tests.igual((select count(*) from invitaciones_pendientes_mias())::text, '0', 'ya no queda pendiente');
  perform tests.igual((select estado::text from grupos where id = g), 'activo', 'Σ socios = 100 activa el grupo');
  perform tests.falla(format($q$select aceptar_invitacion_por_id(%L)$q$, inv), 'invitacion_aceptada');
  perform tests.admin();
end $$;
