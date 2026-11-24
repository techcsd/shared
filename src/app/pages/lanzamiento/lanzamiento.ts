import { Component, OnInit, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { FormacionService, ItemLanzamiento } from '../../core/formacion.service';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { t } from '../../core/i18n/i18n';

/** Lanzamiento (SA35, SA19): checklist de datos reales y paso de demo a real (los datos demo se borran, nunca se mezclan). */
@Component({
  selector: 'app-lanzamiento',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './lanzamiento.html',
  styleUrl: '../p4-comun.scss',
})
export class LanzamientoPage implements OnInit {
  t = t;
  tk = (k: string): string => t(k as ClaveI18n);
  lista = signal<ItemLanzamiento[]>([]);
  error = signal<string | null>(null);
  aviso = signal<string | null>(null);

  constructor(
    public grupos: GrupoService,
    private form: FormacionService,
  ) {}

  async ngOnInit(): Promise<void> {
    await this.cargar();
  }

  async cargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    const r = await this.form.checklist(g);
    if (r.error) this.error.set(t('error.solo_socios'));
    this.lista.set(r.datos ?? []);
  }

  async pasar(): Promise<void> {
    this.error.set(null);
    const g = this.grupos.grupo()?.id;
    if (!g || !window.confirm(t('lanz.confirmar'))) return;
    const r = await this.form.pasarAReal(g);
    if (r.error) return void this.error.set(t('app.error.generico'));
    if (!r.datos?.ok) {
      this.error.set(t('lanz.faltan'));
      return;
    }
    this.aviso.set(t('lanz.listo'));
    await this.grupos.cargar();
    await this.cargar();
  }
}
