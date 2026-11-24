import { DecimalPipe } from '@angular/common';
import { Component, OnInit, computed, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { MiembroModel } from '../../../shared/models/grupo.model';
import { SalidaSocioCaso, SalidaSocioOferta } from '../../../shared/models/p4.model';
import { GobiernoService } from '../../core/gobierno.service';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { t } from '../../core/i18n/i18n';
import { claveError } from '../../core/reserva.service';

/** Salida o venta de un socio (SA33): preferencia de los demás, valoración registrada, aceptación de todos y traspaso de %. La app no mueve dinero. */
@Component({
  selector: 'app-salida-socio',
  standalone: true,
  imports: [FormsModule, DecimalPipe],
  templateUrl: './salida-socio.html',
  styleUrl: '../p4-comun.scss',
})
export class SalidaSocioPage implements OnInit {
  t = t;
  tk = (k: string): string => t(k as ClaveI18n);
  casos = signal<SalidaSocioCaso[]>([]);
  ofertas = signal<Record<string, SalidaSocioOferta[]>>({});
  miembros = signal<MiembroModel[]>([]);
  error = signal<string | null>(null);
  nota = '';
  valoracion = '';
  oPorcentaje: number | null = null;
  oValor: number | null = null;

  yo = computed(() => this.grupos.activa()?.id ?? null);
  monedaGrupo = computed(() => this.grupos.grupo()?.moneda ?? 'DOP');

  constructor(
    public grupos: GrupoService,
    private gob: GobiernoService,
  ) {}

  async ngOnInit(): Promise<void> {
    await this.cargar();
  }

  async cargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    this.miembros.set(await this.grupos.miembros(g));
    const casos = await this.gob.casosSalida(g);
    this.casos.set(casos);
    const of: Record<string, SalidaSocioOferta[]> = {};
    for (const c of casos) of[c.id] = await this.gob.ofertasSalida(c.id);
    this.ofertas.set(of);
  }

  nombre(id: string): string {
    return this.miembros().find((m) => m.id === id)?.perfil?.nombre ?? '—';
  }

  sumaOfertas(c: SalidaSocioCaso): number {
    return (this.ofertas()[c.id] ?? []).reduce((s, o) => s + o.porcentaje, 0);
  }

  private async ejecutar(r: Promise<{ error: string | null }>): Promise<void> {
    this.error.set(null);
    const res = await r;
    if (res.error) this.error.set(t(claveError(res.error) as ClaveI18n));
    await this.cargar();
  }

  solicitar(): Promise<void> {
    const g = this.grupos.grupo()?.id ?? '';
    return this.ejecutar(this.gob.solicitarSalida(g, this.nota));
  }

  valorar(c: SalidaSocioCaso): Promise<void> {
    return this.ejecutar(this.gob.valorarSalida(c.id, this.valoracion));
  }

  ofertar(c: SalidaSocioCaso): Promise<void> {
    return this.ejecutar(this.gob.ofertarSalida(c.id, this.oPorcentaje ?? 0, this.oValor ?? 0, this.monedaGrupo()));
  }

  responder(c: SalidaSocioCaso, acepta: boolean): Promise<void> {
    return this.ejecutar(this.gob.responderSalida(c.id, acepta));
  }

  cerrar(c: SalidaSocioCaso): Promise<void> {
    return this.ejecutar(this.gob.cerrarSalida(c.id));
  }

  cancelar(c: SalidaSocioCaso): Promise<void> {
    return this.ejecutar(this.gob.cancelarSalida(c.id));
  }
}
