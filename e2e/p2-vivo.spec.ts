import { createClient } from '@supabase/supabase-js';
import { expect, test, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';

// Prueba de reservas contra shared-dev con los usuarios demo. Se activa con E2E_VIVO=1.
test.skip(!process.env['E2E_VIVO'], 'Requiere E2E_VIVO=1 y shared-dev con seed demo');
test.describe.configure({ mode: 'serial' });

const env: Record<string, string> = {};
for (const l of readFileSync('.env.local', 'utf8').split(/\r?\n/)) {
  const m = l.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
  if (m) env[m[1]] = m[2];
}
const URL = env['NG_APP_SUPABASE_URL'];
const ANON = env['NG_APP_SUPABASE_ANON_KEY'];
const SERVICIO = env['SUPABASE_SERVICE_ROLE_KEY_DEV'];
const ACTIVO = '20000000-0000-4000-8000-000000000001';

const fechaFutura = (offset: number) =>
  new Date(Date.now() + offset * 86400000).toISOString().slice(0, 10);
const base = 120 + Math.floor(Math.random() * 100);
const DIA = fechaFutura(base);

let ordenId = '';
let ordenCodigo = '';
const creadas: string[] = [];

async function entrar(page: Page, correo: string) {
  await page.goto('/login');
  await page.getByLabel('Correo').fill(correo);
  await page.getByLabel('Contraseña').fill('Demo1234!');
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page).toHaveURL(/\/calendario/);
}

async function cliente(correo: string) {
  const c = createClient(URL, ANON, { auth: { persistSession: false } });
  const { error } = await c.auth.signInWithPassword({ email: correo, password: 'Demo1234!' });
  if (error) throw error;
  return c;
}

const admin = () => createClient(URL, SERVICIO, { auth: { persistSession: false } });

test.afterAll(async () => {
  // limpieza de los datos de prueba (solo shared-dev)
  const a = admin();
  const { data } = await a
    .from('reservas')
    .select('id')
    .eq('activo_id', ACTIVO)
    .gte('creado_en', new Date(Date.now() - 3600000).toISOString());
  const ids = [...creadas, ...(data ?? []).map((r) => r.id)];
  if (ids.length) {
    await a.from('solicitudes_911').delete().in('reserva_id', ids);
    await a.from('reservas').delete().in('id', ids);
  }
});

