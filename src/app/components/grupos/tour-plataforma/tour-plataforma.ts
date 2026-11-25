import { Component, Input, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { t } from '../../../core/i18n/i18n';

interface PasoTour {
  clave: 'calendario' | 'reservas' | 'gastos' | 'mantenimiento' | 'reportes';
  icono: string; // trazado SVG (24x24)
}

/** «Explorar la plataforma»: recorrido de solo lectura con tarjetas ilustrativas (sin datos reales ni backend). */
@Component({
  selector: 'app-tour-plataforma',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './tour-plataforma.html',
  styleUrl: './tour-plataforma.scss',
})
export class TourPlataforma {
  t = t;
  /** El directorio público solo se ofrece si la plataforma lo habilitó (apagado por defecto). */
  @Input() directorio = false;
  abierto = signal(false);
  paso = signal(0);

  readonly pasos: PasoTour[] = [
    { clave: 'calendario', icono: 'M3.5 6.5a3 3 0 0 1 3-3h11a3 3 0 0 1 3 3v11a3 3 0 0 1-3 3h-11a3 3 0 0 1-3-3zM3.5 10h17M8 3v4M16 3v4' },
    { clave: 'reservas', icono: 'M3 17c2 0 2.5 1.5 4.5 1.5S10 17 12 17s2.5 1.5 4.5 1.5S19 17 21 17M5 14 12 4l7 10zM12 4v10' },
    { clave: 'gastos', icono: 'M3 7a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v10a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3zM3 10h18M16.5 14.5H18' },
    { clave: 'mantenimiento', icono: 'M14.5 6.5a4 4 0 0 0 5 5L11 20a2.1 2.1 0 0 1-3-3l8.5-8.5a4 4 0 0 0-2-2z' },
    { clave: 'reportes', icono: 'M5 20V10M12 20V4M19 20v-7' },
  ];

  alternar(): void {
    this.abierto.set(!this.abierto());
  }

  ir(delta: number): void {
    const n = this.pasos.length;
    this.paso.set((this.paso() + delta + n) % n);
  }

  titulo(p: PasoTour): string {
    return t(`tour.${p.clave}.titulo` as never);
  }

  texto(p: PasoTour): string {
    return t(`tour.${p.clave}.texto` as never);
  }
}
