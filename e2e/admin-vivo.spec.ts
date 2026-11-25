import { createClient } from '@supabase/supabase-js';
import { expect, test, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';

// Panel de administración de plataforma contra shared-dev: crear usuario, agregarlo a un grupo sin invitación,
// repartir/quitar, bloquear y borrar; y que un usuario normal no entre. Requiere E2E_VIVO=1.
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
const NUEVO = `e2e.admin.${Date.now()}@shared.test`;
const CLAVE_NUEVO = 'E2e-Admin-2026';

const servicio = () => createClient(URL, SERVICIO, { auth: { persistSession: false } });
let eraAdmin = false;
let adminId = '';

async function entrar(page: Page, correo: string, clave = 'Demo1234!') {
  await page.goto('/login');
  await page.getByLabel('Correo').fill(correo);
  await page.getByLabel('Contraseña', { exact: true }).fill(clave);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page).toHaveURL(/\/calendario/);
}

test.beforeAll(async () => {
  const s = servicio();
  const { data: lista } = await s.auth.admin.listUsers({ perPage: 200 });
  adminId = lista.users.find((u) => u.email === ADMIN)!.id;
  const { data: ya } = await s.from('plataforma_admins').select('usuario_id').eq('usuario_id', adminId);
  eraAdmin = (ya ?? []).length > 0;
  if (!eraAdmin) await s.from('plataforma_admins').insert({ usuario_id: adminId });
});

test.afterAll(async () => {
  const s = servicio();
  const { data: lista } = await s.auth.admin.listUsers({ perPage: 200 });
  const u = lista.users.find((x) => x.email === NUEVO);
  if (u) {
    await s.from('miembros').delete().eq('usuario_id', u.id);
    await s.auth.admin.deleteUser(u.id);
  }
  if (!eraAdmin) await s.from('plataforma_admins').delete().eq('usuario_id', adminId);
});

test('un usuario normal no entra al panel ni a la edge function', async ({ page }) => {
  await entrar(page, NORMAL);
  await page.goto('/admin');
  await expect(page).not.toHaveURL(/\/admin/);
  const c = createClient(URL, ANON, { auth: { persistSession: false } });
  await c.auth.signInWithPassword({ email: NORMAL, password: 'Demo1234!' });
  const token = (await c.auth.getSession()).data.session!.access_token;
  const r = await fetch(`${URL}/functions/v1/admin-usuarios`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}`, apikey: ANON },
    body: JSON.stringify({ accion: 'crear', email: 'no@shared.test', password: 'Abcdefgh1', nombre: 'No' }),
  });
  expect(r.status).toBe(403);
  const rpc = await c.rpc('admin_usuarios_listar');
  expect(rpc.error?.message ?? '').toContain('solo_admin_plataforma');
});

test('el admin crea un usuario, lo agrega a un grupo sin invitación, lo bloquea y lo borra', async ({ page }) => {
  await entrar(page, ADMIN);
  await page.goto('/admin');
  await expect(page.getByRole('heading', { name: 'Administración de la plataforma' })).toBeVisible();

  // crear usuario
  await page.getByLabel('Correo', { exact: true }).fill(NUEVO);
  await page.getByLabel('Nombre', { exact: true }).fill('E2E Admin');
  await page.getByLabel('Contraseña (mínimo 8)').fill(CLAVE_NUEVO);
  await page.getByRole('button', { name: 'Crear usuario' }).last().click();
  await expect(page.getByText('Usuario creado.')).toBeVisible();
  await expect(page.getByText(NUEVO)).toBeVisible();

  // el usuario nuevo ya puede entrar
  const c = createClient(URL, ANON, { auth: { persistSession: false } });
  const { error } = await c.auth.signInWithPassword({ email: NUEVO, password: CLAVE_NUEVO });
  expect(error).toBeNull();

  // agregarlo al grupo demo (activo, suma 100) con 0 %: no rompe el 100
  await page.getByRole('button', { name: /^Grupos/ }).click();
  await page.getByRole('button', { name: 'Gestionar' }).first().click();
  await page.getByLabel('Usuario', { exact: true }).selectOption({ label: `E2E Admin (${NUEVO})` });
  await page.getByLabel('Rol', { exact: true }).selectOption('capitan');
  await page.getByRole('button', { name: 'Agregar al grupo' }).click();
  await expect(page.getByText('Usuario agregado al grupo.')).toBeVisible();
  const s = servicio();
  const { data: lista } = await s.auth.admin.listUsers({ perPage: 200 });
  const nuevoId = lista.users.find((u) => u.email === NUEVO)!.id;
  const { data: m } = await s.from('miembros').select('rol, estado, porcentaje').eq('usuario_id', nuevoId);
  expect(m).toEqual([{ rol: 'capitan', estado: 'activo', porcentaje: 0 }]);

  // quitarlo (queda como salido)
  await page.locator('div.cab', { hasText: NUEVO }).getByRole('button', { name: 'Quitar del grupo' }).click();
  await expect(page.getByText('Miembro quitado')).toBeVisible();
  const { data: m2 } = await s.from('miembros').select('estado').eq('usuario_id', nuevoId);
  expect(m2).toEqual([{ estado: 'salido' }]);

  // bloquear y desbloquear
  await page.getByRole('button', { name: /^Usuarios/ }).click();
  const fila = page.locator('article', { hasText: NUEVO });
  await fila.getByRole('button', { name: 'Bloquear' }).click();
  await expect(page.getByText('Usuario bloqueado.')).toBeVisible();
  const bloqueado = await createClient(URL, ANON, { auth: { persistSession: false } }).auth.signInWithPassword({ email: NUEVO, password: CLAVE_NUEVO });
  expect(bloqueado.error).not.toBeNull();
  await fila.getByRole('button', { name: 'Desbloquear' }).click();
  await expect(page.getByText('Usuario desbloqueado.')).toBeVisible();

  // el admin no puede quedarse sin permisos ni borrarse a sí mismo
  const propia = page.locator('article', { hasText: ADMIN });
  await propia.getByRole('button', { name: 'Borrar' }).click();
  await propia.getByRole('alertdialog').getByRole('button', { name: 'Borrar' }).click();
  await expect(page.getByText('No se puede borrar:')).toBeVisible();

  // borrar el usuario de prueba
  await fila.getByRole('button', { name: 'Borrar' }).click();
  await fila.getByRole('alertdialog').getByRole('button', { name: 'Borrar' }).click();
  await expect(page.getByText('Usuario borrado.')).toBeVisible();
  await expect(page.getByText(NUEVO)).toHaveCount(0);

  // la bitácora quedó registrada
  const { data: bit } = await s.from('admin_acciones').select('accion').in('accion', ['usuario_crear', 'usuario_borrar', 'miembro_guardar']);
  expect((bit ?? []).length).toBeGreaterThanOrEqual(3);
});
