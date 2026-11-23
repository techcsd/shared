import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: 'e2e',
  use: { baseURL: 'http://localhost:4310', locale: 'es-DO' },
  webServer: {
    command: 'npm start -- --port 4310',
    url: 'http://localhost:4310',
    reuseExistingServer: false,
    timeout: 120000,
  },
});
