-- Panel de administración de plataforma: solo admin; porcentajes siguen sumando 100; borrado seguro; bitácora.
do $$
declare
  adm uuid; a uuid; b uuid; c uuid; ext uuid; nuevo uuid;
  g uuid; gf uuid; n int; j jsonb; s numeric;
begin
  perform tests.admin();
  adm := tests.crear_usuario('adm_admin@test.local', 'Admin Plataforma');
  a := tests.crear_usuario('adm_a@test.local', 'Socio A');
  b := tests.crear_usuario('adm_b@test.local', 'Socio B');
  c := tests.crear_usuario('adm_c@test.local', 'Socio C');
  ext := tests.crear_usuario('adm_ext@test.local', 'Ajeno');
  delete from plataforma_admins;                   -- los tests anteriores comparten base: partir de un solo admin
  insert into plataforma_admins (usuario_id) values (adm);

  perform tests.como(a);
  g := crear_grupo('Grupo Admin', 'DOP', 'America/Santo_Domingo', 'ADM', 100);   -- A 100 % → activo
  perform tests.igual((select estado::text from grupos where id = g), 'activo', 'el grupo nace activo con un socio al 100 %');

  -- ============ nadie sin permiso ejecuta nada del panel (socio, ajeno, anónimo)
  perform tests.como(a);
  perform tests.falla($q$select admin_usuarios_listar()$q$, 'solo_admin_plataforma');
  perform tests.falla($q$select admin_grupos_listar()$q$, 'solo_admin_plataforma');
  perform tests.falla(format($q$select admin_grupo_miembros(%L)$q$, g), 'solo_admin_plataforma');
  perform tests.falla(format($q$select admin_miembro_guardar(%L, %L, 'socio', 0)$q$, g, b), 'solo_admin_plataforma');
  perform tests.falla(format($q$select admin_porcentajes_fijar(%L, '[]'::jsonb)$q$, g), 'solo_admin_plataforma');
  perform tests.falla(format($q$select admin_miembro_quitar(%L, %L)$q$, g, a), 'solo_admin_plataforma');
  perform tests.falla(format($q$select admin_usuario_borrable(%L)$q$, b), 'solo_admin_plataforma');
  perform tests.falla(format($q$select admin_plataforma_asignar(%L, true)$q$, a), 'solo_admin_plataforma');
  perform tests.falla($q$select admin_directorio_set(true)$q$, 'solo_admin_plataforma');
  perform tests.falla($q$select admin_bitacora_listar(10)$q$, 'solo_admin_plataforma');
  perform tests.falla($q$select admin_accion_registrar('x', 'y', '{}'::jsonb)$q$, 'solo_admin_plataforma');
  perform tests.falla($q$select admin_exigir()$q$);                       -- ni siquiera el ayudante interno
  perform tests.falla($q$select * from admin_acciones$q$);               -- la bitácora no es legible por la API
  perform tests.como(ext);
  perform tests.falla($q$select admin_usuarios_listar()$q$, 'solo_admin_plataforma');
  perform tests.como_anonimo();
  perform tests.falla($q$select admin_usuarios_listar()$q$);
  perform tests.falla($q$select admin_miembro_guardar(gen_random_uuid(), gen_random_uuid(), 'socio', 0)$q$);

  -- ============ el admin ve usuarios y grupos
  perform tests.como(adm);
  j := admin_usuarios_listar();
  perform tests.igual(jsonb_array_length(j) >= 5, true, 'lista los usuarios');
  perform tests.igual((select count(*)::int from jsonb_array_elements(j) x where (x ->> 'es_admin')::boolean), 1, 'marca al admin de plataforma');
  perform tests.igual((select jsonb_array_length(x -> 'grupos') from jsonb_array_elements(j) x where x ->> 'correo' = 'adm_a@test.local'), 1, 'muestra los grupos del usuario');
  j := admin_grupos_listar();
  perform tests.igual((select (x ->> 'miembros')::int from jsonb_array_elements(j) x where (x ->> 'id')::uuid = g), 1, 'cuenta miembros');
  perform tests.igual((select (x ->> 'suma_porcentajes')::numeric from jsonb_array_elements(j) x where (x ->> 'id')::uuid = g), 100::numeric, 'suma 100');

  -- ============ agregar socios a un grupo ACTIVO sin invitación: con % > 0 se rechaza (rompería el 100), con 0 se acepta
  perform tests.falla(format($q$select admin_miembro_guardar(%L, %L, 'socio', 40)$q$, g, b), 'porcentajes_invalidos');
  perform tests.admin();
  perform tests.igual((select count(*)::int from miembros where grupo_id = g), 1, 'el rechazo no dejó miembros a medias');
  perform tests.como(adm);
  perform admin_miembro_guardar(g, b, 'socio', 0);
  perform admin_miembro_guardar(g, c, 'socio', 0);
  perform tests.admin();
  perform tests.igual((select count(*)::int from miembros where grupo_id = g and estado = 'activo'), 3, 'tres miembros activos');
  perform tests.como(adm);
  perform tests.falla(format($q$select admin_miembro_guardar(%L, %L, 'capitan', 10)$q$, g, ext), 'porcentaje_invalido');   -- solo socio tiene %
  perform tests.falla(format($q$select admin_miembro_guardar(%L, gen_random_uuid(), 'socio', 0)$q$, g), 'usuario_no_existe');

  -- ============ repartir porcentajes: atómico, exactamente 100
  perform tests.falla(format($q$select admin_porcentajes_fijar(%L, %L::jsonb)$q$, g,
    jsonb_build_array(jsonb_build_object('usuario_id', a, 'porcentaje', 50), jsonb_build_object('usuario_id', b, 'porcentaje', 30),
                      jsonb_build_object('usuario_id', c, 'porcentaje', 30))), 'porcentajes_invalidos');       -- 110
  perform tests.falla(format($q$select admin_porcentajes_fijar(%L, %L::jsonb)$q$, g,
    jsonb_build_array(jsonb_build_object('usuario_id', a, 'porcentaje', 60), jsonb_build_object('usuario_id', b, 'porcentaje', 30))), 'porcentajes_invalidos'); -- falta C
  perform tests.falla(format($q$select admin_porcentajes_fijar(%L, %L::jsonb)$q$, g,
    jsonb_build_array(jsonb_build_object('usuario_id', a, 'porcentaje', 60), jsonb_build_object('usuario_id', a, 'porcentaje', 40),
                      jsonb_build_object('usuario_id', b, 'porcentaje', 0))), 'porcentajes_invalidos');         -- A repetido
  perform tests.falla(format($q$select admin_porcentajes_fijar(%L, %L::jsonb)$q$, g,
    jsonb_build_array(jsonb_build_object('usuario_id', a, 'porcentaje', 60), jsonb_build_object('usuario_id', b, 'porcentaje', 50),
                      jsonb_build_object('usuario_id', c, 'porcentaje', -10))));                                   -- negativo
  perform tests.admin();
  perform tests.igual((select porcentaje from miembros where grupo_id = g and usuario_id = a), 100::numeric, 'los intentos fallidos no cambiaron nada');
  perform tests.como(adm);
  perform admin_porcentajes_fijar(g, jsonb_build_array(
    jsonb_build_object('usuario_id', a, 'porcentaje', 50), jsonb_build_object('usuario_id', b, 'porcentaje', 33.34),
    jsonb_build_object('usuario_id', c, 'porcentaje', 16.66)));
  perform tests.admin();
  select sum(porcentaje) into s from miembros where grupo_id = g and rol = 'socio' and estado = 'activo';
  perform tests.como(adm);
  perform tests.igual(s, 100::numeric, 'los porcentajes siguen sumando 100 tras repartir');

  -- ============ quitar: un socio con % en grupo activo no sale sin repartir; con 0 % sí
  perform tests.falla(format($q$select admin_miembro_quitar(%L, %L)$q$, g, c), 'porcentaje_pendiente');
  perform admin_porcentajes_fijar(g, jsonb_build_array(
    jsonb_build_object('usuario_id', a, 'porcentaje', 60), jsonb_build_object('usuario_id', b, 'porcentaje', 40),
    jsonb_build_object('usuario_id', c, 'porcentaje', 0)));
  perform admin_miembro_quitar(g, c);
  perform tests.admin();
  perform tests.igual((select estado::text from miembros where grupo_id = g and usuario_id = c), 'salido', 'C queda como salido (historial intacto)');
  perform tests.como(adm);
  perform tests.admin();
  select sum(porcentaje) into s from miembros where grupo_id = g and rol = 'socio' and estado = 'activo';
  perform tests.como(adm);
  perform tests.igual(s, 100::numeric, 'sigue en 100 tras quitar');
  perform admin_miembro_guardar(g, c, 'admin_operativo', 0);              -- reactivar con otro rol
  perform tests.admin();
  perform tests.igual((select rol::text from miembros where grupo_id = g and usuario_id = c), 'admin_operativo', 'cambia de rol');
  perform tests.como(adm);
  perform tests.admin();
  perform tests.igual((select estado::text from miembros where grupo_id = g and usuario_id = c), 'activo', 'reactivado');
  perform tests.como(adm);

  -- ============ grupo en formación: agregar socios hasta 100 lo activa
  perform tests.como(b);
  gf := crear_grupo('Grupo en formación', 'DOP', 'America/Santo_Domingo', 'FOR', 40);
  perform tests.igual((select estado::text from grupos where id = gf), 'formacion', 'con 40 % queda en formación');
  perform tests.como(adm);
  perform tests.falla(format($q$select admin_miembro_guardar(%L, %L, 'socio', 70)$q$, gf, a), 'porcentajes_invalidos');   -- 110
  perform admin_miembro_guardar(gf, a, 'socio', 60);
  perform tests.admin();
  perform tests.igual((select estado::text from grupos where id = gf), 'activo', 'al llegar a 100 % se activa');
  perform tests.como(adm);

  -- ============ borrado seguro
  j := admin_usuario_borrable(a);
  perform tests.igual((j ->> 'ok')::boolean, false, 'un socio con % en grupo activo no es borrable');
  perform tests.igual((j -> 'motivos') @> '"socio_en_grupo_activo"'::jsonb, true, 'explica por qué');
  j := admin_usuario_borrable(adm);
  perform tests.igual((j -> 'motivos') @> '"es_el_mismo"'::jsonb, true, 'no puede borrarse a sí mismo');
  perform tests.igual((j -> 'motivos') @> '"ultimo_admin_plataforma"'::jsonb, true, 'ni borrar al último admin');
  perform tests.igual((admin_usuario_borrable(ext) ->> 'ok')::boolean, true, 'un usuario sin datos sí es borrable');

  -- ============ admin de plataforma: otorgar y no quedarse sin ninguno
  perform tests.falla(format($q$select admin_plataforma_asignar(%L, false)$q$, adm), 'ultimo_admin_plataforma');
  perform admin_plataforma_asignar(ext, true);
  perform tests.admin();
  perform tests.igual((select count(*)::int from plataforma_admins), 2, 'se otorgó');
  perform tests.como(adm);
  perform admin_plataforma_asignar(ext, false);
  perform tests.admin();
  perform tests.igual((select count(*)::int from plataforma_admins), 1, 'se quitó');
  perform tests.como(adm);

  -- ============ directorio
  perform admin_directorio_set(true);
  perform tests.igual(directorio_habilitado(), true, 'se enciende');
  perform admin_directorio_set(false);
  perform tests.igual(directorio_habilitado(), false, 'se apaga');

  -- ============ auditoría de cada cambio + bitácora del admin, ambas inmutables
  perform tests.admin();
  perform tests.igual((select count(*)::int from auditoria where tabla = 'miembros' and motivo = 'administración de plataforma' and grupo_id = g) >= 5, true, 'los cambios de miembros quedan en auditoría con motivo');
  perform tests.igual((select count(*)::int from admin_acciones where accion = 'miembro_guardar') >= 4, true, 'bitácora del admin');
  perform tests.igual((select count(*)::int from admin_acciones where accion = 'porcentajes_fijar') >= 2, true, 'bitácora de porcentajes');
  perform tests.falla($q$update admin_acciones set accion = 'x'$q$, 'solo_adicion');
  perform tests.falla($q$delete from admin_acciones$q$, 'solo_adicion');
  perform tests.como(adm);
  perform admin_accion_registrar('usuario_crear', 'x@y', '{"k":1}'::jsonb);
  perform tests.igual(jsonb_array_length(admin_bitacora_listar(100)) >= 8, true, 'lista la bitácora');

  -- ============ el dinero no se toca: nada del panel escribe en el libro mayor
  perform tests.admin();
  select count(*) into n from libro_mayor where grupo_id in (g, gf);
  perform tests.igual(n, 0, 'sin movimientos de libro mayor');
end $$;
