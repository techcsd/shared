# CONTEXTO-ACTUALIZACIÓN-1 — Ronda 23-nov-2026 (IDs SA1–SA35, SB1–SB10, SC1–SC10) — SHARED

Carpeta: `C:\developer\shared improvements\noviembre 2026\imp 23112026\`
Repo (vacío al escribir esto): `C:\Users\xavie\Desktop\X Dev\dev\shared`
Fuente: `Bote_Compartido_Estatuto_y_App.pptx` (Felipe, v1.0, 18-nov-2026, 18 láminas) + descripción original del proyecto + respuestas de Xaviel en esta sesión.
**Numeración de Shared (empieza de cero, independiente de SGC/csd-app):** contexto **1** · prompts **1–5** · IDs **SA** (PPT), **SB** (decisiones de Xaviel), **SC** (hallazgos) · fila de cobertura **1+**.

---

## §0 Estado real (leído, no supuesto)

| | Shared |
|---|---|
| Carpeta del repo | `C:\Users\xavie\Desktop\X Dev\dev\shared` — **existe y está vacía** (0 entradas). No hay `git init`, ni `package.json`, ni `CLAUDE.md`. |
| Carpeta de mejoras | `C:\developer\shared improvements\` — existe; esta es su primera ronda. |
| Referencia de formato | `C:\developer\improvements\` (SGC + csd-app): carpeta por mes → `imp DDMMYYYY` → `CONTEXTO-ACTUALIZACION-N.md`, `PROMPT-N-*.md`, `PLAN.md`, `COBERTURA-NOTAS.md`; `INICIO-SESION.md` en la raíz. Reglas A y B. Ya replicado aquí. |
| Cuentas | Vercel y Supabase **existentes** (las mismas de Xaviel), pero Shared va como **proyecto distinto**: no se liga a SGC ni a csd-app (SB6). |
| Estado del producto | Nada construido. Primero documentación y arquitectura (preferencia de Xaviel: planeación → arquitectura → documentación → implementación progresiva). |

**Consecuencia:** el primer paso de Claude Code no es código. Es `F0` del PROMPT-1: escribir `CLAUDE.md` y `docs/` con lo que está aquí, y solo entonces `F1` (scaffold).

---

## §1 Notas, literales

### A. El PPT de Felipe (lámina por lámina; ninguna se pierde)

**L1 · Portada.** «Bote Compartido: estatuto de uso y aplicación de gestión — Propuesta para revisión del socio · Versión 1.0 · 18 de noviembre de 2026. Documento de trabajo: cada regla está abierta a cambios, y al final hay espacio para tus propuestas.»

**L2 · Qué buscamos.** **SA1** «< 1 min para reservar el bote desde el celular · 2 socios con exactamente los mismos derechos · 50 / 50 en mantenimiento y reparaciones generales. Reglas claras + una aplicación que las hace cumplir. Quien reserva primero, usa; cada uno paga lo que usa; lo común se divide a mitad; y todo queda registrado para evitar malentendidos entre los dos.»

**L3 · Cómo funciona una salida.** **SA2** «1. Reservar: elijo fecha, horario, destino, personas y responsable. Veo el fee estimado. 2. Notificar: se genera la orden (BOT-2026-0001) y el otro socio marca "Leído y enterado". 3. Salir: check-in: capitán, combustible y horómetro inicial de cada motor. 4. Regresar: check-out: lecturas finales, combustible, gastos, fotos e incidencias. 5. Liquidar: se calculan cargos y se actualiza el estado de cuenta de cada socio. Si la fecha ya está ocupada, el paso 1 ofrece la "Prioridad 911" (ver estatuto 2).»

**L4 · Estatuto propuesto.** «Cinco reglas base para usar el bote sin fricciones. Revisa cada una y anota qué cambiarías.»

**L5 · Estatuto 1 · Reservas: quien confirma primero, usa.**
- **SA4** «Sin cuotas de días: no hay un mínimo ni máximo mensual: se asigna por orden de reserva.»
- **SA3** «Aviso, no permiso: la reserva libre se confirma al instante. El otro socio marca "Leído y enterado", que NO es una aprobación.»
- **SA5** «Sin choques: nunca dos reservas confirmadas que se solapen; también se bloquean días de mantenimiento y preparación.»
- **SA6** «Datos completos: fecha, salida y regreso, uso (personal, familiar, negocios, invitado), destino, responsable y personas.»
- **SA7** «Estados de una reserva: Borrador · Confirmada · En curso · Finalizada · Cancelada · Bloqueada por mantenimiento. Cada cambio guarda quién lo hizo y cuándo.»

**L6 · Estatuto 2 · Prioridad 911: pedir, nunca quitar.** **SA8** «Socio B solicita: fecha ya reservada por A. Indica motivo (cumpleaños, evento familiar, cliente, negocio), urgencia y alternativa. Socio A decide: dentro de la app. Mientras no acepte, su reserva sigue vigente. Acepta ceder → cambio inmediato; avisa a ambos. Rechaza → se mantiene la reserva de A. Contrapropone → ofrece otra fecha u horario. La 911 no cancela ni desplaza automáticamente a nadie. Es una petición entre socios. Queda historial de mensajes, decisiones y horas, y la app impide cambios unilaterales o reservas duplicadas.»

**L7 · Estatuto 3 · Capacidad según quién usa el bote.** **SA9** «Uso de un socio propietario: 15 personas como máximo — total a bordo, incluido el socio, siempre que la capacidad certificada del bote no sea menor. Uso por un invitado: 8 personas como máximo — invitado responsable + hasta 7 acompañantes. Se registra nombre y email del invitado y el socio anfitrión. La app muestra el límite antes de confirmar y no deja pasarse. El límite legal de la embarcación siempre manda sobre estos números.»

**L8 · Estatuto 4 · Quién paga qué.**
- **SA10** «50/50 Gastos comunes: mantenimiento y reparaciones generales del bote: servicio, proveedor, factura y vencimiento.»
- **SA11** «100% Uso individual: fee del destino + combustible, marina, hielo, tripulación, limpieza, comida. Paga quien reservó, aunque invite a un tercero.»
- **SA12** «En revisión · Daños de una salida: se registra evidencia y presupuesto; se decide entre socios. Nunca se cobra automáticamente.»
- **SA13** «Estado de cuenta de cada socio = cargos individuales + 50 % de gastos comunes − pagos y abonos.»

**L9 · Estatuto 5 · Registro de salidas y motores.** **SA14** «Antes de salir: fecha y hora real de salida · capitán o responsable a bordo · destino confirmado · combustible inicial · horómetro inicial de CADA motor. Al regresar: fecha y hora real de regreso · horómetro final de CADA motor · combustible agregado / consumido · gastos con factura o foto · incidencias y observaciones. Horas por motor = lectura final − lectura inicial. No se aceptan valores negativos; toda corrección pide motivo. La orden solo se cierra con los datos completos.»

**L10 · La aplicación.** **SA15** «Web para el celular, en español, con el calendario como pantalla principal.»

**L11 · Quién entra y qué puede ver.** **SA16** «Socio 1 y Socio 2: mismas facultades: reservar, registrar uso y gastos, responder prioridades y ver balances. Solo ellos ven finanzas. Administrador operativo (opcional): registra horómetros, combustible, facturas y reparaciones. No puede cambiar acuerdos entre socios. Invitado: recibe por email fecha, horario, punto de encuentro, reglas y contacto. No ve tarifas ni datos del otro socio. Capitán / encargado (futuro): se podrá agregar más adelante, con acceso limitado a la operación del bote.»

**L12 · Las ocho pantallas.** **SA17** «Calendario (disponible, mío, del socio y mantenimiento) · Reservar (pocos pasos, destino y fee estimado) · Detalle de orden (cronología, avisos, costos y archivos) · Prioridad 911 (solicitud, respuesta e historial) · Operación (salida, regreso, motores y gastos) · Finanzas (cargos, 50/50, pagos y balances) · Mantenimiento (tareas, servicios, facturas y alertas) · Configuración (bote, motores, destinos, tarifas, correos). Menú inferior: Calendario · Mis salidas · Gastos · Mantenimiento · Más.»

**L13 · Reportes.** **SA18** «Dashboard mensual y anual: salidas, días usados, duración, horas por motor, combustible, fees, daños y saldo de cada socio. Socio 1 vs Socio 2: comparativo de frecuencia de uso y costo, total del bote y tendencia mes a mes. Estado de cuenta: detalle de cargos, mitad de comunes y pagos, con sus comprobantes adjuntos. Exportar: PDF y Excel, filtrando por fecha, socio, destino, tipo de salida y estado. Las estadísticas no limitan reservas. Sirven para que los dos veamos lo mismo, con los mismos números, y conversemos sobre datos y no sobre impresiones.»

**L14 · Para decidir juntos.** «Puntos abiertos y temas nuevos para el estatuto. Escribe tu propuesta en la última columna.»

**L15 · Pendientes (1 de 2).**
- **SA19** «Datos del bote: nombre, capacidad legal certificada, número de motores y lecturas iniciales de horómetro.»
- **SA20** «Tarifas y moneda: destinos finales (playa, pesca, La Romana, otros) y fee de cada uno. ¿RD$ o US$? ¿Por destino, por hora o ambos?»
- **SA21** «Combustible: ¿se devuelve el bote lleno, se cobra lo consumido, o va incluido en el fee del destino?»
- **SA22** «Cancelaciones: ¿con cuánta anticipación se puede cancelar sin cargo? ¿qué pasa si se cancela tarde?»

**L16 · Pendientes (2 de 2).**
- **SA23** «Reservas de varios días: ¿se permiten? ¿cuál sería el máximo de días seguidos por socio?»
- **SA24** «Daños en una salida: ¿se cargan directo al socio que usó el bote, o siempre requieren acuerdo entre los dos?»
- **SA25** «Administración: ¿tendremos capitán o administrador? ¿quién carga y quién valida las facturas?»
- **SA26** «Mantenimiento preventivo: calendario y criterio: ¿por fecha, por horas de motor o lo que ocurra primero?»

**L17 · Temas que sugiere agregar Felipe.** «No están en la especificación actual: son sugerencias para conversarlas. Agrega o quita lo que quieras.»
- **SA27** «Feriados y temporada alta: Semana Santa, Navidad, Año Nuevo: ¿rotación anual?»
- **SA28** «Quién puede capitanear: licencia y experiencia exigidas para manejar.»
- **SA29** «Seguro y deducible: quién paga el deducible si hay un siniestro.»
- **SA30** «Seguridad a bordo: capitán sobrio, chalecos, menores y clima.»
- **SA31** «Entrega del bote: limpio, revisado y con checklist al devolverlo.»
- **SA32** «Fondo común: aporte mensual para imprevistos y mantenimiento.»
- **SA33** «Salida o venta de un socio: derecho de preferencia y cómo se valora el bote.»
- **SA34** «Desacuerdos: conversación directa; si no hay acuerdo, un mediador.»

**L18 · Próximos pasos.** **SA35** «1. Tu revisión: comenta las 5 reglas y llena las tablas de pendientes. 2. Reunión de cierre: acordamos el estatuto final y lo firmamos. 3. Configurar datos: bote, motores, destinos, tarifas y correos reales. 4. Lanzamiento: probamos la app con datos demo y luego en uso real. Puedes responder escribiendo directo en este archivo o por WhatsApp.»

### B. Lo que Xaviel pidió y decidió en esta sesión

**SB9** (descripción original del proyecto, literal): «this is a page/app that basically do similar functions as airbnb but with cars for example, if 10 people doesnt have the money to buy a ferrari, if they all together have the money they must buy it as a group and by the app they gonna manage it, like the hours that each member is allowed to use it, in which schedule, how they manage the vehicle maintenance, bills, and the (seguro del vehiculo). i already create the folder with the name of the project in this path(where the project gonna be storaged): "C:\Users\xavie\Desktop\X Dev\dev\shared". lets take the technical decitions about which framework we gonna use, how it gonna work and so on.»

**SB10** (pedido de esta sesión, literal): «i receive a pptx from felipe, that basically contain the idea that he has about this project. so lets make it real, by understanding it and building it. review the ppt, ask me questions, and so on. lets make the plan, context, and prompts to claude code cli in order to give it master prompts that claude code cli can use to build it with a solid plan and route.»

**SB7** Nombre: «the name gonna be "Shared" why? because i think is a self explained name i guess... i like it». Decisión: **Shared como nombre en código**; marca visible se decide después y vive en un solo archivo.

**SB8** Mejoras: «The improvements gonna be storaged here: "C:\developer\shared improvements" as the same way that we did it with the improvements of sgc and csd app: "C:\developer\improvements" segmented by months and inside it segmented by date».

**SB1** Alcance: **«Genérico completo desde ya»** (N socios, N activos, multi-grupo).
**SB2** Activos: **«Tipos totalmente configurables»**.
**SB3** Grupos: «hagamos todo completo, pero la parte de dinero se puede quedar como algo bypasseable por ahora, ya que estamos en fase inicial y estaremos haciendo pruebas.»
**SB4** Reglas de uso: **«Políticas configurables por grupo»** (default = estatuto de Felipe).
**SB5** Stack: **Angular PWA + Supabase + Vercel**.
**SB6** Contexto: «es un proyecto de felipe, se usaran las mismas cuentas de vercel y supabase, pero como un proyecto diferente, osea no se ligara a sgc y csd app, aunque si estara dentro de constructora sd por asi decirlo ya que es algo de la compania.»

---

## §2 Diagnóstico — huecos y contradicciones del PPT (SC1–SC10) y cómo se resuelven

| ID | Hallazgo | Por qué importa | DEFAULT aplicado |
|---|---|---|---|
| **SC1** | El PPT es **1 bote, 2 socios, 50/50**; la descripción original y SB1 piden **N socios, N activos, multi-grupo**. | Si «Socio 1/2» y «50%» se codifican fijos, generalizar luego obliga a reescribir. | El modelo es genérico (`grupos`, `activos`, `miembros.porcentaje`). Felipe es **un grupo de 2 miembros al 50/50** con el bote como activo. Nada en código dice «Socio 1». |
| **SC2** | **La fórmula del estado de cuenta (L8) está incompleta**: no dice quién adelantó el dinero. | Si A paga 100 de reparación, B debe 50 a A. Sin un libro mayor los balances no cuadran. | **Libro mayor** (cuentas: miembros, fondo, externo). Invariante: la suma de balances de miembros + fondo = 0. Ver §3.6. |
| **SC3** | **Daños**: L8 dice «nunca automático»; L16 pregunta si se cargan directo. | Contradicción interna. | **Siempre acuerdo entre socios** (DF-11). El flujo `en_revision` no genera cargos hasta que se acuerde. |
| **SC4** | **Combustible**: L8 lo pone como gasto individual; L15 pregunta cómo se cobra. | Define cuánto se liquida por salida. | `consumido` (DF-08), política configurable. |
| **SC5** | **¿A dónde va el fee del destino?** No se dice. | Sin destinatario no hay contabilidad posible. | Va al **fondo común** (DF-07), configurable (`fondo` / `otros socios` / `informativo`). **Pregunta a Felipe, con default aplicado.** |
| **SC6** | **«Se confirma al instante» (L5) vs estado «Borrador» (L3).** | Hay que saber cuándo existe un borrador. | Borrador = asistente de reserva sin confirmar, persistido 24 h para retomar; **confirmar es instantáneo** (DF-14). |
| **SC7** | **Moneda RD$/US$** abierta. | Montos en dos monedas rompen sumas. | Moneda por grupo (DOP por defecto); cada monto guarda moneda y tasa (DF-05). |
| **SC8** | **Invitados sin cuenta** reciben email pero no entran. | Implica enlaces firmados, no login. | Enlace firmado con expiración, solo lectura, sin finanzas (DF-31). |
| **SC9** | **El estatuto es un documento legal** (venta de socio, deducible, mediador); una app no lo reemplaza. | Riesgo legal real. | La app guarda **versiones del estatuto y acuses de cada socio** (no es firma legal). **Recomendación física: que un abogado revise el estatuto antes de firmarlo.** |
| **SC10** | **La parte «Airbnb» (formar grupos y juntar el dinero)** no está en el PPT; sí en la descripción original. | Manejar dinero ajeno tiene riesgo legal y operativo. | Se construye completa (SB3) pero **sin custodia de dinero**: los aportes se registran y se confirman a mano (modo `registro`), dinero «bypasseable». |

**Repetidos / relaciones:** SA3 está en L3 y L5 (misma regla). SA9 (capacidad) y SA19 (capacidad legal certificada) son la misma validación. SA13 (fórmula) depende de SA10/SA11/SA12. SA27–SA34 son sugerencias de Felipe: se construyen como **políticas/módulos** apagables, no como código fijo.

---

## §3 Arquitectura propuesta (Claude Code la refina en F0 y la deja en `docs/`)

### 3.1 Stack (SB5, DF-01)
- **Frontend:** Angular (última estable), componentes standalone, signals, rutas lazy, **SCSS con variables CSS** (sin Tailwind, preferencia de Xaviel), **PWA** (`@angular/pwa`, instalable en el celular, actualización con aviso). Mobile-first. Textos con `t()` (es base, en secundario; sin `ht`).
- **Backend:** **Supabase** (proyecto **nuevo** `shared`, no un schema dentro de otro proyecto): Postgres, Auth, Storage, Realtime, Edge Functions (Deno), `pg_cron`.
- **Hosting:** **Vercel** (proyecto nuevo `shared`), rewrites SPA.
- **Correo:** Resend (ya usado en SGC) vía edge function; salida con reintento y registro del motivo de cada fallo.
- **Reglas en la base, no solo en la UI:** exclusión de solapamientos, topes de capacidad, lecturas no negativas y auditoría viven en Postgres (constraints, triggers, RPC `security definer` con `search_path` fijo). La UI nunca es la única barrera.

### 3.2 Multi-tenencia (SB1)
Todo cuelga de `grupo_id`. **RLS en todas las tablas**; helpers SQL `es_miembro(grupo)`, `rol_en(grupo)`, `es_socio(grupo)`. Un usuario puede pertenecer a varios grupos (selector de grupo). **Finanzas visibles solo a miembros con rol `socio`**. El service role solo en edge functions. Tests de RLS obligatorios («el usuario del grupo A no lee nada del grupo B»).

### 3.3 Modelo de datos (resumen; nombres en español como en SGC)
- **Identidad y gobierno:** `perfiles`, `grupos` (nombre, moneda, zona horaria, prefijo de orden), `miembros` (grupo, usuario, rol, `porcentaje`, estado), `invitaciones_miembro`, `grupo_politicas` (JSONB validado + versión), `estatuto_versiones`, `estatuto_acuses`.
- **Activos configurables (SB2):** `tipos_activo` (plantillas de sistema `bote`/`carro`/`otro` + los del grupo; define: campos personalizados, **componentes** con su medidor —p. ej. «Motor ×N» con horómetro, «Odómetro» en km—, checklists por momento, categorías de gasto, terminología, prefijo de orden, límites de capacidad por tipo de uso), `activos` (tipo, valores de campos, capacidad legal), `activo_componentes` (p. ej. Motor 1, Motor 2, lectura inicial), `destinos` y `tarifas`.
- **Reservas:** `reservas` (rango `tstzrange`, **constraint de exclusión GiST** `(activo_id WITH =, rango WITH &&)` para estados que ocupan calendario), `ordenes` (número `{PREFIJO}-{AAAA}-{NNNN}` atómico por grupo/año), `reserva_acuses` («Leído y enterado»), `reserva_bloqueos` (mantenimiento/preparación), `solicitudes_911` + `solicitudes_911_mensajes`, `invitados` + `invitado_enlaces` (token hasheado, expira).
- **Operación:** `salidas_checkin`/`salidas_checkout` (o `operaciones`), `lecturas` (orden, componente, momento inicio/fin, valor; **fin ≥ inicio**; correcciones = fila nueva con `motivo`), `combustible_registros`, `checklist_respuestas`, `incidencias`, `evidencias` (fotos/archivos en Storage).
- **Dinero:** `gastos` (alcance `comun`/`individual`/`dano`, monto, moneda, tasa, pagado_por, proveedor, factura, vencimiento, estado `registrado`/`validado`/`disputado`, validado_por), `cargos`, `pagos` (confirmados por el receptor), `libro_mayor`, `fondo_comun` (+ aportes), `danos_casos` (evidencia, presupuesto, decisión).
- **Mantenimiento y riesgo:** `mantenimiento_planes` (criterio fecha / horas / lo que ocurra primero), `mantenimiento_tareas`, `servicios`, `polizas_seguro`, `siniestros`, `capitanes` (licencia, vencimiento, experiencia).
- **Gobierno social:** `disputas` (+ mediador temporal), `salida_socio_casos` (derecho de preferencia, valoración registrada), `temporada_alta`/`feriados` + rotación.
- **Formación de grupos (SB3):** `propuestas_compra`, `propuesta_participantes`, `propuesta_aportes` (confirmación manual), `directorio_publicaciones` (opt-in).
- **Transversal:** `auditoria` (inmutable: trigger genérico, sin UPDATE/DELETE para nadie), `notificaciones` (outbox + entregas con motivo de fallo), `errores_cliente`.

### 3.4 Estados y reglas clave
- Reserva: `borrador → confirmada → en_curso → finalizada`; `cancelada`; `bloqueada_mantenimiento`. Solo `confirmada`/`en_curso`/`bloqueada_mantenimiento` ocupan calendario. Cada transición por RPC, guarda quién y cuándo (auditoría).
- **911:** `pendiente → aceptada | rechazada | contrapropuesta → (acepta/rechaza la contrapropuesta)`; **nunca** mueve una reserva sin la aceptación del titular; aceptar ejecuta el cambio en una sola transacción y avisa a todos.
- Capacidad efectiva = `min(límite por tipo de uso, capacidad legal del activo)`; el RPC rechaza lo que exceda aunque la UI falle.
- Orden: solo se cierra (`finalizada`) con check-in y check-out completos y checklists obligatorios.

### 3.5 Políticas por grupo (SB4) y estatuto versionado
`grupo_politicas` guarda cada política con su **valor por defecto = estatuto de Felipe** (§4). Cambiar una política de un grupo activo crea una **versión nueva del estatuto** que rige solo cuando **todos los socios la aceptan** (DF-30); mientras tanto rige la anterior. Cubre SA27–SA34 como políticas apagables.

### 3.6 Libro mayor (resuelve SC2)
Cada gasto genera asientos: **crédito** a quien lo pagó (miembro, fondo o externo), **débito** a quien le corresponde (comunes: por `porcentaje`; individuales: a quien reservó; daños: solo tras acuerdo). **Balance de un miembro = créditos − débitos ± pagos entre miembros.** Positivo = le deben. Pago entre miembros: credita al que paga, debita al que recibe, y el receptor lo confirma. **Invariante probado con tests:** suma de balances de miembros + saldo del fondo = 0 (por moneda). Modo `finanzas = registro` (SB3): todo se calcula y se muestra, **nada bloquea** (ni reservas por deuda ni pasarelas); los pagos se marcan a mano.

### 3.7 Invitados (SC8, DF-31)
Sin cuenta. `/g/:token` (edge `guest-view`) devuelve solo fecha, horario, punto de encuentro, reglas y contacto; **nunca** tarifas, finanzas ni datos de otros socios. Token aleatorio, guardado hasheado, expira 24 h después del regreso, con límite de intentos.

### 3.8 Pantallas (SA17) y roles (SA16)
Las 8 pantallas de la L12 + pantallas del módulo genérico (Grupos, Propuestas de compra, Estatuto, Disputas, Seguro, Capitanes, Reportes). Menú inferior: **Calendario · Mis salidas · Gastos · Mantenimiento · Más** (lo demás cuelga de «Más»). Roles: `socio`, `admin_operativo` (no cambia acuerdos), `capitan`, `mediador` (temporal, solo un caso), `invitado` (sin cuenta, por enlace).

### 3.9 Visual (DF-35)
UI **funcional**, tokens SCSS y diseño sobrio mobile-first; **sin ornamento** hasta que Xaviel apruebe un mock en Claude Design (misma regla que SGC). La ronda visual va aparte.

---

## §4 Defaults (Claude Code los aplica, reporta y sigue — Regla A)

| ID | Tema (nota) | DEFAULT |
|---|---|---|
| DF-01 | Cuentas (SB6) | Proyecto Supabase **nuevo** `shared`; proyecto Vercel nuevo `shared`; mismas cuentas; sin vínculo con SGC/csd-app. |
| DF-02 | Marca (SB7) | `Shared`; un solo archivo `src/app/core/brand.ts` + `manifest` para cambiarla. |
| DF-03 | Idioma (SA15) | `es` base; claves `en`; sin `ht`. |
| DF-04 | Zona horaria | `America/Santo_Domingo` por grupo, configurable; se guarda `timestamptz`. |
| DF-05 | Moneda (SA20) | Por grupo, default **DOP (RD$)**; USD permitido; cada monto guarda moneda y tasa del día. |
| DF-06 | Modelo de tarifa (SA20) | **Por destino** (fee fijo); «por hora» y «ambos» soportados por política. Fee = 0 hasta que se configure. |
| DF-07 | Destino del fee (SC5) | **Fondo común** (alternativas: otros socios en proporción / solo informativo). |
| DF-08 | Combustible (SA21) | **Se cobra lo consumido** al que reservó (alternativas: devolver lleno / incluido en el fee). |
| DF-09 | Cancelaciones (SA22) | Sin cargo hasta **48 h** antes; tardía → se registra como «cancelación tardía», cargo **0 %** (configurable). |
| DF-10 | Varios días (SA23) | Permitidos; **máx. 3 días seguidos** por socio (`null` = sin tope). |
| DF-11 | Daños (SA12, SA24) | Siempre **acuerdo entre socios**; jamás cargo automático. |
| DF-12 | Administración (SA25) | Sin capitán/administrador al inicio. Si existe `admin_operativo`, él carga facturas y **un socio las valida**; si las carga un socio, **otro socio las valida**. |
| DF-13 | Mantenimiento (SA26) | **Por fecha u horas de motor, lo que ocurra primero.** |
| DF-14 | Borrador (SC6) | Solo existe mientras el asistente no se confirma (se guarda 24 h para retomar); confirmar es instantáneo. |
| DF-15 | Acuse (SA3) | Lo marcan **todos los demás socios**; no bloquea; recordatorio a las 24 h y 2 h antes. |
| DF-16 | Derechos de uso (SA1, SA4) | **Iguales, sin cuotas.** Alternativas por política: proporcional al % o cuota de horas/días por socio (descripción original). |
| DF-17 | Capacidad (SA9) | Socio **15**, invitado **8** (1 + 7); `min(límite, capacidad legal)`; sin capacidad legal no se activa el activo. |
| DF-18 | Preparación (SA5) | Buffer antes/después de cada salida: **0 h**, configurable. |
| DF-19 | Feriados (SA27) | Política `temporada_alta` con rotación anual de Semana Santa/Navidad/Año Nuevo; **apagada** hasta que los socios la acepten en el estatuto. |
| DF-20 | Capitanes (SA28) | Registro con licencia y vencimiento; **sin capitán con licencia vigente no se hace el check-in** (política, configurable). |
| DF-21 | Seguro y deducible (SA29) | Pólizas con vencimiento (alertas 30 y 7 días); el deducible de un siniestro entra al **flujo de daños** (acuerdo, nunca automático). |
| DF-22 | Seguridad (SA30) | Checklist de salida **obligatorio** (capitán sobrio, chalecos, menores, clima), editable por tipo de activo. |
| DF-23 | Entrega (SA31) | Checklist de regreso **obligatorio** (limpio, revisado, combustible). |
| DF-24 | Fondo común (SA32) | Aporte mensual configurable, **0 (apagado)**; los fees de destino entran aquí. |
| DF-25 | Salida/venta (SA33) | Caso registrado con **derecho de preferencia de 30 días** para los demás socios; valoración = valor acordado y documentado; la app **no mueve dinero**. |
| DF-26 | Desacuerdos (SA34) | Hilo directo; a los **7 días** sin acuerdo se puede invitar un mediador (rol temporal, solo ese caso). |
| DF-27 | Finanzas (SB3) | Modo **`registro`**: sin bloqueos por deuda, sin pasarelas, pagos marcados a mano y confirmados por el receptor. |
| DF-28 | Formación de grupos (SB3, SC10) | Sin custodia de dinero; aportes confirmados a mano; propuestas **privadas por enlace**; directorio público **opt-in, apagado**. |
| DF-29 | Tipos de activo (SB2) | Plantillas de sistema **Bote, Carro, Otro** (no editables, clonables); cada grupo crea/edita los suyos. |
| DF-30 | Estatuto (SA35, SC9) | Versionado; un cambio rige cuando **todos los socios** lo aceptan; acuses guardados (no son firma legal). |
| DF-31 | Invitados (SC8) | Sin cuenta; enlace firmado, expira 24 h tras el regreso, solo lectura. |
| DF-32 | Número de orden (SA2) | `{PREFIJO}-{AAAA}-{NNNN}` por grupo y año; prefijo del tipo (`BOT`, `CAR`, `ORD`). |
| DF-33 | Exportación (SA18) | PDF y Excel en edge function; tope 5.000 filas por export. |
| DF-34 | Notificaciones | Correo (Resend) + in-app; push web apagado; **fallo de envío = registro con motivo + 1 reintento** (lección SGC: nada silencioso). |
| DF-35 | Visual | Funcional, sin ornamento; ronda visual tras mock aprobado en Claude Design. |
| DF-36 | Roles (SA16) | `socio`, `admin_operativo`, `capitan`, `mediador`, `invitado` (sin cuenta). |
| DF-37 | Datos del bote (SA19) | Se siembra «Bote Demo» (cap. 15, 2 motores en 0 h) **solo en modo demo**; los datos reales los carga Xaviel en Configuración. |
| DF-38 | Auth | Supabase Auth: correo + contraseña y enlace mágico; alta de socios por invitación por correo. |
| DF-39 | Auditoría | Inmutable; las correcciones son filas nuevas con `motivo` obligatorio. |
| DF-40 | Modo demo (SA35) | `modo_demo` por grupo: banner visible, datos demo, botón de reinicio; separado de datos reales. |

---

## §5 Riesgos

1. **Alcance grande para un solo desarrollador.** «Genérico completo + tipos configurables + formación de grupos» es el triple de trabajo que el PPT de Felipe. Por eso el plan (PLAN §2) deja **el flujo de Felipe usable de punta a punta antes de las fases genéricas más pesadas** (formación de grupos y directorio van al final, PROMPT-5).
2. **Tipos de activo configurables** son lo más difícil de probar bien (campos y medidores dinámicos). Mitigación: plantillas de sistema primero, editor después, validación en base y en app.
3. **Dinero ajeno.** Aunque esté «bypasseable», el libro mayor y los balances **tienen que cuadrar** desde el día 1; un error aquí destruye la confianza de los socios. Tests de invariantes obligatorios.
4. **Legal.** El estatuto, la venta de un socio, el deducible y cualquier recaudo de aportes necesitan revisión de un abogado. La app no sustituye un contrato.
5. **Seguridad de invitados.** Enlaces sin cuenta: tokens fuertes, hasheados, con expiración.
6. **Decisiones de Felipe sin cerrar** (L15/L16): se aplican defaults y todo es política configurable, así que cambiar una decisión **no** exige reescribir código.
7. **Sin diseño visual aprobado**: funcional primero; no gastar tiempo en CSS decorativo.

## §6 Hallazgos propios
- El PPT usa «Socio 1 / Socio 2» como etiquetas fijas y 50/50 como constante: ambos se vuelven **datos** (miembros y porcentajes).
- La métrica «< 1 min para reservar» es **medible**: la v1 mide el tiempo del asistente de reserva (evento en `errores_cliente`/métricas) para comprobarla en pruebas.
- Felipe ofrece responder «en el archivo o por WhatsApp»: el PLAN deja una **lista de preguntas para Felipe** (§7) para llevarle en un solo mensaje.

## §7 Preguntas para llevarle a Felipe (con el default que ya aplicamos)
1. ¿El fee de cada destino a dónde va? *(default: fondo común)*
2. ¿Combustible: lo consumido, devolver lleno o incluido? *(default: lo consumido)*
3. ¿Cancelación sin cargo hasta cuántas horas antes? *(default: 48 h)*
4. ¿Máximo de días seguidos por socio? *(default: 3)*
5. ¿Habrá capitán o administrador? ¿Quién valida facturas? *(default: no al inicio; valida el otro socio)*
6. Datos reales del bote: nombre, capacidad legal certificada, número de motores y horómetros iniciales.
7. Destinos y fee de cada uno, y moneda. *(default: DOP, por destino)*
8. ¿Rotación de feriados activada desde el inicio? *(default: apagada)*
9. ¿Aporte mensual al fondo común? ¿De cuánto? *(default: 0)*
10. ¿Quién es el abogado que revisará el estatuto?
