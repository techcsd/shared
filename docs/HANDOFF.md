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

## PROMPT-3 (operación y finanzas) — estado (2026-11-24)
- **shared-dev**: migraciones 18–22 aplicadas y probadas en vivo (`E2E_VIVO=1 npx playwright test e2e/p3-vivo.spec.ts`, 4/4; reinicia los datos demo de operación/finanzas al empezar y al terminar).
- **shared-prod**: **pendiente** aplicar migraciones 11–22 (P2 + P3) + edge functions + cron; luego merge `dev` → `main`. Orden: base primero, código después.
- Cambia P2: `reserva_iniciar/finalizar` ya no sirven; la salida se inicia/cierra desde `/operacion/:id` (check-in/check-out con datos completos).
- Storage: el bucket privado `evidencias` lo crea la migración 18 (solo si existe el esquema `storage`); fotos de factura/foto de operación se suben desde la app.
- Gancho para P4: `capitan_licencia_ok()` (hoy siempre verdadero) → reemplazar con el registro de capitanes; vínculo `danos_casos.siniestro_id` (sin FK) para el seguro.
- Probar en dev: una salida completa con dos usuarios y comparar los balances con una cuenta a mano (ver informe del PROMPT-3). Botón «Reiniciar datos de prueba de finanzas» en Más → Finanzas (solo grupos demo).
- Datos de prueba de dev: tras `demo_reiniciar_operacion` quedan limpias las tablas de operación/finanzas; las reservas se conservan.

## PROMPT-4 (mantenimiento, seguro, capitanes, reportes y gobierno) — estado (2026-11-24)
- **shared-dev**: migraciones 23–25 y edge `exportar-reporte` desplegadas; e2e vivo 4/4.
- **shared-prod**: pendiente aplicar 23–25 y `exportar-reporte`.
- **Cambia P3:** con la política `capitanes.licencia_vigente_requerida` (por defecto activa) el check-in exige un capitán registrado con licencia vigente. **En un grupo nuevo hay que registrar capitanes (Más → Capitanes) antes de la primera salida.** El seed demo ya los trae.
- **Hueco conocido:** la venta a un tercero (no socio) no está soportada: la salida de socio traspasa a socios existentes; para un comprador externo el caso se cierra por cancelación y se usa el flujo de invitación cuando el estatuto lo permita (PROMPT-5 añade propuestas de compra).
- Mediador: se invita por enlace `/mediar/<token>` (el mediador necesita cuenta con el correo invitado).

## PROMPT-5 (formación, directorio, demo/real, endurecimiento, lanzamiento) — estado (2026-11-24)
- **shared-dev**: migraciones 26–27 y edge functions actualizadas; e2e vivo OK.
- **shared-prod**: pendiente aplicar 23–27 y desplegar `exportar-reporte` y `guest-view` actualizados (ver `docs/DESPLIEGUE.md`). **Nada a producción sin el OK de Xaviel.**
- Informe final de la ronda: `docs/INFORME-RONDA-1.md`.
- Para ver «Salud del sistema» hay que registrarse como administrador de plataforma (`insert into plataforma_admins …`, ver `docs/OPERACION.md`).
- Directorio: apagado (`update plataforma_config set valor = 'true' where clave = 'directorio_habilitado'` para encenderlo).
