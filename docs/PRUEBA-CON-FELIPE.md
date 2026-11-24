# Prueba con Felipe — un ciclo completo en `dev` (≈ 20 minutos, dos personas, dos celulares)

**Entorno:** el preview de Vercel de `dev` (usa `shared-dev` con datos demo). Usuarios: `felipe.demo@shared.test` y `xaviel.demo@shared.test`, clave `Demo1234!`. El grupo «Bote Demo» tiene el banner de demostración. Más → Finanzas → «Reiniciar datos de prueba» deja limpias las finanzas.

> Marca la hora: la meta es reservar **en menos de 1 minuto** desde el celular. El tiempo real se guarda solo (Más → Salud del sistema, solo admin de plataforma).

## 1. Reservar (Felipe)
1. Entra. Debe abrir el **calendario**. Toca un día libre → «Reservar».
2. Elige horas, uso (familiar), destino «Playa» (fee 5,000), 6 personas → «Confirmar». Anota la orden `BOT-2026-NNNN` y cuánto tardaste.
3. Intenta el mismo horario otra vez: debe decir que está ocupado.

## 2. «Leído y enterado» y 911 (Xaviel)
1. Xaviel ve la reserva en el calendario y marca «Leído y enterado» (no es una aprobación).
2. Xaviel pide **Prioridad 911** sobre esa reserva. Felipe la ve en Más → Prioridad 911 y la **rechaza** (nada cambia) o la acepta (la reserva pasa a Xaviel en una sola operación).

## 3. Salir (Felipe, check-in)
1. Reservas → la orden → «Salir». Faltan datos a propósito: capitán, combustible inicial, lectura inicial de **cada motor**, checklist de seguridad. Mira que la app diga **qué falta**.
2. Completa y «Salir». (El capitán debe estar registrado con licencia vigente: Más → Capitanes; en la demo ya lo está.)

## 4. Gastos y regreso (Felipe)
1. En la misma pantalla agrega un gasto del viaje: hielo, 300 (con foto si quieres).
2. Pon lecturas finales (≥ iniciales), combustible final, checklist de entrega → «Registrar regreso y cerrar». Prueba primero una lectura final **menor** que la inicial: debe rechazarla.
3. Debe quedar **finalizada** y liquidada.

## 5. Validar y revisar los números (Xaviel)
1. Gastos → el gasto de hielo sale «Provisional» → «Validar» (lo valida el *otro* socio).
2. Más → Finanzas → Balances. **Cuenta a mano:** Felipe debe el fee (5,000) → −5,000; el hielo lo pagó él y es suyo → 0 neto; el fondo común +5,000. La suma de todas las cuentas debe dar 0.
3. Estado de cuenta de Felipe: ver cada cargo con su detalle.
4. Pagos: Felipe registra un pago de 1,000 al fondo; Xaviel lo confirma → el balance cambia **solo después** de confirmar.

## 6. Extras (5 min cada uno)
- **Daño:** Más → Finanzas → Daños: abrir un caso, proponer reparto 50/50, aceptar con el otro usuario. Antes de aceptar no hay cargos.
- **Mantenimiento:** Mantenimiento → plan «Aceite» cada 50 h o 1 año → registrar un servicio con costo 1,500 y vencimiento → aparece como gasto común provisional.
- **Reportes:** Más → Reportes: comparar el dashboard con los balances; exportar Excel y PDF y comparar las filas.
- **Desacuerdo y mediador:** Más → Desacuerdos: abrir uno; a los 7 días se puede invitar un mediador (en la demo se adelanta cambiando la fecha en la base).
- **Invitado sin cuenta:** reservar con uso «Invitado» y abrir su enlace `/g/<token>` en una ventana privada: solo fecha, horario, punto de encuentro y reglas.

## 7. Paso a datos reales (cuando estén listos)
Más → Lanzamiento muestra la lista: capacidad legal certificada, motores con lectura inicial, destinos, tarifas, correos, capitán con licencia, seguro, estatuto. «Pasar a datos reales» **borra los datos de prueba** de ese grupo. Antes: abogado revisa el estatuto (SC9) y se acuerdan los defaults (`docs/DECISIONES.md`).

## Qué anotar
Tiempos de reserva, cualquier pantalla confusa, cualquier número que no coincida con la cuenta a mano, y qué política quieren distinta (fee al fondo, combustible, cancelación…).
