import { createClient } from '@supabase/supabase-js';
import { expect, test, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';

// El activo como entidad editable, contra shared-dev: admin edita, socio sin permiso solo lee, el admin delega,
// galería con portada, documento privado, historial y valor solo para socios. Requiere E2E_VIVO=1.
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
const CLAVE = 'Entidad-E2E-2026';
const SUFIJO = Date.now();
const correo = (n: string) => `e2e.entidad.${n}.${SUFIJO}@shared.test`;
const DUENO = correo('dueno');
const SOCIO2 = correo('socio2');
const SOCIO3 = correo('socio3');
const AJENO = correo('ajeno');
const DESCRIPCION = 'Ferrari 296 GTB de prueba para la ficha completa.';
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64',
);
const PDF = Buffer.from('%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n');

const ids: Record<string, string> = {};
let grupoId = '';
let activoId = '';
let rutaDoc = '';

const servicio = () => createClient(URL, SERVICIO, { auth: { persistSession: false } });

async function entrar(page: Page, mail: string) {
  await page.goto('/login');
  await page.getByLabel('Correo').fill(mail);
  await page.getByLabel('Contraseña', { exact: true }).fill(CLAVE);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page).not.toHaveURL(/\/login/);
}

const ir = (page: Page, editar = false, tab = '') =>
  page.goto(`/activo?activo=${activoId}${editar ? '&editar=1' : ''}${tab ? `&tab=${tab}` : ''}`);

test.beforeAll(async () => {
  const s = servicio();
  for (const [n, mail] of [['dueno', DUENO], ['socio2', SOCIO2], ['socio3', SOCIO3], ['ajeno', AJENO]] as const) {
    const { data } = await s.auth.admin.createUser({ email: mail, password: CLAVE, email_confirm: true, user_metadata: { nombre: `E2E ${n}` } });
    ids[n] = data.user!.id;
  }
  const dueno = createClient(URL, ANON, { auth: { persistSession: false } });
  await dueno.auth.signInWithPassword({ email: DUENO, password: CLAVE });
  const g = await dueno.rpc('crear_grupo', { p_nombre: 'Entidad E2E', p_moneda: 'DOP', p_zona_horaria: 'America/Santo_Domingo', p_prefijo: 'ENE', p_porcentaje: 50 });
  grupoId = g.data as string;
  const tipo = await dueno.from('tipos_activo').select('id').eq('clave', 'bote').is('grupo_id', null).single();
  const a = await dueno.rpc('crear_activo', { p_grupo: grupoId, p_tipo: tipo.data!.id, p_nombre: 'Ferrari Entidad', p_capacidad_legal: 2 });
  activoId = a.data as string;
  // los otros dos socios entran en una sola transacción (los porcentajes deben sumar 100)
  const ins = await s.from('miembros').insert([
    { grupo_id: grupoId, usuario_id: ids['socio2'], rol: 'socio', porcentaje: 30 },
    { grupo_id: grupoId, usuario_id: ids['socio3'], rol: 'socio', porcentaje: 20 },
  ]);
  if (ins.error) throw new Error(ins.error.message);
});

test.afterAll(async () => {
  const s = servicio();
  if (grupoId) {
    for (const b of ['activos', 'activo-documentos']) {
      const lista = await s.storage.from(b).list(grupoId);
      const rutas = (lista.data ?? []).map((f) => `${grupoId}/${f.name}`);
      if (rutas.length) await s.storage.from(b).remove(rutas);
    }
    await s.from('grupos').delete().eq('id', grupoId);
  }
  for (const id of Object.values(ids)) await s.auth.admin.deleteUser(id);
});

