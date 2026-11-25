import { Component, Input, signal } from '@angular/core';
import { Icono } from '../../ui/icono/icono';
import { ActivoService } from '../../../app/core/activo.service';
import { t } from '../../../app/core/i18n/i18n';

type Variante = 'hero' | 'normal' | 'mini';
type TipoIcono = 'bote' | 'carro' | 'otro';

/**
 * Tarjeta del activo: foto si la hay, o un ícono SVG según el tipo sobre un degradado.
 * `mini` es el avatar del encabezado; `normal` sirve para listas; `hero` abre la vitrina.
 */
@Component({
  selector: 'app-activo-tarjeta',
  standalone: true,
  imports: [Icono],
  templateUrl: './activo-tarjeta.html',
  styleUrl: './activo-tarjeta.scss',
})
export class ActivoTarjeta {
  t = t;
  @Input() nombre = '';
  @Input() tipoClave = '';
  @Input() tipoNombre = '';
  @Input() descripcion: string | null = null;
  @Input() imagenPath: string | null = null;
  @Input() capacidad: number | null = null;
  @Input() puntoEncuentro: string | null = null;
  @Input() variante: Variante = 'normal';

  private fallo = signal<string | null>(null);

  constructor(private activos: ActivoService) {}

  /** URL de la foto, salvo que haya fallado al cargar (entonces se muestra el ícono). */
  url(): string | null {
    const path = this.imagenPath;
    if (!path || this.fallo() === path) return null;
    return this.activos.urlImagen(path);
  }

  alFallar(): void {
    this.fallo.set(this.imagenPath);
  }

  /** Nombre del trazo en el conjunto de iconos de la app. */
  trazo(): string {
    const i = this.icono();
    return i === 'bote' ? 'activo' : i === 'carro' ? 'carro' : 'caja';
  }

  icono(): TipoIcono {
    const c = this.tipoClave.toLowerCase();
    if (c.includes('bote') || c.includes('lancha') || c.includes('yate') || c.includes('barco')) return 'bote';
    if (c.includes('carro') || c.includes('auto') || c.includes('vehic')) return 'carro';
    return 'otro';
  }
}
