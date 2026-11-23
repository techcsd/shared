-- 2026-11-23 · 07 · Tipos de activo configurables (SB2) con validación en la base

-- Valida la definición JSON de un tipo de activo. Lanza excepción con el motivo; devuelve true si es válida.
create function tipo_activo_validar(def jsonb) returns boolean
language plpgsql immutable set search_path = public, pg_temp as $$
declare
  v_clave text;
  v_claves text[];
  v_item jsonb;
  v_momento text;
  v_permitidas constant text[] :=
    array['campos', 'componentes', 'checklists', 'categorias_gasto', 'terminologia', 'limites_capacidad'];
  k text;
begin
  if def is null or jsonb_typeof(def) <> 'object' then
    raise exception 'tipo_invalido: la definición debe ser un objeto' using errcode = 'check_violation';
  end if;
  for k in select jsonb_object_keys(def) loop
    if not (k = any (v_permitidas)) then
      raise exception 'tipo_invalido: clave desconocida %', k using errcode = 'check_violation';
    end if;
  end loop;

  -- campos personalizados
  if def ? 'campos' then
    if jsonb_typeof(def -> 'campos') <> 'array' or jsonb_array_length(def -> 'campos') > 50 then
      raise exception 'tipo_invalido: campos debe ser un arreglo (máx. 50)' using errcode = 'check_violation';
    end if;
    v_claves := '{}';
    for v_item in select * from jsonb_array_elements(def -> 'campos') loop
      v_clave := v_item ->> 'clave';
      if jsonb_typeof(v_item) <> 'object' or v_clave is null or v_clave !~ '^[a-z][a-z0-9_]{0,39}$' then
        raise exception 'tipo_invalido: clave de campo inválida (%)', v_clave using errcode = 'check_violation';
      end if;
      if v_clave = any (v_claves) then
        raise exception 'tipo_invalido: campo repetido %', v_clave using errcode = 'check_violation';
      end if;
      v_claves := v_claves || v_clave;
      if coalesce(length(trim(v_item ->> 'etiqueta')), 0) not between 1 and 80 then
        raise exception 'tipo_invalido: etiqueta del campo % vacía o muy larga', v_clave using errcode = 'check_violation';
      end if;
      if (v_item ->> 'tipo') is null or (v_item ->> 'tipo') not in ('texto', 'numero', 'fecha', 'booleano', 'opcion') then
        raise exception 'tipo_invalido: tipo de campo inválido en %', v_clave using errcode = 'check_violation';
      end if;
      if v_item ? 'obligatorio' and jsonb_typeof(v_item -> 'obligatorio') <> 'boolean' then
        raise exception 'tipo_invalido: obligatorio debe ser booleano en %', v_clave using errcode = 'check_violation';
      end if;
      if (v_item ->> 'tipo') = 'opcion' and (coalesce(jsonb_typeof(v_item -> 'opciones'), '') <> 'array'
         or jsonb_array_length(v_item -> 'opciones') = 0) then
        raise exception 'tipo_invalido: el campo % necesita opciones', v_clave using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  -- componentes con medidor
  if def ? 'componentes' then
    if jsonb_typeof(def -> 'componentes') <> 'array' or jsonb_array_length(def -> 'componentes') > 20 then
      raise exception 'tipo_invalido: componentes debe ser un arreglo (máx. 20)' using errcode = 'check_violation';
    end if;
    v_claves := '{}';
    for v_item in select * from jsonb_array_elements(def -> 'componentes') loop
      v_clave := v_item ->> 'clave';
      if jsonb_typeof(v_item) <> 'object' or v_clave is null or v_clave !~ '^[a-z][a-z0-9_]{0,39}$' then
        raise exception 'tipo_invalido: clave de componente inválida (%)', v_clave using errcode = 'check_violation';
      end if;
      if v_clave = any (v_claves) then
        raise exception 'tipo_invalido: componente repetido %', v_clave using errcode = 'check_violation';
      end if;
      v_claves := v_claves || v_clave;
      if coalesce(length(trim(v_item ->> 'etiqueta')), 0) not between 1 and 80 then
        raise exception 'tipo_invalido: etiqueta del componente % inválida', v_clave using errcode = 'check_violation';
      end if;
      if coalesce((v_item ->> 'cantidad_defecto')::int, 0) not between 1 and 20 then
        raise exception 'tipo_invalido: cantidad_defecto de % debe estar entre 1 y 20', v_clave using errcode = 'check_violation';
      end if;
      if jsonb_typeof(v_item -> 'medidor') <> 'object'
         or (v_item -> 'medidor' ->> 'tipo') not in ('horometro', 'odometro')
         or coalesce(length(trim(v_item -> 'medidor' ->> 'unidad')), 0) not between 1 and 10 then
        raise exception 'tipo_invalido: medidor inválido en componente %', v_clave using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  -- checklists por momento
  if def ? 'checklists' then
    if jsonb_typeof(def -> 'checklists') <> 'object' then
      raise exception 'tipo_invalido: checklists debe ser un objeto' using errcode = 'check_violation';
    end if;
    for v_momento in select jsonb_object_keys(def -> 'checklists') loop
      if v_momento not in ('salida', 'regreso', 'seguridad') then
        raise exception 'tipo_invalido: momento de checklist desconocido %', v_momento using errcode = 'check_violation';
      end if;
      if jsonb_typeof(def -> 'checklists' -> v_momento) <> 'array' or jsonb_array_length(def -> 'checklists' -> v_momento) > 50 then
        raise exception 'tipo_invalido: checklist % debe ser un arreglo (máx. 50)', v_momento using errcode = 'check_violation';
      end if;
      v_claves := '{}';
      for v_item in select * from jsonb_array_elements(def -> 'checklists' -> v_momento) loop
        v_clave := v_item ->> 'clave';
        if jsonb_typeof(v_item) <> 'object' or v_clave is null or v_clave !~ '^[a-z][a-z0-9_]{0,39}$'
           or coalesce(length(trim(v_item ->> 'texto')), 0) not between 1 and 200
           or (v_item ? 'obligatorio' and jsonb_typeof(v_item -> 'obligatorio') <> 'boolean') then
          raise exception 'tipo_invalido: ítem inválido en checklist % (%)', v_momento, v_clave using errcode = 'check_violation';
        end if;
        if v_clave = any (v_claves) then
          raise exception 'tipo_invalido: ítem repetido % en %', v_clave, v_momento using errcode = 'check_violation';
        end if;
        v_claves := v_claves || v_clave;
      end loop;
    end loop;
  end if;

  -- categorías de gasto
  if def ? 'categorias_gasto' then
    if jsonb_typeof(def -> 'categorias_gasto') <> 'array' or jsonb_array_length(def -> 'categorias_gasto') > 30 then
      raise exception 'tipo_invalido: categorias_gasto debe ser un arreglo (máx. 30)' using errcode = 'check_violation';
    end if;
    for v_item in select * from jsonb_array_elements(def -> 'categorias_gasto') loop
      if jsonb_typeof(v_item) <> 'string' or length(trim(v_item #>> '{}')) not between 1 and 60 then
        raise exception 'tipo_invalido: categoría de gasto inválida' using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  -- terminología
  if def ? 'terminologia' then
    if jsonb_typeof(def -> 'terminologia') <> 'object' then
      raise exception 'tipo_invalido: terminologia debe ser un objeto' using errcode = 'check_violation';
    end if;
    for k in select jsonb_object_keys(def -> 'terminologia') loop
      if jsonb_typeof(def -> 'terminologia' -> k) <> 'string' or length(def -> 'terminologia' ->> k) not between 1 and 60 then
        raise exception 'tipo_invalido: terminología % inválida', k using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  -- límites de capacidad por tipo de uso (SA9)
  if def ? 'limites_capacidad' then
    if jsonb_typeof(def -> 'limites_capacidad') <> 'object' then
      raise exception 'tipo_invalido: limites_capacidad debe ser un objeto' using errcode = 'check_violation';
    end if;
    for k in select jsonb_object_keys(def -> 'limites_capacidad') loop
      if k not in ('socio', 'invitado') then
        raise exception 'tipo_invalido: límite de capacidad desconocido %', k using errcode = 'check_violation';
      end if;
      if jsonb_typeof(def -> 'limites_capacidad' -> k) <> 'number'
         or (def -> 'limites_capacidad' ->> k)::numeric <> floor((def -> 'limites_capacidad' ->> k)::numeric)
         or (def -> 'limites_capacidad' ->> k)::numeric < 1 then
        raise exception 'tipo_invalido: límite % debe ser un entero ≥ 1', k using errcode = 'check_violation';
      end if;
    end loop;
  end if;
  return true;
end $$;

create table tipos_activo (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid references grupos (id) on delete cascade, -- null = plantilla de sistema
  clave text not null check (clave ~ '^[a-z][a-z0-9_]{1,39}$'),
  nombre text not null check (length(trim(nombre)) between 2 and 80),
  es_sistema boolean not null default false,
  clonado_de uuid references tipos_activo (id) on delete set null,
  definicion jsonb not null check (tipo_activo_validar(definicion)),
  prefijo_orden text not null default 'ORD' check (prefijo_orden ~ '^[A-Z]{2,5}$'),
  version int not null default 1,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  check (es_sistema = (grupo_id is null))
);
create unique index tipos_activo_clave_unica
  on tipos_activo (coalesce(grupo_id, '00000000-0000-0000-0000-000000000000'::uuid), clave);
create trigger tipos_activo_actualizado before update on tipos_activo
  for each row execute function set_actualizado_en();
create trigger tipos_activo_auditar after insert or update or delete on tipos_activo
  for each row execute function auditar();

-- Las plantillas de sistema no se editan ni se borran (se clonan).
create function tipos_activo_proteger_sistema() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if old.es_sistema and coalesce(current_setting('app.permitir_sistema', true), '') <> 'on' then
    raise exception 'plantilla_de_sistema_inmutable: clónala para editarla' using errcode = 'insufficient_privilege';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
create trigger tipos_activo_sistema_inmutable before update or delete on tipos_activo
  for each row execute function tipos_activo_proteger_sistema();

-- Plantillas de sistema (DF-29): Bote, Carro, Otro
insert into tipos_activo (grupo_id, clave, nombre, es_sistema, prefijo_orden, definicion) values
(null, 'bote', 'Bote', true, 'BOT', $j$
{
  "campos": [
    {"clave": "matricula", "etiqueta": "Matrícula", "tipo": "texto", "obligatorio": false},
    {"clave": "eslora", "etiqueta": "Eslora", "tipo": "numero", "obligatorio": false, "unidad": "m"},
    {"clave": "marca", "etiqueta": "Marca / modelo", "tipo": "texto", "obligatorio": false}
  ],
  "componentes": [
    {"clave": "motor", "etiqueta": "Motor", "cantidad_defecto": 2, "medidor": {"tipo": "horometro", "unidad": "h"}}
  ],
  "checklists": {
    "salida": [
      {"clave": "capitan_sobrio", "texto": "Capitán o responsable sobrio y con licencia", "obligatorio": true},
      {"clave": "chalecos", "texto": "Chalecos salvavidas para todos a bordo", "obligatorio": true},
      {"clave": "menores", "texto": "Menores con chaleco y acompañados", "obligatorio": true},
      {"clave": "clima", "texto": "Clima y estado del mar revisados", "obligatorio": true}
    ],
    "regreso": [
      {"clave": "limpio", "texto": "Bote limpio", "obligatorio": true},
      {"clave": "revisado", "texto": "Bote revisado (sin daños nuevos)", "obligatorio": true},
      {"clave": "combustible", "texto": "Combustible registrado", "obligatorio": true}
    ],
    "seguridad": [
      {"clave": "extintor", "texto": "Extintor vigente", "obligatorio": true},
      {"clave": "botiquin", "texto": "Botiquín completo", "obligatorio": true},
      {"clave": "bengalas", "texto": "Bengalas y señales", "obligatorio": false}
    ]
  },
  "categorias_gasto": ["combustible", "marina", "hielo", "tripulacion", "limpieza", "comida", "mantenimiento", "reparacion", "seguro", "otros"],
  "terminologia": {"activo": "Bote", "salida": "Salida", "responsable": "Capitán"},
  "limites_capacidad": {"socio": 15, "invitado": 8}
}$j$::jsonb),
(null, 'carro', 'Carro', true, 'CAR', $j$
{
  "campos": [
    {"clave": "placa", "etiqueta": "Placa", "tipo": "texto", "obligatorio": false},
    {"clave": "marca", "etiqueta": "Marca", "tipo": "texto", "obligatorio": false},
    {"clave": "modelo", "etiqueta": "Modelo", "tipo": "texto", "obligatorio": false},
    {"clave": "anio", "etiqueta": "Año", "tipo": "numero", "obligatorio": false}
  ],
  "componentes": [
    {"clave": "odometro", "etiqueta": "Odómetro", "cantidad_defecto": 1, "medidor": {"tipo": "odometro", "unidad": "km"}}
  ],
  "checklists": {
    "salida": [
      {"clave": "licencia", "texto": "Conductor con licencia vigente", "obligatorio": true},
      {"clave": "neumaticos", "texto": "Neumáticos y luces revisados", "obligatorio": true},
      {"clave": "combustible", "texto": "Nivel de combustible registrado", "obligatorio": true}
    ],
    "regreso": [
      {"clave": "limpio", "texto": "Carro limpio", "obligatorio": true},
      {"clave": "sin_danos", "texto": "Sin daños nuevos", "obligatorio": true},
      {"clave": "combustible", "texto": "Combustible registrado", "obligatorio": true}
    ],
    "seguridad": []
  },
  "categorias_gasto": ["combustible", "peaje", "lavado", "parqueo", "mantenimiento", "reparacion", "seguro", "otros"],
  "terminologia": {"activo": "Carro", "salida": "Uso", "responsable": "Conductor"},
  "limites_capacidad": {"socio": 5, "invitado": 4}
}$j$::jsonb),
(null, 'otro', 'Otro', true, 'ORD', $j$
{
  "campos": [],
  "componentes": [],
  "checklists": {"salida": [], "regreso": [], "seguridad": []},
  "categorias_gasto": ["mantenimiento", "reparacion", "seguro", "otros"],
  "terminologia": {"activo": "Activo", "salida": "Uso", "responsable": "Responsable"},
  "limites_capacidad": {"socio": 10, "invitado": 5}
}$j$::jsonb);
