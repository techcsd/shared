import { DecimalPipe } from '@angular/common';
import { Component, OnInit, computed, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { ActivoModel } from '../../../shared/models/config.model';
import { PolizaModel, SiniestroModel } from '../../../shared/models/p4.model';
import { ConfiguracionService } from '../../core/configuracion.service';
import { GobiernoService } from '../../core/gobierno.service';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { t } from '../../core/i18n/i18n';
import { claveError } from '../../core/reserva.service';

/** Seguro y siniestros (SA29): pólizas, aviso permanente sin póliza vigente (no bloquea) y deducible por acuerdo. */
@Component({
  selector: 'app-seguro',
  standalone: true,
  imports: [FormsModule, DecimalPipe, RouterLink],
  templateUrl: './seguro.html',
  styleUrl: '../p4-comun.scss',
})
export class SeguroPage implements OnInit {
  t = t;
  tk = (k: string): string => t(k as ClaveI18n);
  polizas = signal<PolizaModel[]>([]);
  siniestros = signal<SiniestroModel[]>([]);
  activos = signal<ActivoModel[]>([]);
  error = signal<string | null>(null);
  aviso = signal<string | null>(null);
  hoy = new Date().toISOString().slice(0, 10);

  activo = '';
  aseguradora = '';
  numero = '';
  cobertura = '';
  desde = '';
  hasta = '';
  deducible: number | null = 0;
  sDescripcion = '';

  sinPoliza = computed(() =>
    this.activos().filter(
      (a) => !this.polizas().some((p) => p.activo_id === a.id && p.vigente_desde <= this.hoy && p.vigente_hasta >= this.hoy),
    ),
  );

  constructor(
    public grupos: GrupoService,
    private gob: GobiernoService,
    private config: ConfiguracionService,
  ) {}

  async ngOnInit(): Promise<void> {
    await this.cargar();
  }

  async cargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    const [p, s, a] = await Promise.all([this.gob.polizas(g), this.gob.siniestros(g), this.config.activos(g)]);
    this.polizas.set(p);
    this.siniestros.set(s);
    this.activos.set(a.filter((x) => x.estado === 'activo'));
    if (!this.activo && a[0]) this.activo = a[0].id;
  }

  nombreActivo(id: string): string {
    return this.activos().find((a) => a.id === id)?.nombre ?? '';
  }

  private mostrarError(msg: string): void {
    this.error.set(t(claveError(msg) as ClaveI18n));
  }

  async guardarPoliza(): Promise<void> {
    this.error.set(null);
    const g = this.grupos.grupo()?.id;
    if (!g || !this.aseguradora || !this.desde || !this.hasta) return;
    const r = await this.gob.guardarPoliza(g, {
      activo: this.activo,
      aseguradora: this.aseguradora,
      numero: this.numero,
      cobertura: this.cobertura,
      desde: this.desde,
      hasta: this.hasta,
      deducible: this.deducible ?? 0,
      moneda: this.grupos.grupo()?.moneda ?? 'DOP',
    });
    if (r.error) return this.mostrarError(r.error);
    this.aseguradora = this.numero = this.cobertura = '';
    await this.cargar();
  }

  async abrirSiniestro(): Promise<void> {
    this.error.set(null);
    const g = this.grupos.grupo()?.id;
    if (!g || this.sDescripcion.trim().length < 3) return;
    const r = await this.gob.abrirSiniestro(g, this.activo, this.sDescripcion);
    if (r.error) return this.mostrarError(r.error);
    this.sDescripcion = '';
    this.aviso.set(t('seg.siniestro_ok'));
    await this.cargar();
  }

  async estado(s: SiniestroModel, estado: string): Promise<void> {
    const r = await this.gob.estadoSiniestro(s.id, estado);
    if (r.error) this.mostrarError(r.error);
    await this.cargar();
  }
}
