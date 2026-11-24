export type EstadoReserva =
  'borrador' | 'confirmada' | 'en_curso' | 'finalizada' | 'cancelada' | 'bloqueada_mantenimiento';
export type UsoReserva = 'personal' | 'familiar' | 'negocios' | 'invitado';

export interface ReservaModel {
  id: string;
  grupo_id: string;
  activo_id: string;
  rango: string; // tstzrange en texto: ["2026-12-05 14:00:00+00","2026-12-05 20:00:00+00")
  estado: EstadoReserva;
  tipo_bloqueo: 'mantenimiento' | 'preparacion' | null;
  motivo_bloqueo: string | null;
  uso: UsoReserva | null;
  destino_id: string | null;
  personas: number | null;
  reservado_por: string | null;
  responsable_miembro: string | null;
  responsable_invitado: string | null;
  borrador_expira_en: string | null;
  cancelada_en: string | null;
  cancelacion_tardia: boolean;
  cargo_cancelacion: number | null;
  motivo_cancelacion: string | null;
  creado_en: string;
  orden?: { codigo: string } | { codigo: string }[] | null;
}

export interface RangoFecha {
  inicio: Date;
  fin: Date;
}

/** Convierte un tstzrange de Postgres en dos fechas. */
export function parseRango(texto: string): RangoFecha {
  const m = texto.match(
    /["']?(\d{4}-\d{2}-\d{2}[ T][\d:.]+(?:[+-]\d{2}(?::?\d{2})?|Z)?)["']?\s*,\s*["']?(\d{4}-\d{2}-\d{2}[ T][\d:.]+(?:[+-]\d{2}(?::?\d{2})?|Z)?)["']?/,
  );
  if (!m) throw new Error(`Rango inválido: ${texto}`);
  const aIso = (s: string) => {
    let t = s.replace(' ', 'T');
    if (/[+-]\d{2}$/.test(t)) t += ':00';
    if (!/(Z|[+-]\d{2}:\d{2})$/.test(t)) t += 'Z';
    return new Date(t);
  };
  return { inicio: aIso(m[1]), fin: aIso(m[2]) };
}

export function codigoOrden(r: ReservaModel): string | null {
  const o = r.orden;
  if (!o) return null;
  return Array.isArray(o) ? (o[0]?.codigo ?? null) : o.codigo;
}

export type Motivo911 = 'cumpleanos' | 'evento_familiar' | 'cliente' | 'negocio';
export type Urgencia911 = 'baja' | 'media' | 'alta';
export type Estado911 =
  | 'pendiente'
  | 'aceptada'
  | 'rechazada'
  | 'contrapropuesta'
  | 'aceptada_contra'
  | 'rechazada_contra'
  | 'expirada';

export interface Solicitud911Model {
  id: string;
  reserva_id: string;
  titular_id: string;
  solicitante_id: string;
  motivo: Motivo911;
  urgencia: Urgencia911;
  alternativa: string | null;
  rango: string;
  uso: UsoReserva;
  personas: number;
  estado: Estado911;
  contra_rango: string | null;
  expira_en: string;
  creado_en: string;
  resuelta_en: string | null;
}

export interface Mensaje911Model {
  id: string;
  solicitud_id: string;
  autor_id: string | null;
  tipo: string;
  texto: string | null;
  creado_en: string;
}

export interface NotificacionModel {
  id: string;
  tipo: string;
  titulo: string;
  cuerpo: string | null;
  datos: Record<string, unknown>;
  leida_en: string | null;
  creado_en: string;
}

export interface TemporadaModel {
  id: string;
  periodo: string;
  anio: number;
  desde: string;
  hasta: string;
  miembro_prioridad: string;
  libre_desde: string;
}

export interface EventoAuditoria {
  id: number;
  tabla: string;
  accion: string;
  antes: Record<string, unknown> | null;
  despues: Record<string, unknown> | null;
  actor: string | null;
  momento: string;
  motivo: string | null;
}
