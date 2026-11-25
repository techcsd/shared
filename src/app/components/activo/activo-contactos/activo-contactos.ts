import { Component, OnChanges } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Icono } from '../../../../shared/ui/icono/icono';
import { CATEGORIAS_CONTACTO, CategoriaContacto, ContactoActivo } from '../../../../shared/models/activo-entidad.model';
import { ActivoSeccion } from '../activo-seccion';

interface FilaContacto {
  id: string | null;
  categoria: CategoriaContacto;
  nombre: string;
  telefono: string;
  correo: string;
  notas: string;
  original: string;
}

/** Contactos y proveedores: marina, mecánico, aseguradora, emergencias… con llamada, WhatsApp y correo en un toque. */
@Component({
  selector: 'app-activo-contactos',
  standalone: true,
  imports: [FormsModule, Icono],
  templateUrl: './activo-contactos.html',
})
export class ActivoContactosSeccion extends ActivoSeccion implements OnChanges {
  categorias = CATEGORIAS_CONTACTO;
  filas: FilaContacto[] = [];
  nueva: FilaContacto = this.vacia();

  ngOnChanges(): void {
    this.filas = this.d.contactos.map((c) => this.aFila(c));
    this.nueva = this.vacia();
  }

  private vacia(): FilaContacto {
    return { id: null, categoria: 'marina', nombre: '', telefono: '', correo: '', notas: '', original: '' };
  }

  private aFila(c: ContactoActivo): FilaContacto {
    const f: FilaContacto = {
      id: c.id,
      categoria: c.categoria,
      nombre: c.nombre,
      telefono: c.telefono ?? '',
      correo: c.correo ?? '',
      notas: c.notas ?? '',
      original: '',
    };
    f.original = this.firma(f);
    return f;
  }

  private firma(f: FilaContacto): string {
    return JSON.stringify([f.categoria, f.nombre, f.telefono, f.correo, f.notas]);
  }

  sucia(f: FilaContacto): boolean {
    return this.firma(f) !== f.original;
  }

  tel(c: ContactoActivo): string {
    return `tel:${(c.telefono ?? '').replace(/[^\d+]/g, '')}`;
  }

  /** WhatsApp pide el número solo con dígitos (con código de país). */
  wa(c: ContactoActivo): string {
    return `https://wa.me/${(c.telefono ?? '').replace(/\D/g, '')}`;
  }

  icono(cat: CategoriaContacto): string {
    return cat === 'emergencia' ? 'alerta' : cat === 'aseguradora' ? 'escudo' : cat === 'mecanico' ? 'llave' : cat === 'marina' ? 'ancla' : 'usuario';
  }

  async guardar(f: FilaContacto): Promise<void> {
    if (f.nombre.trim().length < 2) return;
    const a = this.d.activo;
    const ok = await this.hacer(() =>
      this.activos.guardarFila(
        'activo_contactos',
        a.grupo_id,
        a.id,
        {
          categoria: f.categoria,
          nombre: f.nombre.trim(),
          telefono: f.telefono.trim() || null,
          correo: f.correo.trim() || null,
          notas: f.notas.trim() || null,
        },
        f.id ?? undefined,
      ),
    );
    if (ok && !f.id) this.nueva = this.vacia();
  }

  async quitar(f: FilaContacto): Promise<void> {
    if (f.id) await this.hacer(() => this.activos.borrarFila('activo_contactos', f.id as string));
  }

  async mover(i: number, delta: number): Promise<void> {
    const ids = this.filas.map((f) => f.id as string);
    const j = i + delta;
    if (j < 0 || j >= ids.length) return;
    [ids[i], ids[j]] = [ids[j], ids[i]];
    await this.hacer(() => this.activos.reordenar('activo_contactos', ids), false);
  }
}
