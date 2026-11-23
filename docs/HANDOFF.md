# HANDOFF — Shared (2026-11-23)

## Estado
PROMPT-1 completo en local (F0–F5). Todo verde: build, lint, 17 tests unitarios, 5 archivos de test SQL, e2e smoke, `verify:i18n` (201 claves), `verify:politicas` (32). **Nada commiteado ni desplegado.**

## Lo que Xaviel debe hacer (físico)
1. Crear proyecto Supabase **`shared-dev`** (nuevo, no SGC/x-core). Poner `NG_APP_SUPABASE_URL` y `NG_APP_SUPABASE_ANON_KEY` en `.env.local`. Luego: `npx supabase link --project-ref <ref>` y `npx supabase db push` (migraciones `supabase/migrations/`). En Auth → URL: `http://localhost:4200` y la de Vercel dev.
2. Crear proyecto Vercel `shared` y repo privado GitHub `shared`.
3. `RESEND_API_KEY` y remitente como secrets de edge (aún no hay edge function de correo: las invitaciones son enlaces copiables, DF-48).
4. Dar OK para commit/PR `feature/f1-scaffold` → `dev`.
5. Datos reales del bote (capacidad legal certificada, motores, horómetros) y abogado para el estatuto.

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
