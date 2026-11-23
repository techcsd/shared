-- 2026-11-23 · 04 · Gobierno: catálogo de políticas, políticas por grupo, estatuto, errores, notificaciones

create table politicas_catalogo (
  clave text primary key check (clave ~ '^[a-z0-9_.]+$'),
  categoria text not null,
  tipo text not null check (tipo in ('booleano', 'entero', 'numero', 'enum', 'lista')),
  valor_defecto jsonb not null,
  minimo numeric,
  maximo numeric,
  opciones jsonb,
  nullable boolean not null default false,
  df text,
  descripcion text not null default '',
  orden int not null default 0
);

create table estatuto_versiones (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  numero int not null check (numero > 0),
  estado estado_version not null default 'pendiente',
  cambios jsonb not null check (jsonb_typeof(cambios) = 'object'),
  motivo text check (motivo is null or length(motivo) <= 500),
  propuesta_por uuid references auth.users (id) on delete set null,
  creado_en timestamptz not null default now(),
  vigente_desde timestamptz,
  unique (grupo_id, numero)
);
create unique index estatuto_una_vigente on estatuto_versiones (grupo_id) where estado = 'vigente';
create trigger estatuto_versiones_auditar after insert or update or delete on estatuto_versiones
  for each row execute function auditar();

create table grupo_politicas (
  grupo_id uuid not null references grupos (id) on delete cascade,
  clave text not null references politicas_catalogo (clave),
  valor jsonb not null,
  version_id uuid references estatuto_versiones (id) on delete set null,
  actualizado_en timestamptz not null default now(),
  primary key (grupo_id, clave)
);
create trigger grupo_politicas_auditar after insert or update or delete on grupo_politicas
  for each row execute function auditar('clave');

create table estatuto_acuses (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references grupos (id) on delete cascade,
  version_id uuid not null references estatuto_versiones (id) on delete cascade,
  miembro_id uuid not null references miembros (id) on delete cascade,
  acepta boolean not null,
  momento timestamptz not null default now(),
  unique (version_id, miembro_id)
);
create trigger estatuto_acuses_auditar after insert or update or delete on estatuto_acuses
  for each row execute function auditar();

create table errores_cliente (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid references auth.users (id) on delete set null,
  grupo_id uuid references grupos (id) on delete set null,
  mensaje text not null check (length(mensaje) <= 1000),
  pila text check (pila is null or length(pila) <= 4000),
  ruta text check (ruta is null or length(ruta) <= 300),
  agente text check (agente is null or length(agente) <= 300),
  meta jsonb,
  momento timestamptz not null default now()
);
create index errores_cliente_momento_idx on errores_cliente (momento desc);

create table notificaciones (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid references grupos (id) on delete cascade,
  usuario_id uuid not null references auth.users (id) on delete cascade,
  tipo text not null,
  titulo text not null,
  cuerpo text,
  datos jsonb not null default '{}'::jsonb,
  canal text not null default 'app' check (canal in ('app', 'correo')),
  estado_envio text not null default 'pendiente' check (estado_envio in ('pendiente', 'enviado', 'fallido')),
  motivo_fallo text,
  reintentos int not null default 0 check (reintentos >= 0),
  leida_en timestamptz,
  creado_en timestamptz not null default now()
);
create index notificaciones_usuario_idx on notificaciones (usuario_id, leida_en);
