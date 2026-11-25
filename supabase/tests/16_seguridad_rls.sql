-- Auditoría automática de seguridad: RLS en todas las tablas, ningún acceso anónimo, escrituras solo por RPC,
-- toda función security definer con search_path fijo y sin ejecución pública.
do $$
declare r record; v_lista text; v_permitidas text[];
begin
  perform tests.admin();

  -- 1) RLS activa en TODAS las tablas de public
  select string_agg(c.relname, ', ') into v_lista
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  if v_lista is not null then raise exception 'SEGURIDAD: tablas sin RLS: %', v_lista; end if;

  -- 2) anon no tiene NINGÚN privilegio sobre tablas ni vistas de public
  select string_agg(distinct table_name, ', ') into v_lista
    from information_schema.role_table_grants where table_schema = 'public' and grantee = 'anon';
  if v_lista is not null then raise exception 'SEGURIDAD: anon tiene acceso a: %', v_lista; end if;

  -- 3) authenticated solo escribe (INSERT) donde está previsto; nunca UPDATE ni DELETE directo; el resto va por RPC
  v_permitidas := array['activo_campos', 'activo_componentes', 'activo_contactos', 'activo_documentos', 'activo_equipo', 'activo_ficha', 'activo_fotos', 'activo_mejoras', 'activo_valor', 'activos', 'destinos', 'grupo_correos', 'tarifas', 'tasas_cambio', 'tipos_activo'];   -- configuración: solo socio por RLS
  select string_agg(distinct table_name || ':' || privilege_type, ', ') into v_lista
    from information_schema.role_table_grants
   where table_schema = 'public' and grantee = 'authenticated'
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
     and not (table_name = any (v_permitidas) and privilege_type in ('INSERT', 'UPDATE', 'DELETE'))
     and not (table_name in ('eventos_cliente', 'errores_cliente') and privilege_type = 'INSERT')
     and table_name not in (select viewname from pg_views where schemaname = 'public');
  if v_lista is not null then raise exception 'SEGURIDAD: authenticated escribe directo en: %', v_lista; end if;
  -- y en esas tablas de configuración TODA política de escritura exige ser socio del grupo (o, en el activo, tener permiso de edición)
  select string_agg(tablename || '.' || policyname, ', ') into v_lista
    from pg_policies
   where schemaname = 'public' and tablename = any (v_permitidas) and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
     and coalesce(qual, '') || coalesce(with_check, '') not like '%es_socio%'
     and coalesce(qual, '') || coalesce(with_check, '') not like '%puede_editar_activo%';   -- el activo: admin del grupo o socio con permiso (mig. 34)
  if v_lista is not null then raise exception 'SEGURIDAD: políticas de escritura sin es_socio: %', v_lista; end if;

  -- 4) toda función security definer tiene search_path fijo
  select string_agg(p.proname, ', ') into v_lista
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%');
  if v_lista is not null then raise exception 'SEGURIDAD: security definer sin search_path fijo: %', v_lista; end if;

  -- 5) anon no ejecuta ninguna función de negocio (solo las que se listan: ninguna)
  select string_agg(p.proname, ', ') into v_lista
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')
     and p.prorettype <> 'trigger'::regtype                                                         -- los triggers no se invocan
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e');           -- funciones de extensiones (citext, btree_gist)
  if v_lista is not null then raise exception 'SEGURIDAD: anon puede ejecutar: %', v_lista; end if;

  -- 6) las funciones internas (sin permiso para clientes) siguen cerradas
  select string_agg(f, ', ') into v_lista
    from unnest(array['notificar', 'notificar_correo', 'lm_linea', 'asentar_fee', 'gasto_asentar', 'liquidar_operacion', 'alerta_una_vez',
                      'avisar_equipo', 'mantenimiento_evaluar', 'cron_mantenimiento', 'invitado_ver', 'hash_token', 'repartir_pesos']) f
   where exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = f and has_function_privilege('authenticated', p.oid, 'execute'));
  if v_lista is not null then raise exception 'SEGURIDAD: funciones internas abiertas a authenticated: %', v_lista; end if;
end $$;

-- 7) Un test por política: cada tabla con datos de un grupo no se ve desde otro grupo
do $$
declare a uuid; b uuid; ga uuid; gb uuid; r record; n int; v_filas text := '';
begin
  perform tests.admin();
  a := tests.crear_usuario('rls_a@test.local', 'A');
  b := tests.crear_usuario('rls_b@test.local', 'B');
  perform tests.como(a);
  ga := crear_grupo('RLS A', 'DOP', 'America/Santo_Domingo', 'RLA', 100);
  perform gasto_registrar(ga, 'comun', 'otros', 10, 'DOP');
  perform capitan_guardar(ga, null, 'Capi', null, 'L', current_date + 9, 1, null);
  perform disputa_abrir(ga, 'Tema de prueba', null, null, 'hola');
  perform dano_abrir(ga, 'Daño de prueba');
  perform tests.como(b);
  gb := crear_grupo('RLS B', 'DOP', 'America/Santo_Domingo', 'RLB', 100);
  -- B no ve NADA del grupo A en ninguna tabla que tenga grupo_id
  for r in select c.table_name from information_schema.columns c
            join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
           where c.table_schema = 'public' and c.column_name = 'grupo_id' order by 1 loop
    begin
      execute format('select count(*) from %I where grupo_id = %L', r.table_name, ga) into n;
    exception when insufficient_privilege then
      n := 0;   -- sin privilegio de lectura también es aislamiento
    end;
    if n > 0 then v_filas := v_filas || r.table_name || ' (' || n || '), '; end if;
  end loop;
  if v_filas <> '' then raise exception 'SEGURIDAD: el grupo B ve datos del grupo A en: %', v_filas; end if;
  -- y A sí ve lo suyo (la política no bloquea de más)
  perform tests.como(a);
  perform tests.igual((select count(*)::int from gastos where grupo_id = ga), 1, 'A ve sus gastos');
  perform tests.igual((select count(*)::int from capitanes where grupo_id = ga), 1, 'A ve sus capitanes');
  perform tests.igual((select count(*)::int from disputas where grupo_id = ga), 1, 'A ve sus disputas');
end $$;

-- 8) Tokens: ≥ 128 bits de entropía y solo se guarda el hash
do $$
declare a uuid; g uuid; t text;
begin
  perform tests.admin();
  a := tests.crear_usuario('tok_a@test.local', 'A');
  perform tests.crear_usuario('tok_b@test.local', 'B');
  perform tests.como(a);
  g := crear_grupo('Tokens', 'DOP', 'America/Santo_Domingo', 'TOK', 50);
  t := invitar_miembro(g, 'tok_b@test.local', 'socio', 50);
  perform tests.igual(length(t) >= 32, true, 'token de invitación de al menos 128 bits en hex (' || length(t) || ' caracteres)');
  perform tests.admin();
  perform tests.igual((select count(*)::int from invitaciones_miembro where token_hash = t), 0, 'el token en claro no se guarda');
  perform tests.igual((select count(*)::int from invitaciones_miembro where token_hash = hash_token(t)), 1, 'solo su hash');
end $$;
