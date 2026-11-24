# DECISIONES — Shared (Regla A: aplicado por defecto)

Fecha de todas: **2026-11-23**. Estado: «aplicado por defecto» = nadie lo ha rechazado; cambiar uno es cambiar una **política configurable**, no código. Fuente: `docs/origen/CONTEXTO-ACTUALIZACION-1.md §4`.

| ID | Tema (nota) | DEFAULT | Estado |
|---|---|---|---|
| DF-01 | Cuentas (SB6) | Proyecto Supabase nuevo `shared`; Vercel nuevo `shared`; mismas cuentas; sin vínculo con SGC/csd-app | aplicado por defecto |
| DF-02 | Marca (SB7) | `Shared`; un solo archivo `src/app/core/brand.ts` + manifest | aplicado por defecto |
| DF-03 | Idioma (SA15) | `es` base; claves `en`; sin `ht` | aplicado por defecto |
| DF-04 | Zona horaria | `America/Santo_Domingo` por grupo; `timestamptz` | aplicado por defecto |
| DF-05 | Moneda (SA20) | Por grupo, default DOP; USD permitido; cada monto guarda moneda y tasa del día | aplicado por defecto |
| DF-06 | Modelo de tarifa (SA20) | Por destino (fee fijo); «hora» y «ambos» por política; fee 0 hasta configurar | aplicado por defecto |
| DF-07 | Destino del fee (SC5) | Fondo común (alt.: socios proporcional / informativo) | aplicado por defecto |
| DF-08 | Combustible (SA21) | Se cobra lo consumido al que reservó | aplicado por defecto |
| DF-09 | Cancelaciones (SA22) | Sin cargo hasta 48 h; tardía = «cancelación tardía», cargo 0 % | aplicado por defecto |
| DF-10 | Varios días (SA23) | Permitidos; máx. 3 días seguidos (`null` = sin tope) | aplicado por defecto |
| DF-11 | Daños (SA12, SA24) | Siempre acuerdo entre socios; jamás automático | aplicado por defecto |
| DF-12 | Administración (SA25) | Sin capitán/admin al inicio; valida el otro socio | aplicado por defecto |
| DF-13 | Mantenimiento (SA26) | Fecha u horas, lo que ocurra primero | aplicado por defecto |
| DF-14 | Borrador (SC6) | Solo mientras el asistente no se confirma (24 h); confirmar es instantáneo | aplicado por defecto |
| DF-15 | Acuse (SA3) | Lo marcan los demás socios; no bloquea; recordatorio 24 h y 2 h | aplicado por defecto |
| DF-16 | Derechos de uso (SA1, SA4) | Iguales, sin cuotas (alt.: proporcional / cuota) | aplicado por defecto |
| DF-17 | Capacidad (SA9) | Socio 15, invitado 8 (1+7); `min(límite, capacidad legal)`; sin capacidad legal no se activa | aplicado por defecto |
| DF-18 | Preparación (SA5) | Buffer 0 h antes/después, configurable | aplicado por defecto |
| DF-19 | Feriados (SA27) | `temporada_alta` con rotación anual; apagada hasta aceptarla | aplicado por defecto |
| DF-20 | Capitanes (SA28) | Licencia y vencimiento; sin capitán con licencia vigente no hay check-in | aplicado por defecto |
| DF-21 | Seguro y deducible (SA29) | Alertas 30 y 7 días; deducible entra al flujo de daños (acuerdo) | aplicado por defecto |
| DF-22 | Seguridad (SA30) | Checklist de salida obligatorio | aplicado por defecto |
| DF-23 | Entrega (SA31) | Checklist de regreso obligatorio | aplicado por defecto |
| DF-24 | Fondo común (SA32) | Aporte mensual 0 (apagado); fees entran aquí | aplicado por defecto |
| DF-25 | Salida/venta (SA33) | Preferencia 30 días; valoración documentada; la app no mueve dinero | aplicado por defecto |
| DF-26 | Desacuerdos (SA34) | Hilo directo; a los 7 días se puede invitar mediador | aplicado por defecto |
| DF-27 | Finanzas (SB3) | Modo `registro`: sin bloqueos, sin pasarelas | aplicado por defecto |
| DF-28 | Formación de grupos (SC10) | Sin custodia; aportes a mano; privadas por enlace; directorio opt-in apagado | aplicado por defecto |
| DF-29 | Tipos de activo (SB2) | Plantillas de sistema Bote, Carro, Otro (no editables, clonables) | aplicado por defecto |
| DF-30 | Estatuto (SA35, SC9) | Versionado; rige cuando **todos** los socios aceptan; acuses ≠ firma legal | aplicado por defecto |
| DF-31 | Invitados (SC8) | Sin cuenta; enlace firmado, expira 24 h tras el regreso, solo lectura | aplicado por defecto |
| DF-32 | Número de orden (SA2) | `{PREFIJO}-{AAAA}-{NNNN}` por grupo y año (`BOT`,`CAR`,`ORD`) | aplicado por defecto |
| DF-33 | Exportación (SA18) | PDF y Excel en edge; tope 5.000 filas | aplicado por defecto |
| DF-34 | Notificaciones | Correo (Resend) + in-app; push apagado; fallo = registro con motivo + 1 reintento | aplicado por defecto |
| DF-35 | Visual | Funcional sin ornamento hasta mock aprobado | aplicado por defecto |
| DF-36 | Roles (SA16) | `socio`, `admin_operativo`, `capitan`, `mediador`, `invitado` (sin cuenta) | aplicado por defecto |
| DF-37 | Datos del bote (SA19) | «Bote Demo» (cap. 15, 2 motores en 0 h) solo en modo demo | aplicado por defecto |
| DF-38 | Auth | Correo + contraseña y enlace mágico; alta de socios por invitación | aplicado por defecto |
| DF-39 | Auditoría | Inmutable; correcciones = filas nuevas con `motivo` | aplicado por defecto |
| DF-40 | Modo demo (SA35) | `modo_demo` por grupo: banner, datos demo, reinicio | aplicado por defecto |

