import { expect, test } from '@playwright/test';

// Prueba contra un Supabase real con datos demo (supabase/seed.sql). Se activa con E2E_VIVO=1.
test.skip(!process.env['E2E_VIVO'], 'Requiere E2E_VIVO=1 y shared-dev con seed demo');

async function entrar(page: import('@playwright/test').Page, correo: string) {
  await page.goto('/login');
  await page.getByLabel('Correo').fill(correo);
  await page.getByLabel('Contraseña').fill('Demo1234!');
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
}

test('socio demo: calendario, grupo, banner demo y menú inferior', async ({ page }) => {
  await entrar(page, 'felipe.demo@shared.test');
  await expect(page).toHaveURL(/\/calendario/);
  await expect(page.getByRole('list', { name: 'Leyenda del calendario' })).toBeVisible();
  await expect(page.getByText('Bote Demo (Felipe y Xaviel)')).toBeVisible();
  await expect(page.getByText('MODO DEMO')).toBeVisible();
  const menu = page.getByRole('navigation', { name: 'Navegación principal' });
  for (const t of ['Calendario', 'Mis salidas', 'Gastos', 'Mantenimiento', 'Más']) {
    await expect(menu.getByText(t, { exact: true })).toBeVisible();
  }
});

test('socio demo: configuración muestra el Bote Demo y el estatuto sus políticas', async ({
  page,
}) => {
  await entrar(page, 'felipe.demo@shared.test');
  await page.getByRole('link', { name: 'Más', exact: true }).click();
  await page.getByRole('link', { name: 'Configuración' }).click();
  await expect(page.getByText('Bote Demo', { exact: false }).first()).toBeVisible();
  await page.getByRole('tab', { name: 'Destinos' }).click();
  await expect(page.getByText('La Romana')).toBeVisible();
  await page.goto('/mas/estatuto');
  await expect(page.getByText('Máximo de días seguidos')).toBeVisible();
  await expect(page.getByText('no una firma legal', { exact: false })).toBeVisible();
});

test('admin operativo: no ve Finanzas ni Configuración en «Más»', async ({ page }) => {
  await entrar(page, 'xaviel.demo@shared.test');
  await expect(page).toHaveURL(/\/calendario/);
  // Xaviel es socio en el grupo de Felipe; cambia al grupo de 10 donde es admin operativo
  await page.goto('/grupos');
  await page
    .getByRole('article')
    .filter({ hasText: 'Carro Demo' })
    .getByRole('button', { name: 'Abrir' })
    .click();
  await page.getByRole('link', { name: 'Más', exact: true }).click();
  await expect(page.getByRole('link', { name: 'Finanzas' })).toHaveCount(0);
  await expect(page.getByRole('link', { name: 'Configuración' })).toHaveCount(0);
  await page.goto('/mas/finanzas');
  await expect(page).toHaveURL(/\/mas$/);
});
