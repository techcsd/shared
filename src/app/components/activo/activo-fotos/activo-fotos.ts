import { Component, HostListener, OnChanges, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Icono } from '../../../../shared/ui/icono/icono';
import { FotoActivo } from '../../../../shared/models/activo-entidad.model';
import { ActivoSeccion } from '../activo-seccion';

/** Galería: portada, varias fotos con descripción, orden y visor ampliado. */
@Component({
  selector: 'app-activo-fotos',
  standalone: true,
  imports: [FormsModule, Icono],
  templateUrl: './activo-fotos.html',
})
export class ActivoFotos extends ActivoSeccion implements OnChanges {
  visor = signal<number | null>(null);
  pies: Record<string, string> = {};
  subiendo = signal(false);

  ngOnChanges(): void {
    this.pies = {};
    for (const f of this.d.fotos) this.pies[f.id] = f.descripcion ?? '';
  }

  url(f: FotoActivo): string {
    return this.activos.urlImagen(f.ruta) ?? '';
  }

  fotoVisor(): FotoActivo | null {
    const i = this.visor();
    return i === null ? null : (this.d.fotos[i] ?? null);
  }

  abrir(i: number): void {
    this.visor.set(i);
  }

  @HostListener('document:keydown', ['$event'])
  teclas(ev: KeyboardEvent): void {
    const i = this.visor();
    if (i === null) return;
    if (ev.key === 'Escape') this.visor.set(null);
    if (ev.key === 'ArrowRight') this.visor.set((i + 1) % this.d.fotos.length);
    if (ev.key === 'ArrowLeft') this.visor.set((i - 1 + this.d.fotos.length) % this.d.fotos.length);
  }

  /** Sube varias fotos seguidas; cada una se reduce en el navegador antes de enviarse. */
  async elegir(ev: Event): Promise<void> {
    const input = ev.target as HTMLInputElement;
    const archivos = Array.from(input.files ?? []);
    input.value = '';
    if (!archivos.length) return;
    this.subiendo.set(true);
    let orden = this.d.fotos.length;
    let alguna = false;
    for (const a of archivos) {
      const r = await this.activos.subirFoto(this.d.activo.grupo_id, this.d.activo.id, a, orden);
      if (r.error) {
        this.toast.error(this.errorTexto(r.error));
        break;
      }
      alguna = true;
      orden++;
    }
    this.subiendo.set(false);
    if (alguna) {
      this.toast.ok(this.t('app.guardado'));
      this.cambio.emit();
    }
  }

  async guardarPie(f: FotoActivo): Promise<void> {
    const nuevo = (this.pies[f.id] ?? '').trim();
    if (nuevo === (f.descripcion ?? '')) return;
    await this.hacer(() => this.activos.guardarFila('activo_fotos', this.d.activo.grupo_id, this.d.activo.id, { descripcion: nuevo || null }, f.id));
  }

  async portada(f: FotoActivo): Promise<void> {
    await this.hacer(() => this.activos.portada(f.id));
  }

  async quitar(f: FotoActivo): Promise<void> {
    await this.hacer(() => this.activos.borrarFoto(f));
  }

  async mover(i: number, delta: number): Promise<void> {
    const ids = this.d.fotos.map((f) => f.id);
    const j = i + delta;
    if (j < 0 || j >= ids.length) return;
    [ids[i], ids[j]] = [ids[j], ids[i]];
    await this.hacer(() => this.activos.reordenar('activo_fotos', ids), false);
  }
}
