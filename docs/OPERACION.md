# OPERACIÓN — runbook de Shared

## Dónde mirar
- **Salud del sistema** (Más → Salud del sistema; solo administrador de plataforma): errores del cliente (24 h), cola de correos con su motivo de fallo, reservas por día y mediana del asistente de reserva.
- **Hacer a alguien administrador de plataforma:** `insert into plataforma_admins (usuario_id) values ('<uuid>');` (SQL editor de Supabase; no hay UI a propósito).
- **Cron:** `select cron.job_run_details …` y `select cron_mantenimiento();` (devuelve recordatorios, borradores limpiados, 911 expiradas, aportes del fondo, alertas de mantenimiento, propuestas expiradas y si disparó el envío).

## Si no llegan correos
1. Salud del sistema → «Cola de correos»: ¿hay `fallido`? El motivo se guarda (`notificaciones.motivo_fallo`).
2. Motivo «You can only send testing emails to …»: **no hay dominio verificado en Resend**. Verifica el dominio y define el secret `RESEND_REMITENTE` (p. ej. `Shared <no-responder@tu-dominio>`).
3. Sin filas pendientes pero sin envío: ¿corre el cron? `select * from cron.job;` debe mostrar `shared-mantenimiento` cada minuto. Si no: `node scripts/configurar-cron.mjs dev|prod`.
4. Edge: `npx supabase functions logs enviar-notificaciones` (o el panel). Debe existir el secret `RESEND_API_KEY`.
5. Un correo con reintentos = 2 queda `fallido` definitivo (un único reintento, DF-34).

## Si falla un export (PDF/Excel)
- 403 → quien lo pide no es `socio` (por diseño). 400 → filtros inválidos (UUID). 413 → cuerpo > 4 KB.
- Compara con la pantalla: la cabecera `X-Filas` de la respuesta debe igualar las filas de la tabla.
- Logs: `npx supabase functions logs exportar-reporte`. El tope es 5.000 filas: filtra por fechas.

## Si un enlace (invitado, invitación, mediador, propuesta) no abre
- Respuesta idéntica 404/«no válido» para inexistente, expirado o ajeno (sin enumeración). Causas reales: expiró (invitado: 24 h tras el regreso), ya se usó, el correo de la sesión no coincide con el invitado, o la propuesta ya no está abierta.
- Invitado: `invitado_enlaces` guarda el hash; no se puede «ver» un token. Genera uno nuevo reconfirmando la reserva o creando otro invitado.
- Límite de intentos por IP en `guest-view`: espera o revisa `invitado_intentos`.

## Si dos personas reservan lo mismo
- No puede pasar: la exclusión GiST rechaza el segundo con `horario_ocupado`. Si ocurre, es un bug: abrir incidente con `auditoria`.

## Si los balances no cuadran
- Invariante: `select sum(haber - debe) from libro_mayor where grupo_id = '…'` debe ser **0**. Cada asiento cuadra por constraint. Si no, no confirmar pagos y revisar `auditoria` (`tabla = 'libro_mayor'`).
- Los gastos sin validar cuentan como «provisional»; validar/anular no borra nada (asientos inversos).

## Respaldo y restauración (Supabase)
- **Respaldo:** Supabase hace respaldos diarios del plan; para uno manual: `npx supabase db dump --linked -f respaldo.sql` (esquema+datos; con la contraseña de BD en `SUPABASE_DB_PASSWORD`). Guarda el archivo fuera del repo (contiene datos de personas y finanzas).
- **Storage:** copiar el bucket `evidencias` por separado (panel de Storage o `supabase storage cp -r`); el dump de BD no incluye los archivos.
- **Restaurar:** crear un proyecto vacío, `npx supabase db push` (aplica las migraciones) y luego cargar el dump de datos; o usar el *Point-in-time recovery* del panel si el plan lo incluye. Después correr `node scripts/configurar-cron.mjs <entorno>` (el cron y el Vault no viajan en el dump) y re-desplegar las edge functions y sus secrets.
- Probar la restauración en `dev` antes de necesitarla.

## Mantenimiento rutinario
- Semanal: revisar «Salud del sistema» y fallos de correo.
- Mensual: `npm audit`, revisar políticas de Auth, rotar claves si hubo salidas de personas.
- Antes de cada lanzamiento: `node scripts/release-check.mjs --completo`.

## Panel de administración (`/admin`)
Solo administradores de plataforma (ver «Hacer a alguien administrador» arriba; entrada en Más y en «Mis grupos»).
- **Usuarios:** crear (correo, nombre y contraseña ≥ 8; queda confirmado, sin correo), cambiar contraseña, bloquear/desbloquear (la sesión abierta puede durar hasta 1 h), hacer/quitar admin de plataforma, borrar (con motivos si no se puede; la alternativa es bloquear).
- **Grupos:** lista (estado, activo, miembros, Σ %, movimientos); «Gestionar» permite agregar un usuario existente sin invitación (en un grupo activo con 0 % y luego repartir), repartir porcentajes (deben sumar 100) y quitar miembros (queda como `salido`).
- **Plataforma:** directorio de propuestas (apagado por defecto), enlace a Salud del sistema y las últimas acciones del admin (`admin_acciones`).
- Si algo falla: logs de la función `npx supabase functions logs admin-usuarios`; requiere el secret `APP_URL` para CORS. Para crear al primer admin sigue valiendo el `insert into plataforma_admins` en SQL.
