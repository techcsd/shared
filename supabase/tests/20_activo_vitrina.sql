-- Vitrina del activo (mig. 33): miembros y admin de plataforma ven el resumen; un ajeno no; la vista previa de
-- invitación solo muestra el subconjunto no sensible y solo a quien tiene la invitación pendiente a su correo.
do $$
declare a uuid; b uuid; ext uuid; adm uuid; g uuid; tok text; bote uuid; act uuid; inv uuid; v jsonb; p jsonb;
begin
  perform tests.admin();
  a := tests.crear_usuario('av_a@test.local', 'Dueña');
  b := tests.crear_usuario('av_b@test.local', 'Invitado');
  ext := tests.crear_usuario('av_ext@test.local', 'Ajeno');
  adm := tests.crear_usuario('av_adm@test.local', 'Admin plataforma');
  delete from plataforma_admins;
  insert into plataforma_admins (usuario_id) values (adm);

  perform tests.como(a);
  g := crear_grupo('Grupo Vitrina', 'DOP', 'America/Santo_Domingo', 'VIT', 60);
  select id into bote from tipos_activo where clave = 'bote' and es_sistema;
  act := crear_activo(g, bote, 'Bote Vitrina', 12);
  update activos set descripcion = 'Un bote de 32 pies', punto_encuentro = 'Marina Norte',
         reglas_invitados = 'Chaleco obligatorio', contacto_invitados = 'tel secreto' where id = act;
  insert into destinos (grupo_id, nombre) values (g, 'Playa Vit');
  tok := invitar_miembro(g, 'av_b@test.local', 'socio', 40);

  -- socio: vitrina completa
  v := activo_vitrina(g);
  perform tests.igual(v #>> '{activos,0,nombre}', 'Bote Vitrina', 'el socio ve el activo');
  perform tests.igual(v #>> '{activos,0,descripcion}', 'Un bote de 32 pies', 'el socio ve la descripción');
  perform tests.igual(v #>> '{activos,0,tipo,clave}', 'bote', 'y el tipo');
  perform tests.igual(jsonb_array_length(v -> 'destinos')::text, '1', 'y los destinos');
  perform tests.igual((jsonb_array_length(v #> '{activos,0,componentes}') >= 1)::text, 'true', 'y los componentes');

  -- admin de plataforma: también
  perform tests.como(adm);
  perform tests.igual(activo_vitrina(g) #>> '{activos,0,nombre}', 'Bote Vitrina', 'el admin de plataforma ve la vitrina');

  -- ajeno y anónimo: no
  perform tests.como(ext);
  perform tests.falla(format($q$select activo_vitrina(%L)$q$, g), 'sin_permiso');
  perform tests.como_anonimo();
  perform tests.falla(format($q$select activo_vitrina(%L)$q$, g));
  perform tests.falla(format($q$select activo_vista_por_token(%L)$q$, tok));

  -- el invitado (correo coincidente) ve solo el subconjunto no sensible, por token y por id
  perform tests.como(b);
  p := activo_vista_por_token(tok);
  perform tests.igual(p #>> '{activos,0,nombre}', 'Bote Vitrina', 'el invitado ve el activo por token');
  perform tests.igual(p #>> '{activos,0,punto_encuentro}', 'Marina Norte', 'y el punto de encuentro');
  perform tests.igual((p #> '{activos,0}' ? 'reglas_invitados')::text, 'false', 'sin reglas de invitados');
  perform tests.igual((p #> '{activos,0}' ? 'valores')::text, 'false', 'sin valores internos');
  perform tests.igual((p ? 'destinos')::text, 'false', 'sin destinos ni tarifas');
  perform tests.igual((p::text like '%tel secreto%')::text, 'false', 'el contacto no se filtra');
  inv := (select invitacion_id from invitaciones_pendientes_mias());
  perform tests.igual(activo_vista_por_invitacion(inv) #>> '{activos,0,nombre}', 'Bote Vitrina', 'y por id de invitación');
  perform tests.falla(format($q$select activo_vitrina(%L)$q$, g), 'sin_permiso');   -- aún no es miembro

  -- otro usuario con el token o el id: null, sin pistas
  perform tests.como(ext);
  perform tests.igual((activo_vista_por_token(tok) is null)::text, 'true', 'el ajeno con el token no ve nada');
  perform tests.igual((activo_vista_por_invitacion(inv) is null)::text, 'true', 'ni por id');
  perform tests.igual((activo_vista_por_token('token-que-no-existe') is null)::text, 'true', 'token inexistente: null');

  -- la ruta de la imagen debe estar en la carpeta del grupo
  perform tests.admin();
  perform tests.falla(format($q$update activos set imagen_path = 'otro-grupo/x.webp' where id = %L$q$, act), 'activos_imagen_del_grupo');
  update activos set imagen_path = g || '/' || act || '-abc.webp' where id = act;
  perform tests.como(a);
  perform tests.igual(activo_vitrina(g) #>> '{activos,0,imagen_path}', g || '/' || act || '-abc.webp', 'la vitrina devuelve la ruta de la imagen');
  -- el socio puede editar descripción e imagen (política activos_update, auditada)
  update activos set descripcion = 'Nueva descripción' where id = act;
  perform tests.igual((select descripcion from activos where id = act), 'Nueva descripción', 'el socio edita la descripción');
  perform tests.como(ext);
  perform tests.igual((select count(*) from activos where id = act)::text, '0', 'el ajeno no ve la tabla');
  perform tests.admin();
end $$;
