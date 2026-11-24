import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { t } from '../../core/i18n/i18n';

interface Entrada {
  ruta: string;
  etiqueta: ClaveI18n;
  soloSocio: boolean;
}

/** «Más»: lo que no cabe en el menú inferior. Las entradas solo-socio se ocultan al resto (SA16). */
@Component({
  selector: 'app-mas',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './mas.html',
  styleUrl: './mas.scss',
})
export class MasPage {
  t = t;
  readonly entradas: Entrada[] = [
    { ruta: '/mas/notificaciones', etiqueta: 'mas.notificaciones', soloSocio: false },
    { ruta: '/mas/prioridad-911', etiqueta: 'mas.prioridad_911', soloSocio: false },
    { ruta: '/mas/operacion', etiqueta: 'mas.operacion', soloSocio: false },
    { ruta: '/mas/finanzas', etiqueta: 'mas.finanzas', soloSocio: true },
    { ruta: '/mas/configuracion', etiqueta: 'mas.configuracion', soloSocio: true },
    { ruta: '/mas/estatuto', etiqueta: 'mas.estatuto', soloSocio: true },
    { ruta: '/mas/reportes', etiqueta: 'mas.reportes', soloSocio: false },
    { ruta: '/mas/disputas', etiqueta: 'mas.disputas', soloSocio: true },
    { ruta: '/mas/seguro', etiqueta: 'mas.seguro', soloSocio: false },
    { ruta: '/mas/capitanes', etiqueta: 'mas.capitanes', soloSocio: false },
    { ruta: '/mas/propuestas', etiqueta: 'mas.propuestas', soloSocio: true },
    { ruta: '/mas/grupo', etiqueta: 'mas.grupo', soloSocio: false },
    { ruta: '/mas/perfil', etiqueta: 'mas.perfil', soloSocio: false },
  ];

  constructor(public grupos: GrupoService) {}

  visibles(): Entrada[] {
    return this.entradas.filter((e) => !e.soloSocio || this.grupos.esSocio());
  }
}
