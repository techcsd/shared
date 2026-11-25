import { createClient } from '@supabase/supabase-js';
import { expect, test } from '@playwright/test';
import { readFileSync } from 'node:fs';

// Vitrina del activo contra shared-dev: ícono SVG sin foto, foto tras subirla, y vista previa en la invitación.
// Requiere E2E_VIVO=1.
test.skip(!process.env['E2E_VIVO'], 'Requiere E2E_VIVO=1 y shared-dev');
test.describe.configure({ mode: 'serial' });

const env: Record<string, string> = {};
for (const l of readFileSync('.env.local', 'utf8').split(/\r?\n/)) {
  const m = l.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
  if (m) env[m[1]] = m[2];
}
const URL = env['NG_APP_SUPABASE_URL'];
const ANON = env['NG_APP_SUPABASE_ANON_KEY'];
const SERVICIO = env['SUPABASE_SERVICE_ROLE_KEY_DEV'];
const CLAVE = 'Vitrina-E2E-2026';
const SUFIJO = Date.now();
const DUENO = `e2e.vitrina.dueno.${SUFIJO}@shared.test`;
const INVITADO = `e2e.vitrina.inv.${SUFIJO}@shared.test`;
const DESCRIPCION = 'Ferrari 296 GTB de prueba: dos plazas, V6 híbrido, solo para pruebas.';
// PNG de 1×1 píxel
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64',
);

const ids: string[] = [];
let grupoId = '';
let token = '';

const servicio = () => createClient(URL, SERVICIO, { auth: { persistSession: false } });

async function entrar(page: import('@playwright/test').Page, correo: string) {
  await page.goto('/login');
  await page.getByLabel('Correo').fill(correo);
  await page.getByLabel('Contraseña', { exact: true }).fill(CLAVE);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page).not.toHaveURL(/\/login/);
}

test.beforeAll(async () => {
  const s = servicio();
  for (const correo of [DUENO, INVITADO]) {
    const { data } = await s.auth.admin.createUser({ email: correo, password: CLAVE, email_confirm: true, user_metadata: { nombre: correo.split('@')[0] } });
    ids.push(data.user!.id);
  }
  const dueno = createClient(URL, ANON, { auth: { persistSession: false } });
  await dueno.auth.signInWithPassword({ email: DUENO, password: CLAVE });
  const g = await dueno.rpc('crear_grupo', { p_nombre: 'Vitrina E2E', p_moneda: 'DOP', p_zona_horaria: 'America/Santo_Domingo', p_prefijo: 'VIE', p_porcentaje: 100 });
  grupoId = g.data as string;
  const tipo = await dueno.from('tipos_activo').select('id').eq('clave', 'carro').is('grupo_id', null).single();
  const a = await dueno.rpc('crear_activo', { p_grupo: grupoId, p_tipo: tipo.data!.id, p_nombre: 'Ferrari E2E', p_capacidad_legal: 2 });
  await dueno.from('activos').update({ descripcion: DESCRIPCION, punto_encuentro: 'Marina E2E' }).eq('id', a.data as string);
  const inv = await dueno.rpc('invitar_miembro', { p_grupo: grupoId, p_correo: INVITADO, p_rol: 'admin_operativo', p_porcentaje: 0 });
  token = inv.data as string;
});

test.afterAll(async () => {
  const s = servicio();
  if (grupoId) {
    const lista = await s.storage.from('activos').list(grupoId);
    const rutas = (lista.data ?? []).map((f) => `${grupoId}/${f.name}`);
    if (rutas.length) await s.storage.from('activos').remove(rutas);
    await s.from('grupos').delete().eq('id', grupoId);
  }
  for (const id of ids) await s.auth.admin.deleteUser(id);
});

test('sin foto, la vitrina muestra el ícono SVG, la descripción y los datos', async ({ page }) => {
  await entrar(page, DUENO);
  await page.goto('/activo');
  await expect(page.getByRole('heading', { name: 'Nuestro activo', level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Ferrari E2E' })).toBeVisible();
  await expect(page.getByText(DESCRIPCION)).toBeVisible();
  await expect(page.getByText('Capacidad: 2')).toBeVisible();
  await expect(page.getByText('Marina E2E').first()).toBeVisible();
  // sin foto: ícono SVG, ninguna imagen del bucket
  await expect(page.locator('app-activo-tarjeta .icono[role="img"]').first()).toBeVisible();
  await expect(page.locator('app-activo-tarjeta img')).toHaveCount(0);
  // avatar del encabezado con el ícono
  await expect(page.locator('.avatar-activo app-activo-tarjeta')).toBeVisible();
});

test('un socio sube una foto a la galería y la vitrina la muestra', async ({ page }) => {
  await entrar(page, DUENO);
  await page.goto('/activo?editar=1&tab=fotos');
  await page.locator('#fotos-in').setInputFiles({ name: 'ferrari.png', mimeType: 'image/png', buffer: PNG });
  await expect(page.locator('.ae-foto')).toHaveCount(1);
  await page.getByRole('button', { name: 'Terminar edición' }).click();
  await page.getByRole('tab', { name: 'Resumen' }).click();
  const foto = page.locator('app-activo-tarjeta img').first();
  await expect(foto).toBeVisible();
  await expect(foto).toHaveAttribute('src', new RegExp(`/storage/v1/object/public/activos/${grupoId}/`));
  await expect.poll(() => foto.evaluate((el: HTMLImageElement) => el.naturalWidth)).toBeGreaterThan(0);
});

test('el invitado ve el activo en su invitación y en la página del enlace, y aún no es miembro', async ({ page }) => {
  await entrar(page, INVITADO);
  await expect(page).toHaveURL(/\/grupos/);
  const pendiente = page.locator('.pendiente', { hasText: 'Vitrina E2E' });
  await expect(pendiente).toBeVisible();
  await expect(pendiente.getByText('Ferrari E2E')).toBeVisible();
  await page.goto(`/unirse/${token}`);
  await expect(page.getByRole('heading', { name: 'Ferrari E2E' })).toBeVisible();
  await expect(page.getByText(DESCRIPCION)).toBeVisible();
  // el subconjunto público no incluye datos internos
  await expect(page.getByText('Chaleco')).toHaveCount(0);
});
