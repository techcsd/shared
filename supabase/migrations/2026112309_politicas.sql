-- 2026-11-23 · 09 · Catálogo de políticas (seed GENERADO), validación y motor politica(grupo, clave)

-- Catálogo: el bloque entre marcadores lo genera scripts/gen-politicas.mjs desde supabase/catalogo/politicas.json.
-- BEGIN:CATALOGO
insert into politicas_catalogo (clave, categoria, tipo, valor_defecto, minimo, maximo, opciones, nullable, df, descripcion, orden) values
  ('derechos_uso', 'reservas', 'enum', '"iguales"'::jsonb, null, null, '["iguales","proporcional","cuota"]'::jsonb, false, 'DF-16', 'Iguales para todos, proporcionales al porcentaje, o con cuota de horas por socio.', 1),
  ('derechos_uso.cuota_horas_mes', 'reservas', 'entero', 'null'::jsonb, 0, 744, null, true, 'DF-16', 'Solo aplica si los derechos son por cuota. Vacío = sin cuota.', 2),
  ('reservas.multi_dia_permitido', 'reservas', 'booleano', 'true'::jsonb, null, null, null, false, 'DF-10', 'Permite reservar más de un día seguido.', 3),
  ('reservas.dias_max_seguidos', 'reservas', 'entero', '3'::jsonb, 1, 365, null, true, 'DF-10', 'Tope por socio. Vacío = sin tope.', 4),
  ('reservas.buffer_horas', 'reservas', 'numero', '0'::jsonb, 0, 48, null, false, 'DF-18', 'Margen bloqueado antes y después de cada salida.', 5),
  ('reservas.acuse_requerido', 'reservas', 'booleano', 'true'::jsonb, null, null, null, false, 'DF-15', 'Los demás socios marcan que vieron la reserva. No es una aprobación.', 6),
  ('reservas.acuse_recordatorio_horas', 'reservas', 'lista', '[24,2]'::jsonb, 1, 168, null, false, 'DF-15', 'Horas antes de la salida en que se recuerda el acuse pendiente.', 7),
  ('reservas.borrador_horas', 'reservas', 'entero', '24'::jsonb, 1, 168, null, false, 'DF-14', 'Cuánto se conserva una reserva sin confirmar.', 8),
  ('cancelacion.horas_sin_cargo', 'cancelacion', 'entero', '48'::jsonb, 0, 720, null, false, 'DF-09', 'Más tarde que esto se registra como cancelación tardía.', 9),
  ('cancelacion.cargo_tardio_pct', 'cancelacion', 'numero', '0'::jsonb, 0, 100, null, false, 'DF-09', 'Porcentaje del fee que se carga a quien cancela tarde.', 10),
  ('capacidad.socio', 'capacidad', 'entero', '15'::jsonb, 1, 1000, null, false, 'DF-17', 'Total a bordo, incluido el socio. El límite legal del activo siempre manda.', 11),
  ('capacidad.invitado', 'capacidad', 'entero', '8'::jsonb, 1, 1000, null, false, 'DF-17', 'Invitado responsable más acompañantes. El límite legal manda.', 12),
  ('tarifa.modelo', 'tarifas', 'enum', '"destino"'::jsonb, null, null, '["destino","hora","ambos"]'::jsonb, false, 'DF-06', 'Cobro por destino, por hora de uso, o ambos.', 13),
  ('tarifa.destino_fee_a', 'tarifas', 'enum', '"fondo"'::jsonb, null, null, '["fondo","socios_proporcional","informativo"]'::jsonb, false, 'DF-07', 'A dónde va el fee del destino.', 14),
  ('combustible.modelo', 'tarifas', 'enum', '"consumido"'::jsonb, null, null, '["consumido","devolver_lleno","incluido"]'::jsonb, false, 'DF-08', 'Se cobra lo consumido, se devuelve lleno, o va incluido en el fee.', 15),
  ('danos.modelo', 'finanzas', 'enum', '"acuerdo"'::jsonb, null, null, '["acuerdo"]'::jsonb, false, 'DF-11', 'Siempre se deciden por acuerdo entre socios; nunca se cobran automáticamente.', 16),
  ('finanzas.modo', 'finanzas', 'enum', '"registro"'::jsonb, null, null, '["registro","estricto"]'::jsonb, false, 'DF-27', 'Registro: se calcula y se muestra, nada bloquea. Estricto: reservado para una fase futura.', 17),
  ('fondo.aporte_mensual', 'finanzas', 'numero', '0'::jsonb, 0, 100000000, null, false, 'DF-24', '0 = apagado.', 18),
  ('administracion.requiere_admin', 'gobierno', 'booleano', 'false'::jsonb, null, null, null, false, 'DF-12', 'Si el grupo opera con un administrador que carga facturas.', 19),
  ('administracion.valida_facturas', 'gobierno', 'enum', '"otro_socio"'::jsonb, null, null, '["otro_socio","cualquier_socio"]'::jsonb, false, 'DF-12', 'Otro socio distinto de quien la cargó, o cualquiera.', 20),
  ('mantenimiento.criterio', 'mantenimiento', 'enum', '"primero"'::jsonb, null, null, '["fecha","horas","primero"]'::jsonb, false, 'DF-13', 'Por fecha, por horas de uso, o lo que ocurra primero.', 21),
  ('temporada_alta.activa', 'temporada', 'booleano', 'false'::jsonb, null, null, null, false, 'DF-19', 'Rota entre socios los periodos de mayor demanda.', 22),
  ('temporada_alta.rotacion', 'temporada', 'enum', '"anual"'::jsonb, null, null, '["anual","ninguna"]'::jsonb, false, 'DF-19', 'Cada año cambia quién elige primero.', 23),
  ('temporada_alta.periodos', 'temporada', 'lista', '["semana_santa","navidad","ano_nuevo"]'::jsonb, null, null, '["semana_santa","navidad","ano_nuevo","verano","otro"]'::jsonb, false, 'DF-19', 'Periodos que entran en la rotación.', 24),
  ('capitanes.licencia_vigente_requerida', 'seguridad', 'booleano', 'true'::jsonb, null, null, null, false, 'DF-20', 'Sin capitán con licencia vigente no se hace el check-in.', 25),
  ('seguro.alerta_dias', 'seguridad', 'lista', '[30,7]'::jsonb, 1, 365, null, false, 'DF-21', 'Días antes del vencimiento en que se avisa.', 26),
  ('seguro.deducible_modelo', 'seguridad', 'enum', '"acuerdo"'::jsonb, null, null, '["acuerdo"]'::jsonb, false, 'DF-21', 'Entra al flujo de daños: se decide por acuerdo.', 27),
  ('seguridad.checklist_salida_obligatorio', 'seguridad', 'booleano', 'true'::jsonb, null, null, null, false, 'DF-22', 'Capitán sobrio, chalecos, menores, clima.', 28),
  ('entrega.checklist_regreso_obligatorio', 'seguridad', 'booleano', 'true'::jsonb, null, null, null, false, 'DF-23', 'Limpio, revisado, combustible.', 29),
  ('salida_socio.preferencia_dias', 'gobierno', 'entero', '30'::jsonb, 0, 365, null, false, 'DF-25', 'Plazo en que los demás socios pueden comprar la parte de quien sale.', 30),
  ('desacuerdos.dias_mediador', 'gobierno', 'entero', '7'::jsonb, 1, 90, null, false, 'DF-26', 'Sin acuerdo directo en este plazo se puede invitar un mediador.', 31),
  ('invitados.enlace_horas_tras_regreso', 'invitados', 'entero', '24'::jsonb, 1, 168, null, false, 'DF-31', 'Después de este plazo el enlace deja de funcionar.', 32);
