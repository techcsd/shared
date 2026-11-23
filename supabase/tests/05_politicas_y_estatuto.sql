-- Políticas por grupo y estatuto versionado (criterio F5: 3 → 5 solo cuando el 2.º socio acepta).
do $$
declare
  a uuid; b uuid; adm uuid; solo uuid; g uuid; g1 uuid; t text; v uuid; v2 uuid; est estado_version;
begin
  a := tests.crear_usuario('p_a@test.local', 'Ana');
  b := tests.crear_usuario('p_b@test.local', 'Beto');
  adm := tests.crear_usuario('p_adm@test.local', 'Operativo');
  solo := tests.crear_usuario('p_solo@test.local', 'Solo');

  perform tests.como(a);
  g := crear_grupo('Grupo P', 'DOP', 'America/Santo_Domingo', 'PPP', 50);
  t := invitar_miembro(g, 'p_b@test.local', 'socio', 50);
  perform tests.como(b);
  perform aceptar_invitacion(t);
  perform tests.como(a);
  t := invitar_miembro(g, 'p_adm@test.local', 'admin_operativo', 0);
  perform tests.como(adm);
  perform aceptar_invitacion(t);

  -- Defaults del catálogo (DF)
  perform tests.como(a);
  perform tests.igual(politica(g, 'reservas.dias_max_seguidos'), '3'::jsonb, 'default 3 días');
  perform tests.igual(politica(g, 'cancelacion.horas_sin_cargo'), '48'::jsonb, 'default 48 h');
  perform tests.igual(politica(g, 'finanzas.modo'), '"registro"'::jsonb, 'modo registro');
  perform tests.igual(politica(g, 'capacidad.socio'), '15'::jsonb, 'capacidad socio 15');
  perform tests.falla($q$select politica(gen_random_uuid(), 'no.existe')$q$, 'politica_desconocida');

  -- Admin operativo no propone ni acepta (no cambia acuerdos)
  perform tests.como(adm);
  perform tests.falla(format($q$select proponer_cambio_politica(%L, '{"reservas.dias_max_seguidos": 5}')$q$, g), 'solo_socios_proponen');
  perform tests.igual(politica(g, 'reservas.dias_max_seguidos'), '3'::jsonb, 'admin lee políticas');

  -- Valores inválidos rechazados
  perform tests.como(a);
  perform tests.falla(format($q$select proponer_cambio_politica(%L, '{"reservas.dias_max_seguidos": 0}')$q$, g), 'politica_invalida');
  perform tests.falla(format($q$select proponer_cambio_politica(%L, '{"reservas.dias_max_seguidos": "cinco"}')$q$, g), 'politica_invalida');
  perform tests.falla(format($q$select proponer_cambio_politica(%L, '{"combustible.modelo": "gratis"}')$q$, g), 'politica_invalida');
  perform tests.falla(format($q$select proponer_cambio_politica(%L, '{"inventada.clave": 1}')$q$, g), 'politica_desconocida');
  perform tests.falla(format($q$select proponer_cambio_politica(%L, '{"reservas.acuse_requerido": null}')$q$, g), 'politica_invalida');
  perform tests.falla(format($q$select proponer_cambio_politica(%L, '{"seguro.alerta_dias": [30, 0]}')$q$, g), 'politica_invalida');
  perform tests.falla(format($q$select proponer_cambio_politica(%L, '{"reservas.dias_max_seguidos": 3}')$q$, g), 'sin_cambios');
  perform tests.falla(format($q$select proponer_cambio_politica(%L, '{}')$q$, g), 'sin_cambios');

  -- CRITERIO: 3 → 5 crea versión pendiente; sigue rigiendo 3 hasta que acepta el segundo socio
  v := proponer_cambio_politica(g, '{"reservas.dias_max_seguidos": 5}', 'Más días en verano');
  perform tests.igual((select estado from estatuto_versiones where id = v), 'pendiente'::estado_version, 'versión pendiente');
  perform tests.igual(politica(g, 'reservas.dias_max_seguidos'), '3'::jsonb, 'sigue 3 mientras está pendiente');
  perform tests.falla(format($q$select proponer_cambio_politica(%L, '{"reservas.buffer_horas": 2}')$q$, g), 'ya_hay_version_pendiente');
  -- el proponente no puede aceptar dos veces (su acuse ya existe)
  perform tests.falla(format($q$select aceptar_version(%L)$q$, v));

  perform tests.como(adm);
  perform tests.falla(format($q$select aceptar_version(%L)$q$, v), 'solo_socios_aceptan');

  perform tests.como(b);
  est := aceptar_version(v);
  perform tests.igual(est, 'vigente'::estado_version, 'vigente al aceptar todos');
  perform tests.igual(politica(g, 'reservas.dias_max_seguidos'), '5'::jsonb, 'ahora rige 5');
  perform tests.igual((select count(*)::int from estatuto_acuses where version_id = v and acepta), 2, 'dos acuses');

  -- Nueva versión reemplaza a la vigente; un rechazo no cambia nada
  v2 := proponer_cambio_politica(g, '{"cancelacion.horas_sin_cargo": 24}');
  perform tests.como(a);
  est := aceptar_version(v2, false);
  perform tests.igual(est, 'rechazada'::estado_version, 'un rechazo cierra la propuesta');
  perform tests.igual(politica(g, 'cancelacion.horas_sin_cargo'), '48'::jsonb, 'rige lo anterior');
  perform tests.igual((select estado from estatuto_versiones where id = v), 'vigente'::estado_version, 'la vigente sigue');

  v2 := proponer_cambio_politica(g, '{"cancelacion.horas_sin_cargo": 24}');
  perform tests.como(b);
  perform aceptar_version(v2);
  perform tests.igual(politica(g, 'cancelacion.horas_sin_cargo'), '24'::jsonb, 'segunda versión aplicada');
  perform tests.igual(politica(g, 'reservas.dias_max_seguidos'), '5'::jsonb, 'la anterior se conserva');
  perform tests.admin();
  perform tests.igual((select estado from estatuto_versiones where id = v), 'reemplazada'::estado_version, 'versión anterior reemplazada');
  perform tests.igual((select numero from estatuto_versiones where id = v2), 3, 'numeración consecutiva');

  -- El proponente puede retirar su propuesta
  perform tests.como(a);
  v := proponer_cambio_politica(g, '{"fondo.aporte_mensual": 1000}');
  perform tests.como(b);
  perform tests.falla(format($q$select cancelar_version(%L)$q$, v), 'solo_el_proponente');
  perform tests.como(a);
  perform cancelar_version(v);
  perform tests.igual(politica(g, 'fondo.aporte_mensual'), '0'::jsonb, 'retirada no aplica');

  -- Escritura directa prohibida (solo vía RPC)
  perform tests.falla(format($q$insert into grupo_politicas (grupo_id, clave, valor) values (%L, 'reservas.dias_max_seguidos', '9')$q$, g), 'permission denied');
  perform tests.falla(format($q$update estatuto_versiones set estado = 'vigente' where grupo_id = %L$q$, g), 'permission denied');
  perform tests.falla(format($q$insert into estatuto_acuses (grupo_id, version_id, miembro_id, acepta) values (%L, %L, gen_random_uuid(), true)$q$, g, v), 'permission denied');
  perform tests.falla(format($q$select aplicar_version(%L)$q$, v), 'permission denied');

  -- Aislamiento: un extraño no lee políticas ni versiones del grupo
  perform tests.como(solo);
  perform tests.igual(politica(g, 'reservas.dias_max_seguidos'), null::jsonb, 'extraño recibe null');
  perform tests.igual((select count(*)::int from estatuto_versiones where grupo_id = g), 0, 'extraño no ve versiones');
  perform tests.igual((select count(*)::int from grupo_politicas where grupo_id = g), 0, 'extraño no ve políticas');
  perform tests.igual((select count(*)::int from politicas_del_grupo(g)), 0, 'extraño no ve la lista');
  perform tests.como(a);
  perform tests.igual((select count(*)::int from politicas_del_grupo(g)), 32, 'socio ve las 32 políticas');

  -- DF-45: grupo de un solo socio aplica al instante
  perform tests.como(solo);
  g1 := crear_grupo('Solo', 'DOP', 'America/Santo_Domingo', 'SOL', 100);
  v := proponer_cambio_politica(g1, '{"reservas.dias_max_seguidos": null}');
  perform tests.igual((select estado from estatuto_versiones where id = v), 'vigente'::estado_version, 'un solo socio: rige al instante');
  perform tests.igual(politica(g1, 'reservas.dias_max_seguidos'), 'null'::jsonb, 'sin tope de días (null)');

  -- La auditoría registró los acuses y versiones
  perform tests.admin();
  perform tests.igual((select count(*)::int from auditoria where grupo_id = g and tabla = 'estatuto_versiones') > 0, true, 'auditoría de versiones');
end $$;
