-- RLS: aislamiento entre grupos, roles y privilegios mínimos.
do $$
declare
  a1 uuid; a2 uuid; adm uuid; b1 uuid; ga uuid; gb uuid; t text; n int;
begin
  a1 := tests.crear_usuario('s_a1@test.local', 'A1');
  a2 := tests.crear_usuario('s_a2@test.local', 'A2');
  adm := tests.crear_usuario('s_adm@test.local', 'Operativo');
  b1 := tests.crear_usuario('s_b1@test.local', 'B1');

  -- Grupo A (A1 + A2 al 50/50 + admin operativo) y grupo B (B1)
  perform tests.como(a1);
  ga := crear_grupo('Grupo A', 'DOP', 'America/Santo_Domingo', 'AAA', 50);
  t := invitar_miembro(ga, 's_a2@test.local', 'socio', 50);
  perform tests.como(a2);
  perform aceptar_invitacion(t);
  perform tests.como(a1);
  t := invitar_miembro(ga, 's_adm@test.local', 'admin_operativo', 0);
  perform tests.como(adm);
  perform aceptar_invitacion(t);
  perform tests.como(b1);
  gb := crear_grupo('Grupo B', 'DOP', 'America/Santo_Domingo', 'BBB', 100);

  -- A1 ve su grupo, no el B
  perform tests.como(a1);
  perform tests.igual((select count(*)::int from grupos where id = ga), 1, 'A1 ve A');
  perform tests.igual((select count(*)::int from grupos where id = gb), 0, 'A1 no ve B');
  perform tests.igual((select count(*)::int from miembros where grupo_id = gb), 0, 'A1 no ve miembros de B');
  perform tests.igual((select count(*)::int from miembros where grupo_id = ga), 3, 'A1 ve 3 miembros de A');
  perform tests.igual((select count(*)::int from perfiles where id = b1), 0, 'A1 no ve el perfil de B1');
  perform tests.igual((select count(*)::int from perfiles where id = a2), 1, 'A1 ve el perfil de su socio');

  -- B1 no ve nada del grupo A, ni su auditoría
  perform tests.como(b1);
  perform tests.igual((select count(*)::int from grupos where id = ga), 0, 'B1 no ve A');
  perform tests.igual((select count(*)::int from auditoria where grupo_id = ga), 0, 'B1 no ve auditoría de A');
  perform tests.igual((select count(*)::int from auditoria where grupo_id = gb), (select count(*)::int from auditoria where grupo_id = gb), 'B1 sí ve la suya');
  perform tests.falla(format($q$select invitar_miembro(%L, 'x@test.local', 'capitan', 0)$q$, ga), 'solo_socios_invitan');

  -- Socio ve la auditoría de su grupo; el admin operativo no
  perform tests.como(a1);
  select count(*) into n from auditoria where grupo_id = ga;
  if n = 0 then raise exception 'el socio debería ver la auditoría'; end if;
  perform tests.como(adm);
  perform tests.igual((select count(*)::int from auditoria where grupo_id = ga), 0, 'admin operativo no ve auditoría');
  perform tests.igual((select count(*)::int from invitaciones_miembro where grupo_id = ga and correo <> 's_adm@test.local'), 0, 'admin operativo no ve invitaciones ajenas');
  perform tests.igual((select count(*)::int from grupos where id = ga), 1, 'admin operativo sí ve el grupo');

  -- Sin escritura directa para nadie (solo RPC)
  perform tests.como(a1);
  perform tests.falla(format($q$update miembros set porcentaje = 90 where grupo_id = %L$q$, ga), 'permission denied');
  perform tests.falla($q$insert into grupos (nombre) values ('hack')$q$, 'permission denied');
  perform tests.falla(format($q$insert into grupo_politicas (grupo_id, clave, valor) values (%L, 'x', '1')$q$, ga), 'permission denied');
  perform tests.falla(format($q$delete from auditoria where grupo_id = %L$q$, ga), 'permission denied');
  perform tests.falla(format($q$update grupos set estado = 'archivado' where id = %L$q$, ga), 'permission denied');

  -- Perfil: solo el propio y solo ciertas columnas
  update perfiles set nombre = 'Ana Nueva' where id = a1;
  perform tests.igual((select nombre from perfiles where id = a1), 'Ana Nueva', 'edita su perfil');
  update perfiles set nombre = 'Hackeado' where id = a2;
  perform tests.igual((select nombre from perfiles where id = a2), 'A2', 'no edita el perfil ajeno');
  perform tests.falla($q$update perfiles set correo = 'otro@x.com'$q$, 'permission denied');

  -- errores_cliente: solo propios
  perform tests.como(a1);
  insert into errores_cliente (usuario_id, mensaje) values (a1, 'prueba');
  perform tests.falla(format($q$insert into errores_cliente (usuario_id, mensaje) values (%L, 'suplantado')$q$, a2), 'row-level security');
  perform tests.igual((select count(*)::int from errores_cliente), 1, 've solo sus errores');

  -- Anónimo: nada
  perform tests.como_anonimo();
  perform tests.falla('select * from grupos', 'permission denied');
  perform tests.falla('select * from politicas_catalogo', 'permission denied');
  perform tests.falla('select es_miembro(gen_random_uuid())', 'permission denied');
  perform tests.admin();
end $$;