## Decisiones técnicas adicionales de esta ronda (propias de P1; Regla A)
| ID | Decisión | Por qué | Estado |
|---|---|---|---|
| DF-41 | Migraciones nombradas `AAAAMMDDNN_tema.sql` (p. ej. `2026112301_extensiones.sql`) en vez de `2026-11-23_NN_tema.sql` | El CLI de Supabase exige prefijo numérico único y **ignora** nombres con guiones; el sufijo `NN` conserva fecha + orden | aplicado por defecto (**desvío menor del prompt, reportado**) |
| DF-42 | Tests SQL en `supabase/tests/*.sql` (plain SQL con `DO`/`raise`), ejecutables con `supabase test db` **y** con `npm run test:db` sobre Postgres embebido | No hay Docker en el equipo; pgTAP no disponible en embebido | aplicado por defecto |
| DF-43 | Catálogo de políticas en `supabase/catalogo/politicas.json` → genera migración seed, TS y tabla del estatuto; `verify:politicas` evita deriva | Una sola fuente de verdad SQL/Angular | aplicado por defecto |
| DF-44 | `estado_grupo` = `formacion` → `activo` (automático cuando Σ % socios = 100) → `archivado` | El 50/50 de dos socios no puede estar «activo» hasta que el segundo acepte | aplicado por defecto |
| DF-45 | Un grupo con un solo socio activo aplica sus cambios de política al instante (el proponente es «todos los socios») | Evita bloquear grupos nuevos/demo | aplicado por defecto |
| DF-46 | `porcentaje` visible a todo miembro; finanzas (libro mayor) solo `socio` | Es dato de gobierno, no contabilidad | aplicado por defecto |
| DF-47 | Edición de `porcentaje` tras activar: bloqueada hasta PROMPT-4 (RPC con propuesta y acuses) | Cambiar propiedad es cambiar el estatuto | aplicado por defecto |
| DF-48 | Invitación por enlace copiable en UI; envío por correo vía edge function + Resend queda listo pero **requiere** `RESEND_API_KEY` de Xaviel | Pendiente físico | aplicado por defecto |

## Decisiones técnicas del PROMPT-2 (Regla A; 2026-11-23)
| ID | Decisión | Por qué | Estado |
|---|---|---|---|
| DF-49 | Los bloqueos de mantenimiento/preparación son filas de `reservas` (`estado = bloqueada_mantenimiento`, `tipo_bloqueo`) | Una exclusión GiST no puede cruzar dos tablas; así «nunca dos cosas se solapan» es una sola regla | aplicado por defecto |
| DF-50 | `rango_bloqueo` = rango + `buffer_horas/2` por cada lado; la exclusión usa ese rango | Con buffer B queda un hueco mínimo de B horas entre salidas (DF-18) | aplicado por defecto |
| DF-51 | `proporcional` = tope de horas del mes = % del socio × horas del mes; `cuota` = `derechos_uso.cuota_horas_mes` | El PPT no define «proporcional»; esta es la lectura más simple y es política | aplicado por defecto |
| DF-52 | Temporada alta: el socio con prioridad (rota por año y periodo) reserva solo hasta 14 días antes de que empiece; después queda libre | «Los demás pueden reservar en su turno» es ambiguo; apagada por defecto | aplicado por defecto |
| DF-53 | Solicitud 911: el aviso va a todos los socios; solo el titular decide; vigencia `prioridad_911.expira_horas` (72 h) y expirar nunca toca la reserva | SA8 | aplicado por defecto |
| DF-54 | Aceptar una 911 cancela la reserva del titular y crea la del solicitante en la misma transacción (sin cargo de cancelación tardía) | «Cede la reserva» | aplicado por defecto |
| DF-55 | Orden `{PREFIJO}-{AAAA}-{NNNN}`: el año es el de la confirmación en la zona del grupo; contador atómico por grupo y año | DF-32 | aplicado por defecto |
| DF-56 | Costos de una reserva (`reserva_costos`) solo visibles a socios; el invitado y el admin operativo no ven tarifas | SA16 | aplicado por defecto |
| DF-57 | Correos de invitado: el token en claro vive solo en la cola de salida hasta enviarse y se borra al enviar; la cola de invitados no es legible por ningún cliente | SC8 | aplicado por defecto |
| DF-58 | Las políticas nuevas de cada fase van en su propia migración (upsert) generada desde el mismo JSON (`fase`); nunca se edita una migración ya aplicada | Migraciones aditivas | aplicado por defecto |

