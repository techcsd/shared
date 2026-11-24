-- Formación de grupos: fondeo, conversión exacta (10 aportes desiguales = 100 %), privacidad, directorio apagado, demo → real, salud.
do $$
declare
  u uuid[] := '{}'; ext uuid; adm uuid; i int; v_tipo uuid; pr jsonb; pid uuid; tok text; ap uuid; g uuid; n int; s numeric; j jsonb; r record;
  montos numeric[] := array[1500, 2300, 4100, 800, 9999.99, 3333.33, 1200, 5000, 777.77, 1000.01];
  total numeric := 0; v_ac uuid;
begin
  perform tests.admin();
  for i in 1..10 loop u := u || tests.crear_usuario('pc_' || i || '@test.local', 'P' || i); end loop;
  ext := tests.crear_usuario('pc_ext@test.local', 'Tercero');
  adm := tests.crear_usuario('pc_admin@test.local', 'Admin plataforma');
  select id into v_tipo from tipos_activo where clave = 'carro' and es_sistema;
  select sum(m) into total from unnest(montos) m;

  -- ============ crear, abrir, invitar por enlace
  perform tests.como(u[1]);
  pr := propuesta_crear('Ferrari del grupo', v_tipo, 'Entre todos', total, 'DOP', current_date + 30);
  pid := (pr ->> 'id')::uuid; tok := pr ->> 'token';
  perform tests.igual((select estado from propuestas_compra where id = pid), 'borrador', 'nace borrador');
  perform tests.como(u[2]);
  perform tests.falla(format($q$select propuesta_unirse(%L)$q$, tok), 'propuesta_no_disponible');   -- aún en borrador
  perform tests.como(u[1]);
  perform propuesta_abrir(pid);
  for i in 2..10 loop perform tests.como(u[i]); perform propuesta_unirse(tok); end loop;

  -- ============ un tercero no ve la propuesta (solo vista previa mínima por enlace)
  perform tests.como(ext);
  perform tests.igual((select count(*)::int from propuestas_compra), 0, 'un tercero no ve la propuesta');
  perform tests.igual((select count(*)::int from propuesta_aportes), 0, 'ni los aportes');
  perform tests.igual((propuesta_vista_previa(tok) ->> 'titulo'), 'Ferrari del grupo', 'solo la vista previa por enlace');
  perform tests.falla(format($q$select * from propuesta_totales(%L)$q$, pid), 'sin_permiso');
  perform tests.falla(format($q$select propuesta_aporte_declarar(%L, 100)$q$, pid), 'sin_permiso');

  -- ============ aportes declarados → confirmación manual del organizador; sin custodia
  for i in 1..10 loop
    perform tests.como(u[i]);
    perform propuesta_comprometer(pid, montos[i]);
    ap := propuesta_aporte_declarar(pid, montos[i], 'transferencia ' || i);
    if i > 1 then
      perform tests.falla(format($q$select propuesta_aporte_confirmar(%L)$q$, ap), 'solo_organizador');   -- nadie confirma su propio aporte
    end if;
  end loop;
  perform tests.como(u[1]);
  select confirmado into s from propuesta_totales(pid);
  perform tests.igual(s, 0::numeric, 'declarar no cuenta como confirmado');
  -- el organizador no puede adquirir ni convertir sin lo confirmado
  perform tests.falla(format($q$select propuesta_convertir(%L, 'Grupo Ferrari', 'FER')$q$, pid), 'estado_invalido');
  perform tests.falla(format($q$select propuesta_registrar_adquisicion(%L, 'x')$q$, pid), 'estado_invalido');
  -- confirma todos menos el último: aún no fondeada
  for r in select a.id, a.monto from propuesta_aportes a where a.propuesta_id = pid order by a.monto desc offset 1 loop
    perform propuesta_aporte_confirmar(r.id);
  end loop;
  perform tests.igual((select estado from propuestas_compra where id = pid), 'abierta', 'confirmado < objetivo: sigue abierta');
  -- el último aporte lleva lo confirmado al objetivo → fondeada
  perform propuesta_aporte_confirmar((select id from propuesta_aportes where propuesta_id = pid and estado = 'declarado'));
  perform tests.igual((select estado from propuestas_compra where id = pid), 'fondeada', 'confirmado ≥ precio objetivo: fondeada');
  select precio, confirmado, porcentaje_fondeado into r from propuesta_totales(pid);
  perform tests.igual(r.confirmado, r.precio, 'los totales salen de la base');

  -- ============ adquisición: registro manual con contrato + acuse de TODOS los participantes
  perform tests.falla(format($q$select propuesta_registrar_adquisicion(%L, 'Compré en la agencia')$q$, pid), 'falta_contrato');
  perform propuesta_evidencia_registrar(pid, 'propuestas/' || pid || '/contrato.pdf', 'contrato');
  perform propuesta_registrar_adquisicion(pid, 'Compré en la agencia');
  perform tests.igual((select estado from propuestas_compra where id = pid), 'fondeada', 'falta el acuse de los participantes');
  for i in 2..9 loop perform tests.como(u[i]); perform propuesta_acusar_adquisicion(pid); end loop;
  perform tests.igual((select estado from propuestas_compra where id = pid), 'fondeada', 'con 8 de 10 acuses sigue fondeada');
  perform tests.como(u[10]); perform propuesta_acusar_adquisicion(pid);
  perform tests.igual((select estado from propuestas_compra where id = pid), 'adquirida', 'todos acusaron: adquirida');

  -- ============ conversión en una transacción: porcentajes exactos = aporte / total
  perform tests.como(u[2]);
  perform tests.falla(format($q$select propuesta_convertir(%L, 'X', 'XXX')$q$, pid), 'solo_organizador');
  perform tests.como(u[1]);
  g := propuesta_convertir(pid, 'Grupo Ferrari', 'FER');
  perform tests.admin();
  perform tests.igual((select sum(porcentaje) from miembros where grupo_id = g and rol = 'socio' and estado = 'activo'), 100::numeric, 'la conversión con 10 aportes desiguales suma 100 %');
  perform tests.igual((select count(*)::int from miembros where grupo_id = g), 10, 'diez socios');
  perform tests.igual((select estado::text from grupos where id = g), 'activo', 'grupo activo');
  perform tests.igual((select count(*)::int from activos where grupo_id = g), 1, 'con su activo');
  perform tests.igual((select count(*)::int from estatuto_versiones where grupo_id = g and numero = 1), 1, 'estatuto inicial');
  -- cada porcentaje está a ≤ 0,01 de la proporción exacta
  for i in 1..10 loop
    perform tests.igual(abs((select porcentaje from miembros where grupo_id = g and usuario_id = u[i]) - montos[i] * 100 / total) <= 0.01, true, 'porcentaje del socio ' || i || ' ≈ aporte/total');
  end loop;
  perform tests.igual((select estado from propuestas_compra where id = pid), 'convertida', 'propuesta convertida');
  perform tests.como(u[3]);
  perform tests.igual((select count(*)::int from notificaciones where tipo = 'grupo_creado'), 1, 'los participantes reciben el aviso');
  -- las finanzas del nuevo grupo arrancan en cero (la app no movió dinero)
  perform tests.igual((select count(*)::int from libro_mayor where grupo_id = g), 0, 'sin asientos: no hay dinero en la app');

  -- ============ cancelar no deja grupos huérfanos; reembolso solo registro
  perform tests.como(u[1]);
  pr := propuesta_crear('Otra', v_tipo, null, 1000, 'DOP', null);
  pid := (pr ->> 'id')::uuid; tok := pr ->> 'token';
  perform propuesta_abrir(pid);
  perform tests.como(u[2]); perform propuesta_unirse(tok); ap := propuesta_aporte_declarar(pid, 500);
  perform tests.como(u[1]); perform propuesta_aporte_confirmar(ap);
  perform tests.admin();
  select count(*)::int into n from grupos;
  perform tests.como(u[1]);
  perform tests.falla(format($q$select propuesta_cancelar(%L, '')$q$, pid), 'motivo_requerido');
  perform propuesta_cancelar(pid, 'No se juntó el grupo');
  perform tests.igual((select estado from propuestas_compra where id = pid), 'cancelada', 'cancelada');
  perform tests.admin();
  perform tests.igual((select count(*)::int from grupos), n, 'cancelar no crea ni deja grupos huérfanos');
  perform tests.como(u[1]);
  perform tests.falla(format($q$select propuesta_convertir(%L, 'Z', 'ZZZ')$q$, pid), 'estado_invalido');
  perform propuesta_reembolsar(ap, 'Devuelto por transferencia');
  perform tests.igual((select reembolsado_en is not null from propuesta_aportes where id = ap), true, 'reembolso registrado (solo registro)');
  select confirmado into s from propuesta_totales(pid);
  perform tests.igual(s, 0::numeric, 'lo reembolsado ya no cuenta como confirmado');

  -- ============ directorio: apagado por defecto; con la bandera, datos mínimos y moderación
  perform tests.como(u[1]);
  pr := propuesta_crear('Pública', v_tipo, 'Cualquiera puede ver', 5000, 'DOP', null, 5);
  pid := (pr ->> 'id')::uuid;
  perform propuesta_abrir(pid);
  perform propuesta_directorio_visible(pid, true);
  perform tests.como(ext);
  perform tests.igual(directorio_habilitado(), false, 'el directorio está apagado por defecto');
  perform tests.igual((select count(*)::int from directorio_listar()), 0, 'apagado: no lista nada');
  perform tests.falla(format($q$select directorio_solicitar(%L)$q$, pid), 'directorio_apagado');
  perform tests.admin();
  update plataforma_config set valor = 'true'::jsonb where clave = 'directorio_habilitado';
  insert into plataforma_admins (usuario_id) values (adm);
  perform tests.como(ext);
  perform tests.igual((select count(*)::int from directorio_listar()), 1, 'con la bandera, lista la propuesta abierta y visible');
  select * into r from directorio_listar() limit 1;
  perform tests.igual(r.tipo, 'Carro', 'solo datos mínimos: tipo');
  perform tests.igual(r.cupos_libres, 4, 'cupos libres');
  perform tests.igual((select count(*)::int from propuestas_compra), 0, 'listar no da acceso a la propuesta');
  -- rate limit: 5 solicitudes por hora
  for i in 1..5 loop
    perform tests.como(u[i + 4]);   -- usuarios distintos no se afectan entre sí
  end loop;
  perform tests.como(ext);
  v_ac := directorio_solicitar(pid, 'Quiero entrar');
  perform tests.falla(format($q$select directorio_solicitar(%L)$q$, pid), 'unique');           -- una solicitud pendiente por persona
  perform tests.como(u[1]);
  perform directorio_responder(v_ac, true);
  perform tests.como(ext);
  perform tests.igual((select count(*)::int from propuestas_compra), 1, 'aprobada: ahora es participante');
  -- moderación: reportar y ocultar (solo admin de plataforma)
  perform tests.como(u[3]);
  perform directorio_reportar(pid, 'Parece spam');
  perform tests.falla(format($q$select directorio_ocultar(%L)$q$, pid), 'solo_admin_plataforma');
  perform tests.como(adm);
  perform directorio_ocultar(pid);
  perform tests.como(u[4]);
  perform tests.igual((select count(*)::int from directorio_listar()), 0, 'ocultada: ya no aparece');

  -- ============ salud del sistema: solo admin de plataforma
  perform tests.como(u[1]);
  perform tests.falla($q$select salud_sistema()$q$, 'solo_admin_plataforma');
  perform tests.como(adm);
  j := salud_sistema();
  perform tests.igual(j ? 'errores_24h', true, 'el admin de plataforma ve la salud');
  perform tests.igual((j ->> 'directorio_habilitado')::boolean, true, 'refleja la bandera');
