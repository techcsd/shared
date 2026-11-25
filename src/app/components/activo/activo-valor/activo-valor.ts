import { Component, OnChanges } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Icono } from '../../../../shared/ui/icono/icono';
import { MejoraActivo } from '../../../../shared/models/activo-entidad.model';
import { ActivoSeccion } from '../activo-seccion';

interface FilaMejora {
  id: string | null;
  fecha: string;
  descripcion: string;
  costo: number | null;
  moneda: string;
  proveedor: string;
  original: string;
}

/** Valor del activo y mejoras (solo socios). Es información: no genera cargos ni mueve balances. */
@Component({
  selector: 'app-activo-valor',
  standalone: true,
  imports: [FormsModule, Icono],
  templateUrl: './activo-valor.html',
})
export class ActivoValorSeccion extends ActivoSeccion implements OnChanges {
  val = { compra: null as number | null, monedaCompra: '', fechaCompra: '', estimado: null as number | null, monedaEst: '', fechaEst: '' };
  filas: FilaMejora[] = [];
  nueva!: FilaMejora;

  ngOnChanges(): void {
    const v = this.d.valor;
    const m = this.d.grupo.moneda;
    this.val = {
      compra: v?.precio_compra ?? null,
      monedaCompra: v?.moneda_compra ?? m,
      fechaCompra: v?.fecha_compra ?? '',
      estimado: v?.valor_estimado ?? null,
      monedaEst: v?.moneda_estimado ?? m,
      fechaEst: v?.fecha_estimado ?? '',
    };
    this.filas = (this.d.mejoras ?? []).map((x) => this.aFila(x));
    this.nueva = this.vacia();
  }

  private vacia(): FilaMejora {
    return { id: null, fecha: new Date().toISOString().slice(0, 10), descripcion: '', costo: null, moneda: this.d.grupo.moneda, proveedor: '', original: '' };
  }

  private aFila(x: MejoraActivo): FilaMejora {
    const f: FilaMejora = { id: x.id, fecha: x.fecha, descripcion: x.descripcion, costo: Number(x.costo), moneda: x.moneda, proveedor: x.proveedor ?? '', original: '' };
    f.original = this.firma(f);
    return f;
  }

  private firma(f: FilaMejora): string {
    return JSON.stringify([f.fecha, f.descripcion, f.costo, f.moneda, f.proveedor]);
  }

  sucia(f: FilaMejora): boolean {
    return this.firma(f) !== f.original;
  }

  /** Total invertido por moneda (nunca se suman monedas distintas). */
  totales(): { moneda: string; total: number }[] {
    const m = new Map<string, number>();
    for (const x of this.d.mejoras ?? []) m.set(x.moneda, (m.get(x.moneda) ?? 0) + Number(x.costo));
    return [...m.entries()].map(([moneda, total]) => ({ moneda, total }));
  }

  /** Diferencia entre el valor estimado y el de compra, solo si ambos están en la misma moneda. */
  variacion(): { monto: number; pct: number | null; moneda: string } | null {
    const v = this.d.valor;
    if (!v || v.precio_compra === null || v.valor_estimado === null) return null;
    if (v.moneda_compra !== v.moneda_estimado) return null;
    const monto = Number(v.valor_estimado) - Number(v.precio_compra);
    return { monto, pct: Number(v.precio_compra) > 0 ? (monto / Number(v.precio_compra)) * 100 : null, moneda: v.moneda_estimado ?? '' };
  }

  async guardarValor(): Promise<void> {
    const v = this.val;
    await this.hacer(() =>
      this.activos.guardarUnica('activo_valor', this.d.activo.id, this.d.activo.grupo_id, {
        precio_compra: v.compra === null || (v.compra as unknown) === '' ? null : Number(v.compra),
        moneda_compra: (v.monedaCompra || this.d.grupo.moneda).toUpperCase(),
        fecha_compra: v.fechaCompra || null,
        valor_estimado: v.estimado === null || (v.estimado as unknown) === '' ? null : Number(v.estimado),
        moneda_estimado: (v.monedaEst || this.d.grupo.moneda).toUpperCase(),
        fecha_estimado: v.fechaEst || null,
      }),
    );
  }

  async guardarMejora(f: FilaMejora): Promise<void> {
    if (f.descripcion.trim().length < 2) return;
    const a = this.d.activo;
    const ok = await this.hacer(() =>
      this.activos.guardarFila(
        'activo_mejoras',
        a.grupo_id,
        a.id,
        {
          fecha: f.fecha || new Date().toISOString().slice(0, 10),
          descripcion: f.descripcion.trim(),
          costo: Number(f.costo) || 0,
          moneda: (f.moneda || this.d.grupo.moneda).toUpperCase(),
          proveedor: f.proveedor.trim() || null,
        },
        f.id ?? undefined,
      ),
    );
    if (ok && !f.id) this.nueva = this.vacia();
  }

  async quitar(f: FilaMejora): Promise<void> {
    if (f.id) await this.hacer(() => this.activos.borrarFila('activo_mejoras', f.id as string));
  }
}
