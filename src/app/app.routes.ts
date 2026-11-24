import { Routes } from '@angular/router';
import { authGuard, grupoGuard, rolGuard } from './core/guards/guards';

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
    path: 'propuesta/:token',
    canActivate: [authGuard],
    loadComponent: () => import('./pages/propuesta-unirse/propuesta-unirse').then((m) => m.PropuestaUnirsePage),
  },
  {
    path: 'g/:token',
    loadComponent: () => import('./pages/invitado/invitado').then((m) => m.InvitadoPage),
  },
  {
    path: 'mediar/:token',
    canActivate: [authGuard],
    loadComponent: () => import('./pages/mediar/mediar').then((m) => m.MediarPage),
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
      {
        path: 'mantenimiento',
        loadComponent: () => import('./pages/mantenimiento/mantenimiento').then((m) => m.MantenimientoPage),
      },
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
      {
        path: 'mas/reportes',
        loadComponent: () => import('./pages/reportes/reportes').then((m) => m.ReportesPage),
      },
      {
        path: 'mas/disputas',
        canActivate: [rolGuard(['socio'])],
        loadComponent: () => import('./pages/disputas/disputas').then((m) => m.DisputasPage),
      },
      {
        path: 'mas/salida-socio',
        canActivate: [rolGuard(['socio'])],
        loadComponent: () => import('./pages/salida-socio/salida-socio').then((m) => m.SalidaSocioPage),
      },
      {
        path: 'mas/seguro',
        loadComponent: () => import('./pages/seguro/seguro').then((m) => m.SeguroPage),
      },
      {
        path: 'mas/capitanes',
        loadComponent: () => import('./pages/capitanes/capitanes').then((m) => m.CapitanesPage),
      },
      {
        path: 'mas/propuestas',
        loadComponent: () => import('./pages/propuestas/propuestas').then((m) => m.PropuestasPage),
      },
      {
        path: 'mas/lanzamiento',
        canActivate: [rolGuard(['socio'])],
        loadComponent: () => import('./pages/lanzamiento/lanzamiento').then((m) => m.LanzamientoPage),
      },
      {
        path: 'mas/salud',
        loadComponent: () => import('./pages/salud/salud').then((m) => m.SaludPage),
      },
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
