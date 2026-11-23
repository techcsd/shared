-- Crear grupo, invitar, aceptar, activación automática, tokens.
do $$
declare
  a uuid; b uuid; c uuid; g uuid; token text; n int; r uuid;
begin
  a := tests.crear_usuario('r_a@test.local', 'Ana');
  b := tests.crear_usuario('r_b@test.local', 'Beto');
  c := tests.crear_usuario('r_c@test.local', 'Carla');

  -- Anónimo no puede crear grupos
  perform tests.como_anonimo();
  perform tests.falla($q$select crear_grupo('X')$q$);

  -- Ana crea un grupo 50/50 en formación
  perform tests.como(a);
  g := crear_grupo('Bote de Felipe', 'DOP', 'America/Santo_Domingo', 'BOT', 50);
  perform tests.igual((select estado from grupos where id = g), 'formacion'::estado_grupo, 'grupo en formación');

  -- Zona horaria inválida
  perform tests.falla($q$select crear_grupo('Mal zona', 'DOP', 'Marte/Olimpo', 'ORD', 100)$q$, 'zona_horaria_invalida');

  -- No se puede reservar más de 100
  perform tests.falla(format($q$select invitar_miembro(%L, 'x@test.local', 'socio', 60)$q$, g), 'porcentajes_invalidos');

  -- Invita a Beto al 50 %
  token := invitar_miembro(g, 'R_B@test.local', 'socio', 50);
  perform tests.igual(length(token), 64, 'token de 64 hex');
  perform tests.admin();
  perform tests.igual((select count(*)::int from invitaciones_miembro where token_hash = token), 0, 'token NO se guarda en claro');
  perform tests.igual((select count(*)::int from invitaciones_miembro where token_hash = hash_token(token)), 1, 'se guarda el hash');

  -- Carla (otro correo) no puede aceptar la invitación de Beto
  perform tests.como(c);
  perform tests.falla(format($q$select aceptar_invitacion(%L)$q$, token), 'invitacion_no_valida');

  -- Beto la acepta: el grupo se activa 50/50
  perform tests.como(b);
  perform tests.igual((select porcentaje from previsualizar_invitacion(token)), 50::numeric, 'vista previa');
  r := aceptar_invitacion(token);
  perform tests.igual(r, g, 'devuelve el grupo');
  perform tests.admin();
  perform tests.igual((select estado from grupos where id = g), 'activo'::estado_grupo, 'activación automática');
  perform tests.igual((select sum(porcentaje) from miembros where grupo_id = g), 100::numeric, 'suma 100');

  -- Token usado no sirve otra vez
  perform tests.como(b);
  perform tests.falla(format($q$select aceptar_invitacion(%L)$q$, token), 'invitacion_aceptada');

  -- En grupo activo no se suman socios sin pasar por el estatuto
  perform tests.como(a);
  perform tests.falla(format($q$select invitar_miembro(%L, 'r_c@test.local', 'socio', 10)$q$, g), 'grupo_activo_requiere_estatuto');

  -- Sí se puede invitar un rol sin propiedad (admin operativo) y su porcentaje queda en 0
  token := invitar_miembro(g, 'r_c@test.local', 'admin_operativo', 33);
  perform tests.como(c);
  perform aceptar_invitacion(token);
  perform tests.admin();
  perform tests.igual((select porcentaje from miembros where grupo_id = g and usuario_id = c), 0::numeric, 'admin sin porcentaje');

  -- Beto (socio) puede invitar; Carla (admin_operativo) no
  perform tests.como(c);
  perform tests.falla(format($q$select invitar_miembro(%L, 'z@test.local', 'capitan', 0)$q$, g), 'solo_socios_invitan');

  -- Invitación expirada devuelve null y se marca
  perform tests.como(a);
  token := invitar_miembro(g, 'r_exp@test.local', 'capitan', 0);
  perform tests.admin();
  update invitaciones_miembro set expira_en = now() - interval '1 minute' where token_hash = hash_token(token);
  perform tests.crear_usuario('r_exp@test.local');
  perform tests.como((select id from auth.users where email = 'r_exp@test.local'));
  perform tests.igual(aceptar_invitacion(token), null::uuid, 'expirada devuelve null');

  -- Grupo con 100 % para un solo socio queda activo al crearse
  perform tests.como(a);
  g := crear_grupo('Mío', 'USD', 'America/Santo_Domingo', 'ORD', 100);
  perform tests.admin();
  perform tests.igual((select estado from grupos where id = g), 'activo'::estado_grupo, 'grupo individual activo');
end $$;