end $$;

-- ============ modo demo → real: exige lo esencial y limpia los datos demo
do $$
declare a uuid; g uuid; v_tipo uuid; act uuid; j jsonb; c1 uuid;
begin
  perform tests.admin();
  a := tests.crear_usuario('dr_a@test.local', 'Ana');
  perform tests.como(a);
  g := crear_grupo('Demo a real', 'DOP', 'America/Santo_Domingo', 'DEM', 100, true);
  select id into v_tipo from tipos_activo where clave = 'bote' and es_sistema;
  act := crear_activo(g, v_tipo, 'Bote real', 12);
  update activos set estado = 'activo' where id = act;
  j := grupo_pasar_a_real(g);
  perform tests.igual((j ->> 'ok')::boolean, false, 'faltan datos: no pasa a real');
  perform tests.igual((j -> 'faltan')::text like '%destinos%', true, 'falta destinos');
  insert into destinos (grupo_id, nombre) values (g, 'Playa');
  insert into tarifas (grupo_id, destino_id, tipo, monto, moneda) select g, id, 'fee_destino', 100, 'DOP' from destinos where grupo_id = g;
  insert into grupo_correos (grupo_id, correo, tipo) values (g, 'ops@test.local', 'ordenes');
  perform gasto_registrar(g, 'comun', 'otros', 100, 'DOP');                 -- dato demo
  j := grupo_pasar_a_real(g);
  perform tests.igual((j ->> 'ok')::boolean, true, 'con lo esencial pasa a real');
  perform tests.admin();
  perform tests.igual((select modo_demo from grupos where id = g), false, 'ya no es demo');
  perform tests.igual((select count(*)::int from gastos where grupo_id = g), 0, 'los datos demo se borraron');
  perform tests.como(a);
  perform tests.falla(format($q$select demo_reiniciar_operacion(%L)$q$, g), 'solo_demo');   -- un grupo real ya no se reinicia
  perform tests.falla(format($q$select grupo_pasar_a_real(%L)$q$, g), 'no_es_demo');
end $$;
