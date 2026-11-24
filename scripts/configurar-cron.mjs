// Configura por entorno: secretos en Vault (URL de funciones + service role) y el pg_cron de cada minuto.
// Uso: node scripts/configurar-cron.mjs dev|prod     (lee .env.local; nunca imprime claves)
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const entorno = process.argv[2];
if (!['dev', 'prod'].includes(entorno)) {
  console.error('Uso: node scripts/configurar-cron.mjs dev|prod');
  process.exit(1);
}
const sufijo = entorno.toUpperCase();
const env = {};
if (existsSync('.env.local')) {
  for (const l of readFileSync('.env.local', 'utf8').split(/\r?\n/)) {
    const m = l.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m) env[m[1]] = m[2];
  }
}
const ref = env[`SUPABASE_PROJECT_REF_${sufijo}`];
const clave = env[`SUPABASE_SERVICE_ROLE_KEY_${sufijo}`];
if (!ref || !clave) {
  console.error(`Faltan SUPABASE_PROJECT_REF_${sufijo} o SUPABASE_SERVICE_ROLE_KEY_${sufijo} en .env.local`);
  process.exit(1);
}
const url = `https://${ref}.supabase.co/functions/v1`;
const q = (s) => `'${s.replaceAll("'", "''")}'`;
const sql = `
create extension if not exists pg_net;
create extension if not exists pg_cron;
do $$
begin
  if exists (select 1 from vault.secrets where name = 'shared_functions_url') then
    perform vault.update_secret((select id from vault.secrets where name = 'shared_functions_url'), ${q(url)});
  else
    perform vault.create_secret(${q(url)}, 'shared_functions_url');
  end if;
  if exists (select 1 from vault.secrets where name = 'shared_service_key') then
    perform vault.update_secret((select id from vault.secrets where name = 'shared_service_key'), ${q(clave)});
  else
    perform vault.create_secret(${q(clave)}, 'shared_service_key');
  end if;
end $$;
select cron.schedule('shared-mantenimiento', '* * * * *', 'select public.cron_mantenimiento()');
`;
const tmp = join(tmpdir(), `shared-cron-${Date.now()}.sql`);
writeFileSync(tmp, sql);
try {
  execFileSync('npx', ['supabase', 'db', 'query', `--remote=${ref}`, '--yes', '-f', tmp], { stdio: ['ignore', 'pipe', 'pipe'], shell: true });
  console.log(`cron configurado en ${entorno} (${ref}): cada minuto, vía Vault`);
} finally {
  rmSync(tmp, { force: true });
}
