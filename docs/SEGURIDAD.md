# SEGURIDAD — Shared (revisión del PROMPT-5, 2026-11-24)

## Lo revisado y cómo se comprueba
| Área | Qué se revisó | Evidencia |
|---|---|---|
| **RLS** | Todas las tablas de `public` tienen RLS; `anon` no tiene ningún privilegio; `authenticated` solo escribe directo en las tablas de configuración (y solo por política `es_socio`) y en `eventos_cliente`/`errores_cliente` (insert propio); el resto, solo por RPC | `supabase/tests/16_seguridad_rls.sql` (se rompe si una tabla nueva queda sin RLS) |
| **Aislamiento entre grupos** | Un usuario del grupo B no lee **nada** del grupo A en ninguna tabla con `grupo_id` (consulta dinámica sobre todas) | test 16 §7 |
| **RPC `security definer`** | Todas tienen `search_path` fijo (comprobado en catálogo); validan rol con `coalesce(rol_en(...) in (...), false)` (un `NULL not in` no lanza error); las funciones internas no son ejecutables por clientes | test 16 §4–§6 y tests 06–15 |
| **Funciones públicas** | Ningún rol anónimo ejecuta funciones de negocio (migración 27); `invitado_ver` solo con `service_role` | test 16 §5 |
| **Dinero** | Libro mayor de solo adición (sin UPDATE ni DELETE salvo borrado del grupo o reinicio demo); cada asiento cuadra (constraint trigger diferido); pagos solo cuentan si los confirma el receptor | tests 10, 12 |
| **Tokens** | Invitaciones, mediador y propuestas: dos UUID aleatorios concatenados (≈ 244 bits), solo se guarda el **hash** SHA-256, expiración (invitaciones, invitado), límite de intentos por IP (invitado), respuesta idéntica para inexistente/expirado/ajeno (sin enumeración); el mediador exige además que coincida el correo | tests 02, 06, 14, 16 §8 |
| **Storage** | Bucket `evidencias` privado; políticas por carpeta (`{grupo}/op/…` miembros, `{grupo}/fin/{usuario}/…` socios y quien lo subió, `propuestas/{id}/…` participantes); tamaño máx. 10 MB y tipos limitados (imágenes y PDF); URLs firmadas de 10 min | migraciones 18, 26 |
| **Edge functions** | Validación de entrada (UUID, tamaño de cuerpo ≤ 4 KB), tope de 5.000 filas, CORS restringido a `APP_URL` + localhost, **`service_role` solo en `guest-view` y `enviar-notificaciones`** (nunca en el cliente); `exportar-reporte` corre con el JWT del usuario | `supabase/functions/*`, e2e p4 (403 al admin operativo) |
| **Cabeceras** | CSP estricta (`script-src 'self'`, sin inline), HSTS, X-Frame-Options DENY, nosniff, Referrer-Policy, Permissions-Policy | `vercel.json`; `npm run verify:csp` (la app carga sin violaciones) |
| **Dependencias** | `npm audit --omit=dev`: 0 vulnerabilidades (2026-11-24) | — |
| **Secrets** | `.env.local` fuera de git; ningún patrón de clave en archivos versionados ni **en el historial** (se buscaron las claves reales de `.env.local`) | `node scripts/release-check.mjs` |
| **Cuentas** | Cierre de sesión en todos los dispositivos (Perfil); la caché local (calendario, última orden, cola) se borra al salir | `AuthService`, `OfflineService` |

## Pendiente (ajustes en paneles, no en código)
1. **Supabase → Auth:** activar *Confirm email*, subir la longitud mínima de contraseña (≥ 10) y revisar los límites de *rate limits* (inicios de sesión, OTP, correos). El código ya trata el error de límite como un fallo normal.
2. **CORS de las edge functions:** el secret `APP_URL` debe contener el dominio definitivo (separado por comas si hay varios).
3. **`hawkscan`:** el escáner DAST no estaba disponible en la sesión (sin runtime ni `HAWK_API_KEY`); queda pendiente correrlo contra `shared-dev` cuando exista.
4. **Dominio de Resend:** hasta tener dominio verificado, los correos a terceros fallan (se registran con su motivo, no se pierde nada).
5. **Rotación de claves:** al pasar a datos reales, rotar `service_role` de prod si alguna vez se compartió fuera de `.env.local`.
6. **Revisión legal:** el estatuto y las propuestas de compra no son documentos legales (SC9, SC10): un abogado debe revisar antes de aportar dinero real.

## Qué no hace la app (por diseño)
- No custodia, mueve ni procesa dinero: no hay pasarelas, cuentas ni tarjetas. Los aportes y pagos son **registros** que se confirman entre personas.
- El directorio público está **apagado** (`plataforma_config.directorio_habilitado = false`) y, encendido, muestra solo tipo, precio objetivo, % fondeado y cupos.
