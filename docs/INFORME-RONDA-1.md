# INFORME FINAL — Ronda 1 (23-nov-2026) · PROMPT-1 a PROMPT-5

Estado al 2026-11-24. **Hecho** = construido y probado; **Parcial** = construido con una limitación declarada; **No** = no construido.

## 1. Notas del PPT de Felipe (SA1–SA35)
| ID | Estado | Dónde | Prompt/fase |
|---|---|---|---|
| SA1 | **Hecho (medido)** | e2e `p5-vivo`: 5 reservas en móvil emulado, promedio ≈ 0,7 s *automatizado*; el tiempo con personas queda en `eventos_cliente.reserva_asistente_ms` (Salud del sistema). 50/50 en comunes = por % (`repartir_por_porcentaje`) | P1/P2/P5 F3 |
| SA2 | Hecho | `reserva_confirmar` (orden `BOT-AAAA-NNNN`), `checkin_registrar`, `checkout_registrar`, `liquidar_operacion` | P2, P3 |
| SA3 | Hecho | `reserva_marcar_enterado`, recordatorios 24 h/2 h (`recordatorios_acuse`) | P2 |
| SA4 | Hecho | política `derechos_uso` (iguales / proporcional / cuota) | P1, P2 |
| SA5 | Hecho | exclusión GiST `reservas_sin_solapamiento` + bloqueos de mantenimiento (`tarea_programar`) | P2, P4 |
| SA6 | Hecho | `reservas_datos_completos`, asistente de 4 pasos | P2 |
| SA7 | Hecho | enum de 6 estados + trigger de transiciones + `auditoria` | P2 |
| SA8 | Hecho | `prioridad_911_*` (aceptar/rechazar/contraproponer/expirar, atómico) | P2 |
| SA9 | Hecho | `capacidad_efectiva` (socio 15 / invitado 8; manda el límite legal), invitados con anfitrión | P2 |
| SA10 | Hecho | gasto `comun` por % + servicio → gasto (`servicio_registrar`) | P3, P4 |
| SA11 | Hecho | gasto `individual` a quien reservó (aunque invite a un tercero) | P3 |
| SA12 | Hecho | `danos_casos` (acuerdo unánime, nunca automático) | P3 |
| SA13 | Hecho | `libro_mayor` + `estado_cuenta` (amplía la fórmula con quién adelantó, SC2) | P3 |
| SA14 | Hecho | lecturas por componente (≥ 0, fin ≥ inicio, continuidad), correcciones con motivo, cierre solo con datos completos | P3 |
| SA15 | **Hecho** | PWA instalable (manifest `standalone`, `lang es`), inicio = calendario, UI en español | P1, P5 |
| SA16 | Hecho | roles `socio`, `admin_operativo`, `capitan`, `mediador`, invitado; pruebas de RLS por rol | P1–P4 |
| SA17 | Hecho | las 8 pantallas + menú inferior (Calendario · Mis salidas · Gastos · Mantenimiento · Más) | P1–P4 |
| SA18 | Hecho | `reporte_dashboard`, `reporte_salidas`, edge `exportar-reporte` (PDF y Excel, 5.000 filas) | P4 |
| SA19 | **Parcial** | el modelo y el asistente (`Más → Lanzamiento`) están; **los datos reales del bote son pendiente físico** (capacidad legal certificada, motores, horómetros) | P1, P5 |
| SA20 | Hecho | tarifas por destino (fee) y por hora, moneda y tasa por monto | P1, P3 |
| SA21 | Hecho | política `combustible.modelo` (consumido / devolver_lleno / incluido) | P1, P3 |
| SA22 | Hecho | cancelación tardía con cargo visible antes de confirmar; cargo asentado | P2, P3 |
| SA23 | Hecho | política de varios días y máximo de días seguidos | P2 |
| SA24 | Hecho | daños = acuerdo | P3 |
| SA25 | Hecho | admin operativo carga, un socio valida (DF-12) | P3, P4 |
| SA26 | Hecho | planes con criterio fecha/horas/primero y alertas | P4 |
| SA27 | Hecho | `temporada_alta` con rotación anual, apagada por defecto | P2 |
| SA28 | Hecho | `capitanes` + licencia vigente exigida al check-in | P4 |
| SA29 | Hecho | pólizas, alertas 30/7 días, deducible → flujo de daños | P4 |
| SA30 | Hecho | checklist de seguridad obligatorio | P3 |
| SA31 | Hecho | checklist de entrega obligatorio | P3 |
| SA32 | Hecho | `fondo_aportes` (0 por defecto), fees al fondo | P3 |
| SA33 | **Parcial** | salida/venta a **socios** con preferencia, valoración, aceptación unánime y traspaso de %; **la venta a un tercero no está soportada** | P4 |
| SA34 | Hecho | disputas + mediador por enlace a los 7 días, solo lectura del caso | P4 |
| SA35 | Parcial | estatuto versionado con acuses (no es firma legal), modo demo → real; **la reunión de cierre y la firma son físicas** | P1, P5 |

