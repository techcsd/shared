-- El activo como entidad editable (mig. 34): permisos (admin del grupo, socio con permiso, socio sin permiso, miembro no socio,
-- ajeno, admin de plataforma), campos propios validados, galería con portada, documentos privados/alertas, valor y mejoras
-- (solo socios, sin tocar el libro mayor) e historial acotado al grupo.
do $$
declare
  cre uuid; s2 uuid; s3 uuid; op uuid; ext uuid; adm uuid; cre2 uuid;
  g uuid; g2 uuid; bote uuid; act uuid; act2 uuid; m_s3 uuid; m_cre uuid;
  n int; v jsonb; h jsonb; f1 uuid; f2 uuid; f3 uuid; c1 uuid; c2 uuid;
  l_antes numeric; l_filas_antes int; l_despues numeric; l_filas_despues int; r1 text; r2 text; r3 text;
begin
  perform tests.admin();
  cre := tests.crear_usuario('ae_cre@test.local', 'Creadora');
  s2 := tests.crear_usuario('ae_s2@test.local', 'Socio Dos');
  s3 := tests.crear_usuario('ae_s3@test.local', 'Socio Tres');
  op := tests.crear_usuario('ae_op@test.local', 'Operativo');
  ext := tests.crear_usuario('ae_ext@test.local', 'Ajeno');
  adm := tests.crear_usuario('ae_adm@test.local', 'Admin plataforma');
  cre2 := tests.crear_usuario('ae_cre2@test.local', 'Otra creadora');
  delete from plataforma_admins;
  insert into plataforma_admins (usuario_id) values (adm);

  perform tests.como(cre);
  g := crear_grupo('Grupo Entidad', 'DOP', 'America/Santo_Domingo', 'ENT', 60);
  select id into bote from tipos_activo where clave = 'bote' and es_sistema;
  act := crear_activo(g, bote, 'Bote Entidad', 12);
  perform tests.admin();
  insert into miembros (grupo_id, usuario_id, rol, porcentaje) values (g, s2, 'socio', 30), (g, s3, 'socio', 10);
  insert into miembros (grupo_id, usuario_id, rol, porcentaje) values (g, op, 'admin_operativo', 0);
  select id into m_s3 from miembros where grupo_id = g and usuario_id = s3;
  select id into m_cre from miembros where grupo_id = g and usuario_id = cre;
  select coalesce(sum(haber - debe), 0), count(*) into l_antes, l_filas_antes from libro_mayor;

  -- permiso inicial: el creador edita; los demás socios no
  perform tests.igual((select puede_editar_activo from miembros where id = m_cre)::text, 'true', 'el creador nace con permiso');
  perform tests.igual((select puede_editar_activo from miembros where grupo_id = g and usuario_id = s2)::text, 'false', 'el otro socio no');

  -- socio SIN permiso: lee pero no escribe (ni activo ni tablas nuevas)
  perform tests.como(s2);
  update activos set descripcion = 'hackeo' where id = act;
  get diagnostics n = row_count;
  perform tests.igual(n, 0, 'socio sin permiso no edita el activo');
  perform tests.falla(format($q$insert into activo_equipo (grupo_id, activo_id, nombre) values (%L, %L, 'Ancla')$q$, g, act), 'row-level security');
  perform tests.falla(format($q$select activo_permiso_editar(%L, %L, true)$q$, g, m_s3), 'sin_permiso');
  perform tests.igual((activo_detalle(act) #>> '{permisos,editar}'), 'false', 'el detalle dice que no puede editar');
  perform tests.igual(jsonb_typeof(activo_detalle(act) -> 'socios'), 'null', 'y no lista socios para permisos');

  -- el admin del grupo concede el permiso; el creador no puede quitárselo
  perform tests.como(cre);
  perform activo_permiso_editar(g, m_s3, true);
  perform tests.falla(format($q$select activo_permiso_editar(%L, %L, false)$q$, g, m_cre), 'creador_siempre_edita');
  perform tests.falla(format($q$select activo_permiso_editar(%L, %L, true)$q$, g,
    (select id from miembros where grupo_id = g and usuario_id = op)), 'miembro_invalido');
  v := activo_detalle(act);
  perform tests.igual(v #>> '{permisos,admin}', 'true', 'el creador es admin');
  perform tests.igual(jsonb_array_length(v -> 'socios')::text, '3', 'y ve a los 3 socios para dar permisos');

  -- socio CON permiso: edita; pero no concede permisos (no es admin del grupo)
  perform tests.como(s3);
  update activos set descripcion = 'Bote con permiso' where id = act;
  get diagnostics n = row_count;
  perform tests.igual(n, 1, 'el socio con permiso edita el activo');
  insert into activo_equipo (grupo_id, activo_id, nombre, cantidad, condicion) values (g, act, 'Chalecos', 12, 'bueno');
  insert into activo_equipo (grupo_id, activo_id, nombre, cantidad, condicion) values (g, act, 'Ancla', 1, 'nuevo');
  perform tests.falla(format($q$select activo_permiso_editar(%L, %L, false)$q$, g, m_cre), 'sin_permiso');
  perform tests.falla(format($q$insert into activo_equipo (grupo_id, activo_id, nombre, condicion) values (%L, %L, 'X', 'roto')$q$, g, act));
  perform tests.falla(format($q$insert into activo_equipo (grupo_id, activo_id, nombre, cantidad) values (%L, %L, 'X', -1)$q$, g, act));

  -- retirar el permiso
  perform tests.como(cre);
  perform activo_permiso_editar(g, m_s3, false);
  perform tests.como(s3);
  perform tests.falla(format($q$insert into activo_equipo (grupo_id, activo_id, nombre) values (%L, %L, 'Otro')$q$, g, act), 'row-level security');
  perform tests.como(cre);
  perform activo_permiso_editar(g, m_s3, true);

  -- campos propios: validación por tipo, opciones y etiqueta única
  perform tests.como(cre);
  insert into activo_campos (grupo_id, activo_id, etiqueta, tipo, unidad, valor) values (g, act, 'Año', 'numero', null, '2021');
  insert into activo_campos (grupo_id, activo_id, etiqueta, tipo, opciones, valor) values (g, act, 'Combustible', 'seleccion', '["Diésel","Gasolina"]', '"Diésel"');
  insert into activo_campos (grupo_id, activo_id, etiqueta, tipo, valor) values (g, act, 'Última revisión', 'fecha', '"2026-10-01"');
  insert into activo_campos (grupo_id, activo_id, etiqueta, tipo, valor) values (g, act, 'Tiene GPS', 'si_no', 'true');
  insert into activo_campos (grupo_id, activo_id, etiqueta, tipo) values (g, act, 'Sin valor aún', 'texto');
  perform tests.falla(format($q$insert into activo_campos (grupo_id, activo_id, etiqueta, tipo, valor) values (%L, %L, 'Mal', 'numero', '"abc"')$q$, g, act), 'valor_invalido');
  perform tests.falla(format($q$insert into activo_campos (grupo_id, activo_id, etiqueta, tipo, valor) values (%L, %L, 'Mal2', 'fecha', '"ayer"')$q$, g, act), 'valor_invalido');
  perform tests.falla(format($q$insert into activo_campos (grupo_id, activo_id, etiqueta, tipo, valor) values (%L, %L, 'Mal3', 'si_no', '"si"')$q$, g, act), 'valor_invalido');
  perform tests.falla(format($q$insert into activo_campos (grupo_id, activo_id, etiqueta, tipo, opciones, valor) values (%L, %L, 'Mal4', 'seleccion', '["A","B"]', '"C"')$q$, g, act), 'valor_invalido');
  perform tests.falla(format($q$insert into activo_campos (grupo_id, activo_id, etiqueta, tipo) values (%L, %L, 'Mal5', 'seleccion')$q$, g, act), 'opciones_requeridas');
  perform tests.falla(format($q$insert into activo_campos (grupo_id, activo_id, etiqueta, tipo) values (%L, %L, ' año ', 'texto')$q$, g, act), 'duplicate');
  update activo_campos set etiqueta = 'Año de fabricación' where activo_id = act and etiqueta = 'Año';
  get diagnostics n = row_count;
  perform tests.igual(n, 1, 'renombrar un campo propio');
  -- los campos del tipo siguen en activos.valores (validados por el tipo)
  update activos set valores = '{"matricula": "ABC-123", "eslora": 9.5}'::jsonb where id = act;
  get diagnostics n = row_count;
  perform tests.igual(n, 1, 'los campos del tipo se editan con permiso');
  perform tests.falla(format($q$update activos set valores = '{"eslora": "larga"}'::jsonb where id = %L$q$, act));

  -- contactos y ubicación
  insert into activo_contactos (grupo_id, activo_id, categoria, nombre, telefono, correo) values (g, act, 'marina', 'Marina Norte', '+1 809-555-0100', 'marina@ejemplo.com');
  perform tests.falla(format($q$insert into activo_contactos (grupo_id, activo_id, nombre, telefono) values (%L, %L, 'Mal', 'llámame')$q$, g, act));
  perform tests.falla(format($q$insert into activo_contactos (grupo_id, activo_id, nombre, categoria) values (%L, %L, 'Mal', 'espía')$q$, g, act));
  insert into activo_ficha (activo_id, grupo_id, condicion, condicion_notas, ubicacion_texto, ubicacion_url)
  values (act, g, 'buena', 'Casco limpio', 'Marina Norte, muelle 4', 'https://maps.example.com/?q=marina');
  perform tests.falla(format($q$update activo_ficha set ubicacion_url = 'javascript:alert(1)' where activo_id = %L$q$, act));
  perform tests.falla(format($q$update activo_ficha set ubicacion_url = 'http://sin-https.example' where activo_id = %L$q$, act));
  perform tests.igual((select condicion_actualizada_por from activo_ficha where activo_id = act), cre, 'la condición guarda quién la actualizó');

  -- galería: la ruta debe estar en la carpeta del grupo; la portada se copia a activos.imagen_path
  r1 := g || '/' || gen_random_uuid() || '.webp';
  r2 := g || '/' || gen_random_uuid() || '.webp';
  r3 := g || '/' || gen_random_uuid() || '.webp';
  perform tests.falla(format($q$insert into activo_fotos (grupo_id, activo_id, ruta) values (%L, %L, %L)$q$, g, act, gen_random_uuid() || '/x.webp'));
  insert into activo_fotos (grupo_id, activo_id, ruta, descripcion, orden) values (g, act, r1, 'Proa', 0) returning id into f1;
  insert into activo_fotos (grupo_id, activo_id, ruta, descripcion, orden) values (g, act, r2, 'Cabina', 1) returning id into f2;
  insert into activo_fotos (grupo_id, activo_id, ruta, descripcion, orden) values (g, act, r3, 'Popa', 2) returning id into f3;
  perform tests.igual((select imagen_path from activos where id = act), r1, 'la primera foto es la portada');
  perform activo_foto_portada(f2);
  perform tests.igual((select imagen_path from activos where id = act), r2, 'cambiar la portada se refleja en el activo');
  perform tests.igual((select count(*) from activo_fotos where activo_id = act and es_portada)::int, 1, 'una sola portada');
  perform activo_reordenar('activo_fotos', array[f3, f1, f2]);
  perform tests.igual((select string_agg(descripcion, ',' order by orden) from activo_fotos where activo_id = act), 'Popa,Proa,Cabina', 'reordenar fotos');
  delete from activo_fotos where id = f2;   -- borra la portada: otra la releva
  perform tests.igual((select count(*) from activo_fotos where activo_id = act and es_portada)::int, 1, 'tras borrar la portada hay otra');
  perform tests.igual((select imagen_path from activos where id = act) is not null, true, 'y el activo conserva imagen');
  perform tests.falla(format($q$select activo_reordenar('activos', array[%L]::uuid[])$q$, act), 'tabla_invalida');
  perform tests.como(s2);
  perform tests.falla(format($q$select activo_foto_portada(%L)$q$, f1), 'sin_permiso');
  perform tests.falla(format($q$select activo_reordenar('activo_fotos', array[%L]::uuid[])$q$, f1), 'sin_permiso');

  -- documentos: facturas/contratos solo socios; el miembro no socio ve matrícula, no factura
  perform tests.como(cre);
  insert into activo_documentos (grupo_id, activo_id, tipo, titulo, ruta, mime, vence_en)
  values (g, act, 'matricula', 'Matrícula 2026', g || '/' || gen_random_uuid() || '.pdf', 'application/pdf', current_date + 5);
  insert into activo_documentos (grupo_id, activo_id, tipo, titulo, ruta, mime)
  values (g, act, 'factura', 'Factura de compra', g || '/' || gen_random_uuid() || '.pdf', 'application/pdf');
  perform tests.falla(format($q$insert into activo_documentos (grupo_id, activo_id, tipo, titulo, ruta) values (%L, %L, 'secreto', 'Mal', %L)$q$, g, act, g || '/a.pdf'));
  perform tests.falla(format($q$insert into activo_documentos (grupo_id, activo_id, tipo, titulo, ruta) values (%L, %L, 'otro', 'Ruta ajena', %L)$q$, g, act, gen_random_uuid() || '/a.pdf'));
  perform tests.falla(format($q$insert into activo_documentos (grupo_id, activo_id, tipo, titulo, ruta, emitido_en, vence_en) values (%L, %L, 'otro', 'Fechas mal', %L, '2026-05-01', '2026-01-01')$q$, g, act, g || '/b.pdf'));
  perform tests.como(op);
  perform tests.igual((select count(*) from activo_documentos where activo_id = act)::int, 1, 'el miembro no socio ve solo la matrícula');
  perform tests.igual(jsonb_array_length(activo_detalle(act) -> 'documentos')::text, '1', 'y el detalle también');
  perform tests.igual(jsonb_typeof(activo_detalle(act) -> 'valor'), 'null', 'sin valor para no socios');
  perform tests.como(s2);
  perform tests.igual((select count(*) from activo_documentos where activo_id = act)::int, 2, 'un socio ve ambos');

  -- valor y mejoras: solo socios; no tocan el libro mayor
  perform tests.como(cre);
  insert into activo_valor (activo_id, grupo_id, precio_compra, moneda_compra, fecha_compra, valor_estimado, moneda_estimado, fecha_estimado)
  values (act, g, 2500000, 'DOP', '2024-01-15', 2300000, 'DOP', current_date);
  perform tests.falla(format($q$update activo_valor set precio_compra = -5 where activo_id = %L$q$, act));
  insert into activo_mejoras (grupo_id, activo_id, fecha, descripcion, costo, moneda) values (g, act, current_date, 'GPS nuevo', 18500, 'DOP');
  perform tests.falla(format($q$insert into activo_mejoras (grupo_id, activo_id, descripcion, costo) values (%L, %L, 'Mal', -1)$q$, g, act));
  perform tests.como(op);
  perform tests.igual((select count(*) from activo_valor)::int, 0, 'el no socio no ve el valor');
  perform tests.igual((select count(*) from activo_mejoras)::int, 0, 'ni las mejoras');
  perform tests.como(s2);
  perform tests.igual((select count(*) from activo_mejoras where activo_id = act)::int, 1, 'el socio sí ve las mejoras');
  perform tests.igual(activo_detalle(act) #>> '{valor,precio_compra}', '2500000.00', 'y el valor en el detalle');

  -- ajeno: nada de nada
  perform tests.como(ext);
  perform tests.falla(format($q$select activo_detalle(%L)$q$, act), 'sin_permiso');
  perform tests.falla(format($q$select activo_historial(%L)$q$, act), 'sin_permiso');
  perform tests.igual((select count(*) from activo_equipo)::int, 0, 'el ajeno no ve equipo');
  perform tests.igual((select count(*) from activo_fotos)::int, 0, 'ni fotos');
  perform tests.igual((select count(*) from activo_campos)::int, 0, 'ni campos');
  perform tests.falla(format($q$insert into activo_equipo (grupo_id, activo_id, nombre) values (%L, %L, 'Intruso')$q$, g, act), 'row-level security');
  perform tests.como_anonimo();
  perform tests.falla(format($q$select activo_detalle(%L)$q$, act));
  perform tests.falla($q$select count(*) from activo_equipo$q$);

  -- historial: legible, con actor, acotado al activo; valor/mejoras/facturas solo para socios
  perform tests.como(s2);
  h := activo_historial(act);
  perform tests.igual((jsonb_array_length(h) > 5)::text, 'true', 'el historial tiene entradas');
  perform tests.igual((select count(*) from jsonb_array_elements(h) e where e ->> 'tabla' = 'activo_equipo' and e ->> 'titulo' = 'Chalecos')::int, 1, 'incluye el equipo agregado');
  perform tests.igual((select count(*) from jsonb_array_elements(h) e where e ->> 'actor' = 'Socio Tres' and e ->> 'tabla' = 'activo_equipo')::int, 2, 'con el actor correcto');
  perform tests.igual((select count(*) from jsonb_array_elements(h) e where e ->> 'tabla' = 'activo_mejoras')::int, 1, 'un socio ve las mejoras en el historial');
  perform tests.igual((select count(*) from jsonb_array_elements(h) e where e ->> 'tabla' = 'activos' and e ->> 'accion' = 'UPDATE'
                          and exists (select 1 from jsonb_array_elements(e -> 'cambios') c where c ->> 'campo' = 'descripcion'))::int, 1, 'y el cambio de descripción con su campo');
  perform tests.como(op);
  h := activo_historial(act);
  perform tests.igual((select count(*) from jsonb_array_elements(h) e where e ->> 'tabla' in ('activo_valor', 'activo_mejoras'))::int, 0, 'el no socio no ve valor ni mejoras en el historial');
  perform tests.igual((select count(*) from jsonb_array_elements(h) e where e ->> 'titulo' = 'Factura de compra')::int, 0, 'ni facturas');
  perform tests.igual((jsonb_array_length(h) > 0)::text, 'true', 'pero sí lo demás');

  -- otro grupo: su historial no mezcla datos del primero
  perform tests.como(cre2);
  g2 := crear_grupo('Otro Grupo', 'DOP', 'America/Santo_Domingo', 'OTR', 100);
  act2 := crear_activo(g2, bote, 'Otro Bote', 8);
  insert into activo_equipo (grupo_id, activo_id, nombre) values (g2, act2, 'Remo');
  h := activo_historial(act2);
  perform tests.igual((select count(*) from jsonb_array_elements(h) e where e ->> 'titulo' in ('Chalecos', 'Ancla', 'GPS nuevo'))::int, 0, 'el historial del otro grupo no mezcla datos');
  perform tests.falla(format($q$select activo_historial(%L)$q$, act), 'sin_permiso');
  -- no puede colgar filas de su grupo de un activo ajeno
  perform tests.falla(format($q$insert into activo_equipo (grupo_id, activo_id, nombre) values (%L, %L, 'Cruce')$q$, g2, act), 'foreign key');
  perform tests.falla(format($q$insert into activo_equipo (grupo_id, activo_id, nombre) values (%L, %L, 'Cruce')$q$, g, act), 'row-level security');

  -- admin de plataforma: edita y lee sin ser miembro
  perform tests.como(adm);
  insert into activo_equipo (grupo_id, activo_id, nombre) values (g, act, 'Botiquín');
  perform tests.igual(activo_detalle(act) #>> '{permisos,editar}', 'true', 'el admin de plataforma edita');
  perform tests.igual((jsonb_array_length(activo_historial(act)) > 5)::text, 'true', 'y ve el historial');

  -- alertas de vencimiento de documentos: una sola vez por umbral
  perform tests.admin();
  perform tests.igual(activo_documentos_evaluar() >= 1, true, 'avisa del documento por vencer');
  select count(*) into n from notificaciones where tipo = 'documento_por_vencer' and grupo_id = g;
  perform tests.igual(n > 0, true, 'hay notificaciones a los socios');
  perform tests.igual(activo_documentos_evaluar(), 0, 'no repite el aviso');
  perform tests.igual((select count(*) from notificaciones where tipo = 'documento_por_vencer' and grupo_id = g and usuario_id = op)::int, 1,
    'la matrícula avisa también al administrador operativo');
  perform tests.igual(pg_get_functiondef('public.cron_mantenimiento()'::regprocedure) like '%activo_documentos_evaluar%', true, 'el cron evalúa documentos');

  -- el dinero no se toca
  select coalesce(sum(haber - debe), 0), count(*) into l_despues, l_filas_despues from libro_mayor;
  perform tests.igual(l_despues, l_antes, 'Σ libro mayor sin cambios');
  perform tests.igual(l_filas_despues, l_filas_antes, 'sin asientos nuevos');

  -- limpieza
  delete from grupos where id in (g, g2);
  delete from plataforma_admins;
end $$;
