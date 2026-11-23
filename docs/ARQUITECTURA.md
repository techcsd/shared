# ARQUITECTURA — Shared

Refinamiento de `docs/origen/CONTEXTO-ACTUALIZACION-1.md §3`. Fecha: 2026-11-23.

## 1. Vista general
```
 Celular / navegador (PWA Angular)
   │  supabase-js (anon key + JWT del usuario)         ┌────────────────────────┐
   ├──────────────────────────────────────────────────►│ Supabase (proyecto     │
   │   REST/RPC · Realtime · Storage                    │ nuevo "shared")        │
   │                                                    │  Postgres + RLS        │
   │   enlaces de invitado /g/:token ─► Edge Function ─►│  Auth · Storage        │
   │                                    (service role)  │  Edge Functions (Deno) │
   │                                                    │  pg_cron               │
 Vercel (hosting SPA, rewrites)                         └───────────┬────────────┘
                                                                    │ Resend (correo, solo desde edge)
```

## 2. Capas
| Capa | Responsabilidad | Regla |
|---|---|---|
| Postgres | Invariantes: solapamientos (GiST), topes de capacidad, lecturas ≥ 0, % de miembros = 100, auditoría inmutable, estados | La UI **nunca** es la única barrera |
| RPC `security definer` | Transiciones de estado, creación de grupos/invitaciones/versiones de estatuto, número de orden atómico | `set search_path = public, pg_temp`; validan `auth.uid()` y rol |
| RLS | Aislamiento por grupo y por rol (`socio`, `admin_operativo`, `capitan`, `mediador`) | En **todas** las tablas; finanzas solo `socio` |
| Edge Functions | Correo (Resend), vista de invitado, exportes PDF/Excel, cron | Único lugar con service role |
| Angular | Presentación, validación previa (espejo de las reglas), UX móvil | Lógica de negocio en servicios; estado con signals |

## 3. Multi-tenencia
Todo cuelga de `grupo_id`. Helpers SQL (`security definer`, `stable`, para evitar recursión de RLS):
- `es_miembro(g uuid) → boolean` — usuario actual es miembro `activo` del grupo.
- `rol_en(g uuid) → rol_miembro` — su rol (o `null`).
- `es_socio(g uuid) → boolean` — `rol_en(g) = 'socio'`.
Un usuario puede estar en varios grupos; el frontend guarda el grupo activo (`GrupoService.grupoActivo` signal + `localStorage`) y lo manda en cada consulta. **El grupo activo del cliente no es una barrera**: RLS decide.

## 4. Frontend
- Angular standalone + signals, rutas **lazy** por página, `ChangeDetection` por defecto (signals), SCSS con variables CSS (`_tokens.scss`), PWA con `@angular/pwa` (service worker + aviso de actualización vía `SwUpdate`).
- `src/app/core`: `brand.ts`, `i18n/` (`t()`, `es.ts`, `en.ts`), `supabase.service.ts`, `error-handler.ts` (global → `errores_cliente`), `conexion.service.ts`, `auth.service.ts`, `grupo.service.ts`, `guards/`.
- Menú inferior: **Calendario · Mis salidas · Gastos · Mantenimiento · Más**. «Más» agrupa el resto. Calendario es `/` (SA15).
- Guards: `authGuard`, `grupoGuard` (hay grupo activo), `rolGuard(['socio'])` para finanzas, `sinAcuerdosGuard` para `admin_operativo`.
- `PoliticaService.valor(clave)` refleja `politica(grupo, clave)` de SQL (catálogo generado desde un único JSON).
- Banner de **modo demo** (DF-40) y aviso de actualización de PWA en el shell.

## 5. Políticas y estatuto
Catálogo único `supabase/catalogo/politicas.json` → genera: migración con la tabla `politicas_catalogo` (seed), `src/app/core/politicas-catalogo.ts` y la tabla de `ESTATUTO-BASE.md`. SQL `politica(grupo, clave)` devuelve el valor de `grupo_politicas` (versión vigente) o el DEFAULT del catálogo. Un cambio crea `estatuto_versiones` (pendiente); cada socio activo la acepta en `estatuto_acuses`; al completarse todos, `aplicar_version()` copia los valores a `grupo_politicas` y marca la versión vigente (la anterior queda `reemplazada`). Acuses = registro, **no firma legal**.

## 6. Auditoría
`auditoria` (append-only): trigger genérico `auditar()` en cada tabla de negocio registra tabla, registro, acción, antes, después, actor (`auth.uid()`), momento y motivo (`set_config('app.motivo', ..., true)` desde el RPC). Un trigger `BEFORE UPDATE/DELETE/TRUNCATE` lanza excepción para **cualquier** rol y se revocan privilegios. Las correcciones son filas nuevas con `motivo` (DF-39).

## 7. Tipos de activo configurables
`tipos_activo.definicion` (jsonb) define campos, componentes con medidor, checklists, categorías de gasto, terminología, prefijo y límites de capacidad. Doble validación: `tipo_activo_validar(jsonb)` en SQL (CHECK) y esquema en la app antes de guardar. Plantillas de sistema `bote`, `carro`, `otro` son inmutables (trigger) y se **clonan**. `activos` solo pasa a `activo` con `capacidad_legal > 0` (CHECK).

## 8. Entornos y despliegue
| Entorno | Supabase | Vercel | Rama |
|---|---|---|---|
| local | Postgres embebido (tests) / `supabase start` si hay Docker | `ng serve` | `feature/*` |
| dev | proyecto `shared-dev` | preview de `dev` | `dev` |
| prod | proyecto `shared-prod` | producción | `main` (solo con OK de Xaviel) |
Variables: `NG_APP_SUPABASE_URL`, `NG_APP_SUPABASE_ANON_KEY` (frontend); `SUPABASE_SERVICE_ROLE_KEY`, `RESEND_API_KEY` solo como secrets de edge. Ver `.env.example`.

## 9. Calidad
Lint (ESLint + Prettier), tests unitarios (Angular/Vitest o Karma según CLI), tests SQL (`supabase/tests/*.sql`, RLS y constraints), smoke e2e (Playwright), GitHub Actions (lint, build, test, test:db). `verify:i18n` y `verify:politicas` en CI.

## 10. Riesgos técnicos asumidos
- Sin Docker local: tests SQL sobre Postgres embebido con un esquema `auth` simulado; equivalencia con Supabase real se confirma en `shared-dev` cuando exista.
- `pg_cron` no existe en Postgres embebido: su `create extension` está protegido y los jobs se crean en migraciones posteriores solo si la extensión está.
