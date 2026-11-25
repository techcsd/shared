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

## PROMPT-3 — Operación y finanzas
| Fase | Estado | Evidencia |
|---|---|---|
| F0 sincronizar | ✅ | rama `feature/p3-operacion-finanzas` desde `dev` |
| F1 check-in | ✅ | migración 18; pantalla `/operacion/:id`; lecturas por componente, continuidad, checklist obligatorio |
| F2 check-out y cierre | ✅ | migración 20; lista de faltantes; correcciones con motivo; solo se cierra con datos completos |
| F3 gastos | ✅ | pantalla Gastos (menú inferior); validación por otro socio; foto de factura; vencimientos |
| F4 libro mayor y estado de cuenta | ✅ | migración 19; pantalla Finanzas (balances, estado de cuenta con comprobantes, pagos) |
| F5 daños | ✅ | caso + hilo + propuesta + acuerdo unánime (DF-11) |
| F6 fondo común | ✅ | saldo, movimientos, aporte mensual (0 = apagado) |
| F7 modo registro y pruebas de dinero | ✅ | tests 09–12 (2 y 10 socios), e2e vivo del ciclo completo |
| F8 cierre | ⏳ | PR a `dev`; aplicar P2 y P3 a shared-prod pendiente del OK de Xaviel |

Verificación: `npm run test:db` → 12 archivos / 22 migraciones; unitarios 23; `verify:i18n` 579 claves; e2e vivo P3 4/4 contra shared-dev.

## PROMPT-4 — Mantenimiento, seguro, capitanes, reportes y gobierno
| Fase | Estado | Evidencia |
|---|---|---|
| F1 mantenimiento | ✅ | migración 23; pantalla Mantenimiento (menú inferior); tests 13 (horas / fecha / primero) |
| F2 seguro y siniestros | ✅ | pólizas, alertas 30/7, deducible → daños, aviso sin póliza |
| F3 capitanes y licencias | ✅ | licencia vencida bloquea el check-in; e2e vivo |
| F4 admin operativo | ✅ | pruebas de RLS (no cambia políticas, estatuto, daños, 911; no ve finanzas) |
| F5 reportes y exportación | ✅ | dashboard, socio vs socio, estado de cuenta, PDF/Excel (edge); test: total = libro mayor |
| F6 salida/venta de socio | ✅ | casos, ofertas, aceptación unánime, traspaso de %, saldo 0 |
| F7 desacuerdos y mediador | ✅ | mediador a los 7 días, solo lectura del caso, expira al cerrar |
| F8 cierre | ⏳ | PR a `dev`; producción pendiente de OK |

Verificación: `npm run test:db` 14 archivos / 25 migraciones; e2e vivo P4 4/4 contra shared-dev (incluye export xlsx/pdf y 403 del admin operativo).

## PROMPT-5 — Formación de grupos, directorio, demo/real, endurecimiento y lanzamiento
| Fase | Estado | Evidencia |
|---|---|---|
| F1 propuestas de compra | ✅ | migración 26; pantalla Más → Propuestas de compra; test 15 (10 aportes desiguales = 100 %) |
| F2 directorio opcional | ✅ | apagado por defecto; test 15 |
| F3 modo demo y datos reales | ✅ | Más → Lanzamiento; **SA1 medido**: 5 reservas en móvil emulado, promedio 727 ms (automatizado) |
| F4 PWA y rendimiento | ⚠️ parcial | lectura offline + cola (tests unitarios); Lighthouse: ver nota abajo |
| F5 seguridad | ✅ | test 16, CSP verificada, `docs/SEGURIDAD.md`; `hawkscan` no disponible |
| F6 observabilidad | ✅ | Más → Salud del sistema (admin de plataforma), `docs/OPERACION.md` |
| F7 marca y accesibilidad | ✅ | marca solo en `brand.ts` (vigilado por `release-check`); sin rediseño |
| F8 lanzamiento controlado | ✅ | `docs/DESPLIEGUE.md`, `scripts/release-check.mjs`, `docs/PRUEBA-CON-FELIPE.md`, versión 1.0.0-rc.1; **sin desplegar a producción** |
| F9 cierre de la ronda | ✅ | `docs/INFORME-RONDA-1.md` |

Verificación: `npm run test:db` 16 archivos / 27 migraciones; unitarios 28; e2e vivo (smoke, P2–P5) 22/22 contra shared-dev.

**Nota Lighthouse (F4):** NO se pudo medir. Lighthouse 12 contra el Chromium headless de Playwright en Windows devolvió error de protocolo (`Target closed`) y, tras ajustar flags, puntajes 0 que son de la corrida fallida, no del sitio. Queda **pendiente medir en un navegador Chrome real o desde PageSpeed Insights** con la URL de preview. Lo que sí se verificó: PWA instalable (manifest standalone, es), CSP sin violaciones, controles táctiles ≥ 44 px (`min-height: 2.75rem`), etiquetas en todos los campos, foco visible por defecto del navegador.

## Panel de administración de plataforma (2026-11-25)
| Pieza | Estado | Evidencia |
|---|---|---|
| Migración 29 (RPC + bitácora) y 30 (borrado con membresía) | ✅ | test SQL 17_admin_plataforma (no admin denegado en cada RPC, Σ % = 100, borrado seguro, bitácora inmutable) |
| Edge function `admin-usuarios` | ✅ | e2e `admin-vivo`: usuario normal 403; admin crea, agrega, quita, bloquea, borra |
| Pantalla `/admin` (Usuarios · Grupos · Plataforma) | ✅ | lint, build, verify:i18n (895 claves) |

## Tarea C — «Entrar como», acceso total del admin, bienvenida sin grupo (2026-11-25)
| Parte | Estado | Evidencia |
|---|---|---|
| Entrar como | ✅ | edge `admin-usuarios` (impersonar), banner, e2e `admin-entrar-como` |
| Acceso total sin impersonar | ✅ | migración 31; test SQL 18 (lee y configura; no actúa como socio ni toca el libro) |
| Bienvenida sin grupo | ✅ | migración 32, test SQL 19, e2e `bienvenida-vivo` |
| Grupo de Xaviel en prod preparado | ✅ | 5 usuarios demo como socios (30/30/15/15/5/5), Bote Demo 32', destinos, tarifas, correos, capitán y póliza demo; checklist de lanzamiento completo |

## Vitrina del activo
| Pieza | Estado | Evidencia |
|---|---|---|
| Migración 33, test 20, bucket `activos` | ✅ dev y prod | `test:db` 20 archivos |
| `/activo`, tarjeta, avatar, invitación, admin | ✅ | e2e `activo-vitrina` (ícono sin foto, foto tras subirla, invitado ve el activo) |
