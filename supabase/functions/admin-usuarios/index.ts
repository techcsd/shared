// Operaciones de administración de usuarios que requieren la API de administración de Auth (DF-93).
// Quién llama: SOLO un administrador de plataforma. Se verifica aquí (JWT real contra Auth) y la base lo
// vuelve a exigir en cada RPC (`es_admin_plataforma()`): nunca se confía en el cliente.
// El service role se usa ÚNICAMENTE para la API de administración de Auth (crear, clave, bloquear, borrar);
// todo lo demás corre con el JWT del admin. Las claves nunca se devuelven ni se registran.
import { createClient } from 'npm:@supabase/supabase-js@2';

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

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CORREO = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const BLOQUEO_LARGO = '876000h'; // ~100 años: equivale a «bloqueado hasta que se reactive»

Deno.serve(async (req) => {
  fijarCors(req);
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);
  if (Number(req.headers.get('content-length') ?? 0) > 4096) return json({ error: 'cuerpo_muy_grande' }, 413);

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'no_autenticado' }, 401);
  let p: Record<string, unknown>;
  try {
    p = await req.json();
  } catch {
    return json({ error: 'cuerpo_invalido' }, 400);
  }

  const url = Deno.env.get('SUPABASE_URL')!;
  // Cliente con el JWT del que llama: valida la sesión y aplica los permisos reales de la base.
  const db = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: sesion } = await db.auth.getUser(auth.slice(7));
  if (!sesion.user) return json({ error: 'no_autenticado' }, 401);
  const { data: esAdmin } = await db.rpc('es_admin_plataforma');
  if (esAdmin !== true) return json({ error: 'solo_admin_plataforma' }, 403);

  const svc = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const quien = sesion.user.id;
  const bitacora = (accion: string, objetivo: string, detalle: Record<string, unknown> = {}) =>
    db.rpc('admin_accion_registrar', { p_accion: accion, p_objetivo: objetivo, p_detalle: detalle });
  const usuario = String(p['usuario_id'] ?? '');
  const clave = typeof p['password'] === 'string' ? (p['password'] as string) : '';
  const claveValida = (c: string) => c.length >= 8 && c.length <= 72;

  switch (p['accion']) {
    case 'crear': {
      const correo = String(p['email'] ?? '').trim().toLowerCase();
      const nombre = String(p['nombre'] ?? '').trim();
      if (!CORREO.test(correo) || correo.length > 254) return json({ error: 'correo_invalido' }, 400);
      if (!claveValida(clave)) return json({ error: 'clave_invalida' }, 400);
      if (nombre.length < 1 || nombre.length > 120) return json({ error: 'nombre_invalido' }, 400);
      const { data, error } = await svc.auth.admin.createUser({
        email: correo,
        password: clave,
        email_confirm: true,
        user_metadata: { nombre },
      });
      if (error || !data.user) {
        const ya = (error?.message ?? '').toLowerCase().includes('already') || (error as { code?: string } | null)?.code === 'email_exists';
        return json({ error: ya ? 'correo_existe' : 'no_se_pudo_crear' }, ya ? 409 : 400);
      }
      await bitacora('usuario_crear', data.user.id, { correo });
      return json({ ok: true, id: data.user.id, correo });
    }
    case 'clave': {
      if (!UUID.test(usuario)) return json({ error: 'usuario_invalido' }, 400);
      if (!claveValida(clave)) return json({ error: 'clave_invalida' }, 400);
      const { error } = await svc.auth.admin.updateUserById(usuario, { password: clave });
      if (error) return json({ error: 'no_se_pudo_cambiar' }, 400);
      await bitacora('usuario_clave', usuario);
      return json({ ok: true });
    }
    case 'bloquear': {
      if (!UUID.test(usuario)) return json({ error: 'usuario_invalido' }, 400);
      const bloquear = p['bloquear'] === true;
      if (bloquear && usuario === quien) return json({ error: 'es_el_mismo' }, 409);
      const { error } = await svc.auth.admin.updateUserById(usuario, { ban_duration: bloquear ? BLOQUEO_LARGO : 'none' });
      if (error) return json({ error: 'no_se_pudo_cambiar' }, 400);
      await bitacora(bloquear ? 'usuario_bloquear' : 'usuario_desbloquear', usuario);
      return json({ ok: true });
    }
    case 'borrar': {
      if (!UUID.test(usuario)) return json({ error: 'usuario_invalido' }, 400);
      const { data: chequeo, error: e1 } = await db.rpc('admin_usuario_borrable', { p_usuario: usuario });
      if (e1) return json({ error: 'usuario_no_existe' }, 404);
      if (!chequeo?.ok) return json({ error: 'no_borrable', motivos: chequeo?.motivos ?? [] }, 409);
      const { error } = await svc.auth.admin.deleteUser(usuario);
      // Si aún hay datos que lo referencian, la base lo impide: se sugiere bloquear en vez de borrar.
      if (error) return json({ error: 'no_borrable', motivos: ['tiene_datos'] }, 409);
      await bitacora('usuario_borrar', usuario);
      return json({ ok: true });
    }
    case 'impersonar': {
      // «Entrar como»: genera un enlace de un solo uso SIN enviar correo y devuelve solo su token_hash;
      // el cliente lo canjea con verifyOtp. El token nunca se registra ni se guarda; solo queda la bitácora.
      if (!UUID.test(usuario)) return json({ error: 'usuario_invalido' }, 400);
      if (usuario === quien) return json({ error: 'es_el_mismo' }, 409);
      const { data: obj, error: eObj } = await svc.auth.admin.getUserById(usuario);
      if (eObj || !obj.user || !obj.user.email) return json({ error: 'usuario_no_existe' }, 404);
      const bloqueado = obj.user.banned_until ? new Date(obj.user.banned_until).getTime() > Date.now() : false;
      if (bloqueado) return json({ error: 'usuario_bloqueado' }, 409);
      const { data: esOtroAdmin } = await svc.from('plataforma_admins').select('usuario_id').eq('usuario_id', usuario).maybeSingle();
      if (esOtroAdmin) return json({ error: 'no_a_otro_admin' }, 409);
      const { data: enlace, error: eEnl } = await svc.auth.admin.generateLink({ type: 'magiclink', email: obj.user.email });
      const tokenHash = enlace?.properties?.hashed_token;
      if (eEnl || !tokenHash) return json({ error: 'no_se_pudo_entrar' }, 400);
      await bitacora('usuario_entrar_como', usuario, { correo: obj.user.email });
      return json({ ok: true, token_hash: tokenHash, correo: obj.user.email });
    }
    default:
      return json({ error: 'accion_invalida' }, 400);
  }
});
