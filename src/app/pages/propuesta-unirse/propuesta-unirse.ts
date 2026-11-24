import { DecimalPipe } from '@angular/common';
import { Component, Input, OnInit, signal } from '@angular/core';
import { Router } from '@angular/router';
import { FormacionService } from '../../core/formacion.service';
import { ClaveI18n } from '../../core/i18n/es';
import { t } from '../../core/i18n/i18n';
import { claveError } from '../../core/reserva.service';

/** Enlace de una propuesta de compra: /propuesta/:token (requiere sesión). Muestra lo mínimo antes de unirse. */
@Component({
  selector: 'app-propuesta-unirse',
  standalone: true,
  imports: [DecimalPipe],
  templateUrl: './propuesta-unirse.html',
  styleUrl: '../p4-comun.scss',
})
export class PropuestaUnirsePage implements OnInit {
  t = t;
  @Input() token = '';
  vista = signal<{ id: string; titulo: string; precio_objetivo: number; moneda: string; organizador: string } | null>(null);
  error = signal<string | null>(null);
  cargando = signal(true);

  constructor(
    private form: FormacionService,
    private router: Router,
  ) {}

  async ngOnInit(): Promise<void> {
    this.vista.set(await this.form.vistaPrevia(this.token));
    if (!this.vista()) this.error.set(t('prop.enlace_invalido'));
    this.cargando.set(false);
  }

  async unirse(): Promise<void> {
    const r = await this.form.unirse(this.token);
    if (r.error) return void this.error.set(r.error.includes('sin_cupos') ? t('prop.sin_cupos') : t(claveError(r.error) as ClaveI18n));
    await this.router.navigateByUrl('/mas/propuestas');
  }
}
