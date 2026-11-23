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
- Vercel `shared` (equipo CSD): producción → `shared-prod`; preview/development → `shared-dev`. URL: https://shared-xaviel-csd.vercel.app
- Repo: https://github.com/techcsd/shared (cuenta techcsd; XavielT colaborador con push). Vercel conectado por git: push a `dev` = preview, push a `main` = producción.
- Si algún deploy por git queda BLOCKED, el autor del commit no mapea a un miembro del equipo Vercel; alternativa: `git archive main` a un temporal, copiar `.vercel` y `vercel deploy --prod --scope xaviel-csd`.
