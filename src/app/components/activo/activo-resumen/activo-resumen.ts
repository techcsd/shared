import { Component, Input, OnChanges } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { ActivoTarjeta } from '../../../../shared/components/activo-tarjeta/activo-tarjeta';
import { Icono } from '../../../../shared/ui/icono/icono';
import { Vitrina } from '../../../../shared/models/activo.model';
import { CONDICIONES_ACTIVO } from '../../../../shared/models/activo-entidad.model';
import { ActivoSeccion } from '../activo-seccion';

/** Resumen: foto de portada, descripción, condición, ubicación, reglas, tarifas y quién puede editar. */
@Component({
  selector: 'app-activo-resumen',
  standalone: true,
  imports: [FormsModule, RouterLink, ActivoTarjeta, Icono],
  templateUrl: './activo-resumen.html',
})
export class ActivoResumen extends ActivoSeccion implements OnChanges {
  @Input() vit: Vitrina | null = null;
  condiciones = CONDICIONES_ACTIVO;

  edit = { descripcion: '', punto: '', reglas: '', condicion: '', notas: '', ubicacion: '', url: '' };

  ngOnChanges(): void {
    const a = this.d.activo;
    const f = this.d.ficha;
    this.edit = {
      descripcion: a.descripcion ?? '',
      punto: a.punto_encuentro ?? '',
      reglas: a.reglas_invitados ?? '',
      condicion: f?.condicion ?? '',
      notas: f?.condicion_notas ?? '',
      ubicacion: f?.ubicacion_texto ?? '',
      url: f?.ubicacion_url ?? '',
    };
  }

  polizaVigente(): boolean {
    return this.vit?.activos.find((x) => x.id === this.d.activo.id)?.poliza_vigente ?? false;
  }

  async guardar(): Promise<void> {
    const e = this.edit;
    const a = this.d.activo;
    const ok = await this.hacer(() =>
      this.activos.guardarActivo(a.id, {
        descripcion: e.descripcion.trim() || null,
        punto_encuentro: e.punto.trim() || null,
        reglas_invitados: e.reglas.trim() || null,
      }),
      false,
    );
    if (!ok) return;
    await this.hacer(() =>
      this.activos.guardarUnica('activo_ficha', a.id, a.grupo_id, {
        condicion: e.condicion || null,
        condicion_notas: e.notas.trim() || null,
        ubicacion_texto: e.ubicacion.trim() || null,
        ubicacion_url: e.url.trim() || null,
      }),
    );
  }

  async permiso(miembro: string, permitir: boolean): Promise<void> {
    await this.hacer(() => this.activos.permisoEditar(this.d.activo.grupo_id, miembro, permitir));
  }
}
