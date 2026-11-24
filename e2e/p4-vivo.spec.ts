import { createClient } from '@supabase/supabase-js';
import { expect, test, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';

// Mantenimiento por horas, licencia vencida, reporte vs libro mayor, export, mediador sin acceso extra. Requiere E2E_VIVO=1.
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
const GRUPO2 = '10000000-0000-4000-8000-000000000002';
const dia = (o: number) => new Date(Date.now() + o * 86400000).toISOString().slice(0, 10);
const base = 500 + Math.floor(Math.random() * 150);

let grupo = '';
let mFelipe = '';
let reserva = '';
let plan = '';
let disputa = '';

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

test.beforeAll(async () => {
  const a = admin();
  const { data: act } = await a.from('activos').select('grupo_id').eq('id', ACTIVO).single();
  grupo = act!.grupo_id;
  const { data: ms } = await a.from('miembros').select('id, perfil:perfiles(correo)').eq('grupo_id', grupo);
  for (const m of ms ?? []) {
    if ((m.perfil as unknown as { correo: string } | null)?.correo === 'felipe.demo@shared.test') mFelipe = m.id;
  }
  // capitán con licencia vigente (DF-20)
  await a.from('capitanes').delete().eq('grupo_id', grupo).eq('miembro_id', mFelipe);
  const { error } = await a
    .from('capitanes')
    .insert({ grupo_id: grupo, miembro_id: mFelipe, nombre: 'Felipe (demo)', licencia_vence: dia(365) });
  if (error) throw error;
  const f = await cliente('felipe.demo@shared.test');
  const r = await f.rpc('demo_reiniciar_operacion', { p_grupo: grupo });
  if (r.error) throw new Error(r.error.message);
});

test.afterAll(async () => {
  const a = admin();
  const f = await cliente('felipe.demo@shared.test');
  const r = await f.rpc('demo_reiniciar_operacion', { p_grupo: grupo });
  if (r.error) throw new Error(r.error.message);
  if (plan) await a.from('mantenimiento_planes').delete().eq('id', plan);
  await a.from('mantenimiento_tareas').delete().eq('grupo_id', grupo);
  if (disputa) await a.from('disputas').delete().eq('id', disputa);
  if (reserva) await a.from('reservas').delete().eq('id', reserva);
  await a.from('capitanes').update({ licencia_vence: dia(365) }).eq('grupo_id', grupo).eq('miembro_id', mFelipe);
});

test('licencia vencida: el check-in no avanza y dice por qué; renovada, sale', async ({ browser }) => {
  const a = admin();
  const felipe = await cliente('felipe.demo@shared.test');
  const { data: t } = await a.from('tarifas').select('destino_id').eq('grupo_id', grupo).eq('tipo', 'fee_destino').gt('monto', 0).limit(1).single();
  const { data: id, error } = await felipe.rpc('reserva_crear_borrador', {
    p_activo: ACTIVO,
    p_inicio: new Date(`${dia(base)}T13:00:00Z`).toISOString(),
    p_fin: new Date(`${dia(base)}T19:00:00Z`).toISOString(),
    p_uso: 'familiar',
    p_destino: t!.destino_id,
    p_personas: 5,
    p_responsable_miembro: mFelipe,
  });
  expect(error).toBeNull();
  reserva = id as string;
  expect((await felipe.rpc('reserva_confirmar', { p_reserva: reserva })).error).toBeNull();

  await a.from('capitanes').update({ licencia_vence: dia(-1) }).eq('grupo_id', grupo).eq('miembro_id', mFelipe);
  const page = await (await browser.newContext()).newPage();
  await entrar(page, 'felipe.demo@shared.test');
  await page.goto(`/operacion/${reserva}`);
  await page.getByLabel(/Combustible inicial/).fill('100');
  const iniciales = page.locator('input[id^="o-li-"]');
  await iniciales.nth(0).fill('100');
  await iniciales.nth(1).fill('200');
  for (const cb of await page.locator('label.chequeo input[type=checkbox]').all()) await cb.check();
  await page.getByRole('button', { name: 'Salir', exact: true }).click();
  await expect(page.getByText('Falta para poder salir:')).toBeVisible();
  await expect(page.getByText(/Capitán sin licencia vigente/)).toBeVisible();

  await a.from('capitanes').update({ licencia_vence: dia(200) }).eq('grupo_id', grupo).eq('miembro_id', mFelipe);
  await page.getByRole('button', { name: 'Salir', exact: true }).click();
  await expect(page.getByText('Salida registrada. ¡Buen viaje!')).toBeVisible();
});

test('mantenimiento por horas: vence aunque la fecha no llegue; servicio → gasto común provisional', async ({ browser }) => {
  const a = admin();
  const felipe = await cliente('felipe.demo@shared.test');
  const { data: comp } = await a.from('activo_componentes').select('id').eq('activo_id', ACTIVO).order('indice').limit(1).single();
  const { data: pid, error } = await felipe.rpc('plan_guardar', {
    p_grupo: grupo,
    p_id: null,
    p_activo: ACTIVO,
    p_componente: comp!.id,
    p_nombre: 'Aceite motor 1 (e2e)',
    p_criterio: '',
    p_dias: 365,
    p_horas: 50,
  });
  expect(error).toBeNull();
  plan = pid as string;
  // el motor lleva 60 h desde el último servicio; la fecha sigue lejos
  const { data: lec } = await felipe.rpc('lectura_actual', { p_componente: comp!.id });
  expect(Number(lec)).toBeGreaterThanOrEqual(60);
  const up = await a.from('mantenimiento_planes').update({ ultima_lectura: Number(lec) - 60 }).eq('id', plan);
  expect(up.error).toBeNull();

  const page = await (await browser.newContext()).newPage();
  await entrar(page, 'felipe.demo@shared.test');
  await page.goto('/mantenimiento');
  await expect(page.getByRole('alert').filter({ hasText: 'Aceite motor 1 (e2e)' })).toContainText('Vencido');
  await page.getByRole('tab', { name: 'Planes' }).click();
  await expect(page.getByText('Lo que ocurra primero').first()).toBeVisible();

  // registrar el servicio con factura: nace un gasto común sin validar
  await page.getByRole('tab', { name: 'Servicios y facturas' }).click();
  await page.getByLabel('Proveedor').fill('Taller Naval e2e');
  await page.getByLabel('Costo').fill('1500');
  await page.getByRole('button', { name: 'Registrar servicio' }).click();
  await expect(page.getByText('Servicio registrado.')).toBeVisible();
  const x = await (await browser.newContext()).newPage();
  await entrar(x, 'xaviel.demo@shared.test');
  await x.goto('/gastos');
  const tarjeta = x.locator('article.gasto', { hasText: 'Taller Naval e2e' }).first();
  await expect(tarjeta.getByText('Provisional')).toBeVisible();
  await tarjeta.getByRole('button', { name: 'Validar' }).click();
  await expect(tarjeta.getByText('Validado')).toBeVisible();
});

test('reporte = libro mayor; el Excel trae las mismas filas; admin operativo no puede pedirlo', async ({ browser }) => {
  const felipe = await cliente('felipe.demo@shared.test');
  // cierra la salida de la prueba 1 con datos completos (lecturas, combustible, checklist de entrega)
  const { data: comps } = await admin().from('activo_componentes').select('id').eq('activo_id', ACTIVO).order('indice');
  const { data: op } = await admin().from('operaciones').select('id').eq('reserva_id', reserva).single();
  const { data: ini } = await admin().from('lecturas_vigentes').select('componente_id, valor').eq('operacion_id', op!.id).eq('momento', 'inicio');
  const fin = comps!.map((c) => ({ componente_id: c.id, valor: Number(ini!.find((i) => i.componente_id === c.id)!.valor) + 4 }));
  const cierre = await felipe.rpc('checkout_registrar', {
    p_reserva: reserva,
    p_lecturas: fin,
    p_combustible_final: 70,
    p_combustible_agregado: 0,
    p_checklist: [
      { clave: 'limpio', cumple: true },
      { clave: 'revisado', cumple: true },
      { clave: 'combustible', cumple: true },
    ],
    p_incidencias: [],
  });
  expect(cierre.error).toBeNull();
  expect((cierre.data as { cerrada: boolean }).cerrada).toBe(true);

  const anio = new Date().getFullYear();
  const dash = await felipe.rpc('reporte_dashboard', { p_grupo: grupo, p_anio: anio });
  expect(dash.error).toBeNull();
  const filas = await felipe.rpc('reporte_salidas', { p_grupo: grupo });
  expect(filas.error).toBeNull();
  const sumaFee = (filas.data as { fee: number }[]).reduce((s, f) => s + Number(f.fee), 0);
  expect(+sumaFee.toFixed(2)).toBe(+Number(dash.data.fees).toFixed(2));

  // pantalla: mismos números que la RPC (que sale del libro mayor)
  const page = await (await browser.newContext()).newPage();
  await entrar(page, 'felipe.demo@shared.test');
  await page.goto('/mas/reportes');
  await expect(page.getByTestId('kpis')).toBeVisible();
  const fees = (await page.getByTestId('kpi-fees').innerText()).replace(/[^\d]/g, '');
  expect(fees).toBe(Number(dash.data.fees).toFixed(2).replace(/[^\d]/g, ''));
  const n = (filas.data as unknown[]).length;
  await expect(page.getByTestId('tabla-salidas').locator('tbody tr')).toHaveCount(n);
  const filasUI = n;

  // exportar Excel (edge function con el JWT del usuario): mismas filas que la pantalla
  const { data: ses } = await felipe.auth.getSession();
  const resp = await fetch(`${URL}/functions/v1/exportar-reporte`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${ses.session!.access_token}`, apikey: ANON },
    body: JSON.stringify({ grupo, formato: 'xlsx' }),
  });
  expect(resp.status).toBe(200);
  expect(resp.headers.get('x-filas')).toBe(String(filasUI));
  const bytes = new Uint8Array(await resp.arrayBuffer());
  expect(String.fromCharCode(bytes[0], bytes[1])).toBe('PK'); // un .xlsx es un zip
  const pdf = await fetch(`${URL}/functions/v1/exportar-reporte`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${ses.session!.access_token}`, apikey: ANON },
    body: JSON.stringify({ grupo, formato: 'pdf', miembro: mFelipe }),
  });
  expect(pdf.status).toBe(200);
  expect(String.fromCharCode(...new Uint8Array(await pdf.arrayBuffer()).slice(0, 4))).toBe('%PDF');

  // un admin operativo (Xaviel en el grupo de 10) NO puede pedir el reporte financiero, ni por la RPC ni por la exportación
  const adminOp = await cliente('xaviel.demo@shared.test');
  const rpc = await adminOp.rpc('reporte_dashboard', { p_grupo: GRUPO2, p_anio: anio });
  expect(rpc.error?.message ?? '').toContain('solo_socios');
  const { data: s2 } = await adminOp.auth.getSession();
  const prohibido = await fetch(`${URL}/functions/v1/exportar-reporte`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${s2.session!.access_token}`, apikey: ANON },
    body: JSON.stringify({ grupo: GRUPO2, formato: 'xlsx' }),
  });
  expect(prohibido.status).toBe(403);
});

test('mediador: ve solo el caso al que fue invitado, y nada más del grupo', async ({ browser }) => {
  const felipe = await cliente('felipe.demo@shared.test');
  const d = await felipe.rpc('disputa_abrir', { p_grupo: grupo, p_titulo: 'Reparto del seguro (e2e)', p_ref_tipo: null, p_ref_id: null, p_texto: 'No hay acuerdo' });
  expect(d.error).toBeNull();
  disputa = d.data as string;
  // antes de los 7 días no se puede invitar
  const antes = await felipe.rpc('disputa_invitar_mediador', { p_disputa: disputa, p_correo: 'socio01.demo@shared.test' });
  expect(antes.error?.message ?? '').toContain('mediador_aun_no');
  await admin().from('disputas').update({ creado_en: new Date(Date.now() - 8 * 86400000).toISOString() }).eq('id', disputa);
  const inv = await felipe.rpc('disputa_invitar_mediador', { p_disputa: disputa, p_correo: 'socio01.demo@shared.test' });
  expect(inv.error).toBeNull();

  // el mediador entra por el enlace y ve el caso
  const page = await (await browser.newContext()).newPage();
  await entrar(page, 'socio01.demo@shared.test');
  await page.goto(`/mediar/${inv.data}`);
  await expect(page.getByRole('heading', { name: 'Reparto del seguro (e2e)' })).toBeVisible();
  await page.getByLabel('Mensaje').fill('Propongo repartir en partes iguales');
  await page.getByRole('button', { name: 'Enviar' }).click();
  await expect(page.getByText('Propongo repartir en partes iguales')).toBeVisible();

  // por la API: ningún dato del grupo de Felipe
  const med = await cliente('socio01.demo@shared.test');
  for (const tabla of ['gastos', 'libro_mayor', 'reservas', 'operaciones', 'pagos', 'polizas_seguro', 'capitanes']) {
    const r = await med.from(tabla).select('*').eq('grupo_id', grupo);
    expect(r.data ?? [], tabla).toHaveLength(0);
  }
  expect((await med.from('miembros').select('id').eq('grupo_id', grupo)).data).toHaveLength(0);
  const bal = await med.rpc('balances_grupo', { p_grupo: grupo });
  expect(bal.error?.message ?? '').toContain('solo_socios');
  // cerrado el caso, pierde todo acceso
  expect((await felipe.rpc('disputa_cerrar', { p_disputa: disputa, p_resultado: 'acuerdo', p_nota: 'ok' })).error).toBeNull();
  expect((await med.from('disputas').select('id')).data).toHaveLength(0);
});
