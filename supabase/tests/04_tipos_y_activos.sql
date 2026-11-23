-- Tipos de activo configurables, activos, componentes, tarifas y permisos por rol.
do $$
declare
  a uuid; ad uuid; g uuid; t text; sis uuid; tipo uuid; act uuid; n int;
begin
  a := tests.crear_usuario('f4_a@test.local', 'Ana');
  ad := tests.crear_usuario('f4_adm@test.local', 'Operativo');

  perform tests.como(a);
  g := crear_grupo('Grupo F4', 'DOP', 'America/Santo_Domingo', 'MOT', 100);
  t := invitar_miembro(g, 'f4_adm@test.local', 'admin_operativo', 0);
  perform tests.como(ad);
  perform aceptar_invitacion(t);

  -- Plantillas de sistema visibles; no editables ni borrables, ni por un socio
  perform tests.como(a);
  perform tests.igual((select count(*)::int from tipos_activo where es_sistema), 3, 'tres plantillas de sistema');
  select id into sis from tipos_activo where clave = 'bote' and es_sistema;
  update tipos_activo set nombre = 'X' where id = sis;
  delete from tipos_activo where id = sis;
  perform tests.igual((select nombre from tipos_activo where id = sis), 'Bote', 'socio no altera plantilla');
  perform tests.admin();
  perform tests.falla(format($q$update tipos_activo set nombre = 'Hack' where id = %L$q$, sis), 'plantilla_de_sistema_inmutable');
  perform tests.como(a);

  -- Clonar «Otro» como «Moto acuática» y editar su definición (campo Matrícula, componente Horómetro)
  tipo := clonar_tipo_activo((select id from tipos_activo where clave = 'otro' and es_sistema), g, 'Moto acuática', 'moto_acuatica');
  update tipos_activo set definicion = $j${
    "campos": [{"clave": "matricula", "etiqueta": "Matrícula", "tipo": "texto", "obligatorio": true}],
    "componentes": [{"clave": "horometro", "etiqueta": "Horómetro", "cantidad_defecto": 1, "medidor": {"tipo": "horometro", "unidad": "h"}}],
    "checklists": {"salida": [{"clave": "chaleco", "texto": "Chaleco puesto", "obligatorio": true}], "regreso": [], "seguridad": []},
    "categorias_gasto": ["combustible", "otros"],
    "terminologia": {"activo": "Moto acuática"},
    "limites_capacidad": {"socio": 2, "invitado": 2}
  }$j$::jsonb where id = tipo;

  -- Definiciones inválidas no se guardan
  perform tests.falla(format($q$update tipos_activo set definicion = '{"campos":[{"clave":"Mal Clave","etiqueta":"x","tipo":"texto"}]}' where id = %L$q$, tipo), 'tipo_invalido');
  perform tests.falla(format($q$update tipos_activo set definicion = '{"campos":[{"clave":"a","etiqueta":"x","tipo":"inventado"}]}' where id = %L$q$, tipo), 'tipo_invalido');
  perform tests.falla(format($q$update tipos_activo set definicion = '{"componentes":[{"clave":"m","etiqueta":"M","cantidad_defecto":0,"medidor":{"tipo":"horometro","unidad":"h"}}]}' where id = %L$q$, tipo), 'tipo_invalido');
  perform tests.falla(format($q$update tipos_activo set definicion = '{"limites_capacidad":{"socio":0}}' where id = %L$q$, tipo), 'tipo_invalido');
  perform tests.falla(format($q$update tipos_activo set definicion = '{"otra_cosa":1}' where id = %L$q$, tipo), 'tipo_invalido');
  perform tests.falla(format($q$update tipos_activo set definicion = '{"campos":[{"clave":"a","etiqueta":"x","tipo":"opcion"}]}' where id = %L$q$, tipo), 'tipo_invalido');

  -- Crear activo de ese tipo: aparecen sus componentes (Horómetro) con lectura inicial 0
  act := crear_activo(g, tipo, 'Moto 1', null, '{}'::jsonb);
  perform tests.igual((select count(*)::int from activo_componentes where activo_id = act and clave = 'horometro'), 1, 'componente Horómetro creado');
  perform tests.igual((select estado from activos where id = act), 'borrador'::estado_activo, 'nace en borrador');

  -- Sin capacidad legal no se activa
  perform tests.falla(format($q$update activos set estado = 'activo' where id = %L$q$, act), 'valor_invalido');
  update activos set valores = '{"matricula": "MA-123"}' where id = act;
  perform tests.falla(format($q$update activos set estado = 'activo' where id = %L$q$, act), 'activos_capacidad_para_activar');
  -- Con capacidad pero sin el campo obligatorio (Matrícula) tampoco
  update activos set valores = '{}' where id = act;
  perform tests.falla(format($q$update activos set estado = 'activo', capacidad_legal = 2 where id = %L$q$, act), 'valor_invalido');
  -- Valor con tipo incorrecto
  perform tests.falla(format($q$update activos set valores = '{"matricula": 5}' where id = %L$q$, act), 'valor_invalido');
  -- Campo inexistente
  perform tests.falla(format($q$update activos set valores = '{"zzz": "x"}' where id = %L$q$, act), 'valor_invalido');
  -- Completo: se activa
  update activos set valores = '{"matricula": "MA-123"}', capacidad_legal = 2, estado = 'activo' where id = act;
  perform tests.igual((select estado from activos where id = act), 'activo'::estado_activo, 'activo con capacidad y matrícula');

  -- Lecturas iniciales no negativas
  perform tests.falla(format($q$update activo_componentes set lectura_inicial = -1 where activo_id = %L$q$, act));
  update activo_componentes set lectura_inicial = 12.5 where activo_id = act;

  -- Bote de sistema: 2 motores por defecto, y se puede cambiar la cantidad
  act := crear_activo(g, sis, 'Bote Demo', 15, '{}'::jsonb);
  perform tests.igual((select count(*)::int from activo_componentes where activo_id = act), 2, 'bote con 2 motores');
  act := crear_activo(g, sis, 'Bote 3 motores', 15, '{}'::jsonb, '{"motor": 3}'::jsonb);
  perform tests.igual((select count(*)::int from activo_componentes where activo_id = act), 3, 'cantidad de motores configurable');

  -- Destinos y tarifas (sin solapamiento de vigencias)
  insert into destinos (grupo_id, nombre) values (g, 'Playa');
  insert into tarifas (grupo_id, destino_id, tipo, monto, moneda, vigente_desde, vigente_hasta)
    select g, id, 'fee_destino', 5000, 'DOP', '2026-01-01', '2026-12-31' from destinos where grupo_id = g;
  perform tests.falla(format($q$insert into tarifas (grupo_id, destino_id, tipo, monto, moneda, vigente_desde)
    select %L, id, 'fee_destino', 6000, 'DOP', '2026-06-01' from destinos where grupo_id = %L$q$, g, g), 'tarifas_sin_solapamiento');
  perform tests.falla(format($q$insert into tarifas (grupo_id, tipo, monto, moneda) values (%L, 'fee_destino', -1, 'DOP')$q$, g));
  perform tests.falla(format($q$insert into destinos (grupo_id, nombre) values (%L, 'PLAYA')$q$, g));

  -- Admin operativo: ve activos y destinos; NO ve tarifas ni escribe configuración
  perform tests.como(ad);
  perform tests.igual((select count(*)::int from activos where grupo_id = g) > 0, true, 'admin ve activos');
  perform tests.igual((select count(*)::int from destinos where grupo_id = g), 1, 'admin ve destinos');
  perform tests.igual((select count(*)::int from tarifas where grupo_id = g), 0, 'admin NO ve tarifas');
  perform tests.falla(format($q$insert into destinos (grupo_id, nombre) values (%L, 'Pesca')$q$, g), 'row-level security');
  update activos set nombre = 'Hack' where grupo_id = g;
  perform tests.igual((select count(*)::int from activos where nombre = 'Hack'), 0, 'admin no edita activos');
  perform tests.falla(format($q$select clonar_tipo_activo(%L, %L, 'Mío', 'mio')$q$, sis, g), 'solo_socios');
  perform tests.falla(format($q$select crear_activo(%L, %L, 'Otro', 5)$q$, g, sis), 'solo_socios');
  perform tests.falla(format($q$select actualizar_grupo(%L, 'Hack', 'America/Santo_Domingo', 'ZZZ')$q$, g), 'solo_socios');

  -- Otro grupo no ve ni usa tipos/activos ajenos
  perform tests.admin();
  perform tests.crear_usuario('f4_otro@test.local');
  perform tests.como((select id from auth.users where email = 'f4_otro@test.local'));
  perform tests.igual((select count(*)::int from tipos_activo where not es_sistema), 0, 'otro usuario no ve tipos del grupo');
  perform tests.igual((select count(*)::int from activos), 0, 'otro usuario no ve activos');

  -- Actualizar datos del grupo (socio)
  perform tests.como(a);
  perform actualizar_grupo(g, 'Grupo F4 renombrado', 'America/Santo_Domingo', 'mot');
  perform tests.igual((select prefijo from grupos where id = g), 'MOT', 'prefijo en mayúsculas');
  perform tests.falla(format($q$select actualizar_grupo(%L, 'X', 'Marte/Olimpo', 'MOT')$q$, g), 'zona_horaria_invalida');
  perform tests.admin();
end $$;
