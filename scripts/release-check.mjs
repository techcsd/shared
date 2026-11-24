// Verificación previa a un lanzamiento. Uso: node scripts/release-check.mjs [--completo]
// Sin --completo: revisiones rápidas (secrets, migraciones con reversa, marca, i18n, políticas, versión).
// Con --completo: además lint, tests unitarios, tests SQL, build y CSP.
import { spawnSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync } from 'node:fs';

const completo = process.argv.includes('--completo');
let fallos = 0;
const ok = (m) => console.log(`  ✔ ${m}`);
const mal = (m) => {
  console.error(`  ✘ ${m}`);
  fallos++;
};
const sh = (cmd, args) => spawnSync(cmd, args, { encoding: 'utf8', shell: process.platform === 'win32' });

console.log('Versión');
const pkg = JSON.parse(readFileSync('package.json', 'utf8'));
/^\d+\.\d+\.\d+/.test(pkg.version) && pkg.version !== '0.0.0' ? ok(`package.json ${pkg.version}`) : mal(`versión sin definir (${pkg.version})`);

console.log('Secrets (nada de valores en el repo)');
const archivos = sh('git', ['ls-files']).stdout.split(/\r?\n/).filter(Boolean);
if (archivos.some((f) => /(^|\/)\.env(\.local)?$/.test(f))) mal('un .env está versionado');
else ok('.env y .env.local no están versionados');
const patrones = [/sb_secret_[A-Za-z0-9_-]{10,}/, /service_role['"]?\s*[:=]\s*['"]eyJ[A-Za-z0-9._-]{40,}/, /\bre_[A-Za-z0-9]{20,}\b/, /-----BEGIN (RSA |EC )?PRIVATE KEY-----/, /eyJhbGciOi[A-Za-z0-9._-]{80,}/];
let hallazgos = 0;
for (const f of archivos) {
  if (/\.(png|ico|jpg|jpeg|webp|woff2?|lock|json)$/.test(f) && !/(vercel|config)\.json$/.test(f)) continue;
  if (f.endsWith('package-lock.json') || f.startsWith('graphify-out/')) continue;
  let txt = '';
  try {
    txt = readFileSync(f, 'utf8');
  } catch {
    continue;
  }
  for (const p of patrones) if (p.test(txt)) { mal(`posible secret en ${f}`); hallazgos++; }
}
if (!hallazgos) ok('sin patrones de claves en los archivos versionados');

console.log('Migraciones (aditivas, fechadas, con reversa)');
const migs = readdirSync('supabase/migrations').filter((f) => f.endsWith('.sql')).sort();
const sinReversa = migs.filter((m) => !existsSync(`supabase/migrations/_reversa/${m.replace('.sql', '_reversa.sql')}`));
sinReversa.length ? mal(`sin reversa: ${sinReversa.join(', ')}`) : ok(`${migs.length} migraciones, todas con reversa`);
const nombres = new Set(migs.map((m) => m.slice(0, 10)));
nombres.size === migs.length ? ok('prefijos numéricos únicos') : mal('hay prefijos de migración repetidos');

console.log('Marca (solo en src/app/core/brand.ts)');
const lista = sh('git', ['grep', '-n', '-E', "['\"`>]Shared['\"`<]", '--', 'src', ':!src/app/core/brand.ts', ':!src/app/core/i18n/*.ts', ':!*.spec.ts']).stdout.trim();
lista ? mal(`texto de marca fuera de brand.ts:\n${lista}`) : ok('ningún componente escribe la marca a mano');

console.log('Verificaciones del repositorio');
for (const [nombre, cmd, args] of [
  ['verify:i18n', 'node', ['scripts/verify-i18n.mjs']],
  ['verify:politicas', 'node', ['scripts/gen-politicas.mjs', '--check']],
]) {
  const r = sh(cmd, args);
  r.status === 0 ? ok(`${nombre}: ${r.stdout.trim().split('\n').pop()}`) : mal(`${nombre} falló\n${r.stdout}${r.stderr}`);
}

if (completo) {
  console.log('Completo (lint, tests, build, CSP)');
  for (const [nombre, cmd, args] of [
    ['lint', 'npm', ['run', 'lint']],
    ['test unitarios', 'npm', ['test']],
    ['test:db', 'npm', ['run', 'test:db']],
    ['build', 'npm', ['run', 'build']],
    ['verify:csp', 'node', ['scripts/verify-csp.mjs']],
  ]) {
    const r = sh(cmd, args);
    r.status === 0 ? ok(nombre) : mal(`${nombre} falló\n${(r.stdout + r.stderr).slice(-800)}`);
  }
}

console.log(fallos ? `\nrelease-check: ${fallos} problema(s). NO lanzar.` : '\nrelease-check OK');
process.exit(fallos ? 1 : 0);
