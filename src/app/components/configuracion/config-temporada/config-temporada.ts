import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { GrupoService } from '../../../core/grupo.service';
import { ClaveI18n } from '../../../core/i18n/es';
import { t } from '../../../core/i18n/i18n';
import { PoliticaService } from '../../../core/politica.service';
import { ReservaService } from '../../../core/reserva.service';
import { MiembroModel } from '../../../../shared/models/grupo.model';
import { TemporadaModel } from '../../../../shared/models/reserva.model';

/** Feriados y temporada alta con rotación anual (SA27, DF-19). Apagada por defecto: se activa en el Estatuto. */
@Component({
  selector: 'app-config-temporada',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './config-temporada.html',
  styleUrl: './config-temporada.scss',
})
export class ConfigTemporada implements OnInit {
  t = t;
  activa = signal(false);
  lista = signal<TemporadaModel[]>([]);
  miembros = signal<MiembroModel[]>([]);
  error = signal<string | null>(null);
  periodos = ['semana_santa', 'navidad', 'ano_nuevo', 'verano', 'otro'];
  periodo = 'navidad';
  anio = new Date().getFullYear();
  desde = '';
  hasta = '';

  constructor(
    private grupos: GrupoService,
    private reservas: ReservaService,
    private politicas: PoliticaService,
  ) {}

  async ngOnInit(): Promise<void> {
    await this.recargar();
  }

  private async recargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    this.activa.set((await this.politicas.valor(g, 'temporada_alta.activa')) === true);
    this.lista.set(await this.reservas.temporadas(g));
    this.miembros.set(await this.grupos.miembros(g));
  }

  periodoTexto(p: string): string {
    const mapa: Record<string, ClaveI18n> = {
      semana_santa: 'temp.semana_santa',
      navidad: 'temp.navidad',
      ano_nuevo: 'temp.ano_nuevo',
      verano: 'temp.verano',
      otro: 'temp.otro',
    };
    return t(mapa[p] ?? 'temp.otro');
  }

  quien(id: string): string {
    return this.miembros().find((m) => m.id === id)?.perfil?.nombre ?? '—';
  }

  async generar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    this.error.set(null);
    const err = await this.reservas.generarTemporada(
      g,
      this.periodo,
      Number(this.anio),
      this.desde,
      this.hasta,
    );
    if (err) this.error.set(err.includes('duplicate') ? t('temp.ya_existe') : err);
    await this.recargar();
  }

  async quitar(id: string): Promise<void> {
    const err = await this.reservas.quitarTemporada(id);
    if (err) this.error.set(err);
    await this.recargar();
  }
}
