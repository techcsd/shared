import { Component, OnChanges } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Icono } from '../../../../shared/ui/icono/icono';
import { CampoDef } from '../../../../shared/models/config.model';
import { CampoPropio, TIPOS_CAMPO_PROPIO, TipoCampoPropio } from '../../../../shared/models/activo-entidad.model';
import { ActivoSeccion } from '../activo-seccion';

interface FilaCampo {
  id: string | null;
  etiqueta: string;
  tipo: TipoCampoPropio;
  unidad: string;
  opciones: string;
  valor: string | number | boolean | null;
  original: string;
}

/** Ficha técnica: campos que sugiere el tipo de activo + campos propios del grupo (agregar, renombrar, ordenar, quitar). */
@Component({
  selector: 'app-activo-ficha',
  standalone: true,
  imports: [FormsModule, Icono],
  templateUrl: './activo-ficha.html',
})
export class ActivoFicha extends ActivoSeccion implements OnChanges {
  tipos = TIPOS_CAMPO_PROPIO;
  valoresTipo: Record<string, string | number | boolean | null> = {};
  filas: FilaCampo[] = [];
  nueva: FilaCampo = this.vacia();

  ngOnChanges(): void {
    const v = this.d.activo.valores ?? {};
    this.valoresTipo = {};
    for (const c of this.camposTipo()) this.valoresTipo[c.clave] = (v[c.clave] as string | number | boolean | null) ?? null;
    this.filas = this.d.campos.map((c) => this.aFila(c));
    this.nueva = this.vacia();
  }

  camposTipo(): CampoDef[] {
    return this.d.activo.tipo.definicion.campos ?? [];
  }

  /** Valor para mostrar de un campo del tipo. */
  textoTipo(c: CampoDef): string {
    const v = this.d.activo.valores?.[c.clave];
    if (v === undefined || v === null || v === '') return '—';
    const txt = typeof v === 'boolean' ? (v ? this.t('activo.si') : this.t('activo.no')) : String(v);
    return c.unidad ? `${txt} ${c.unidad}` : txt;
  }

  textoPropio(c: CampoPropio): string {
    const v = c.valor;
    if (v === null || v === undefined || v === '') return '—';
    if (typeof v === 'boolean') return v ? this.t('activo.si') : this.t('activo.no');
    if (c.tipo === 'fecha') return this.fecha(String(v));
    return c.unidad ? `${v} ${c.unidad}` : String(v);
  }

  hayAlgo(): boolean {
    return this.camposTipo().length > 0 || this.d.campos.length > 0;
  }

  private vacia(): FilaCampo {
    return { id: null, etiqueta: '', tipo: 'texto', unidad: '', opciones: '', valor: null, original: '' };
  }

  private aFila(c: CampoPropio): FilaCampo {
    const f: FilaCampo = {
      id: c.id,
      etiqueta: c.etiqueta,
      tipo: c.tipo,
      unidad: c.unidad ?? '',
      opciones: (c.opciones ?? []).join(', '),
      valor: c.valor,
      original: '',
    };
    f.original = JSON.stringify([f.etiqueta, f.tipo, f.unidad, f.opciones, f.valor]);
    return f;
  }

  sucia(f: FilaCampo): boolean {
    return JSON.stringify([f.etiqueta, f.tipo, f.unidad, f.opciones, f.valor]) !== f.original;
  }

  /** Cambiar el tipo invalida el valor anterior. */
  alCambiarTipo(f: FilaCampo): void {
    f.valor = f.tipo === 'si_no' ? false : null;
  }

  private cuerpo(f: FilaCampo): Record<string, unknown> {
    let valor: string | number | boolean | null = f.valor;
    if (f.tipo === 'numero') valor = f.valor === null || f.valor === '' ? null : Number(f.valor);
    else if (f.tipo === 'texto' || f.tipo === 'fecha' || f.tipo === 'seleccion') valor = f.valor === '' ? null : f.valor;
    return {
      etiqueta: f.etiqueta.trim(),
      tipo: f.tipo,
      unidad: f.unidad.trim() || null,
      opciones: f.tipo === 'seleccion' ? f.opciones.split(',').map((x) => x.trim()).filter(Boolean) : null,
      valor,
    };
  }

  async guardarTipo(): Promise<void> {
    const limpio: Record<string, unknown> = { ...(this.d.activo.valores ?? {}) };
    for (const c of this.camposTipo()) {
      const v = this.valoresTipo[c.clave];
      if (v === null || v === undefined || v === '') delete limpio[c.clave];
      else limpio[c.clave] = c.tipo === 'numero' ? Number(v) : v;
    }
    await this.hacer(() => this.activos.guardarActivo(this.d.activo.id, { valores: limpio }));
  }

  async guardarFila(f: FilaCampo): Promise<void> {
    if (!f.etiqueta.trim()) return;
    const a = this.d.activo;
    const ok = await this.hacer(() => this.activos.guardarFila('activo_campos', a.grupo_id, a.id, this.cuerpo(f), f.id ?? undefined));
    if (ok && !f.id) this.nueva = this.vacia();
  }

  async quitar(f: FilaCampo): Promise<void> {
    if (!f.id) return;
    await this.hacer(() => this.activos.borrarFila('activo_campos', f.id as string));
  }

  async mover(i: number, delta: number): Promise<void> {
    const ids = this.filas.map((f) => f.id as string);
    const j = i + delta;
    if (j < 0 || j >= ids.length) return;
    [ids[i], ids[j]] = [ids[j], ids[i]];
    await this.hacer(() => this.activos.reordenar('activo_campos', ids), false);
  }
}
