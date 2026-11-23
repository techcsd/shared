import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ConfiguracionService } from '../../../core/configuracion.service';
import { GrupoService } from '../../../core/grupo.service';
import { t } from '../../../core/i18n/i18n';
import { DestinoModel, TarifaModel } from '../../../../shared/models/config.model';

/** Destinos (playa, pesca, La Romana, otros) y su fee vigente (SA20). Solo socios ven y editan tarifas. */
@Component({
  selector: 'app-config-destinos',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './config-destinos.html',
  styleUrl: './config-destinos.scss',
})
export class ConfigDestinos implements OnInit {
  t = t;
  destinos = signal<DestinoModel[]>([]);
  tarifas = signal<TarifaModel[]>([]);
  nuevo = '';
  fees: Record<string, number> = {};
  error = signal<string | null>(null);

  constructor(
    public grupos: GrupoService,
    private config: ConfiguracionService,
  ) {}

  async ngOnInit(): Promise<void> {
    await this.recargar();
  }

  get moneda(): string {
    return this.grupos.grupo()?.moneda ?? 'DOP';
  }

  private async recargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    const [d, tf] = await Promise.all([this.config.destinos(g), this.config.tarifas(g)]);
    this.destinos.set(d);
    this.tarifas.set(tf);
    for (const dest of d) this.fees[dest.id] = this.feeVigente(dest.id) ?? 0;
  }

  feeVigente(destino: string): number | null {
    const hoy = new Date().toISOString().slice(0, 10);
    const f = this.tarifas().find(
      (x) =>
        x.destino_id === destino &&
        x.tipo === 'fee_destino' &&
        x.vigente_desde <= hoy &&
        (!x.vigente_hasta || x.vigente_hasta >= hoy),
    );
    return f ? Number(f.monto) : null;
  }

  async agregar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g || !this.nuevo.trim()) return;
    this.error.set(null);
    const r = await this.config.crearDestino(g, this.nuevo, this.destinos().length + 1);
    if (r.error) this.error.set(r.error);
    else this.nuevo = '';
    await this.recargar();
  }

  async alternar(d: DestinoModel): Promise<void> {
    const r = await this.config.cambiarDestino(d.id, { activo: !d.activo });
    if (r.error) this.error.set(r.error);
    await this.recargar();
  }

  async guardarFee(d: DestinoModel): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    this.error.set(null);
    const r = await this.config.fijarFee(g, d.id, Number(this.fees[d.id] ?? 0), this.moneda);
    if (r.error) this.error.set(r.error);
    await this.recargar();
  }
}
