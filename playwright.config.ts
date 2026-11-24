import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: 'e2e',
  workers: 1, // las pruebas vivas comparten datos demo de shared-dev
  use: { baseURL: 'http://localhost:4310', locale: 'es-DO' },
  webServer: {
    command: 'npm start -- --port 4310',
    url: 'http://localhost:4310',
    reuseExistingServer: false,
    timeout: 120000,
  },
});
