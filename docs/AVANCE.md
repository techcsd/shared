# AVANCE — Shared

Última actualización: 2026-11-23 (PROMPT-2) · Rama local `feature/f1-scaffold` (**sin commits**: esperan OK de Xaviel).

| Fase | Estado | Evidencia |
|---|---|---|
| P1·F0 Documentación | ✅ | `CLAUDE.md`, `docs/*` |
| P1·F1 Scaffold | ✅ | `npm run build` · `npm test` · `npm run lint` · e2e smoke (2/2) · PWA (manifest + service worker + aviso de actualización) · `vercel.json` · CI en `.github/workflows/ci.yml` |
| P1·F2 Supabase base | ✅ (local) | 10 migraciones aplican limpias; `npm run test:db` (PGlite): constraints, auditoría inmutable, RLS por rol, RPC. aplicado también a **shared-dev** (real) y verificado |
| P1·F3 Auth/grupos/shell | ✅ código · ⚠️ sin prueba viva | login/registro/enlace mágico/recuperar, grupos, invitaciones por enlace, shell con menú inferior, guards por rol, banner demo. Verificado en vivo contra shared-dev (RLS, RPC, estatuto); la UI Angular aún no probada en navegador con login |
| P1·F4 Tipos de activo y configuración | ✅ código · ⚠️ sin prueba viva | migraciones 07–08, seeds (`supabase/seed.sql`), pantalla Configuración (activos, destinos+fees, tipos con editor, grupo, correos) |
| P1·F5 Políticas y estatuto | ✅ | catálogo único (32 políticas), `politica()`, versiones + acuses; test SQL del criterio 3→5; pantalla Estatuto |
| P1·F6 Cierre | ⏳ | falta: commit/PR (esperan OK), probar en `shared-dev` |

## Entorno
Node 22.23 · Angular 21.2 · Supabase CLI por `npx` (3.3.0) · **sin Docker**: tests SQL con PGlite (`@electric-sql/pglite`) · npm necesita `legacy-peer-deps` (`.npmrc`; bug de arborist con `edgesOut`).

## Pendiente
Ver `docs/HANDOFF.md`.

## PROMPT-2 — Reservas
| Fase | Estado | Evidencia |
|---|---|---|
| F0 sincronizar | ✅ | rama `feature/p2-reservas` desde `dev` |
| F1 modelo y reglas en la base | ✅ | migraciones 11–17; `test:db`: 8 archivos (06 reservas, 07 911) |
| F2 calendario | ✅ | mes/semana/día, leyenda, selector de activo, Realtime, bloqueos |
| F3 reservar | ✅ | asistente de 4 pasos; borrador 24 h; fee y límite antes de confirmar |
| F4 notificaciones y acuse | ✅ | outbox + edge `enviar-notificaciones` + pg_cron; acuse y recordatorios 24 h/2 h |
| F5 Prioridad 911 | ✅ | solicitar/aceptar/rechazar/contraproponer/expirar |
| F6 detalle de orden e invitados | ✅ | cronología, enlace `/g/:token` + edge `guest-view` |
| F7 cancelaciones, bloqueos, temporada | ✅ | cargo visible antes de cancelar; pestaña Temporada |
| F8 cierre | ⏳ | falta aplicar a **shared-prod** y merge a `main` (pendiente de OK explícito) |

Evidencia en vivo contra shared-dev: `E2E_VIVO=1 npx playwright test` → 11/11 (asistente en ~1 s automatizado, choque, acuse, 911 completo, carrera concurrente real: 1 gana y 1 falla, capacidad 16/9, invitado).