-- END:CATALOGO

-- Valida un valor contra el catálogo (tipo, rango, opciones). Lanza excepción; devuelve true si es válido.
create function politica_validar(p_clave text, p_valor jsonb) returns boolean
language plpgsql stable set search_path = public, pg_temp as $$
declare
  c politicas_catalogo;
  v_item jsonb;
  v_n numeric;
begin
  select * into c from politicas_catalogo where clave = p_clave;
  if not found then
    raise exception 'politica_desconocida: %', p_clave using errcode = 'invalid_parameter_value';
  end if;
  if p_valor is null or p_valor = 'null'::jsonb then
    if c.nullable then return true; end if;
    raise exception 'politica_invalida: % no admite vacío', p_clave using errcode = 'check_violation';
  end if;
  case c.tipo
    when 'booleano' then
      if jsonb_typeof(p_valor) <> 'boolean' then
        raise exception 'politica_invalida: % debe ser verdadero/falso', p_clave using errcode = 'check_violation';
      end if;
    when 'entero', 'numero' then
      if jsonb_typeof(p_valor) <> 'number' then
        raise exception 'politica_invalida: % debe ser un número', p_clave using errcode = 'check_violation';
      end if;
      v_n := (p_valor #>> '{}')::numeric;
      if c.tipo = 'entero' and v_n <> floor(v_n) then
        raise exception 'politica_invalida: % debe ser entero', p_clave using errcode = 'check_violation';
      end if;
      if (c.minimo is not null and v_n < c.minimo) or (c.maximo is not null and v_n > c.maximo) then
        raise exception 'politica_invalida: % fuera de rango [%, %]', p_clave, c.minimo, c.maximo using errcode = 'check_violation';
      end if;
    when 'enum' then
      if jsonb_typeof(p_valor) <> 'string' or not (c.opciones @> p_valor) then
        raise exception 'politica_invalida: % no es una opción permitida', p_clave using errcode = 'check_violation';
      end if;
    when 'lista' then
      if jsonb_typeof(p_valor) <> 'array' or jsonb_array_length(p_valor) > 20 then
        raise exception 'politica_invalida: % debe ser una lista (máx. 20)', p_clave using errcode = 'check_violation';
      end if;
      for v_item in select * from jsonb_array_elements(p_valor) loop
        if c.opciones is not null then
          if jsonb_typeof(v_item) <> 'string' or not (c.opciones @> v_item) then
            raise exception 'politica_invalida: elemento no permitido en %', p_clave using errcode = 'check_violation';
          end if;
        else
          if jsonb_typeof(v_item) <> 'number' or (v_item #>> '{}')::numeric <> floor((v_item #>> '{}')::numeric)
             or (v_item #>> '{}')::numeric < coalesce(c.minimo, 0) or (v_item #>> '{}')::numeric > coalesce(c.maximo, 1e9) then
            raise exception 'politica_invalida: elemento fuera de rango en %', p_clave using errcode = 'check_violation';
          end if;
        end if;
      end loop;
  end case;
  return true;
end $$;

-- Motor de políticas: valor vigente del grupo, o el DEFAULT del catálogo. Null si el llamador no es miembro.
create function politica(p_grupo uuid, p_clave text) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_valor jsonb; v_def jsonb; v_existe boolean;
begin
  select true, valor_defecto into v_existe, v_def from politicas_catalogo where clave = p_clave;
  if not coalesce(v_existe, false) then
    raise exception 'politica_desconocida: %', p_clave using errcode = 'invalid_parameter_value';
  end if;
  -- auth.uid() null = contexto interno (edge function con service role, pg_cron)
  if auth.uid() is not null and not es_miembro(p_grupo) then
    return null;
  end if;
  select valor into v_valor from grupo_politicas where grupo_id = p_grupo and clave = p_clave;
  if found then return v_valor; end if;
  return v_def;
end $$;

-- Todas las políticas vigentes del grupo (valor + si es el default), para la UI.
create function politicas_del_grupo(p_grupo uuid) returns table (clave text, valor jsonb, es_defecto boolean)
language sql stable security definer set search_path = public, pg_temp as $$
  select c.clave, coalesce(g.valor, c.valor_defecto), g.clave is null
    from politicas_catalogo c
    left join grupo_politicas g on g.clave = c.clave and g.grupo_id = p_grupo
   where es_miembro(p_grupo)
   order by c.orden
$$;

-- Defensa en profundidad: lo que llegue a grupo_politicas siempre pasa por la validación.
create function grupo_politicas_validar() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  perform politica_validar(new.clave, new.valor);
  return new;
end $$;
create trigger grupo_politicas_validar before insert or update on grupo_politicas
  for each row execute function grupo_politicas_validar();

revoke execute on function politica_validar(text, jsonb), politica(uuid, text), politicas_del_grupo(uuid)
  from public, anon;
grant execute on function politica_validar(text, jsonb), politica(uuid, text), politicas_del_grupo(uuid)
  to authenticated, service_role;
