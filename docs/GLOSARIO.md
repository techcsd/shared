# GLOSARIO — Shared

| Término | Significado |
|---|---|
| **Grupo** | Conjunto de copropietarios que comparten uno o más activos. Todo dato cuelga de un grupo. |
| **Socio / miembro** | Persona con cuenta en un grupo. `socio` tiene `porcentaje` de propiedad; el resto de roles no. «Socio 1/2» no existe: se usa el nombre. |
| **Rol** | `socio`, `admin_operativo` (opera, no cambia acuerdos), `capitan`, `mediador` (temporal, un caso), `invitado` (sin cuenta, por enlace). |
| **Porcentaje** | Participación de un socio; Σ de socios activos = 100 en un grupo activo. Reparte gastos comunes. |
| **Activo** | Cosa compartida (bote, carro, moto acuática…). Tiene **tipo**, capacidad legal, componentes. |
| **Tipo de activo** | Plantilla: campos, componentes con medidor, checklists, categorías de gasto, terminología, límites. Hay de sistema y del grupo. |
| **Componente** | Parte con medidor (Motor 1, Motor 2, Odómetro). Tiene lectura inicial. |
| **Política** | Regla configurable del grupo con valor por defecto (catálogo). |
| **Estatuto** | Conjunto de políticas vigentes, versionado; una versión rige cuando todos los socios la aceptan. |
| **Acuse (estatuto)** | Registro de que un socio aceptó una versión. No es firma legal. |
| **Acuse (reserva) / «Leído y enterado»** | Aviso al otro socio; no es aprobación. |
| **Prioridad 911** | Solicitud de un socio para una fecha ya reservada; el titular decide. Nunca desplaza solo. |
| **Orden** | Registro numerado de una salida (`BOT-2026-0001`). |
| **Check-in / check-out** | Registro de salida y regreso con lecturas, combustible, checklists. |
| **Gasto común / individual / daño** | Alcance de un gasto: reparto por %, a quien reservó, o por acuerdo. |
| **Libro mayor** | Asientos de crédito/débito; Σ balances de miembros + fondo = 0 por moneda. |
| **Fondo común** | Bolsa del grupo para imprevistos y mantenimiento (recibe fees de destino por defecto). |
| **Modo `registro`** | Finanzas que calculan y muestran pero no bloquean ni mueven dinero. |
| **Modo demo** | Grupo con datos de prueba, banner visible y botón de reinicio. |
| **Destino / fee** | Lugar de la salida y su tarifa. |
| **RLS** | Row Level Security de Postgres: aislamiento por fila según usuario/rol. |
| **RPC** | Función SQL invocada desde la app (`security definer`, `search_path` fijo). |
| **DF-xx** | Decisión por defecto (ver `DECISIONES.md`). **SA/SB/SC**: notas del PPT / de Xaviel / hallazgos. |