test('reservar con el asistente en < 1 min, y el otro socio la ve y marca «Leído y enterado»', async ({
  browser,
}) => {
  const felipe = await (await browser.newContext()).newPage();
  await entrar(felipe, 'felipe.demo@shared.test');

  const t0 = Date.now();
  await felipe.goto(`/reservar?fecha=${DIA}`);
  await expect(felipe.getByRole('heading', { name: 'Reservar' })).toBeVisible();
  await felipe.getByLabel('Hora de salida').fill('09:00');
  await felipe.getByLabel('Hora de regreso').fill('15:00');
  await felipe.getByRole('button', { name: 'Siguiente' }).click();
  await felipe.getByRole('radio', { name: 'Familiar' }).click();
  await felipe.getByRole('button', { name: 'Siguiente' }).click();
  await expect(felipe.getByText('Máximo permitido: 15')).toBeVisible(); // límite visible ANTES de confirmar
  await felipe.getByLabel('Personas a bordo').fill('8');
  await felipe.getByRole('button', { name: 'Ver resumen' }).click();
  await expect(felipe.getByText('Fee estimado')).toBeVisible();
  await expect(
    felipe.getByText('5,000 DOP').or(felipe.getByText('5.000 DOP')).first(),
  ).toBeVisible();
  await felipe.getByRole('button', { name: 'Confirmar reserva' }).click();
  await expect(felipe).toHaveURL(/\/reserva\//);
  const ms = Date.now() - t0;
  console.log(`TIEMPO_ASISTENTE_MS=${ms}`);
  expect(ms).toBeLessThan(60000);

  ordenId = felipe.url().split('/reserva/')[1];
  creadas.push(ordenId);
  ordenCodigo = (await felipe.locator('h1').innerText()).trim();
  expect(ordenCodigo).toMatch(/^BOT-\d{4}-\d{4}$/);
  await expect(felipe.getByText('Confirmada').first()).toBeVisible();

  // el otro socio la ve en su calendario (mes) y marca el acuse
  const xaviel = await (await browser.newContext()).newPage();
  await entrar(xaviel, 'xaviel.demo@shared.test');
  await xaviel.goto(`/reserva/${ordenId}`);
  await expect(xaviel.locator('h1')).toHaveText(ordenCodigo);
  await xaviel.getByRole('button', { name: /Marcar «Leído y enterado»/ }).click();
  await expect(xaviel.getByText('lo marcó el')).toBeVisible();
  await expect(xaviel.getByText('Confirmada').first()).toBeVisible(); // no es una aprobación: nada cambia
  // el titular ve quién lo marcó
  await felipe.reload();
  await expect(felipe.getByText('lo marcó el')).toBeVisible();
  // aviso in-app al otro socio (Realtime/outbox)
  await xaviel.goto('/mas/notificaciones');
  await expect(xaviel.getByText(`Nueva reserva ${ordenCodigo}`)).toBeVisible();
});

test('el calendario pinta la reserva y un choque se rechaza con mensaje claro', async ({
  browser,
}) => {
  const xaviel = await (await browser.newContext()).newPage();
  await entrar(xaviel, 'xaviel.demo@shared.test');
  await xaviel.goto('/calendario');
  // ir al mes de la reserva
  const meses = Math.max(0, Math.round((Date.parse(DIA) - Date.now()) / (30 * 86400000)));
  for (let i = 0; i < meses + 1; i++) {
    if (await xaviel.locator(`[data-dia="${DIA}"]`).count()) break;
    await xaviel.getByRole('button', { name: 'Siguiente' }).click();
    await xaviel.waitForTimeout(250);
  }
  const celda = xaviel.locator(`[data-dia="${DIA}"]`);
  await expect(celda.locator('.punto.otro')).toBeVisible(); // es de otro socio
  await celda.click();
  await expect(xaviel.getByText(ordenCodigo)).toBeVisible();
  await expect(xaviel.getByRole('link', { name: 'Prioridad 911' })).toBeVisible();

  // intenta reservar el mismo horario → «horario ocupado»
  await xaviel.goto(`/reservar?fecha=${DIA}`);
  await xaviel.getByLabel('Hora de salida').fill('10:00');
  await xaviel.getByLabel('Hora de regreso').fill('12:00');
  await xaviel.getByRole('button', { name: 'Siguiente' }).click();
  await xaviel.getByRole('button', { name: 'Siguiente' }).click();
  await xaviel.getByLabel('Personas a bordo').fill('3');
  await xaviel.getByRole('button', { name: 'Ver resumen' }).click();
  await xaviel.getByRole('button', { name: 'Confirmar reserva' }).click();
  await expect(xaviel.getByRole('alert')).toContainText('ya está ocupado');
  // el borrador queda sin ocupar el calendario; lo descartamos
  await xaviel.getByRole('button', { name: 'Volver' }).click();
});

test('Prioridad 911: solicitar → el titular acepta → cambio atómico con nueva orden', async ({
  browser,
}) => {
  const xaviel = await (await browser.newContext()).newPage();
  await entrar(xaviel, 'xaviel.demo@shared.test');
  await xaviel.goto(`/mas/prioridad-911?reserva=${ordenId}`);
  await expect(xaviel.getByText('Pedir Prioridad 911')).toBeVisible();
  await xaviel.getByLabel('Mensaje para el titular').fill('Cumple de mi hijo, ¿me la cedes?');
  await xaviel.getByRole('button', { name: 'Enviar solicitud' }).click();
  await expect(xaviel.getByText('Solicitud enviada')).toBeVisible();

  // mientras no acepte, la reserva de Felipe sigue vigente (verificado por API como Xaviel)
  const cx = await cliente('xaviel.demo@shared.test');
  const { data: antes } = await cx.from('reservas').select('estado').eq('id', ordenId).single();
  expect(antes?.estado).toBe('confirmada');
  // Xaviel (solicitante) NO puede decidir ni quitarla
  const decide = await cx.rpc('prioridad_911_responder', {
    p_solicitud: (await cx.from('solicitudes_911').select('id').eq('reserva_id', ordenId).single())
      .data!.id,
    p_accion: 'acepta',
  });
  expect(decide.error?.message).toContain('solo_titular_decide');
  expect((await cx.rpc('reserva_cancelar', { p_reserva: ordenId })).error?.message).toContain(
    'solo_quien_reserva',
  );

  // Felipe, el titular, acepta
  const felipe = await (await browser.newContext()).newPage();
  await entrar(felipe, 'felipe.demo@shared.test');
  await felipe.goto('/mas/prioridad-911');
  await expect(
    felipe
      .getByText('Esperando la respuesta')
      .first()
      .or(felipe.getByRole('button', { name: 'Aceptar y ceder' })),
  ).toBeVisible();
  await felipe.getByRole('button', { name: 'Aceptar y ceder' }).first().click();
  await expect(felipe.getByText('Aceptada').first()).toBeVisible();

  // resultado atómico: la de Felipe cancelada, Xaviel con la suya confirmada y orden nueva
  const { data: sol } = await cx
    .from('solicitudes_911')
    .select('estado, reserva_resultante_id')
    .eq('reserva_id', ordenId)
    .single();
  expect(sol?.estado).toBe('aceptada');
  const { data: nueva } = await cx
    .from('reservas')
    .select('estado, reservado_por')
    .eq('id', sol!.reserva_resultante_id)
    .single();
  expect(nueva?.estado).toBe('confirmada');
  creadas.push(sol!.reserva_resultante_id);
  const { data: vieja } = await cx.from('reservas').select('estado').eq('id', ordenId).single();
  expect(vieja?.estado).toBe('cancelada');
  const { count } = await admin()
    .from('reservas')
    .select('id', { count: 'exact', head: true })
    .eq('activo_id', ACTIVO)
    .eq('estado', 'confirmada')
    .filter('rango', 'ov', `[${DIA}T00:00:00Z,${DIA}T23:59:59Z)`);
  expect(count).toBe(1); // nunca dos a la vez
});

test('carrera real: dos confirmaciones simultáneas del mismo horario → solo una gana', async () => {
  const dia = fechaFutura(base + 1);
  const cf = await cliente('felipe.demo@shared.test');
  const cx = await cliente('xaviel.demo@shared.test');
  const ini = `${dia}T14:00:00Z`;
  const fin = `${dia}T18:00:00Z`;
  const bf = await cf.rpc('reserva_crear_borrador', {
    p_activo: ACTIVO,
    p_inicio: ini,
    p_fin: fin,
    p_uso: 'personal',
    p_destino: null,
    p_personas: 4,
  });
  const bx = await cx.rpc('reserva_crear_borrador', {
    p_activo: ACTIVO,
    p_inicio: ini,
    p_fin: fin,
    p_uso: 'personal',
    p_destino: null,
    p_personas: 4,
  });
  expect(bf.error).toBeNull();
  expect(bx.error).toBeNull();
  creadas.push(bf.data as string, bx.data as string);
  const [rf, rx] = await Promise.all([
    cf.rpc('reserva_confirmar', { p_reserva: bf.data }),
    cx.rpc('reserva_confirmar', { p_reserva: bx.data }),
  ]);
  const ok = [rf, rx].filter((r) => !r.error).length;
  const fallo = [rf, rx].filter((r) => r.error?.message.includes('horario_ocupado')).length;
  expect(ok).toBe(1);
  expect(fallo).toBe(1);
});

test('capacidad: 16 en uso de socio y 9 de invitado se rechazan en la base aunque falle la UI', async () => {
  const dia = fechaFutura(base + 2);
  const cf = await cliente('felipe.demo@shared.test');
  const a = await cf.rpc('reserva_crear_borrador', {
    p_activo: ACTIVO,
    p_inicio: `${dia}T14:00:00Z`,
    p_fin: `${dia}T16:00:00Z`,
    p_uso: 'personal',
    p_destino: null,
    p_personas: 16,
  });
  expect(a.error?.message).toContain('capacidad_excedida');
  const b = await cf.rpc('reserva_crear_borrador', {
    p_activo: ACTIVO,
    p_inicio: `${dia}T14:00:00Z`,
    p_fin: `${dia}T16:00:00Z`,
    p_uso: 'invitado',
    p_destino: null,
    p_personas: 9,
    p_invitado_nombre: 'Pedro Prueba',
    p_invitado_correo: 'pedro@shared.test',
  });
  expect(b.error?.message).toContain('capacidad_excedida');
});

test('invitado sin cuenta: el enlace muestra solo lo permitido; alterado o ajeno no devuelve nada', async ({
  page,
}) => {
  const dia = fechaFutura(base + 3);
  const cf = await cliente('felipe.demo@shared.test');
  const b = await cf.rpc('reserva_crear_borrador', {
    p_activo: ACTIVO,
    p_inicio: `${dia}T14:00:00Z`,
    p_fin: `${dia}T18:00:00Z`,
    p_uso: 'invitado',
    p_destino: '30000000-0000-4000-8000-000000000001',
    p_personas: 8,
    p_invitado_nombre: 'Pedro Prueba',
    p_invitado_correo: 'pedro@shared.test',
  });
  expect(b.error).toBeNull();
  creadas.push(b.data as string);
  expect((await cf.rpc('reserva_confirmar', { p_reserva: b.data })).error).toBeNull();

  const { data: notif } = await admin()
    .from('notificaciones')
    .select('datos')
    .eq('destinatario_correo', 'pedro@shared.test')
    .eq('tipo', 'invitado_enlace')
    .order('creado_en', { ascending: false })
    .limit(1)
    .single();
  const token = (notif!.datos as { token?: string }).token as string;
  expect(token).toHaveLength(64);

  const ok = await fetch(`${URL}/functions/v1/guest-view?token=${token}`);
  expect(ok.status).toBe(200);
  const vista = await ok.json();
  expect(Object.keys(vista).sort()).toEqual([
    'activo',
    'contacto',
    'destino',
    'fin',
    'inicio',
    'invitado',
    'personas',
    'punto_encuentro',
    'reglas',
    'zona_horaria',
  ]);
  expect(JSON.stringify(vista).toLowerCase()).not.toMatch(/fee|tarifa|monto/);
  expect(vista.punto_encuentro).toBe('Marina (demo)');

  const alterado = await fetch(`${URL}/functions/v1/guest-view?token=${token.slice(0, 63)}0`);
  expect(alterado.status).toBe(404);
  const ajeno = await fetch(`${URL}/functions/v1/guest-view?token=${'a'.repeat(64)}`);
  expect(ajeno.status).toBe(404);

  // página pública sin sesión
  await page.goto(`/g/${token}`);
  await expect(page.getByText('Marina (demo)')).toBeVisible();
  await expect(page.getByText('Hola, Pedro Prueba')).toBeVisible();
  await page.goto(`/g/${'b'.repeat(64)}`);
  await expect(page.getByText('no es válido')).toBeVisible();
});
