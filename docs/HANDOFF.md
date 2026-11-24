# HANDOFF — Shared (2026-11-23)

## Estado
PROMPT-1 completo en local (F0–F5). Todo verde: build, lint, 17 tests unitarios, 5 archivos de test SQL, e2e smoke, `verify:i18n` (201 claves), `verify:politicas` (32). **Nada commiteado ni desplegado.**

## Hecho en vivo (2026-11-23)
- Proyecto Supabase **shared-dev** (ref `afjnmhofqsktprrptivl`, org Tech CSD, us-east-1) creado y vinculado; 10 migraciones aplicadas; seed demo cargado.
- Prueba viva contra la API real: login de usuarios demo, aislamiento entre grupos, admin operativo sin tarifas ni propuestas, escritura directa denegada, criterio 3→5, activo sin capacidad no se activa. Todo OK.
- Repo privado XavielT/shared, PR #1 abierto contra `dev`.

## Pendiente (físico)
1. `vercel login` y crear el proyecto Vercel `shared` (conectar al repo).
2. `RESEND_API_KEY` y remitente (secrets de edge; en archivo .local).
3. Revisar y mergear el PR #1; datos reales del bote; abogado del estatuto.
4. En Supabase → Auth → URL Configuration: agregar la URL de Vercel cuando exista (hoy solo localhost:4200).

## Cómo probar en dev (cuando exista shared-dev)
1. `npx supabase db push`; para datos demo aplicar `supabase/seed.sql` (solo dev). Usuarios demo `felipe.demo@shared.test` / `xaviel.demo@shared.test`, clave `Demo1234!`.
2. `npm start` → entrar como Felipe → ver «Bote Demo» 50/50 con banner demo.
3. Más → Configuración: ver activo, 2 motores en 0 h, 4 destinos con fee. Crear tipo «Moto acuática» (clonar «Otro», campo Matrícula, componente Horómetro), crear activo, intentar activarlo sin capacidad (debe negarse).
4. Más → Estatuto: cambiar «Máximo de días seguidos» 3→5 como Felipe; entrar como Xaviel y aceptar; comprobar que antes de aceptar sigue 3.
5. Entrar como `socio01.demo…` (grupo de 10 con carro) y verificar que no ve el grupo de Felipe.

## Riesgos / ojo
- El seed para Supabase real (rama con `crypt`/`auth.identities`) **no se pudo probar** (sin Docker); revisar al aplicarlo.
- Tests SQL corren en PGlite, no en Postgres de Supabase: confirmar en `shared-dev`.
- `UPDATE` bloqueado por RLS afecta 0 filas sin error: no asumir éxito en la UI sin comprobar.
- Etiquetas del catálogo de políticas están solo en español (viven en el JSON); `en` pendiente.
- Cambiar % de propiedad tras activar y sumar socios a un grupo activo: bloqueado hasta PROMPT-4 (DF-47).

## Estado de despliegue (2026-11-23, actualización)
- Supabase: `shared-dev` (`afjnmhofqsktprrptivl`, datos demo) y `shared-prod` (`mxqbyeohzlawcxfwfivd`, solo migraciones, sin seed). Ambos con las 10 migraciones y Resend como secret (remitente pendiente: sin dominio verificado).
- Vercel `shared` (equipo CSD): producción → `shared-prod`; preview/development → `shared-dev`. URL pública: https://shared-csd.vercel.app (alias sin nombres; los alias automáticos de Vercel con el slug del equipo existen pero no se usan)
- Repo: https://github.com/techcsd/shared (cuenta techcsd; XavielT colaborador con push). Vercel conectado por git: push a `dev` = preview, push a `main` = producción.
- Si algún deploy por git queda BLOCKED, el autor del commit no mapea a un miembro del equipo Vercel; alternativa: `git archive main` a un temporal, copiar `.vercel` y `vercel deploy --prod --scope xaviel-csd`.

## Pendiente para después (decidido por Xaviel)
- Convertir la cuenta `techcsd` (hoy usuario) en **organización** de GitHub, dejando a `XavielT` como owner antes. Ventajas: varios owners y equipos, secrets de Actions a nivel de org, apps instaladas una vez, auditoría. Es de una sola vía y la cuenta deja de poder iniciar sesión. Se hace desde `techcsd`: Settings → Account → Turn into an organization.
- Dominio verificado de Resend (hoy no hay); edge function de invitaciones por correo.
- Edición de textos: etiquetas del catálogo de políticas solo en español.

## PROMPT-2 (reservas) — estado
- **shared-dev**: migraciones 11–17, edge functions y cron aplicados y probados en vivo.
- **shared-prod**: **pendiente** aplicar migraciones 11–17, desplegar las 2 edge functions y correr `node scripts/configurar-cron.mjs prod`; luego merge `dev` → `main`. No hacerlo al revés (el código nuevo consulta tablas que prod aún no tiene).
- Correo: el pipeline funciona; sin dominio verificado Resend solo entrega al correo propietario de la cuenta (el resto queda `fallido` con su motivo y 1 reintento). Cuando haya dominio: verificar en Resend y poner `RESEND_REMITENTE`.
- `APP_URL` es un secret de edge (por defecto https://shared-csd.vercel.app).
- Probar en dev: reservar con dos usuarios, choque, 911 completo, enlace de invitado (ver informe del PROMPT-2).
