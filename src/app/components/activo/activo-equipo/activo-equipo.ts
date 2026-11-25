import { Component, OnChanges } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Icono } from '../../../../shared/ui/icono/icono';
import { CONDICIONES_EQUIPO, CondicionEquipo, EquipoActivo } from '../../../../shared/models/activo-entidad.model';
import { ActivoSeccion } from '../activo-seccion';

interface FilaEquipo {
  id: string | null;
  nombre: string;
  cantidad: number;
  condicion: CondicionEquipo;
  notas: string;
  original: string;
}

/** Equipamiento y accesorios: lista editable con cantidad, condición y notas. */
@Component({
  selector: 'app-activo-equipo',
  standalone: true,
  imports: [FormsModule, Icono],
  templateUrl: './activo-equipo.html',
})
export class ActivoEquipoSeccion extends ActivoSeccion implements OnChanges {
  condiciones = CONDICIONES_EQUIPO;
  filas: FilaEquipo[] = [];
  nueva: FilaEquipo = this.vacia();

  ngOnChanges(): void {
    this.filas = this.d.equipo.map((e) => this.aFila(e));
    this.nueva = this.vacia();
  }

  private vacia(): FilaEquipo {
    return { id: null, nombre: '', cantidad: 1, condicion: 'bueno', notas: '', original: '' };
  }

  private aFila(e: EquipoActivo): FilaEquipo {
    const f: FilaEquipo = { id: e.id, nombre: e.nombre, cantidad: e.cantidad, condicion: e.condicion, notas: e.notas ?? '', original: '' };
    f.original = this.firma(f);
    return f;
  }

  private firma(f: FilaEquipo): string {
    return JSON.stringify([f.nombre, f.cantidad, f.condicion, f.notas]);
  }

  sucia(f: FilaEquipo): boolean {
    return this.firma(f) !== f.original;
  }

  /** Resumen para la vista de solo lectura: cuántos artículos y cuántos necesitan atención. */
  atencion(): number {
    return this.d.equipo.filter((e) => e.condicion === 'reparar' || e.condicion === 'faltante').length;
  }

  async guardar(f: FilaEquipo): Promise<void> {
    if (!f.nombre.trim()) return;
    const a = this.d.activo;
    const ok = await this.hacer(() =>
      this.activos.guardarFila(
        'activo_equipo',
        a.grupo_id,
        a.id,
        { nombre: f.nombre.trim(), cantidad: Number(f.cantidad) || 0, condicion: f.condicion, notas: f.notas.trim() || null },
        f.id ?? undefined,
      ),
    );
    if (ok && !f.id) this.nueva = this.vacia();
  }

  async quitar(f: FilaEquipo): Promise<void> {
    if (f.id) await this.hacer(() => this.activos.borrarFila('activo_equipo', f.id as string));
  }

  async mover(i: number, delta: number): Promise<void> {
    const ids = this.filas.map((f) => f.id as string);
    const j = i + delta;
    if (j < 0 || j >= ids.length) return;
    [ids[i], ids[j]] = [ids[j], ids[i]];
    await this.hacer(() => this.activos.reordenar('activo_equipo', ids), false);
  }
}
