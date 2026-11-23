-- Constraints de base (porcentajes, roles) y auditoría inmutable.
do $$
declare
  u1 uuid; u2 uuid; g uuid; n int;
begin
  u1 := tests.crear_usuario('c1@test.local', 'Uno');
  u2 := tests.crear_usuario('c2@test.local', 'Dos');

  -- Perfil automático al crear el usuario
  perform tests.igual((select nombre from perfiles where id = u1), 'Uno', 'perfil automático');

  -- Grupo en formación con 60 + 50 = 110 → falla al validar
  insert into grupos (nombre) values ('G110') returning id into g;
  insert into miembros (grupo_id, usuario_id, porcentaje) values (g, u1, 60), (g, u2, 50);
  begin
    set constraints all immediate;
    raise exception 'no debió permitir suma 110';
  exception when check_violation then
    null;
  end;
  set constraints all deferred;
  delete from grupos where id = g;

  -- Grupo activo con suma 60 → falla
  insert into grupos (nombre, estado) values ('G60', 'activo') returning id into g;
  insert into miembros (grupo_id, usuario_id, porcentaje) values (g, u1, 60);
  begin
    set constraints all immediate;
    raise exception 'no debió permitir activo con suma 60';
  exception when check_violation then
    null;
  end;
  set constraints all deferred;
  delete from grupos where id = g;

  -- Grupo activo 50/50 → pasa
  insert into grupos (nombre, estado) values ('G5050', 'activo') returning id into g;
  insert into miembros (grupo_id, usuario_id, porcentaje) values (g, u1, 50), (g, u2, 50);
  set constraints all immediate;
  set constraints all deferred;

  -- Solo un socio puede tener porcentaje > 0
  perform tests.falla(format(
    $q$insert into miembros (grupo_id, usuario_id, rol, porcentaje)
       values (%L, %L, 'admin_operativo', 10)$q$, g,
    tests.crear_usuario('c3@test.local')));

  -- Porcentaje fuera de rango
  perform tests.falla(format(
    $q$update miembros set porcentaje = 101 where grupo_id = %L and usuario_id = %L$q$, g, u1));

  -- Auditoría: el INSERT de grupo y miembros quedó registrado
  select count(*) into n from auditoria where tabla = 'grupos' and registro_id = g::text and accion = 'INSERT';
  perform tests.igual(n, 1, 'auditoría de grupos');
  select count(*) into n from auditoria where grupo_id = g and tabla = 'miembros';
  perform tests.igual(n, 2, 'auditoría de miembros');

  -- Inmutable incluso para el dueño/superusuario
  perform tests.falla('update auditoria set motivo = ''x''', 'inmutable');
  perform tests.falla('delete from auditoria', 'inmutable');
  perform tests.falla('truncate auditoria', 'inmutable');

  -- Un cambio con motivo se guarda
  perform set_config('app.motivo', 'prueba de motivo', true);
  update grupos set nombre = 'G5050 renombrado' where id = g;
  select count(*) into n from auditoria where tabla = 'grupos' and accion = 'UPDATE' and motivo = 'prueba de motivo';
  perform tests.igual(n, 1, 'motivo en auditoría');
end $$;
