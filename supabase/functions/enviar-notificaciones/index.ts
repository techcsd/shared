// Envía por Resend los correos pendientes del outbox `notificaciones`.
// Cada fallo se registra con su motivo y se reintenta UNA vez (DF-34: nada silencioso).
// Se dispara desde pg_cron (cron_mantenimiento) con la service role en el Authorization.
import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? '';
const REMITENTE = Deno.env.get('RESEND_REMITENTE') ?? 'Shared <onboarding@resend.dev>';
const APP_URL = Deno.env.get('APP_URL') ?? 'https://shared-csd.vercel.app';
const MAX_INTENTOS = 2; // intento inicial + un reintento

const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

interface Fila {
  id: string;
  usuario_id: string | null;
  destinatario_correo: string | null;
  tipo: string;
  titulo: string;
  cuerpo: string | null;
  datos: Record<string, unknown>;
  reintentos: number;
}

function plantilla(f: Fila): { asunto: string; html: string } {
  // El texto de usuarios es dato: siempre escapado.
  let accion = `<p><a href="${APP_URL}">Abrir Shared</a></p>`;
  if (f.tipo === 'invitado_enlace' && typeof f.datos.token === 'string') {
    accion = `<p><a href="${APP_URL}/g/${encodeURIComponent(f.datos.token)}">Ver los detalles de tu salida</a> (punto de encuentro, reglas y contacto).</p>`;
  } else if (f.tipo.startsWith('prioridad_911')) {
    accion = `<p><a href="${APP_URL}/mas/prioridad-911">Ver Prioridad 911</a></p>`;
  } else if (f.datos.reserva_id) {
    accion = `<p><a href="${APP_URL}/reserva/${encodeURIComponent(String(f.datos.reserva_id))}">Ver la orden</a></p>`;
  }
  return {
    asunto: f.titulo,
    html: `<div style="font-family:system-ui,sans-serif;max-width:32rem"><h2>${esc(f.titulo)}</h2><p>${esc(f.cuerpo)}</p>${accion}<hr><small>Shared · mensaje automático</small></div>`,
  };
}

async function enviar(para: string, f: Fila): Promise<string | null> {
  if (!RESEND_API_KEY) return 'RESEND_API_KEY no configurada';
  const { asunto, html } = plantilla(f);
  try {
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: REMITENTE, to: [para], subject: asunto, html }),
    });
    if (r.ok) return null;
    return `Resend ${r.status}: ${(await r.text()).slice(0, 400)}`;
  } catch (e) {
    return `red: ${String(e).slice(0, 400)}`;
  }
}

Deno.serve(async () => {
  const db = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data, error } = await db
    .from('notificaciones')
    .select('id, usuario_id, destinatario_correo, tipo, titulo, cuerpo, datos, reintentos')
    .eq('canal', 'correo')
    .or(`estado_envio.eq.pendiente,and(estado_envio.eq.fallido,reintentos.lt.${MAX_INTENTOS})`)
    .order('creado_en')
    .limit(25);
  if (error) return Response.json({ error: error.message }, { status: 500 });

  let enviados = 0;
  let fallidos = 0;
  for (const f of (data ?? []) as Fila[]) {
    let correo = f.destinatario_correo;
    if (!correo && f.usuario_id) {
      const { data: p } = await db.from('perfiles').select('correo').eq('id', f.usuario_id).maybeSingle();
      correo = p?.correo ?? null;
    }
    if (!correo) {
      await db.from('notificaciones').update({ estado_envio: 'fallido', motivo_fallo: 'sin_correo', reintentos: MAX_INTENTOS }).eq('id', f.id);
      fallidos++;
      continue;
    }
    const motivo = await enviar(correo, f);
    if (motivo === null) {
      // el token del invitado deja de guardarse en claro una vez enviado
      const { token: _t, ...resto } = f.datos;
      await db.from('notificaciones').update({ estado_envio: 'enviado', motivo_fallo: null, datos: resto }).eq('id', f.id);
      enviados++;
    } else {
      await db
        .from('notificaciones')
        .update({ estado_envio: 'fallido', motivo_fallo: motivo, reintentos: f.reintentos + 1 })
        .eq('id', f.id);
      fallidos++;
    }
  }
  return Response.json({ procesadas: (data ?? []).length, enviados, fallidos });
});
