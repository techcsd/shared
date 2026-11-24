// Fechas en la zona horaria del GRUPO (no la del navegador): todo se guarda como timestamptz.

function partes(d: Date, tz: string) {
  const f = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  });
  const o: Record<string, string> = {};
  for (const p of f.formatToParts(d)) o[p.type] = p.value;
  return { y: +o['year'], m: +o['month'], d: +o['day'], h: +o['hour'], mi: +o['minute'] };
}

/** 'AAAA-MM-DD' del instante en la zona dada. */
export function claveDia(d: Date, tz: string): string {
  const p = partes(d, tz);
  return `${p.y}-${String(p.m).padStart(2, '0')}-${String(p.d).padStart(2, '0')}`;
}

function desfaseMs(utcMs: number, tz: string): number {
  const p = partes(new Date(utcMs), tz);
  return Date.UTC(p.y, p.m - 1, p.d, p.h, p.mi) - Math.floor(utcMs / 60000) * 60000;
}

/** Instante UTC que corresponde a 'AAAA-MM-DD' + 'HH:mm' en la zona dada. */
export function instanteDesdeZona(dia: string, hora: string, tz: string): Date {
  const [y, m, d] = dia.split('-').map(Number);
  const [h, mi] = hora.split(':').map(Number);
  const nominal = Date.UTC(y, m - 1, d, h, mi);
  let utc = nominal - desfaseMs(nominal, tz);
  utc = nominal - desfaseMs(utc, tz); // segunda pasada por cambios de horario
  return new Date(utc);
}

export function horaZona(d: Date, tz: string): string {
  const p = partes(d, tz);
  return `${String(p.h).padStart(2, '0')}:${String(p.mi).padStart(2, '0')}`;
}

export function fechaHoraZona(d: Date, tz: string, idioma = 'es'): string {
  return new Intl.DateTimeFormat(idioma, {
    timeZone: tz,
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(d);
}

export function sumarDias(dia: string, n: number): string {
  const [y, m, d] = dia.split('-').map(Number);
  const f = new Date(Date.UTC(y, m - 1, d + n));
  return f.toISOString().slice(0, 10);
}

export interface CeldaDia {
  clave: string;
  delMes: boolean;
}

/** Cuadrícula del mes (semanas completas, lunes primero). `mes` es 'AAAA-MM'. */
export function cuadriculaMes(mes: string): CeldaDia[] {
  const [y, m] = mes.split('-').map(Number);
  const primero = new Date(Date.UTC(y, m - 1, 1));
  const desfase = (primero.getUTCDay() + 6) % 7; // lunes = 0
  const inicio = new Date(Date.UTC(y, m - 1, 1 - desfase));
  const ultimo = new Date(Date.UTC(y, m, 0));
  const total = Math.ceil((desfase + ultimo.getUTCDate()) / 7) * 7;
  const celdas: CeldaDia[] = [];
  for (let i = 0; i < total; i++) {
    const f = new Date(inicio.getTime() + i * 86400000);
    celdas.push({ clave: f.toISOString().slice(0, 10), delMes: f.getUTCMonth() === m - 1 });
  }
  return celdas;
}

export function mesDe(dia: string): string {
  return dia.slice(0, 7);
}

export function sumarMeses(mes: string, n: number): string {
  const [y, m] = mes.split('-').map(Number);
  const f = new Date(Date.UTC(y, m - 1 + n, 1));
  return f.toISOString().slice(0, 7);
}

/** Etiqueta del mes en el idioma (p. ej. «diciembre de 2026»). */
export function nombreMes(mes: string, idioma = 'es'): string {
  const [y, m] = mes.split('-').map(Number);
  return new Intl.DateTimeFormat(idioma, {
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(Date.UTC(y, m - 1, 1)));
}

export function nombreDia(dia: string, idioma = 'es'): string {
  const [y, m, d] = dia.split('-').map(Number);
  return new Intl.DateTimeFormat(idioma, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    timeZone: 'UTC',
  }).format(new Date(Date.UTC(y, m - 1, d)));
}
