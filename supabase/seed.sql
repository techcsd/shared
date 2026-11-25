-- Datos DEMO (DF-37, DF-40). Solo para entornos local/dev. NUNCA aplicar en producción.
-- Contraseña de todos los usuarios demo: Demo1234!  (dato de prueba, no es un secreto)
-- Idempotente: UUID fijos + on conflict do nothing.

do $$
declare
  v_usuarios uuid[];
  v_correos text[] := array['felipe.demo@shared.test', 'xaviel.demo@shared.test'];
  v_nombres text[] := array['Felipe (demo)', 'Xaviel (demo)'];
  i int;
  v_id uuid;
  v_tiene_clave boolean;
  v_tiene_identidades boolean;
begin
  -- 10 socios para el grupo genérico
  for i in 1..10 loop
    v_correos := v_correos || format('socio%s.demo@shared.test', lpad(i::text, 2, '0'));
    v_nombres := v_nombres || format('Socio %s (demo)', i);
  end loop;

  select exists (select 1 from information_schema.columns
                  where table_schema = 'auth' and table_name = 'users' and column_name = 'encrypted_password')
    into v_tiene_clave;
  select to_regclass('auth.identities') is not null into v_tiene_identidades;

  for i in 1..array_length(v_correos, 1) loop
    v_id := ('00000000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid;
    if v_tiene_clave then
      -- Supabase real: requiere pgcrypto (crypt/gen_salt) y columnas de GoTrue.
      execute $q$
        insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
          confirmation_token, recovery_token, email_change_token_new, email_change)
        values ('00000000-0000-0000-0000-000000000000', $1, 'authenticated', 'authenticated', $2,
          extensions.crypt('Demo1234!', extensions.gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}', jsonb_build_object('nombre', $3), now(), now(),
          '', '', '', '')
        on conflict (id) do nothing$q$ using v_id, v_correos[i], v_nombres[i];
      if v_tiene_identidades then
        execute $q$
          insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
          values (gen_random_uuid(), $1, $1::text, jsonb_build_object('sub', $1::text, 'email', $2), 'email', now(), now(), now())
          on conflict do nothing$q$ using v_id, v_correos[i];
      end if;
    else
      insert into auth.users (id, email, raw_user_meta_data)
      values (v_id, v_correos[i], jsonb_build_object('nombre', v_nombres[i]))
      on conflict (id) do nothing;
    end if;
  end loop;
end $$;

-- Perfiles con nombre demo (el trigger los crea al insertar el usuario)
update perfiles set nombre = 'Felipe (demo)' where correo = 'felipe.demo@shared.test';
update perfiles set nombre = 'Xaviel (demo)' where correo = 'xaviel.demo@shared.test';

-- ---------------------------------------------------------------- Grupo 1: Bote Demo, 2 socios 50/50
insert into grupos (id, nombre, moneda, zona_horaria, prefijo, estado, modo_demo, creado_por)
values ('10000000-0000-4000-8000-000000000001', 'Bote Demo (Felipe y Xaviel)', 'DOP', 'America/Santo_Domingo', 'BOT',
        'activo', true, '00000000-0000-4000-8000-000000000001')
on conflict (id) do nothing;
insert into miembros (grupo_id, usuario_id, rol, porcentaje) values
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', 'socio', 50),
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002', 'socio', 50)
on conflict (grupo_id, usuario_id) do nothing;

insert into activos (id, grupo_id, tipo_id, nombre, capacidad_legal, estado, punto_encuentro, contacto_invitados)
select '20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', t.id, 'Bote Demo', 15, 'activo',
       'Marina (demo)', 'felipe.demo@shared.test'
  from tipos_activo t where t.clave = 'bote' and t.es_sistema
on conflict (id) do nothing;
insert into activo_componentes (grupo_id, activo_id, clave, etiqueta, indice, unidad, lectura_inicial)
select '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'motor', 'Motor ' || n, n, 'h', 0
  from generate_series(1, 2) n
