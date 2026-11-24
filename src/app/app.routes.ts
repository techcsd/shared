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
    path: 'g/:token',
    loadComponent: () => import('./pages/invitado/invitado').then((m) => m.InvitadoPage),
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
      {
        path: 'mis-salidas',
        loadComponent: () =>
          import('./pages/mis-salidas/mis-salidas').then((m) => m.MisSalidasPage),
      },
      {
        path: 'reservar',
        loadComponent: () => import('./pages/reservar/reservar').then((m) => m.ReservarPage),
      },
      {
        path: 'reserva/:id',
        loadComponent: () =>
          import('./pages/reserva-detalle/reserva-detalle').then((m) => m.ReservaDetallePage),
      },
      {
        path: 'mas/notificaciones',
        loadComponent: () =>
          import('./pages/notificaciones/notificaciones').then((m) => m.NotificacionesPage),
      },
      {
        path: 'gastos',
        loadComponent: () => import('./pages/gastos/gastos').then((m) => m.GastosPage),
      },
      {
        path: 'operacion/:id',
        loadComponent: () => import('./pages/operacion/operacion').then((m) => m.OperacionPage),
      },
      pendiente('mantenimiento', 'nav.mantenimiento'),
      { path: 'mas', loadComponent: () => import('./pages/mas/mas').then((m) => m.MasPage) },
      {
        path: 'mas/prioridad-911',
        canActivate: [rolGuard(['socio'])],
        loadComponent: () =>
          import('./pages/prioridad-911/prioridad-911').then((m) => m.Prioridad911Page),
      },
      { path: 'mas/operacion', pathMatch: 'full', redirectTo: 'mis-salidas' },
      {
        path: 'mas/finanzas',
        canActivate: [rolGuard(['socio'])],
        loadComponent: () => import('./pages/finanzas/finanzas').then((m) => m.FinanzasPage),
      },
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
