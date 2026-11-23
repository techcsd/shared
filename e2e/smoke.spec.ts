import { expect, test } from '@playwright/test';

test('sin sesión la app lleva al acceso, en español', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveURL(/\/login/);
  await expect(page.locator('h1')).toContainText('Shared');
  await expect(page.getByRole('button', { name: 'Entrar', exact: true })).toBeVisible();
  await expect(page).toHaveTitle(/Shared/);
});

test('las rutas protegidas no se abren sin sesión', async ({ page }) => {
  await page.goto('/mas/finanzas');
  await expect(page).toHaveURL(/\/login\?volver=/);
});
