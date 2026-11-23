// Falla si faltan claves entre es/en o si el código usa claves inexistentes.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const claves = (archivo) => {
  const src = readFileSync(archivo, 'utf8');
  return new Set([...src.matchAll(/^\s*'([a-z0-9_.]+)'\s*:/gm)].map((m) => m[1]));
};
const es = claves('src/app/core/i18n/es.ts');
const en = claves('src/app/core/i18n/en.ts');
const errores = [];
for (const k of es) if (!en.has(k)) errores.push(`Falta en en.ts: ${k}`);
for (const k of en) if (!es.has(k)) errores.push(`Falta en es.ts: ${k}`);

const recorrer = (dir, salida = []) => {
  for (const f of readdirSync(dir)) {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) recorrer(p, salida);
    else if (/\.(ts|html)$/.test(f) && !/\.spec\.ts$/.test(f) && !/i18n[\\/]/.test(p)) salida.push(p);
  }
  return salida;
};
for (const f of recorrer('src')) {
  const src = readFileSync(f, 'utf8');
  for (const m of src.matchAll(/\bt\(\s*'([a-z0-9_.]+)'/g)) {
    if (!es.has(m[1])) errores.push(`${f}: clave no definida ${m[1]}`);
  }
  // claves en datos de rutas / listas: etiqueta: 'x.y', titulo: 'x.y', pendiente('ruta', 'x.y')
  const reDatos = /(?:etiqueta|titulo):\s*'([a-z0-9_]+\.[a-z0-9_.]+)'|pendiente\('[^']+',\s*'([a-z0-9_]+\.[a-z0-9_.]+)'/g;
  for (const m of src.matchAll(reDatos)) {
    const k = m[1] ?? m[2];
    if (!es.has(k)) errores.push(`${f}: clave no definida ${k}`);
  }
}
if (errores.length) {
  console.error(errores.join('\n'));
  process.exit(1);
}
console.log(`verify:i18n OK (${es.size} claves es/en)`);
