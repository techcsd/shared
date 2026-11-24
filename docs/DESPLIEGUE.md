# DESPLIEGUE — Shared

## Entornos (SB6: mismas cuentas, proyecto independiente de SGC/csd-app)
| Entorno | Supabase | Vercel | Datos |
|---|---|---|---|
| **dev** | `shared-dev` (`afjnmhofqsktprrptivl`) | previews (rama `dev` y PRs) | demo (`supabase/seed.sql`) |
| **prod** | `shared-prod` (`mxqbyeohzlawcxfwfivd`) | producción = rama `main` → https://shared-csd.vercel.app | reales, **sin seed** |

Variables por entorno (solo por nombre; valores en `.env.local` y en el panel de Vercel): `NG_APP_SUPABASE_URL`, `NG_APP_SUPABASE_ANON_KEY` (Vercel production → prod; preview/development → dev). **Nunca** el `service_role` en el front. Secrets de edge: `RESEND_API_KEY`, `RESEND_REMITENTE`, `APP_URL`.

## Flujo
`feature/*` → PR a `dev` → Xaviel prueba en el preview → PR `dev` → `main` (producción). **Nada va a producción sin el OK de Xaviel.**

## Pasos para llevar un cambio a producción
1. `node scripts/release-check.mjs --completo` (secrets, migraciones con reversa, marca, i18n, políticas, lint, tests unitarios y SQL, build, CSP).
2. Probar en `dev` (ver `docs/PRUEBA-CON-FELIPE.md`) y, con acceso a `shared-dev`, `E2E_VIVO=1 npx playwright test`.
3. **Base primero, código después** (el código nuevo consulta tablas nuevas):
   ```
   npx supabase link --project-ref <ref prod> --password <SUPABASE_DB_PASSWORD_PROD>
   npx supabase db push --remote --yes
   npx supabase secrets set APP_URL=https://shared-csd.vercel.app --remote=<ref prod> --yes
   npx supabase functions deploy enviar-notificaciones --remote=<ref prod> --use-api --yes
   npx supabase functions deploy guest-view --remote=<ref prod> --use-api --no-verify-jwt --yes
   npx supabase functions deploy exportar-reporte --remote=<ref prod> --use-api --yes
   node scripts/configurar-cron.mjs prod          # solo la primera vez
   npx supabase link --project-ref <ref dev> …    # volver a dejar el repo apuntando a dev
   ```
4. Merge `dev` → `main` (Vercel despliega producción).
5. Verificar: https://shared-csd.vercel.app carga, login, calendario. Mirar «Salud del sistema».

## Reversa
- Código: Vercel → Deployments → promover el anterior (o revert del merge).
- Base: `supabase/migrations/_reversa/<migración>_reversa.sql` (en orden inverso). Algunas reversas **borran datos** (operación, finanzas): úsalas solo en pruebas; en producción preferir una migración correctiva nueva.

## Datos demo vs reales
- Producción no lleva seed. Un grupo de demostración (`modo_demo`) se convierte en real desde Más → Lanzamiento (borra los datos de prueba; nunca se mezclan).
- Primer grupo real: crear el grupo, completar Configuración (activo con capacidad legal certificada, motores con lectura inicial, destinos, tarifas, correos), registrar **capitanes**, póliza de seguro, aceptar el estatuto, y recién entonces la primera salida.

## Dominio y correo
- Resend: verificar dominio y definir `RESEND_REMITENTE`.
- Supabase → Auth → URL Configuration: añadir la URL de producción.