## Decisiones técnicas del PROMPT-3 (Regla A; 2026-11-24)
| ID | Decisión | Por qué | Estado |
|---|---|---|---|
| DF-59 | Lecturas, checklists, combustible, incidencias y libro mayor son **solo adición**: corregir = fila nueva con `motivo` (trigger `solo_adicion`); el valor vigente es la última fila (vistas `lecturas_vigentes`, `checklist_vigente`) | DF-39 y SA14 «toda corrección pide motivo» | aplicado por defecto |
| DF-60 | `reserva_iniciar`/`reserva_finalizar` (P2) ya no existen como atajos: la orden solo avanza por `checkin_registrar` / `checkout_registrar`, y un trigger impide `en_curso` sin check-in y `finalizada` sin cierre completo | SA14: «la orden solo se cierra con los datos completos» | aplicado por defecto (**cambia P2**) |
| DF-61 | Check-in y check-out devuelven `{ok, faltan[]}` (qué falta) en lugar de un error genérico; el check-in no escribe nada si falta algo, el check-out guarda lo enviado y solo cierra si no falta nada | Pedido del PROMPT-3 F2.4 | aplicado por defecto |
| DF-62 | Libro mayor de partida doble: cada asiento cuadra (constraint trigger diferido) y **Σ miembros + fondo + terceros = 0**; mientras no haya «externo» (todo lo pagan miembros o el fondo) **Σ miembros + fondo = 0**, que es el invariante del prompt | «Crédito a quien pagó (miembro, fondo o externo)» obliga a una tercera cuenta si un tercero adelanta | aplicado por defecto (**refina el invariante**, ver informe) |
| DF-63 | Saldo del fondo = lo que se le debe al fondo (una cuenta más); el fee del destino lo carga a quien reservó y lo acredita al fondo, a los demás socios en proporción o a nadie (`tarifa.destino_fee_a`) | DF-07 | aplicado por defecto |
| DF-64 | Combustible (`combustible.modelo`): `consumido` y `devolver_lleno` cargan el gasto de combustible a quien reservó (con `devolver_lleno` además se abre una incidencia si el nivel final es menor al inicial, sin cargo); `incluido` lo absorbe el fondo | DF-08 | aplicado por defecto |
| DF-65 | Reparto exacto por centavos: mayor resto, luego mayor porcentaje, luego id (`repartir_pesos`); la suma de débitos = el gasto, siempre | Invariante (e) | aplicado por defecto |
| DF-66 | Gasto no validado = «provisional»: se asienta al registrarse y el balance separa confirmado/provisional; disputar o anular no borra nada (asiento inverso con motivo) | SA: «se ve y se suma como provisional» | aplicado por defecto |
| DF-67 | Validar facturas: un socio distinto de quien la cargó (`administracion.valida_facturas = otro_socio`); `cualquier_socio` lo relaja; el admin operativo nunca valida ni decide acuerdos | DF-12, SA16 | aplicado por defecto |
| DF-68 | Un pago entre socios o al fondo solo toca los balances cuando lo **confirma el receptor** (al fondo: otro socio); rechazado = sin asientos | SB3 modo registro, SA13 | aplicado por defecto |
| DF-69 | Daños: caso con hilo, presupuesto y propuesta de reparto por socio; cada propuesta nueva reinicia los acuerdos (versión); quien propone queda de acuerdo; **no hay cargos hasta que todos los socios activos acepten**; un rechazo frena el caso | DF-11 | aplicado por defecto |
| DF-70 | Aporte mensual al fondo = monto total del grupo repartido por porcentaje; idempotente por mes; lo genera `cron_mantenimiento` (reemplazada con `create or replace` en la migración 20) o un socio a mano | DF-24 | aplicado por defecto |
| DF-71 | Evidencias (fotos, facturas, comprobantes) en Storage privado `evidencias`: `{grupo}/op/…` visible a miembros, `{grupo}/fin/{usuario}/…` solo a socios y a quien lo subió | SA16 | aplicado por defecto |
| DF-72 | El registro de capitanes llega en el PROMPT-4: `capitan_licencia_ok()` es un gancho que hoy devuelve verdadero (tolerancia pedida); P4 lo reemplaza | DF-20 | aplicado por defecto |
| DF-73 | `finanzas.modo`: hoy solo `registro` tiene comportamiento (nada bloquea); `estricto` queda como valor reservado con el helper `finanzas_modo()` | DF-27 | aplicado por defecto |
| DF-74 | `demo_reiniciar_operacion(grupo)`: borra gastos, libro, pagos, daños y operaciones solo si el grupo es de demostración (el libro mayor tiene el borrado prohibido salvo dentro de esta función) | DF-40; permite repetir pruebas en dev | aplicado por defecto |
