# ESTATUTO BASE — Shared (plantilla inicial de un grupo)

> **Aviso:** este texto es un punto de partida redactado con los defaults de Shared (PPT de Felipe + CONTEXTO §4). **No es asesoría legal.** Un abogado debe revisarlo antes de firmarlo. Los acuses dentro de la app **no son firma legal**: son registro de que cada socio vio y aceptó una versión.
> Cada cláusula con **[política: clave]** es configurable por grupo; cambiarla crea una nueva versión del estatuto que rige cuando **todos los socios** la aceptan.

## Partes
El grupo **«{nombre del grupo}»** ({N} socios), propietario(s) del activo **«{nombre del activo}»**, con porcentajes de propiedad: {nombre → %}. Los porcentajes y los nombres son datos del grupo; en el grupo de Felipe son dos socios al 50 / 50.

## Las 5 reglas del PPT
### 1. Reservas: quien confirma primero, usa
- Sin cuotas de días: se asigna por orden de reserva. **[derechos_uso = iguales]**
- Aviso, no permiso: la reserva libre se confirma al instante; los demás socios marcan «Leído y enterado» (no es aprobación). **[reservas.acuse_requerido = true]**
- Nunca dos reservas confirmadas solapadas; se bloquean mantenimiento y preparación. **[reservas.buffer_horas = 0]**
- Datos completos: fecha, salida y regreso, uso (personal, familiar, negocios, invitado), destino, responsable y personas.
- Estados: Borrador · Confirmada · En curso · Finalizada · Cancelada · Bloqueada por mantenimiento. Cada cambio guarda quién y cuándo.
### 2. Prioridad 911: pedir, nunca quitar
Un socio puede **solicitar** una fecha ya reservada, con motivo, urgencia y alternativa. El titular acepta (cambio inmediato), rechaza o contrapropone. Nada se desplaza sin su aceptación; queda historial.
### 3. Capacidad según quién usa el activo
Socio propietario: máximo **15** personas a bordo **[capacidad.socio]**. Invitado: máximo **8** (responsable + 7) **[capacidad.invitado]**. Se registra nombre y correo del invitado y el socio anfitrión. **El límite legal certificado del activo siempre manda.**
### 4. Quién paga qué
- **50/50** (o por porcentaje de propiedad): gastos comunes — mantenimiento y reparaciones generales.
- **100 % individual:** fee del destino + combustible, marina, hielo, tripulación, limpieza, comida; paga quien reservó, aunque invite a un tercero.
- **Daños de una salida:** se registra evidencia y presupuesto y se decide entre socios; **nunca** se cobra automáticamente. **[danos.modelo = acuerdo]**
- Estado de cuenta = cargos individuales + parte de gastos comunes − pagos y abonos (con libro mayor que registra quién adelantó cada gasto).
### 5. Registro de salidas y motores
Antes de salir: fecha/hora real, capitán o responsable, destino, combustible inicial, horómetro inicial de **cada** motor. Al regresar: fecha/hora real, horómetro final de cada motor, combustible, gastos con factura o foto, incidencias. Horas = final − inicial; no se aceptan valores negativos; toda corrección pide motivo.

## Los 12 pendientes del PPT, con su DEFAULT (editables)
| # | Pendiente | DEFAULT aplicado | Política |
|---|---|---|---|
| SA19 | Datos del bote (capacidad legal certificada) | Se cargan en Configuración; sin capacidad no se activa | `activos.capacidad_legal` |
| SA20 | Moneda y tarifa | DOP; fee por destino | `tarifa.modelo = destino` |
| SA21 | Combustible | Se cobra lo consumido | `combustible.modelo = consumido` |
| SA22 | Cancelaciones | Sin cargo hasta 48 h; cargo tardío 0 % | `cancelacion.horas_sin_cargo`, `cancelacion.cargo_tardio_pct` |
| SA23 | Varios días | Permitidos, máx. 3 seguidos | `reservas.multi_dia_permitido`, `reservas.dias_max_seguidos` |
| SA24 | Daños | Siempre por acuerdo | `danos.modelo = acuerdo` |
| SA25 | Administración | Sin capitán/admin; valida el otro socio | `administracion.valida_facturas = otro_socio` |
| SA26 | Mantenimiento preventivo | Fecha u horas, lo que ocurra primero | `mantenimiento.criterio = primero` |
| SC5 | Destino del fee | Fondo común | `tarifa.destino_fee_a = fondo` |
| SA27 | Feriados y temporada alta | Rotación anual, apagada | `temporada_alta.activa = false` |
| SA28 | Quién puede capitanear | Licencia vigente requerida | `capitanes.licencia_vigente_requerida = true` |
| SA29 | Seguro y deducible | Alertas 30 y 7 días; deducible por acuerdo | `seguro.alerta_dias`, `seguro.deducible_modelo` |