test('el admin del grupo edita descripción, condición y ubicación', async ({ page }) => {
  await entrar(page, DUENO);
  await ir(page, true);
  await expect(page.getByRole('heading', { name: 'Nuestro activo', level: 1 })).toBeVisible();
  await expect(page.getByText('Estás editando')).toBeVisible();
  await page.getByLabel('Descripción', { exact: true }).fill(DESCRIPCION);
  await page.getByLabel('Condición actual').selectOption('buena');
  await page.getByLabel('Ubicación', { exact: true }).fill('Marina Norte, muelle 4');
  await page.getByLabel('Enlace al mapa (https)').fill('https://maps.example.com/?q=marina');
  await page.getByRole('button', { name: 'Guardar', exact: true }).click();
  await expect(page.getByText('Guardado.').first()).toBeVisible();
  await page.getByRole('button', { name: 'Terminar edición' }).click();
  await expect(page.getByText(DESCRIPCION)).toBeVisible();
  await expect(page.getByText('Marina Norte, muelle 4')).toBeVisible();
  await expect(page.getByRole('link', { name: 'Abrir en el mapa' })).toHaveAttribute('href', /maps\.example\.com/);
});

test('ficha propia, equipamiento y contactos se agregan y se ven', async ({ page }) => {
  await entrar(page, DUENO);
  // campo propio
  await ir(page, true, 'ficha');
  await page.getByLabel('Nuevo campo').fill('Año de fabricación');
  await page.locator('#cp-n-t').selectOption('numero');
  await page.getByRole('button', { name: 'Agregar campo' }).click();
  await expect(page.getByText('Guardado.').first()).toBeVisible();
  await page.locator('#cp-v-0').fill('2021');
  await page.locator('.ae-fila-edit').first().getByRole('button', { name: 'Guardar', exact: true }).click();
  await expect(page.getByText('Guardado.').first()).toBeVisible();
  await page.getByRole('button', { name: 'Terminar edición' }).click();
  await expect(page.getByText('Año de fabricación')).toBeVisible();
  await expect(page.getByText('2021')).toBeVisible();
  // equipamiento
  await ir(page, true, 'equipo');
  await page.getByLabel('Nuevo artículo').fill('Chalecos salvavidas');
  await page.locator('#eq-c-nuevo').fill('12');
  await page.getByRole('button', { name: 'Agregar artículo' }).click();
  await expect(page.getByText('Guardado.').first()).toBeVisible();
  await page.getByRole('button', { name: 'Terminar edición' }).click();
  await expect(page.getByText('Chalecos salvavidas')).toBeVisible();
  // contactos con llamada en un toque
  await ir(page, true, 'contactos');
  await page.getByLabel('Nuevo contacto').fill('Marina Norte');
  await page.locator('#ct-t-nuevo').fill('+1 809-555-0100');
  await page.getByRole('button', { name: 'Agregar contacto' }).click();
  await expect(page.getByText('Guardado.').first()).toBeVisible();
  await page.getByRole('button', { name: 'Terminar edición' }).click();
  await expect(page.getByRole('link', { name: 'Llamar' })).toHaveAttribute('href', 'tel:+18095550100');
});

test('galería: la primera foto es la portada y se ve en la ficha', async ({ page }) => {
  await entrar(page, DUENO);
  await ir(page, true, 'fotos');
  await page.locator('#fotos-in').setInputFiles({ name: 'proa.png', mimeType: 'image/png', buffer: PNG });
  await expect(page.locator('.ae-foto')).toHaveCount(1);
  await expect(page.getByText('Portada').first()).toBeVisible();
  await page.locator('#fotos-in').setInputFiles({ name: 'popa.png', mimeType: 'image/png', buffer: PNG });
  await expect(page.locator('.ae-foto')).toHaveCount(2);
  // la segunda pasa a ser la portada
  await page.locator('.ae-foto:not(.portada)').getByRole('button', { name: 'Usar de portada' }).click();
  await expect(page.locator('.ae-foto.portada')).toHaveCount(1);
  await page.getByRole('button', { name: 'Terminar edición' }).click();
  await ir(page);
  const foto = page.locator('app-activo-tarjeta img').first();
  await expect(foto).toBeVisible();
  await expect(foto).toHaveAttribute('src', new RegExp(`/storage/v1/object/public/activos/${grupoId}/`));
});

