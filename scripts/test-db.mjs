// Aplica migraciones + tests SQL sobre PGlite (Postgres en WASM, sin Docker ni permisos de admin).
// Equivale a `supabase test db`: cada supabase/tests/NN_*.sql debe lanzar excepción si algo falla.
import { PGlite } from '@electric-sql/pglite';
import { btree_gist } from '@electric-sql/pglite/contrib/btree_gist';
import { citext } from '@electric-sql/pglite/contrib/citext';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const conSeed = process.argv.includes('--seed');
const db = new PGlite({ extensions: { btree_gist, citext } });
let fallos = 0;

try {
  await db.exec(readFileSync('supabase/tests/_arranque_supabase_simulado.sql', 'utf8'));
  const migs = readdirSync('supabase/migrations')
    .filter((f) => f.endsWith('.sql'))
    .sort();
  for (const f of migs) {
    try {
      await db.exec(readFileSync(join('supabase/migrations', f), 'utf8'));
      console.log('  migración OK', f);
    } catch (e) {
      console.error('  migración FALLÓ', f, '\n    ', e.message);
      throw e;
    }
  }
  if (conSeed && existsSync('supabase/seed.sql')) {
    await db.exec(readFileSync('supabase/seed.sql', 'utf8'));
    console.log('  seed OK');
  }
  const tests = readdirSync('supabase/tests')
    .filter((f) => /^\d.*\.sql$/.test(f))
    .sort();
  for (const f of tests) {
    try {
      await db.exec('reset role;');
      await db.exec(readFileSync(join('supabase/tests', f), 'utf8'));
      console.log('  ✔', f);
    } catch (e) {
      fallos++;
      console.error('  ✘', f, '\n    ', e.message);
    }
  }
  if (fallos === 0) console.log(`test:db OK (${migs.length} migraciones, ${tests.length} archivos de test)`);
} catch (e) {
  console.error(e.message);
  fallos++;
} finally {
  await db.close();
}
process.exit(fallos ? 1 : 0);