on conflict (activo_id, clave, indice) do nothing;

insert into destinos (id, grupo_id, nombre, orden) values
  ('30000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Playa', 1),
  ('30000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'Pesca', 2),
  ('30000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', 'La Romana', 3),
  ('30000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001', 'Otros', 4)
on conflict (id) do nothing;
insert into tarifas (id, grupo_id, destino_id, tipo, monto, moneda, vigente_desde) values
  ('40000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 'fee_destino', 5000, 'DOP', '2026-01-01'),
  ('40000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002', 'fee_destino', 8000, 'DOP', '2026-01-01'),
  ('40000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000003', 'fee_destino', 12000, 'DOP', '2026-01-01'),
  ('40000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000004', 'fee_destino', 3000, 'DOP', '2026-01-01')
on conflict (id) do nothing;

-- Capitanes con licencia vigente (DF-20: sin capitán con licencia vigente no hay check-in)
insert into capitanes (grupo_id, miembro_id, nombre, licencia_numero, licencia_vence, experiencia_anios)
select m.grupo_id, m.id, 'Capitán ' || p.nombre, 'LIC-DEMO-' || substr(m.id::text, 1, 4), current_date + 365, 5
  from miembros m join perfiles p on p.id = m.usuario_id
 where m.grupo_id = '10000000-0000-4000-8000-000000000001'
   and not exists (select 1 from capitanes c where c.grupo_id = m.grupo_id and c.miembro_id = m.id);

-- ---------------------------------------------------------------- Grupo 2: 10 socios con un carro (prueba de lo genérico)
insert into grupos (id, nombre, moneda, zona_horaria, prefijo, estado, modo_demo, creado_por)
values ('10000000-0000-4000-8000-000000000002', 'Carro Demo (10 socios)', 'DOP', 'America/Santo_Domingo', 'CAR',
        'activo', true, '00000000-0000-4000-8000-000000000003')
on conflict (id) do nothing;
insert into miembros (grupo_id, usuario_id, rol, porcentaje)
select '10000000-0000-4000-8000-000000000002', ('00000000-0000-4000-8000-' || lpad((n + 2)::text, 12, '0'))::uuid, 'socio', 10
  from generate_series(1, 10) n
on conflict (grupo_id, usuario_id) do nothing;
-- Xaviel también ve el grupo de 10 como admin operativo (prueba de roles)
insert into miembros (grupo_id, usuario_id, rol, porcentaje)
values ('10000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000002', 'admin_operativo', 0)
on conflict (grupo_id, usuario_id) do nothing;

insert into activos (id, grupo_id, tipo_id, nombre, capacidad_legal, valores, estado)
select '20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', t.id, 'Carro Demo', 5,
       '{"placa": "A000000", "marca": "Demo", "modelo": "Sedán", "anio": 2024}'::jsonb, 'activo'
  from tipos_activo t where t.clave = 'carro' and t.es_sistema
on conflict (id) do nothing;
insert into activo_componentes (grupo_id, activo_id, clave, etiqueta, indice, unidad, lectura_inicial)
values ('10000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', 'odometro', 'Odómetro', 1, 'km', 0)
on conflict (activo_id, clave, indice) do nothing;
insert into destinos (id, grupo_id, nombre, orden)
values ('30000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000002', 'Ciudad', 1)
on conflict (id) do nothing;

-- Vitrina del activo (mig. 33): descripciones de demostración. Sin fotos: se muestra el ícono por tipo.
update activos set descripcion = 'Bote de demostración de 32 pies con dos motores. Sale desde la marina, ideal para paseos familiares y salidas de pesca de un día. Datos de prueba.'
 where id = '20000000-0000-4000-8000-000000000001';
update activos set descripcion = 'Sedán de demostración para cinco personas, compartido entre los socios del grupo. Datos de prueba.'
 where id = '20000000-0000-4000-8000-000000000002';
