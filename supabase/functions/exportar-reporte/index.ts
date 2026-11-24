// Exporta el reporte de salidas a Excel (.xlsx) o PDF (DF-33, tope 5.000 filas).
// Corre con el JWT del usuario: los permisos son los de la base (solo socios ven finanzas; admin operativo → 403).
// Los números salen de la RPC `reporte_salidas` (mismo libro mayor y operación que la pantalla): sin cálculo propio.
import { createClient } from 'npm:@supabase/supabase-js@2';
import * as XLSX from 'npm:xlsx@0.18.5';
import { PDFDocument, StandardFonts, rgb } from 'npm:pdf-lib@1.17.1';

// CORS restringido al dominio de la app (APP_URL, separado por comas) más localhost de desarrollo.
const PERMITIDOS = (Deno.env.get('APP_URL') ?? 'https://shared-csd.vercel.app')
  .split(',')
  .map((x) => x.trim())
  .concat(['http://localhost:4200', 'http://localhost:4310']);
let CORS: Record<string, string> = {};
function fijarCors(req: Request) {
  const origen = req.headers.get('Origin') ?? '';
  CORS = {
    'Access-Control-Allow-Origin': PERMITIDOS.includes(origen) ? origen : PERMITIDOS[0],
    'Access-Control-Allow-Headers': 'content-type, authorization, apikey',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    Vary: 'Origin',
  };
}
const json = (cuerpo: unknown, status = 200) =>
  new Response(JSON.stringify(cuerpo), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

const COLUMNAS: [string, string][] = [
  ['orden', 'Orden'],
  ['fecha', 'Fecha'],
  ['miembro', 'Socio'],
  ['destino', 'Destino'],
  ['uso', 'Tipo'],
  ['estado', 'Estado'],
  ['personas', 'Personas'],
  ['duracion_horas', 'Duración (h)'],
  ['horas_motor', 'Horas motor'],
  ['combustible_consumido', 'Combustible'],
  ['fee', 'Fee'],
  ['gastos_individuales', 'Gastos indiv.'],
];

Deno.serve(async (req) => {
  fijarCors(req);
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);
  if (Number(req.headers.get('content-length') ?? 0) > 4096) return json({ error: 'cuerpo_muy_grande' }, 413);
  let p: Record<string, string | null>;
  try {
    p = await req.json();
  } catch {
    return json({ error: 'cuerpo_invalido' }, 400);
  }
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuid.test(String(p['grupo'] ?? ''))) return json({ error: 'grupo_invalido' }, 400);
  for (const k of ['miembro', 'destino']) {
    if (p[k] && !uuid.test(String(p[k]))) return json({ error: `${k}_invalido` }, 400);
  }
  const formato = p['formato'] === 'pdf' ? 'pdf' : 'xlsx';
  const auth = req.headers.get('Authorization') ?? '';
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data, error } = await db.rpc('reporte_salidas', {
    p_grupo: p['grupo'],
    p_desde: p['desde'] || null,
    p_hasta: p['hasta'] || null,
    p_miembro: p['miembro'] || null,
    p_destino: p['destino'] || null,
    p_uso: p['uso'] || null,
    p_estado: p['estado'] || null,
    p_limite: 5000,
  });
  if (error) return json({ error: error.message }, error.message.includes('solo_socios') ? 403 : 400);
  const filas = (data ?? []) as Record<string, unknown>[];

  if (formato === 'xlsx') {
    const hoja = XLSX.utils.json_to_sheet(
      filas.map((f) => Object.fromEntries(COLUMNAS.map(([k, titulo]) => [titulo, f[k] ?? '']))),
    );
    const libro = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(libro, hoja, 'Salidas');
    const buf = XLSX.write(libro, { type: 'array', bookType: 'xlsx' }) as ArrayBuffer;
    return new Response(buf, {
      headers: {
        ...CORS,
        'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'Content-Disposition': 'attachment; filename="reporte-salidas.xlsx"',
        'X-Filas': String(filas.length),
      },
    });
  }

  const pdf = await PDFDocument.create();
  const fuente = await pdf.embedFont(StandardFonts.Helvetica);
  const negrita = await pdf.embedFont(StandardFonts.HelveticaBold);
  const ancho = 842;
  const alto = 595;
  const margen = 30;
  let pagina = pdf.addPage([ancho, alto]);
  let y = alto - margen;
  const colAncho = (ancho - margen * 2) / COLUMNAS.length;
  const texto = (v: unknown) => String(v ?? '').slice(0, 14);
  const cabecera = () => {
    pagina.drawText('Reporte de salidas', { x: margen, y, size: 14, font: negrita });
    y -= 22;
    COLUMNAS.forEach(([, titulo], i) =>
      pagina.drawText(titulo.slice(0, 14), { x: margen + i * colAncho, y, size: 8, font: negrita }),
    );
    y -= 14;
  };
  cabecera();
  for (const f of filas) {
    if (y < margen) {
      pagina = pdf.addPage([ancho, alto]);
      y = alto - margen;
      cabecera();
    }
    COLUMNAS.forEach(([k], i) =>
      pagina.drawText(texto(f[k]), { x: margen + i * colAncho, y, size: 8, font: fuente, color: rgb(0, 0, 0) }),
    );
    y -= 12;
  }
  const bytes = await pdf.save();
  return new Response(bytes, {
    headers: {
      ...CORS,
      'Content-Type': 'application/pdf',
      'Content-Disposition': 'attachment; filename="reporte-salidas.pdf"',
      'X-Filas': String(filas.length),
    },
  });
});
