import { Component, OnInit, signal } from '@angular/core';
import { FormacionService, Salud } from '../../core/formacion.service';
import { t } from '../../core/i18n/i18n';

/** Salud del sistema (solo administrador de plataforma): errores, cola de correos con su motivo, métricas de uso. */
@Component({
  selector: 'app-salud',
  standalone: true,
  templateUrl: './salud.html',
  styleUrl: '../p4-comun.scss',
})
export class SaludPage implements OnInit {
  t = t;
  datos = signal<Salud | null>(null);
  denegado = signal(false);

  constructor(private form: FormacionService) {}

  async ngOnInit(): Promise<void> {
    const r = await this.form.salud();
    if (r.error) this.denegado.set(true);
    this.datos.set(r.datos);
  }

  estados(s: Salud): [string, number][] {
    return Object.entries(s.notificaciones);
  }
}
