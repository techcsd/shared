// Genera src/app/core/env.generated.ts desde variables de entorno o .env.local (nunca service role).
import { existsSync, readFileSync, writeFileSync } from 'node:fs';

const local = {};
if (existsSync('.env.local')) {
  for (const l of readFileSync('.env.local', 'utf8').split(/\r?\n/)) {
    const m = l.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m) local[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
}
const v = (k) => process.env[k] ?? local[k] ?? '';
const out = `// GENERADO por scripts/gen-env.mjs — no editar ni commitear.
export const ENV = {
  supabaseUrl: ${JSON.stringify(v('NG_APP_SUPABASE_URL'))},
  supabaseAnonKey: ${JSON.stringify(v('NG_APP_SUPABASE_ANON_KEY'))},
};
`;
writeFileSync('src/app/core/env.generated.ts', out);
console.log('env.generated.ts escrito');