## Temas sugeridos por Felipe (SA27–SA34), como políticas apagables
Seguridad a bordo (checklist obligatorio, `seguridad.checklist_salida_obligatorio`) · Entrega del activo (checklist de regreso, `entrega.checklist_regreso_obligatorio`) · Fondo común (aporte mensual 0, `fondo.aporte_mensual`) · Salida o venta de un socio (preferencia de 30 días, `salida_socio.preferencia_dias`) · Desacuerdos (conversación directa; mediador a los 7 días, `desacuerdos.dias_mediador`).

## Catálogo completo de políticas (generado)
<!-- BEGIN:CATALOGO (generado por scripts/gen-politicas.mjs; no editar a mano) -->
| Política | Clave | Defecto | Rango / opciones | DF |
|---|---|---|---|---|
| Derechos de uso | `derechos_uso` | iguales | iguales · proporcional · cuota | DF-16 |
| Cuota de horas al mes | `derechos_uso.cuota_horas_mes` | — | 0–744 | DF-16 |
| Reservas de varios días | `reservas.multi_dia_permitido` | sí | — | DF-10 |
| Máximo de días seguidos | `reservas.dias_max_seguidos` | 3 | 1–365 | DF-10 |
| Horas de preparación | `reservas.buffer_horas` | 0 | 0–48 | DF-18 |
| Pedir «Leído y enterado» | `reservas.acuse_requerido` | sí | — | DF-15 |
| Recordatorios del acuse (horas antes) | `reservas.acuse_recordatorio_horas` | 24, 2 | 1–168 | DF-15 |
| Vida del borrador (horas) | `reservas.borrador_horas` | 24 | 1–168 | DF-14 |
| Cancelación sin cargo (horas antes) | `cancelacion.horas_sin_cargo` | 48 | 0–720 | DF-09 |
| Cargo por cancelación tardía (%) | `cancelacion.cargo_tardio_pct` | 0 | 0–100 | DF-09 |
| Personas máx. (uso de socio) | `capacidad.socio` | 15 | 1–1000 | DF-17 |
| Personas máx. (uso de invitado) | `capacidad.invitado` | 8 | 1–1000 | DF-17 |
| Modelo de tarifa | `tarifa.modelo` | destino | destino · hora · ambos | DF-06 |
| Destino del fee | `tarifa.destino_fee_a` | fondo | fondo · socios_proporcional · informativo | DF-07 |
| Combustible | `combustible.modelo` | consumido | consumido · devolver_lleno · incluido | DF-08 |
| Daños | `danos.modelo` | acuerdo | acuerdo | DF-11 |
| Modo de finanzas | `finanzas.modo` | registro | registro · estricto | DF-27 |
| Aporte mensual al fondo común | `fondo.aporte_mensual` | 0 | 0–100000000 | DF-24 |
| Requiere administrador operativo | `administracion.requiere_admin` | no | — | DF-12 |
| Quién valida las facturas | `administracion.valida_facturas` | otro_socio | otro_socio · cualquier_socio | DF-12 |
| Criterio de mantenimiento | `mantenimiento.criterio` | primero | fecha · horas · primero | DF-13 |
| Temporada alta con rotación | `temporada_alta.activa` | no | — | DF-19 |
| Rotación | `temporada_alta.rotacion` | anual | anual · ninguna | DF-19 |
| Periodos de temporada alta | `temporada_alta.periodos` | semana_santa, navidad, ano_nuevo | semana_santa · navidad · ano_nuevo · verano · otro | DF-19 |
| Exigir licencia vigente al capitán | `capitanes.licencia_vigente_requerida` | sí | — | DF-20 |
| Alertas de vencimiento del seguro (días antes) | `seguro.alerta_dias` | 30, 7 | 1–365 | DF-21 |
| Deducible de un siniestro | `seguro.deducible_modelo` | acuerdo | acuerdo | DF-21 |
| Checklist de salida obligatorio | `seguridad.checklist_salida_obligatorio` | sí | — | DF-22 |
| Checklist de regreso obligatorio | `entrega.checklist_regreso_obligatorio` | sí | — | DF-23 |
| Derecho de preferencia (días) | `salida_socio.preferencia_dias` | 30 | 0–365 | DF-25 |
| Días para invitar un mediador | `desacuerdos.dias_mediador` | 7 | 1–90 | DF-26 |
| Vigencia del enlace de invitado (horas tras el regreso) | `invitados.enlace_horas_tras_regreso` | 24 | 1–168 | DF-31 |
<!-- END:CATALOGO -->

## Firma y revisión
Fecha de aceptación en la app: ______ · Revisión legal por: ______ (pendiente: abogado a definir por Xaviel/Felipe).
