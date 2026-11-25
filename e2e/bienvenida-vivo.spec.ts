import { createClient } from '@supabase/supabase-js';
import { expect, test } from '@playwright/test';
import { readFileSync } from 'node:fs';

// Pantalla de bienvenida de un usuario SIN grupos contra shared-dev. Requiere E2E_VIVO=1.
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
const CLAVE = 'Bienvenida-2026';
const SUFIJO = Date.now();
const NUEVO = `e2e.nuevo.${SUFIJO}@shared.test`;
const DUENO = `e2e.dueno.${SUFIJO}@shared.test`;
const ids: string[] = [];
let grupoId = '';

const servicio = () => createClient(URL, SERVICIO, { auth: { persistSession: false } });

test.beforeAll(async () => {
  const s = servicio();
  for (const correo of [NUEVO, DUENO]) {
    const { data } = await s.auth.admin.createUser({ email: correo, password: CLAVE, email_confirm: true, user_metadata: { nombre: correo.split('@')[0] } });
    ids.push(data.user!.id);
  }
});

test.afterAll(async () => {
  const s = servicio();
  if (grupoId) await s.from('grupos').delete().eq('id', grupoId);
  for (const id of ids) await s.auth.admin.deleteUser(id);
});

test('un usuario sin grupos ve la bienvenida con 3 opciones y el formulario de crear oculto', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Correo').fill(NUEVO);
  await page.getByLabel('Contraseña', { exact: true }).fill(CLAVE);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page).toHaveURL(/\/grupos/);

  await expect(page.getByRole('heading', { name: 'Bienvenido a Shared', level: 1 })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Tengo una invitación' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Explorar la plataforma' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Crear un grupo' })).toBeVisible();
  // el formulario no aparece hasta pedirlo
  await expect(page.getByLabel('Nombre del grupo')).toHaveCount(0);
  await page.getByRole('button', { name: 'Crear un grupo nuevo' }).click();
  await expect(page.getByLabel('Nombre del grupo')).toBeVisible();
  await page.getByRole('button', { name: 'Cancelar' }).click();
  await expect(page.getByLabel('Nombre del grupo')).toHaveCount(0);

  // no queda atrapado: perfil y cerrar sesión siguen a mano
  await expect(page.getByRole('link', { name: 'Mi perfil' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Salir', exact: true })).toBeVisible();
  // el recorrido es de solo lectura
  await page.getByRole('button', { name: 'Ver el recorrido' }).click();
  await expect(page.getByRole('heading', { name: 'Calendario sin choques' })).toBeVisible();
  await page.getByRole('button', { name: 'Siguiente' }).click();
  await expect(page.getByRole('heading', { name: 'Reservas y salidas' })).toBeVisible();
  // directorio apagado por defecto: sin entrada
  await expect(page.getByRole('link', { name: 'Ver propuestas y directorio' })).toHaveCount(0);
});

test('pegar un enlace inválido o inexistente muestra un error claro', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Correo').fill(NUEVO);
  await page.getByLabel('Contraseña', { exact: true }).fill(CLAVE);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page).toHaveURL(/\/grupos/);

  const campo = page.getByLabel('Enlace o código de invitación');
  await campo.fill('hola');
  await page.getByRole('button', { name: 'Abrir invitación' }).click();
  await expect(page.getByRole('alert').filter({ hasText: 'no parece un enlace' })).toBeVisible();

  await campo.fill(`https://shared-csd.vercel.app/unirse/${'a'.repeat(64)}`);
  await page.getByRole('button', { name: 'Abrir invitación' }).click();
  await expect(page.getByRole('alert').filter({ hasText: 'No encontramos esa invitación' })).toBeVisible();
});

test('una invitación a mi correo aparece sola y se acepta con un clic', async ({ page }) => {
  // el dueño crea un grupo y me invita (cuenta real, sin enviar correo: la RPC solo guarda la invitación)
  const dueno = createClient(URL, ANON, { auth: { persistSession: false } });
  await dueno.auth.signInWithPassword({ email: DUENO, password: CLAVE });
  const { data: g } = await dueno.rpc('crear_grupo', { p_nombre: `Grupo Bienvenida ${SUFIJO}`, p_moneda: 'DOP', p_zona_horaria: 'America/Santo_Domingo', p_prefijo: 'BIE', p_porcentaje: 60 });
  grupoId = g as string;
  const { error } = await dueno.rpc('invitar_miembro', { p_grupo: grupoId, p_correo: NUEVO, p_rol: 'socio', p_porcentaje: 40 });
  expect(error).toBeNull();

  await page.goto('/login');
  await page.getByLabel('Correo').fill(NUEVO);
  await page.getByLabel('Contraseña', { exact: true }).fill(CLAVE);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page).toHaveURL(/\/grupos/);
  const tarjeta = page.locator('.pendiente', { hasText: `Grupo Bienvenida ${SUFIJO}` });
  await expect(tarjeta).toBeVisible();
  await tarjeta.getByRole('button', { name: 'Aceptar invitación' }).click();
  await expect(page).toHaveURL(/\/calendario/);

  // otra persona no ve esa invitación (ya aceptada y, además, no era suya)
  const otro = createClient(URL, ANON, { auth: { persistSession: false } });
  await otro.auth.signInWithPassword({ email: DUENO, password: CLAVE });
  const { data: lista } = await otro.rpc('invitaciones_pendientes_mias');
  expect(lista).toEqual([]);
});
