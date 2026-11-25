import { createClient } from '@supabase/supabase-js';
import { devices, expect, test, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';

// Cierre de la ronda contra shared-dev: SA1 (< 1 min en móvil emulado, 5 reservas), PWA/es/calendario y el ciclo
// completo proponer → fondear → convertir → reservar → operar → liquidar → reportar. Requiere E2E_VIVO=1.
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
const dia = (o: number) => new Date(Date.now() + o * 86400000).toISOString().slice(0, 10);

const admin = () => createClient(URL, SERVICIO, { auth: { persistSession: false } });
async function cliente(correo: string) {
  const c = createClient(URL, ANON, { auth: { persistSession: false } });
  const { error } = await c.auth.signInWithPassword({ email: correo, password: 'Demo1234!' });
  if (error) throw error;
  return c;
}
async function entrar(page: Page, correo: string) {
  await page.goto('/login');
  await page.getByLabel('Correo').fill(correo);
  await page.getByLabel('Contraseña', { exact: true }).fill('Demo1234!');
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await expect(page).toHaveURL(/\/calendario/);
}

const reservasSA1: string[] = [];
let grupoNuevo = '';
let propuestaId = '';

test.afterAll(async () => {
  const a = admin();
  if (reservasSA1.length) await a.from('reservas').delete().in('id', reservasSA1);
  if (grupoNuevo) {
    await a.from('reservas').delete().eq('grupo_id', grupoNuevo);
    const { error } = await a.from('grupos').delete().eq('id', grupoNuevo);
    if (error) throw new Error(`no se pudo borrar el grupo de prueba: ${error.message}`);
  }
  if (propuestaId) await a.from('propuestas_compra').delete().eq('id', propuestaId);
});

test('SA1: reservar desde un móvil emulado en < 1 min (5 reservas) y SA15: PWA en español con el calendario de inicio', async ({ browser }) => {
  const ctx = await browser.newContext({ ...devices['iPhone 13'], locale: 'es-DO' });
  const page = await ctx.newPage();
  await entrar(page, 'felipe.demo@shared.test'); // SA15: tras entrar, la pantalla de inicio es el calendario
  expect(await page.locator('html').getAttribute('lang')).toBe('es');

  const manifest = await (await page.request.get('/manifest.webmanifest')).json();
  expect(manifest.display).toBe('standalone');
  expect(manifest.lang).toBe('es');
  expect(manifest.start_url).toMatch(/^(\.\/|\/)?$|calendario/);
  expect(manifest.icons.length).toBeGreaterThan(1);

  const tiempos: number[] = [];
  const base = 700 + Math.floor(Math.random() * 100);
  for (let i = 0; i < 5; i++) {
    const t0 = Date.now();
    await page.goto(`/reservar?fecha=${dia(base + i * 2)}`);
    await page.getByLabel('Hora de salida').fill('09:00');
    await page.getByLabel('Hora de regreso').fill('15:00');
    await page.getByRole('button', { name: 'Siguiente' }).click();
    await page.getByRole('radio', { name: 'Familiar' }).click();
    await page.getByRole('button', { name: 'Siguiente' }).click();
    await page.getByLabel('Personas a bordo').fill('6');
    await page.getByRole('button', { name: 'Ver resumen' }).click();
    await page.getByRole('button', { name: 'Confirmar reserva' }).click();
    await expect(page).toHaveURL(/\/reserva\//);
    tiempos.push(Date.now() - t0);
    reservasSA1.push(page.url().split('/reserva/')[1]);
  }
  const prom = Math.round(tiempos.reduce((s, x) => s + x, 0) / tiempos.length);
  console.log(`SA1_TIEMPOS_MS=${tiempos.join(',')} PROMEDIO_MS=${prom}`);
  for (const ms of tiempos) expect(ms).toBeLessThan(60000);
  // medidas tomadas del cliente: el evento queda registrado para el análisis con personas reales
  const a = admin();
  const { count } = await a.from('eventos_cliente').select('*', { count: 'exact', head: true }).eq('tipo', 'reserva_asistente_ms');
  expect(count ?? 0).toBeGreaterThanOrEqual(5);
});

test('aviso legal visible: la app no custodia dinero', async ({ browser }) => {
  const page = await (await browser.newContext()).newPage();
  await entrar(page, 'felipe.demo@shared.test');
  await page.goto('/mas/propuestas');
  await expect(page.getByTestId('aviso-legal')).toContainText('NO custodia dinero');
  await expect(page.getByTestId('aviso-legal')).toContainText('abogado');
});

test('ciclo completo: proponer → fondear → convertir → reservar → operar → liquidar → reportar', async () => {
  const a = admin();
  const org = await cliente('socio02.demo@shared.test');
  const p3 = await cliente('socio03.demo@shared.test');
  const p4 = await cliente('socio04.demo@shared.test');
  const { data: tipo } = await a.from('tipos_activo').select('id').eq('clave', 'carro').eq('es_sistema', true).single();

  // proponer y abrir
  const pr = await org.rpc('propuesta_crear', {
    p_titulo: 'Carro compartido (e2e)', p_tipo: tipo!.id, p_descripcion: 'prueba', p_precio: 300000, p_moneda: 'DOP', p_fecha_limite: dia(30), p_cupos: 5,
  });
  expect(pr.error).toBeNull();
  propuestaId = pr.data.id;
  expect((await org.rpc('propuesta_abrir', { p_prop: propuestaId })).error).toBeNull();
  expect((await p3.rpc('propuesta_unirse', { p_token: pr.data.token })).error).toBeNull();
  expect((await p4.rpc('propuesta_unirse', { p_token: pr.data.token })).error).toBeNull();

  // aportes declarados (la app no mueve dinero) y confirmados a mano por el organizador
  const aportes: [Awaited<ReturnType<typeof cliente>>, number][] = [[org, 150000], [p3, 90000], [p4, 60000]];
  const ids: string[] = [];
  for (const [c, monto] of aportes) {
    await c.rpc('propuesta_comprometer', { p_prop: propuestaId, p_monto: monto });
    const r = await c.rpc('propuesta_aporte_declarar', { p_prop: propuestaId, p_monto: monto, p_nota: 'transferencia' });
    expect(r.error).toBeNull();
    ids.push(r.data as string);
  }
  const antes = await org.rpc('propuesta_totales', { p_prop: propuestaId });
  expect(Number(antes.data[0].confirmado)).toBe(0); // declarar no es confirmar
  expect((await p3.rpc('propuesta_aporte_confirmar', { p_aporte: ids[0] })).error?.message ?? '').toContain('solo_organizador');
  for (const id of ids) expect((await org.rpc('propuesta_aporte_confirmar', { p_aporte: id })).error).toBeNull();
  const { data: est } = await a.from('propuestas_compra').select('estado').eq('id', propuestaId).single();
  expect(est!.estado).toBe('fondeada');

  // adquisición: contrato + acuse de todos
  expect((await org.rpc('propuesta_evidencia_registrar', { p_prop: propuestaId, p_ruta: `propuestas/${propuestaId}/contrato.pdf`, p_tipo: 'contrato' })).error).toBeNull();
  expect((await org.rpc('propuesta_registrar_adquisicion', { p_prop: propuestaId, p_nota: 'Comprado en la agencia' })).error).toBeNull();
  expect((await p3.rpc('propuesta_acusar_adquisicion', { p_prop: propuestaId })).error).toBeNull();
  expect((await p4.rpc('propuesta_acusar_adquisicion', { p_prop: propuestaId })).error).toBeNull();

  // conversión: 50 / 30 / 20 %
  const g = await org.rpc('propuesta_convertir', { p_prop: propuestaId, p_nombre_grupo: 'Carro e2e', p_prefijo: 'EEE' });
  expect(g.error).toBeNull();
  grupoNuevo = g.data as string;
  const { data: ms } = await a.from('miembros').select('id, porcentaje, usuario_id').eq('grupo_id', grupoNuevo);
  expect(ms!.map((m) => Number(m.porcentaje)).sort((x, y) => y - x)).toEqual([50, 30, 20]);

  // el activo se completa y se activa; destino, tarifa y capitán
  const { data: act } = await org.from('activos').select('id').eq('grupo_id', grupoNuevo).single();
  expect((await org.from('activos').update({ capacidad_legal: 5, estado: 'activo' }).eq('id', act!.id)).error).toBeNull();
  const { data: dest } = await org.from('destinos').insert({ grupo_id: grupoNuevo, nombre: 'Centro' }).select('id').single();
  await org.from('tarifas').insert({ grupo_id: grupoNuevo, destino_id: dest!.id, tipo: 'fee_destino', monto: 1000, moneda: 'DOP' });
  const { data: yo } = await org.from('miembros').select('id').eq('grupo_id', grupoNuevo).eq('porcentaje', 50).single();
  expect((await org.rpc('capitan_guardar', { p_grupo: grupoNuevo, p_id: null, p_nombre: 'Conductor e2e', p_miembro: yo!.id, p_licencia: 'L-1', p_vence: dia(200), p_anios: 3, p_notas: null, p_estado: 'activo' })).error).toBeNull();

  // reservar y operar (carro: odómetro)
  const r = await org.rpc('reserva_crear_borrador', {
    p_activo: act!.id, p_inicio: new Date(`${dia(5)}T13:00:00Z`).toISOString(), p_fin: new Date(`${dia(5)}T17:00:00Z`).toISOString(),
    p_uso: 'personal', p_destino: dest!.id, p_personas: 3, p_responsable_miembro: yo!.id,
  });
  expect(r.error).toBeNull();
  expect((await org.rpc('reserva_confirmar', { p_reserva: r.data })).error).toBeNull();
  const { data: comp } = await a.from('activo_componentes').select('id').eq('activo_id', act!.id);
  const ck = [{ clave: 'licencia', cumple: true }, { clave: 'neumaticos', cumple: true }, { clave: 'combustible', cumple: true }];
  const ci = await org.rpc('checkin_registrar', {
    p_reserva: r.data, p_capitan_miembro: yo!.id, p_capitan_nombre: null, p_destino: dest!.id, p_combustible: 40,
    p_lecturas: comp!.map((c) => ({ componente_id: c.id, valor: 1000 })), p_checklist: ck, p_nota: null,
  });
  expect(ci.data.ok).toBe(true);
  expect((await org.rpc('gasto_registrar', { p_grupo: grupoNuevo, p_alcance: 'individual', p_categoria: 'peaje', p_monto: 200, p_moneda: 'DOP', p_reserva: r.data })).error).toBeNull();
  const co = await org.rpc('checkout_registrar', {
    p_reserva: r.data, p_lecturas: comp!.map((c) => ({ componente_id: c.id, valor: 1042 })), p_combustible_final: 30, p_combustible_agregado: 0,
    p_checklist: [{ clave: 'limpio', cumple: true }, { clave: 'sin_danos', cumple: true }, { clave: 'combustible', cumple: true }], p_incidencias: [],
  });
  expect(co.data.cerrada).toBe(true);

  // reportar: el dashboard coincide con el libro mayor y las cuentas cuadran
  const dash = await org.rpc('reporte_dashboard', { p_grupo: grupoNuevo, p_anio: new Date().getFullYear() });
  expect(dash.error).toBeNull();
  const { data: libro } = await a.from('libro_mayor').select('debe, haber, cuenta_tipo, origen_tipo').eq('grupo_id', grupoNuevo);
  const costo = libro!.filter((l) => l.cuenta_tipo === 'miembro' && l.origen_tipo !== 'pago').reduce((s, l) => s + Number(l.debe), 0);
  expect(+Number(dash.data.costo_total).toFixed(2)).toBe(+costo.toFixed(2));
  expect(Number(dash.data.fees)).toBe(1000);
  expect(Number(dash.data.horas_por_componente[0].horas)).toBe(42);
  const suma = libro!.reduce((s, l) => s + Number(l.haber) - Number(l.debe), 0);
  expect(+suma.toFixed(2)).toBe(0); // la suma de todas las cuentas es 0
});