## 2. Pedidos de Xaviel (SB)
| ID | Estado | Dónde |
|---|---|---|
| SB1 | Hecho | modelo genérico (grupos, miembros con %, N activos) |
| SB2 | Hecho | `tipos_activo` configurables (+ plantillas Bote/Carro/Otro) |
| SB3 | Hecho | modo `registro` sin custodia; propuestas de compra con aportes confirmados a mano |
| SB4 | Hecho | 33 políticas por grupo + estatuto versionado |
| SB5 | Hecho | Angular PWA + Supabase + Vercel |
| SB6 | Hecho | proyectos propios `shared-dev`/`shared-prod`, Vercel `shared`; `docs/DESPLIEGUE.md` |
| SB7 | Hecho | marca solo en `src/app/core/brand.ts` (`release-check` lo vigila) |
| SB8 | Hecho | rondas en `C:\developer\shared improvements\…` |
| SB9 | Hecho | propuestas de compra → fondeo → adquisición → conversión en grupo (+ horarios, mantenimiento, gastos, seguro) |
| SB10 | Hecho | CONTEXTO, PLAN, P1–P5 |

## 3. Hallazgos (SC1–SC10)
| ID | Estado | Resolución |
|---|---|---|
| SC1 | Hecho | grupos y miembros con % |
| SC2 | Hecho | libro mayor con invariante probado |
| SC3 | Hecho | daños por acuerdo |
| SC4 | Hecho | política de combustible |
| SC5 | Hecho (default) | fee → fondo común; **preguntar a Felipe** si prefiere repartirlo |
| SC6 | Hecho | borrador = asistente sin confirmar (24 h) |
| SC7 | Hecho | moneda y tasa en cada monto |
| SC8 | Hecho | invitado por enlace firmado, solo lectura |
| SC9 | Hecho (software) | versiones + acuses; **abogado = pendiente físico** |
| SC10 | Hecho | sin custodia; aviso legal visible; directorio apagado |

## 4. Resultados de las pruebas
- **Dinero (SQL, `npm run test:db`, 16 archivos / 27 migraciones):** suma de todas las cuentas = 0; **miembros + fondo = 0** mientras no haya terceros; gasto de 100 pagado por A con 50/50 → A +50, B −50; individual a quien reservó; pago sin confirmar no cambia balances; redondeo determinista (100,01 entre 3; montos incómodos entre 10 socios); ciclo completo de 10 socios; conversión de propuesta con 10 aportes desiguales suma 100 %; reportes = libro mayor.
- **Seguridad:** `16_seguridad_rls.sql` (RLS en todo, sin acceso anónimo, escrituras solo por RPC, `search_path` fijo, aislamiento entre grupos, tokens); mediador sin acceso extra (SQL y e2e); admin operativo sin finanzas/acuerdos (SQL y e2e); CSP verificada; `npm audit` 0.
- **e2e en vivo contra `shared-dev`:** 22 pruebas (smoke, P2, P3, P4, P5) incluyendo carrera real de dos confirmaciones, export xlsx/pdf y el ciclo proponer → reportar.
- **Tiempo de reserva medido (SA1):** 5 reservas en móvil emulado: 891, 623, 718, 717, 688 ms (promedio 727 ms). **Es tiempo automatizado**: no demuestra la meta con personas; ese número se mide con Felipe y se lee en «Salud del sistema».

## 5. Decisiones DF que Xaviel debería revisar
DF-07 (fee al fondo), DF-08/64 (combustible), DF-09 (cancelación tardía 0 % por defecto), DF-12 (quién valida facturas), DF-17 (capacidad 15/8), DF-20/79 (**licencia obligatoria en el check-in desde P4**), DF-62 (el invariante tiene un matiz con terceros), DF-70 (aporte mensual total del grupo repartido por %), DF-83 (salida de socio solo a socios).

## 6. Lo que debe probar Xaviel en `dev`
`docs/PRUEBA-CON-FELIPE.md` (ciclo completo con dos usuarios y balances contra cuenta a mano) y, aparte, propuesta de compra → conversión, servicio de mantenimiento con alerta, licencia vencida, exportar Excel y comparar, invitar mediador.

## 7. Pendientes físicos
Dominio verificado en Resend; datos reales del bote (SA19); abogado para estatuto y propuestas (SC9/SC10); reunión de cierre y firma (SA35); activar *Confirm email* y límites en Supabase Auth; convertir `techcsd` en organización de GitHub (decidido para después); correr `hawkscan` (no disponible en la sesión); Lighthouse en dispositivo real.

## 8. Huecos y riesgos
- **Lighthouse (≥ 90 móvil): NO medido** (el Chromium headless de Playwright no lo soporta en esta máquina); medir en Chrome real o PageSpeed Insights.
- **Venta a un tercero** (SA33): no soportada; el comprador externo requiere un flujo de invitación coordinado con el cierre.
- **Estatuto:** al convertir una propuesta se crea la versión 1 en estado pendiente; rige cuando todos los socios la aceptan.
- **Offline:** la cola solo cubre `gasto_registrar` y `lectura_corregir`; las lecturas del check-in/out se envían con el flujo normal (no hay cola para ellas).
- **Producción:** al activar la exigencia de licencia, un grupo sin capitanes registrados no podrá hacer check-in hasta registrar uno.
- **Edge functions:** el CORS usa una variable de módulo (posible carrera mínima entre peticiones simultáneas de orígenes distintos; sin impacto en seguridad).
- Presupuesto de bundle inicial elevado a 700 kB (el diccionario i18n crece); candidato a carga perezosa del idioma inglés.
