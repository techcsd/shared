import { createClient } from '@supabase/supabase-js';
import { expect, test, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';

// Ciclo completo contra shared-dev con los usuarios demo: reservar → check-in → gastos → check-out → liquidar → balances.
// Se activa con E2E_VIVO=1. Reinicia los datos demo de operación y finanzas al empezar y al terminar.
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

const dia = (offset: number) => new Date(Date.now() + offset * 86400000).toISOString().slice(0, 10);
const base = 300 + Math.floor(Math.random() * 200);

let grupo = '';
let reserva = '';
let feeEsperado = 0;
let miembroFelipe = '';
let miembroXaviel = '';

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

async function balances(c: Awaited<ReturnType<typeof cliente>>) {
  const { data, error } = await c.rpc('balances_grupo', { p_grupo: grupo });
  if (error) throw error;
  const f = (id: string | null, tipo: string) =>
    Number(
      (data as { cuenta_tipo: string; miembro_id: string | null; balance: number }[]).find(
        (b) => b.cuenta_tipo === tipo && b.miembro_id === id,
      )?.balance ?? 0,
    );
  return {
    felipe: f(miembroFelipe, 'miembro'),
    xaviel: f(miembroXaviel, 'miembro'),
    fondo: f(null, 'fondo'),
  };
}

test.beforeAll(async () => {
  const a = admin();
  const { data: act } = await a.from('activos').select('grupo_id').eq('id', ACTIVO).single();
  grupo = act!.grupo_id;
  const { data: ms } = await a
    .from('miembros')
    .select('id, perfil:perfiles(correo)')
    .eq('grupo_id', grupo);
  for (const m of ms ?? []) {
    const correo = (m.perfil as unknown as { correo: string } | null)?.correo;
    if (correo === 'felipe.demo@shared.test') miembroFelipe = m.id;
    if (correo === 'xaviel.demo@shared.test') miembroXaviel = m.id;
  }
  const felipe = await cliente('felipe.demo@shared.test');
  const r = await felipe.rpc('demo_reiniciar_operacion', { p_grupo: grupo });
  if (r.error) throw new Error(`reinicio demo falló: ${r.error.message}`);
});

test.afterAll(async () => {
  const felipe = await cliente('felipe.demo@shared.test');
  const r = await felipe.rpc('demo_reiniciar_operacion', { p_grupo: grupo });
  if (r.error) throw new Error(`reinicio demo falló: ${r.error.message}`);
  if (reserva) {
    const a = admin();
    await a.from('reservas').delete().eq('id', reserva);
  }
});

test('reserva confirmada → check-in con faltantes → salida', async ({ browser }) => {
  const felipe = await cliente('felipe.demo@shared.test');
  const { data: t } = await admin()
    .from('tarifas')
    .select('destino_id, monto')
    .eq('grupo_id', grupo)
    .eq('tipo', 'fee_destino')
    .gt('monto', 0)
    .limit(1)
    .single();
  feeEsperado = Number(t!.monto);
  const ini = new Date(`${dia(base)}T13:00:00Z`);
  const fin = new Date(`${dia(base)}T19:00:00Z`);
  const { data: id, error } = await felipe.rpc('reserva_crear_borrador', {
    p_activo: ACTIVO,
    p_inicio: ini.toISOString(),
    p_fin: fin.toISOString(),
    p_uso: 'familiar',
    p_destino: t!.destino_id,
    p_personas: 6,
    p_responsable_miembro: miembroFelipe,
  });
  expect(error).toBeNull();
  reserva = id as string;
  const c = await felipe.rpc('reserva_confirmar', { p_reserva: reserva });
  expect(c.error).toBeNull();

  const page = await (await browser.newContext()).newPage();
  await entrar(page, 'felipe.demo@shared.test');
  await page.goto(`/operacion/${reserva}`);
  await expect(page.getByRole('heading', { name: /Salida \(check-in\)/ })).toBeVisible();

  // sin checklist ni combustible: la base responde QUÉ falta, no un error genérico
  await page.getByRole('button', { name: 'Salir', exact: true }).click();
  await expect(page.getByText('Falta para poder salir:')).toBeVisible();
  await expect(page.getByText(/Checklist pendiente/).first()).toBeVisible();
  await expect(page.getByText(/Combustible inicial/).nth(1)).toBeVisible();

  // completo todo
  await page.getByLabel(/Combustible inicial/).fill('100');
  const iniciales = page.locator('input[id^="o-li-"]');
  await iniciales.nth(0).fill('100');
  await iniciales.nth(1).fill('200');
  for (const cb of await page.locator('label.chequeo input[type=checkbox]').all()) await cb.check();
  await page.getByRole('button', { name: 'Salir', exact: true }).click();
  await expect(page.getByText('Salida registrada. ¡Buen viaje!')).toBeVisible();
  await expect(page.getByRole('heading', { name: /Regreso \(check-out\)/ })).toBeVisible();
});

test('regreso: faltantes, lectura final menor rechazada, gasto del viaje, cierre y liquidación', async ({
  browser,
}) => {
  const antes = await balances(await cliente('felipe.demo@shared.test'));
  const page = await (await browser.newContext()).newPage();
  await entrar(page, 'felipe.demo@shared.test');
  await page.goto(`/operacion/${reserva}`);
  await expect(page.getByRole('heading', { name: /Regreso \(check-out\)/ })).toBeVisible();

  // en blanco: lista de lo que falta; la orden NO se cierra
  await page.getByRole('button', { name: 'Registrar regreso y cerrar' }).click();
  await expect(page.getByText('Falta para cerrar la orden:')).toBeVisible();
  await expect(page.getByText(/Lectura final/).first()).toBeVisible();

  // lectura final menor que la inicial: la base la rechaza con mensaje claro
  const finales = page.locator('input[id^="o-lf-"]');
  const n = await finales.count();
  expect(n).toBe(2); // un campo por motor
  await finales.nth(0).fill('0');
  const inicial = Number(
    (await page.locator('label[for^="o-lf-"]').first().innerText()).match(/Inicio: ([\d.]+)/)![1],
  );
  expect(inicial).toBe(100);
  await page.getByRole('button', { name: 'Registrar regreso y cerrar' }).click();
  await expect(page.getByText('La lectura final no puede ser menor que la inicial.')).toBeVisible();

  // gasto individual del viaje (se carga a quien reservó) con foto opcional
  await page.getByLabel('Categoría').selectOption('hielo');
  await page.getByLabel(/^Monto/).fill('300');
  await page.getByRole('button', { name: 'Agregar gasto' }).click();
  await expect(page.getByText('hielo').first()).toBeVisible();
  await expect(page.getByText(/300 DOP/).first()).toBeVisible();

  // datos completos
  for (let i = 0; i < n; i++) {
    const ini = Number(
      (await page.locator('label[for^="o-lf-"]').nth(i).innerText()).match(/Inicio: ([\d.]+)/)![1],
    );
    await finales.nth(i).fill(String(ini + 5));
  }
  await page.getByLabel(/Combustible final/).fill('60');
  await page.getByLabel(/Combustible agregado/).fill('10');
  for (const cb of await page.locator('label.chequeo input[type=checkbox]').all()) await cb.check();
  await page.getByRole('button', { name: 'Registrar regreso y cerrar' }).click();
  await expect(page.getByText('Orden cerrada y liquidada.')).toBeVisible();

  // resumen: horas = final − inicial; consumido = 100 + 10 − 60 = 50
  await expect(page.getByText('Resumen de la salida')).toBeVisible();
  await expect(page.getByText(/\(5\)/).first()).toBeVisible();

  // balances: Felipe debe el fee y su gasto individual (que él mismo pagó se compensa); el fondo recibe el fee
  const despues = await balances(await cliente('felipe.demo@shared.test'));
  expect(+(despues.felipe - antes.felipe).toFixed(2)).toBe(-feeEsperado);
  expect(+(despues.fondo - antes.fondo).toFixed(2)).toBe(feeEsperado);
  expect(+(despues.xaviel - antes.xaviel).toFixed(2)).toBe(0);
});

test('Xaviel valida el gasto y los balances cuadran; un pago solo cuenta cuando lo confirma el receptor', async ({
  browser,
}) => {
  const felipeApi = await cliente('felipe.demo@shared.test');
  const xavielApi = await cliente('xaviel.demo@shared.test');
  const x = await (await browser.newContext()).newPage();
  await entrar(x, 'xaviel.demo@shared.test');

  // gasto común de 100 que paga Felipe → +50 / −50
  const antes = await balances(felipeApi);
  const g = await felipeApi.rpc('gasto_registrar', {
    p_grupo: grupo,
    p_alcance: 'comun',
    p_categoria: 'mantenimiento',
    p_monto: 100,
    p_moneda: 'DOP',
  });
  expect(g.error).toBeNull();
  const tras = await balances(felipeApi);
  expect(+(tras.felipe - antes.felipe).toFixed(2)).toBe(50);
  expect(+(tras.xaviel - antes.xaviel).toFixed(2)).toBe(-50);

  // el que cargó no valida lo suyo; el otro socio sí, desde la pantalla Gastos
  const propio = await felipeApi.rpc('gasto_validar', { p_gasto: g.data });
  expect(propio.error?.message ?? '').toContain('otro_socio');
  await x.goto('/gastos');
  await expect(x.getByText('Gastos provisionales (sin validar)')).toBeVisible();
  const tarjeta = x.locator('article.gasto', { hasText: 'mantenimiento' }).first();
  await expect(tarjeta.getByText('Provisional')).toBeVisible();
  await tarjeta.getByRole('button', { name: 'Validar' }).click();
  await expect(tarjeta.getByText('Validado')).toBeVisible();

  // pantalla Finanzas: la suma de todas las cuentas es 0
  await x.goto('/mas/finanzas');
  await expect(x.getByText('Balance por socio')).toBeVisible();
  await expect(x.getByTestId('suma-total')).toHaveText(/^-?0([.,]00)?$/);

  // un pago sin confirmar NO cambia balances; confirmado, sí
  const antesPago = await balances(felipeApi);
  const p = await xavielApi.rpc('pago_registrar', {
    p_grupo: grupo,
    p_a_miembro: miembroFelipe,
    p_monto: 20,
    p_moneda: 'DOP',
  });
  expect(p.error).toBeNull();
  expect(await balances(felipeApi)).toEqual(antesPago);
  await x.goto('/mas/finanzas');
  await x.getByRole('tab', { name: 'Pagos' }).click();
  const f = await (await browser.newContext()).newPage();
  await entrar(f, 'felipe.demo@shared.test');
  await f.goto('/mas/finanzas');
  await f.getByRole('tab', { name: 'Pagos' }).click();
  await f.getByRole('button', { name: 'Confirmar que lo recibí' }).first().click();
  await expect(f.getByText('Confirmado').first()).toBeVisible();
  const trasPago = await balances(felipeApi);
  expect(+(trasPago.felipe - antesPago.felipe).toFixed(2)).toBe(-20);
  expect(+(trasPago.xaviel - antesPago.xaviel).toFixed(2)).toBe(20);
});

test('un daño no cobra nada hasta que acuerdan todos los socios', async () => {
  const felipe = await cliente('felipe.demo@shared.test');
  const xaviel = await cliente('xaviel.demo@shared.test');
  const antes = await balances(felipe);
  const c = await felipe.rpc('dano_abrir', { p_grupo: grupo, p_titulo: 'Rayón en el casco' });
  expect(c.error).toBeNull();
  const prop = await felipe.rpc('dano_proponer', {
    p_caso: c.data,
    p_presupuesto: 1000,
    p_moneda: 'DOP',
    p_pagado_tipo: 'miembro',
    p_pagado_miembro: miembroFelipe,
    p_propuesta: [
      { miembro_id: miembroFelipe, monto: 400 },
      { miembro_id: miembroXaviel, monto: 600 },
    ],
  });
  expect(prop.error).toBeNull();
  expect(await balances(felipe)).toEqual(antes); // sin acuerdo completo, ningún cargo
  const r = await xaviel.rpc('dano_responder', { p_caso: c.data, p_acepta: true });
  expect(r.error).toBeNull();
  const despues = await balances(felipe);
  expect(+(despues.felipe - antes.felipe).toFixed(2)).toBe(600); // adelantó 1000, le toca 400
  expect(+(despues.xaviel - antes.xaviel).toFixed(2)).toBe(-600);
});
