// Genera, desde supabase/catalogo/politicas.json, el seed SQL, el catálogo TS y la tabla del estatuto.
// Uso: node scripts/gen-politicas.mjs [--check]   (--check falla si algo está desactualizado)
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const modoCheck = process.argv.includes('--check');
const catalogo = JSON.parse(readFileSync('supabase/catalogo/politicas.json', 'utf8'));

// Validación básica del propio catálogo
const claves = new Set();
for (const p of catalogo) {
  if (claves.has(p.clave)) throw new Error(`Clave repetida: ${p.clave}`);
  claves.add(p.clave);
  if (!['booleano', 'entero', 'numero', 'enum', 'lista'].includes(p.tipo)) throw new Error(`Tipo inválido en ${p.clave}`);
  if (p.tipo === 'enum' && !p.opciones?.includes(p.defecto)) throw new Error(`Defecto fuera de opciones en ${p.clave}`);
}

const sql = (s) => `'${String(s).replaceAll("'", "''")}'`;
const num = (n) => (n === undefined || n === null ? 'null' : String(n));
const json = (v) => `${sql(JSON.stringify(v))}::jsonb`;

const filasSql = catalogo
  .map(
    (p, i) =>
      `  (${sql(p.clave)}, ${sql(p.categoria)}, ${sql(p.tipo)}, ${json(p.defecto)}, ${num(p.minimo)}, ${num(p.maximo)}, ${
        p.opciones ? json(p.opciones) : 'null'
      }, ${p.nullable ? 'true' : 'false'}, ${sql(p.df ?? '')}, ${sql(p.descripcion ?? '')}, ${i + 1})`,
  )
  .join(',\n');
const bloqueSql = `insert into politicas_catalogo (clave, categoria, tipo, valor_defecto, minimo, maximo, opciones, nullable, df, descripcion, orden) values\n${filasSql};`;

const ts = `// GENERADO por scripts/gen-politicas.mjs desde supabase/catalogo/politicas.json — no editar a mano.
export type TipoPolitica = 'booleano' | 'entero' | 'numero' | 'enum' | 'lista';

export interface PoliticaCatalogo {
  clave: string;
  categoria: string;
  tipo: TipoPolitica;
  defecto: unknown;
  nullable: boolean;
  minimo?: number;
  maximo?: number;
  opciones?: string[];
  df: string;
  etiqueta: string;
  descripcion: string;
}

export const POLITICAS_CATALOGO: PoliticaCatalogo[] = ${JSON.stringify(
  catalogo.map((p) => ({
    clave: p.clave,
    categoria: p.categoria,
    tipo: p.tipo,
    defecto: p.defecto,
    nullable: Boolean(p.nullable),
    ...(p.minimo !== undefined ? { minimo: p.minimo } : {}),
    ...(p.maximo !== undefined ? { maximo: p.maximo } : {}),
    ...(p.opciones ? { opciones: p.opciones } : {}),
    df: p.df ?? '',
    etiqueta: p.etiqueta,
    descripcion: p.descripcion ?? '',
  })),
  null,
  2,
)};
`;

const fmt = (v) => (v === null ? '—' : Array.isArray(v) ? v.join(', ') : typeof v === 'boolean' ? (v ? 'sí' : 'no') : String(v));
const tablaMd =
  '| Política | Clave | Defecto | Rango / opciones | DF |\n|---|---|---|---|---|\n' +
  catalogo
    .map((p) => {
      const rango = p.opciones ? p.opciones.join(' · ') : p.minimo !== undefined ? `${p.minimo}–${p.maximo}` : '—';
      return `| ${p.etiqueta} | \`${p.clave}\` | ${fmt(p.defecto)} | ${rango} | ${p.df ?? ''} |`;
    })
    .join('\n');

function reemplazarBloque(ruta, inicio, fin, contenido) {
  const actual = readFileSync(ruta, 'utf8');
  const i = actual.indexOf(inicio);
  const j = actual.indexOf(fin);
  if (i < 0 || j < 0) throw new Error(`Faltan marcadores ${inicio} / ${fin} en ${ruta}`);
  return actual.slice(0, i + inicio.length) + '\n' + contenido + '\n' + actual.slice(j);
}

const salidas = [
  {
    ruta: 'supabase/migrations/2026112309_politicas.sql',
    nuevo: () => reemplazarBloque('supabase/migrations/2026112309_politicas.sql', '-- BEGIN:CATALOGO', '-- END:CATALOGO', bloqueSql),
  },
  { ruta: 'src/app/core/politicas-catalogo.ts', nuevo: () => ts },
  {
    ruta: 'docs/ESTATUTO-BASE.md',
    nuevo: () => reemplazarBloque('docs/ESTATUTO-BASE.md', '<!-- BEGIN:CATALOGO (generado por scripts/gen-politicas.mjs; no editar a mano) -->', '<!-- END:CATALOGO -->', tablaMd),
  },
];

let desactualizados = 0;
for (const s of salidas) {
  if (!existsSync(s.ruta) && s.ruta.endsWith('.ts')) {
    if (modoCheck) desactualizados++;
    else writeFileSync(s.ruta, s.nuevo());
    continue;
  }
  const nuevo = s.nuevo();
  const actual = readFileSync(s.ruta, 'utf8');
  if (nuevo !== actual) {
    if (modoCheck) {
      console.error(`Desactualizado: ${s.ruta} (corre npm run gen:politicas)`);
      desactualizados++;
    } else {
      writeFileSync(s.ruta, nuevo);
      console.log(`escrito ${s.ruta}`);
    }
  }
}
if (modoCheck) {
  if (desactualizados) process.exit(1);
  console.log(`verify:politicas OK (${catalogo.length} políticas)`);
}
