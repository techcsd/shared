import { DecimalPipe } from '@angular/common';
import { Component, OnInit, computed, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DestinoModel } from '../../../shared/models/config.model';
import { MiembroModel } from '../../../shared/models/grupo.model';
import { Dashboard, FilaReporte } from '../../../shared/models/p4.model';
import { ConfiguracionService } from '../../core/configuracion.service';
import { FiltroReporte, GobiernoService } from '../../core/gobierno.service';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { t } from '../../core/i18n/i18n';
import { claveError } from '../../core/reserva.service';

/** Reportes (SA18): dashboard mensual/anual, socio vs socio, salidas filtrables y exportación PDF/Excel. Solo lectura. */
@Component({
  selector: 'app-reportes',
  standalone: true,
  imports: [FormsModule, DecimalPipe],
  templateUrl: './reportes.html',
  styleUrl: '../p4-comun.scss',
})
export class ReportesPage implements OnInit {
  t = t;
  dash = signal<Dashboard | null>(null);
  filas = signal<FilaReporte[]>([]);
  miembros = signal<MiembroModel[]>([]);
  destinos = signal<DestinoModel[]>([]);
  error = signal<string | null>(null);
  cargando = signal(true);
  anio = new Date().getFullYear();
  mes = '';
  f: FiltroReporte = {};

  maxMes = computed(() => Math.max(1, ...(this.dash()?.por_mes.map((m) => Math.max(m.costo, 0)) ?? [1])));
  maxSocio = computed(() => Math.max(1, ...(this.dash()?.por_miembro.map((m) => Math.max(m.costo, 0)) ?? [1])));
  monedaGrupo = computed(() => this.grupos.grupo()?.moneda ?? 'DOP');
  totalFee = computed(() => this.filas().reduce((s, x) => s + x.fee, 0));

  constructor(
    public grupos: GrupoService,
    private gob: GobiernoService,
    private config: ConfiguracionService,
  ) {}

  async ngOnInit(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    this.miembros.set((await this.grupos.miembros(g)).filter((m) => m.rol === 'socio'));
    this.destinos.set(await this.config.destinos(g));
    await this.cargar();
  }

  private mostrarError(msg: string): void {
    this.error.set(t(claveError(msg) as ClaveI18n));
  }

  async cargar(): Promise<void> {
    this.error.set(null);
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    const d = await this.gob.dashboard(g, this.anio, this.mes ? Number(this.mes) : null);
    if (d.error) this.mostrarError(d.error);
    this.dash.set(d.datos);
    const s = await this.gob.reporteSalidas(g, this.f);
    if (s.error) this.mostrarError(s.error);
    this.filas.set(s.datos ?? []);
    this.cargando.set(false);
  }

  async exportar(formato: 'xlsx' | 'pdf'): Promise<void> {
    this.error.set(null);
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    const r = await this.gob.exportar(g, formato, this.f);
    if (r.error || !r.datos) return void this.error.set(t('app.error.generico'));
    const url = URL.createObjectURL(r.datos);
    const a = document.createElement('a');
    a.href = url;
    a.download = `reporte-salidas.${formato}`;
    a.click();
    URL.revokeObjectURL(url);
  }

  ancho(valor: number, max: number): string {
    return `${Math.max(2, Math.round((Math.max(valor, 0) / max) * 100))}%`;
  }
}
