import { TestBed } from '@angular/core/testing';
import {
  ActivatedRouteSnapshot,
  Router,
  RouterStateSnapshot,
  UrlTree,
  provideRouter,
} from '@angular/router';
import { AuthService } from '../auth.service';
import { GrupoService } from '../grupo.service';
import { authGuard, grupoGuard, rolGuard } from './guards';

const ruta = {} as ActivatedRouteSnapshot;
const estado = (url: string) => ({ url }) as RouterStateSnapshot;

function configurar(auth: Partial<AuthService>, grupos: Partial<GrupoService>) {
  TestBed.configureTestingModule({
    providers: [
      provideRouter([]),
      { provide: AuthService, useValue: auth },
      { provide: GrupoService, useValue: grupos },
    ],
  });
}

describe('guards', () => {
  it('authGuard manda a /login con el destino si no hay sesión', async () => {
    configurar({ listo: Promise.resolve(), autenticado: (() => false) as never }, {});
    const r = await TestBed.runInInjectionContext(() => authGuard(ruta, estado('/mas/grupo')));
    expect(r instanceof UrlTree).toBe(true);
    expect(TestBed.inject(Router).serializeUrl(r as UrlTree)).toBe('/login?volver=%2Fmas%2Fgrupo');
  });

  it('authGuard deja pasar con sesión', async () => {
    configurar({ listo: Promise.resolve(), autenticado: (() => true) as never }, {});
    expect(await TestBed.runInInjectionContext(() => authGuard(ruta, estado('/')))).toBe(true);
  });

  it('grupoGuard manda a /grupos si no hay grupo activo', async () => {
    configurar(
      { listo: Promise.resolve(), autenticado: (() => true) as never },
      { cargado: (() => true) as never, activa: (() => null) as never },
    );
    const r = await TestBed.runInInjectionContext(() => grupoGuard(ruta, estado('/')));
    expect(TestBed.inject(Router).serializeUrl(r as UrlTree)).toBe('/grupos');
  });

  it('rolGuard(socio) bloquea al admin operativo y deja pasar al socio', () => {
    configurar({}, { rol: (() => 'admin_operativo') as never });
    const bloqueado = TestBed.runInInjectionContext(() =>
      rolGuard(['socio'])(ruta, estado('/mas/finanzas')),
    );
    expect(TestBed.inject(Router).serializeUrl(bloqueado as UrlTree)).toBe('/mas');
    TestBed.resetTestingModule();
    configurar({}, { rol: (() => 'socio') as never });
    expect(
      TestBed.runInInjectionContext(() => rolGuard(['socio'])(ruta, estado('/mas/finanzas'))),
    ).toBe(true);
  });
});
