import { describe, expect, it, vi } from 'vitest';
import { OfflineService } from './offline.service';
import { SupabaseService } from './supabase.service';

function servicio(rpc: (n: string, a: unknown) => Promise<{ error: { message: string } | null }>) {
  localStorage.clear();
  return new OfflineService({ cliente: { rpc } } as unknown as SupabaseService);
}

describe('OfflineService', () => {
  it('nunca encola reservas ni confirmaciones (el choque exige el servidor)', () => {
    const s = servicio(async () => ({ error: null }));
    expect(s.encolar('reserva_confirmar', { p_reserva: 'x' })).toBe(false);
    expect(s.encolar('reserva_crear_borrador', {})).toBe(false);
    expect(s.pendientes()).toBe(0);
  });

  it('encola gastos y correcciones de lectura, y los envía en orden al volver la red', async () => {
    const llamadas: string[] = [];
    const s = servicio(async (n) => {
      llamadas.push(n);
      return { error: null };
    });
    expect(s.encolar('gasto_registrar', { p_monto: 10 })).toBe(true);
    expect(s.encolar('lectura_corregir', { p_valor: 5 })).toBe(true);
    expect(s.pendientes()).toBe(2);
    const r = await s.sincronizar();
    expect(r).toEqual({ enviados: 2, descartados: 0 });
    expect(llamadas).toEqual(['gasto_registrar', 'lectura_corregir']);
    expect(s.pendientes()).toBe(0);
  });

  it('si sigue sin red, conserva lo pendiente; si el servidor lo rechaza por reglas, lo descarta', async () => {
    let paso = 0;
    const s = servicio(async () => {
      paso++;
      return { error: { message: paso === 1 ? 'monto_invalido' : 'Failed to fetch' } };
    });
    s.encolar('gasto_registrar', { a: 1 });
    s.encolar('gasto_registrar', { a: 2 });
    const r = await s.sincronizar();
    expect(r.descartados).toBe(1);
    expect(s.pendientes()).toBe(1);
  });

  it('guarda y lee la copia local del calendario', () => {
    const s = servicio(async () => ({ error: null }));
    s.guardar('calendario.a1', [{ id: 'r1' }]);
    expect(s.leer<{ id: string }[]>('calendario.a1')).toEqual([{ id: 'r1' }]);
    s.limpiarTodo();
    expect(s.leer('calendario.a1')).toBeNull();
  });

  it('distingue fallo de red de fallo de reglas', () => {
    const s = servicio(vi.fn());
    expect(s.esFalloDeRed('TypeError: Failed to fetch')).toBe(true);
    expect(s.esFalloDeRed('horario_ocupado')).toBe(false);
  });
});
