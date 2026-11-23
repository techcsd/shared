# AVANCE — Shared

Última actualización: 2026-11-23 · Rama local `feature/f1-scaffold` (**sin commits**: esperan OK de Xaviel).

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
