import { createClient } from '@supabase/supabase-js';
import { expect, test, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';

// «Entrar como» y acceso total del admin de plataforma contra shared-dev. Requiere E2E_VIVO=1.
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
const ADMIN = 'xaviel.demo@shared.test';
const NORMAL = 'felipe.demo@shared.test';
const CLAVE = 'Demo1234!';

const servicio = () => createClient(URL, SERVICIO, { auth: { persistSession: false } });
let eraAdmin = false;
let adminId = '';
let normalId = '';
let grupoAjenoId = '';
let ajenoId = '';
let nombreAjeno = '';

async function entrar(page: Page, correo: string) {
  await page.goto('/login');
  await page.getByLabel('Correo').fill(correo);
  await page.getByLabel('Contraseña', { exact: true }).fill(CLAVE);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page).toHaveURL(/\/calendario/);
}

test.beforeAll(async () => {
  const s = servicio();
  const { data: lista } = await s.auth.admin.listUsers({ perPage: 200 });
  adminId = lista.users.find((u) => u.email === ADMIN)!.id;
  normalId = lista.users.find((u) => u.email === NORMAL)!.id;
  const { data: ya } = await s.from('plataforma_admins').select('usuario_id').eq('usuario_id', adminId);
  eraAdmin = (ya ?? []).length > 0;
  if (!eraAdmin) await s.from('plataforma_admins').insert({ usuario_id: adminId });
  // un grupo ajeno: lo crea un usuario temporal del que el admin no es miembro
  const correo = `e2e.ajeno.${Date.now()}@shared.test`;
  const { data: u } = await s.auth.admin.createUser({ email: correo, password: CLAVE, email_confirm: true, user_metadata: { nombre: 'Dueño Ajeno' } });
  ajenoId = u.user!.id;
  const c = createClient(URL, ANON, { auth: { persistSession: false } });
  await c.auth.signInWithPassword({ email: correo, password: CLAVE });
  nombreAjeno = `Grupo Ajeno ${Date.now()}`;
  const { data: g } = await c.rpc('crear_grupo', { p_nombre: nombreAjeno, p_moneda: 'DOP', p_zona_horaria: 'America/Santo_Domingo', p_prefijo: 'AJE', p_porcentaje: 100 });
  grupoAjenoId = g as string;
});

test.afterAll(async () => {
  const s = servicio();
  if (grupoAjenoId) await s.from('grupos').delete().eq('id', grupoAjenoId);
  if (ajenoId) await s.auth.admin.deleteUser(ajenoId);
  if (!eraAdmin) await s.from('plataforma_admins').delete().eq('usuario_id', adminId);
});

test('el admin entra como un usuario, ve el banner, datos del usuario y vuelve a su cuenta', async ({ page }) => {
  await entrar(page, ADMIN);
  await page.goto('/admin');
  const tarjeta = page.locator('article.tarjeta', { hasText: NORMAL }).first();
  await expect(tarjeta).toBeVisible();
  await tarjeta.getByRole('button', { name: 'Entrar como' }).click();

  // ahora la app es la de Felipe
  await expect(page.getByRole('alert').filter({ hasText: 'Estás viendo Shared como' })).toBeVisible();
  await expect(page).toHaveURL(/\/calendario/);
  // sesión real de Felipe: su perfil lo confirma y no es admin de plataforma
  await page.goto('/perfil');
  await expect(page.getByRole('alert').filter({ hasText: 'Estás viendo Shared como' })).toBeVisible();
  await page.goto('/admin');
  await expect(page).not.toHaveURL(/\/admin/); // como Felipe no hay panel de administración

  // volver restaura al admin
  await page.getByRole('button', { name: 'Volver a mi cuenta' }).click();
  await expect(page).toHaveURL(/\/admin/);
  await expect(page.getByRole('alert').filter({ hasText: 'Estás viendo Shared como' })).toHaveCount(0);
  await expect(page.locator('article.tarjeta', { hasText: NORMAL }).first()).toBeVisible();
});

test('en la lista no hay «Entrar como» para otros admins, bloqueados ni para uno mismo', async ({ page }) => {
  await entrar(page, ADMIN);
  await page.goto('/admin');
  const propia = page.locator('article.tarjeta', { hasText: ADMIN }).first();
  await expect(propia).toBeVisible();
  await expect(propia.getByRole('button', { name: 'Entrar como' })).toHaveCount(0);
});

test('el admin abre un grupo ajeno sin ser miembro y lo ve (vista de administrador)', async ({ page }) => {
  await entrar(page, ADMIN);
  await page.goto('/admin');
  await page.getByRole('button', { name: 'Grupos' }).click();
  const tarjeta = page.locator('article.tarjeta', { hasText: nombreAjeno }).first();
  await tarjeta.getByRole('button', { name: 'Abrir como administrador' }).click();
  await expect(page).toHaveURL(/\/calendario/);
  await expect(page.getByText('Vista de administrador de plataforma')).toBeVisible();
});

test('la edge function rechaza «impersonar» sin sesión y a quien no es admin; y a un admin como objetivo', async () => {
  const sin = await fetch(`${URL}/functions/v1/admin-usuarios`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: ANON },
    body: JSON.stringify({ accion: 'impersonar', usuario_id: normalId }),
  });
  expect(sin.status).toBe(401);

  const felipe = createClient(URL, ANON, { auth: { persistSession: false } });
  const { data: s1 } = await felipe.auth.signInWithPassword({ email: NORMAL, password: CLAVE });
  const comoFelipe = await fetch(`${URL}/functions/v1/admin-usuarios`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: ANON, Authorization: `Bearer ${s1.session!.access_token}` },
    body: JSON.stringify({ accion: 'impersonar', usuario_id: adminId }),
  });
  expect(comoFelipe.status).toBe(403);
  const texto = await comoFelipe.text();
  expect(texto).not.toContain('token_hash');

  const adm = createClient(URL, ANON, { auth: { persistSession: false } });
  const { data: s2 } = await adm.auth.signInWithPassword({ email: ADMIN, password: CLAVE });
  const aMismo = await fetch(`${URL}/functions/v1/admin-usuarios`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: ANON, Authorization: `Bearer ${s2.session!.access_token}` },
    body: JSON.stringify({ accion: 'impersonar', usuario_id: adminId }),
  });
  expect(aMismo.status).toBe(409);
});
