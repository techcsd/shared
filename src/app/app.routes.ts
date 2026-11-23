import { Route, Routes } from '@angular/router';
import { ClaveI18n } from './core/i18n/es';
import { authGuard, grupoGuard, rolGuard } from './core/guards/guards';

const pendiente = (path: string, titulo: ClaveI18n, soloSocio = false): Route => ({
  path,
  loadComponent: () => import('./pages/proximamente/proximamente').then((m) => m.ProximamentePage),
  data: { titulo },
  ...(soloSocio ? { canActivate: [rolGuard(['socio'])] } : {}),
});

// Rutas lazy. Finanzas y acuerdos: solo `socio` (SA16). El calendario es la pantalla principal (SA15).
export const routes: Routes = [
  { path: 'login', loadComponent: () => import('./pages/login/login').then((m) => m.LoginPage) },
  {
    path: 'restablecer',
    loadComponent: () => import('./pages/restablecer/restablecer').then((m) => m.RestablecerPage),
  },
  {
    path: 'unirse/:token',
    canActivate: [authGuard],
    loadComponent: () => import('./pages/unirse/unirse').then((m) => m.UnirsePage),
  },
  {
    path: 'grupos',
    canActivate: [authGuard],
    loadComponent: () => import('./pages/grupos/grupos').then((m) => m.GruposPage),
  },
  {
    path: '',
    canActivate: [authGuard, grupoGuard],
    loadComponent: () => import('./pages/shell/shell').then((m) => m.Shell),
    children: [
      { path: '', pathMatch: 'full', redirectTo: 'calendario' },
      {
        path: 'calendario',
        loadComponent: () => import('./pages/calendario/calendario').then((m) => m.CalendarioPage),
      },
      pendiente('mis-salidas', 'nav.mis_salidas'),
      pendiente('gastos', 'nav.gastos'),
      pendiente('mantenimiento', 'nav.mantenimiento'),
      { path: 'mas', loadComponent: () => import('./pages/mas/mas').then((m) => m.MasPage) },
      pendiente('mas/prioridad-911', 'mas.prioridad_911'),
      pendiente('mas/operacion', 'mas.operacion'),
      pendiente('mas/finanzas', 'mas.finanzas', true),
      {
        path: 'mas/configuracion',
        canActivate: [rolGuard(['socio'])],
        loadComponent: () =>
          import('./pages/configuracion/configuracion').then((m) => m.ConfiguracionPage),
      },
      {
        path: 'mas/estatuto',
        loadComponent: () => import('./pages/estatuto/estatuto').then((m) => m.EstatutoPage),
      },
      pendiente('mas/reportes', 'mas.reportes'),
      pendiente('mas/disputas', 'mas.disputas', true),
      pendiente('mas/seguro', 'mas.seguro'),
      pendiente('mas/capitanes', 'mas.capitanes'),
      pendiente('mas/propuestas', 'mas.propuestas', true),
      {
        path: 'mas/grupo',
        loadComponent: () => import('./pages/miembros/miembros').then((m) => m.MiembrosPage),
      },
      {
        path: 'mas/perfil',
        loadComponent: () => import('./pages/perfil/perfil').then((m) => m.PerfilPage),
      },
    ],
  },
  { path: '**', redirectTo: '' },
];
