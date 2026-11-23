import { TestBed } from '@angular/core/testing';
import { AuthService } from './auth.service';
import { GrupoService } from './grupo.service';
import { SupabaseService } from './supabase.service';

const grupo = (id: string, nombre: string, demo = false) => ({
  id,
  nombre,
  moneda: 'DOP',
  zona_horaria: 'America/Santo_Domingo',
  prefijo: 'BOT',
  estado: 'activo',
  modo_demo: demo,
});

function crear(filas: unknown[]) {
  const cadena = {
    select: () => cadena,
    eq: () => cadena,
    then: (f: (v: unknown) => unknown) => f({ data: filas, error: null }),
  };
  TestBed.configureTestingModule({
    providers: [
      { provide: SupabaseService, useValue: { cliente: { from: () => cadena } } },
      { provide: AuthService, useValue: { usuario: () => ({ id: 'u1' }) } },
    ],
  });
  return TestBed.inject(GrupoService);
}

describe('GrupoService', () => {
  beforeEach(() => localStorage.clear());

  it('toma el primer grupo, expone rol y modo demo', async () => {
    const s = crear([
      { id: 'm1', rol: 'socio', porcentaje: 50, grupo: grupo('g1', 'Bote Demo', true) },
      { id: 'm2', rol: 'admin_operativo', porcentaje: 0, grupo: grupo('g2', 'Carro') },
    ]);
    await s.cargar();
    expect(s.grupo()?.nombre).toBe('Bote Demo');
    expect(s.rol()).toBe('socio');
    expect(s.esSocio()).toBe(true);
    expect(s.modoDemo()).toBe(true);
  });

  it('cambia de grupo y el rol cambia con él', async () => {
    const s = crear([
      { id: 'm1', rol: 'socio', porcentaje: 50, grupo: grupo('g1', 'A') },
      { id: 'm2', rol: 'admin_operativo', porcentaje: 0, grupo: grupo('g2', 'B') },
    ]);
    await s.cargar();
    s.seleccionar('g2');
    expect(s.grupo()?.nombre).toBe('B');
    expect(s.esSocio()).toBe(false);
  });

  it('sin membresías no hay grupo activo', async () => {
    const s = crear([]);
    await s.cargar();
    expect(s.activa()).toBeNull();
    expect(s.rol()).toBeNull();
  });
});
