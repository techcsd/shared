/** Interpreta lo que alguien pega para unirse: un enlace /unirse/… o /propuesta/… o solo el código. Solo lee; no confía en nada. */
export type TipoEnlace = 'invitacion' | 'propuesta' | 'desconocido';

export interface EnlaceInterpretado {
  tipo: TipoEnlace;
  token: string;
}

// Los tokens son hex/alfanuméricos largos (invitación: 64 hex). Cualquier cosa fuera de este alfabeto se rechaza.
const TOKEN = /^[A-Za-z0-9_-]{16,200}$/;

export function interpretarEnlace(texto: string): EnlaceInterpretado | null {
  const limpio = (texto ?? '').trim();
  if (!limpio || limpio.length > 2000) return null;
  const ruta = limpio.match(/\/(unirse|propuesta)\/([^/?#\s]+)/i);
  if (ruta) {
    let token = ruta[2];
    try {
      token = decodeURIComponent(token);
    } catch {
      return null;
    }
    if (!TOKEN.test(token)) return null;
    return { tipo: ruta[1].toLowerCase() === 'unirse' ? 'invitacion' : 'propuesta', token };
  }
  if (TOKEN.test(limpio)) return { tipo: 'desconocido', token: limpio };
  return null;
}
