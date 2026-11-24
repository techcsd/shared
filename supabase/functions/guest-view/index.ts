// Vista pública del invitado (SC8, DF-31): devuelve SOLO fecha, horario, punto de encuentro, reglas y contacto.
// Sin sesión. Token aleatorio hasheado en la base, expira tras el regreso, límite de intentos por IP.
import { createClient } from 'npm:@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, authorization, apikey',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};
const json = (cuerpo: unknown, status = 200) =>
  new Response(JSON.stringify(cuerpo), { status, headers: { ...CORS, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });

async function sha256(s: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  let token = new URL(req.url).searchParams.get('token') ?? '';
  if (!token && req.method === 'POST') {
    try {
      token = String((await req.json()).token ?? '');
    } catch {
      /* cuerpo inválido */
    }
  }
  if (!/^[a-f0-9]{64}$/.test(token)) return json({ error: 'no_encontrado' }, 404);

  const ip = req.headers.get('x-forwarded-for')?.split(',')[0].trim() ?? 'desconocida';
  const ipHash = await sha256(`${ip}|${Deno.env.get('SUPABASE_URL')}`);
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  });
  const { data, error } = await db.rpc('invitado_ver', { p_token: token, p_ip_hash: ipHash });
  if (error) {
    if (error.message.includes('demasiados_intentos')) return json({ error: 'demasiados_intentos' }, 429);
    return json({ error: 'error' }, 500);
  }
  if (!data) return json({ error: 'no_encontrado' }, 404); // token inexistente, expirado o ajeno: misma respuesta
  return json(data);
});
