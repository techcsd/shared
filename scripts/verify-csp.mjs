// Sirve dist/ con las cabeceras de vercel.json y comprueba que la app carga sin violaciones de CSP.
// Uso: npm run build && node scripts/verify-csp.mjs
import { chromium } from '@playwright/test';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join } from 'node:path';

const raiz = 'dist/shared/browser';
if (!existsSync(join(raiz, 'index.html'))) {
  console.error('Falta dist/: corre `npm run build` primero.');
  process.exit(1);
}
const cfg = JSON.parse(readFileSync('vercel.json', 'utf8'));
const cabeceras = Object.fromEntries(
  (cfg.headers.find((h) => h.source === '/(.*)')?.headers ?? []).map((h) => [h.key, h.value]),
);
const tipos = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json', '.ico': 'image/x-icon' };

const servidor = createServer((req, res) => {
  const ruta = decodeURIComponent((req.url ?? '/').split('?')[0]);
  let archivo = join(raiz, ruta);
  if (!existsSync(archivo) || statSync(archivo).isDirectory()) archivo = join(raiz, 'index.html');
  res.writeHead(200, { ...cabeceras, 'Content-Type': tipos[extname(archivo)] ?? 'application/octet-stream' });
  res.end(readFileSync(archivo));
});
await new Promise((r) => servidor.listen(4399, r));

const navegador = await chromium.launch();
const pagina = await navegador.newPage();
const violaciones = [];
pagina.on('console', (m) => {
  if (/content security policy|refused to/i.test(m.text())) violaciones.push(m.text());
});
await pagina.goto('http://localhost:4399/login');
await pagina.waitForSelector('input[type=password]', { timeout: 15000 });
const color = await pagina.evaluate(() => getComputedStyle(document.body).backgroundColor);
await navegador.close();
servidor.close();

console.log(`cabeceras aplicadas: ${Object.keys(cabeceras).join(', ')}`);
if (violaciones.length) {
  console.error('VIOLACIONES DE CSP:\n' + violaciones.join('\n'));
  process.exit(1);
}
console.log(`verify:csp OK (la app carga sin violaciones; fondo ${color})`);
