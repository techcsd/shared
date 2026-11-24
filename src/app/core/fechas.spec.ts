import {
  claveDia,
  cuadriculaMes,
  horaZona,
  instanteDesdeZona,
  sumarDias,
  sumarMeses,
} from './fechas';
import { parseRango } from '../../shared/models/reserva.model';

const RD = 'America/Santo_Domingo'; // UTC-4 todo el año

describe('fechas por zona horaria', () => {
  it('convierte hora local del grupo a instante UTC y de vuelta', () => {
    const d = instanteDesdeZona('2026-12-05', '09:30', RD);
    expect(d.toISOString()).toBe('2026-12-05T13:30:00.000Z');
    expect(horaZona(d, RD)).toBe('09:30');
    expect(claveDia(d, RD)).toBe('2026-12-05');
  });

  it('un instante de madrugada UTC cae en el día anterior del grupo', () => {
    expect(claveDia(new Date('2026-12-06T02:00:00Z'), RD)).toBe('2026-12-05');
  });

  it('respeta cambio de horario en otra zona', () => {
    const d = instanteDesdeZona('2026-07-01', '12:00', 'America/New_York'); // EDT = UTC-4
    expect(d.toISOString()).toBe('2026-07-01T16:00:00.000Z');
    const i = instanteDesdeZona('2026-01-15', '12:00', 'America/New_York'); // EST = UTC-5
    expect(i.toISOString()).toBe('2026-01-15T17:00:00.000Z');
  });

  it('cuadrícula del mes con semanas completas empezando en lunes', () => {
    const c = cuadriculaMes('2026-12');
    expect(c.length % 7).toBe(0);
    expect(c.find((x) => x.clave === '2026-12-01')?.delMes).toBe(true);
    expect(new Date(c[0].clave + 'T00:00:00Z').getUTCDay()).toBe(1);
  });

  it('suma días y meses', () => {
    expect(sumarDias('2026-12-31', 1)).toBe('2027-01-01');
    expect(sumarMeses('2026-12', 1)).toBe('2027-01');
    expect(sumarMeses('2026-01', -1)).toBe('2025-12');
  });
});

describe('parseRango', () => {
  it('lee el tstzrange que devuelve PostgREST', () => {
    const r = parseRango('["2026-12-05 14:00:00+00","2026-12-05 20:30:00+00")');
    expect(r.inicio.toISOString()).toBe('2026-12-05T14:00:00.000Z');
    expect(r.fin.toISOString()).toBe('2026-12-05T20:30:00.000Z');
  });
  it('acepta offsets distintos de +00', () => {
    const r = parseRango('["2026-12-05 10:00:00-04","2026-12-05 12:00:00-04")');
    expect(r.inicio.toISOString()).toBe('2026-12-05T14:00:00.000Z');
  });
});