test('documento privado: se sube, no es público y solo los miembros lo firman', async ({ page }) => {
  await entrar(page, DUENO);
  await ir(page, true, 'documentos');
  await page.locator('#doc-archivo').setInputFiles({ name: 'matricula.pdf', mimeType: 'application/pdf', buffer: PDF });
  await expect(page.locator('#doc-titulo')).toHaveValue('matricula');
  await page.locator('#doc-vence').fill('2030-01-01');
  await page.getByRole('button', { name: 'Subir documento' }).click();
  await expect(page.getByText('Guardado.').first()).toBeVisible();
  await expect(page.locator('.ae-doc', { hasText: 'matricula' })).toBeVisible();
  const s = servicio();
  const fila = await s.from('activo_documentos').select('ruta').eq('activo_id', activoId).single();
  rutaDoc = fila.data!.ruta as string;
  // no es público
  const pub = await fetch(`${URL}/storage/v1/object/public/activo-documentos/${rutaDoc}`);
  expect(pub.ok).toBe(false);
  // un ajeno no obtiene URL firmada; un socio sí
  const ajeno = createClient(URL, ANON, { auth: { persistSession: false } });
  await ajeno.auth.signInWithPassword({ email: AJENO, password: CLAVE });
  expect((await ajeno.storage.from('activo-documentos').createSignedUrl(rutaDoc, 60)).error).not.toBeNull();
  const socio = createClient(URL, ANON, { auth: { persistSession: false } });
  await socio.auth.signInWithPassword({ email: SOCIO2, password: CLAVE });
  const firmada = await socio.storage.from('activo-documentos').createSignedUrl(rutaDoc, 60);
  expect(firmada.error).toBeNull();
  expect((await fetch(firmada.data!.signedUrl)).ok).toBe(true);
});

test('un socio sin permiso solo lee; el admin le da permiso y entonces edita', async ({ page, browser }) => {
  // sin permiso
  await entrar(page, SOCIO2);
  await ir(page);
  await expect(page.getByText('Solo lectura')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Editar', exact: true })).toHaveCount(0);
  await expect(page.getByText(DESCRIPCION)).toBeVisible();
  await expect(page.getByRole('tab', { name: 'Valor' })).toBeVisible(); // los socios ven el valor
  await ir(page, true);
  await expect(page.getByText('Estás editando')).toHaveCount(0);

  // el admin del grupo concede el permiso desde el resumen
  const ctx = await browser.newContext();
  const admin = await ctx.newPage();
  await entrar(admin, DUENO);
  await ir(admin);
  await expect(admin.getByText('Quién puede editar el activo')).toBeVisible();
  const caja = admin.locator('.ae-check', { hasText: 'E2E socio3' }).locator('input');
  await caja.check();
  await expect(admin.getByText('Guardado.').first()).toBeVisible();
  await ctx.close();

  // con permiso
  const ctx3 = await browser.newContext();
  const p3 = await ctx3.newPage();
  await entrar(p3, SOCIO3);
  await ir(p3, true, 'equipo');
  await expect(p3.getByText('Estás editando')).toBeVisible();
  await p3.getByLabel('Nuevo artículo').fill('Ancla de repuesto');
  await p3.getByRole('button', { name: 'Agregar artículo' }).click();
  await expect(p3.getByText('Guardado.').first()).toBeVisible();
  await ctx3.close();

  // la base lo confirma: el socio2 sigue sin poder escribir
  const c2 = createClient(URL, ANON, { auth: { persistSession: false } });
  await c2.auth.signInWithPassword({ email: SOCIO2, password: CLAVE });
  const r = await c2.from('activo_equipo').insert({ grupo_id: grupoId, activo_id: activoId, nombre: 'Intruso' });
  expect(r.error).not.toBeNull();
});

test('el historial muestra quién cambió qué; un ajeno no ve el activo', async ({ page }) => {
  await entrar(page, SOCIO2);
  await ir(page, false, 'historial');
  await expect(page.getByText('E2E socio3 agregó equipamiento').first()).toBeVisible();
  await expect(page.getByText('E2E dueno cambió el activo').first()).toBeVisible();
  await expect(page.getByText('Ancla de repuesto').first()).toBeVisible();

  const ajeno = createClient(URL, ANON, { auth: { persistSession: false } });
  await ajeno.auth.signInWithPassword({ email: AJENO, password: CLAVE });
  expect((await ajeno.rpc('activo_detalle', { p_activo: activoId })).error).not.toBeNull();
  expect((await ajeno.rpc('activo_historial', { p_activo: activoId })).error).not.toBeNull();
});
