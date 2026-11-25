import { Component, computed, input } from '@angular/core';

/** Círculo como trazo SVG (cx, cy, r). */
const c = (cx: number, cy: number, r: number): string =>
  `M${cx - r} ${cy}a${r} ${r} 0 1 0 ${2 * r} 0a${r} ${r} 0 1 0 ${-2 * r} 0`;

/** Trazos de cada icono (cuadrícula 24, línea de 1,8): mismo estilo que el menú inferior. */
const TRAZOS: Record<string, string[]> = {
  campana: ['M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9', 'M10.3 21a1.9 1.9 0 0 0 3.4 0'],
  alerta: ['M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z', 'M12 9v4', 'M12 17h.01'],
  timon: [c(12, 12, 2.5), c(12, 12, 8), 'M12 4v5.5M12 14.5V20M4 12h5.5M14.5 12H20'],
  cartera: [
    'M19 7V4a1 1 0 0 0-1-1H5a2 2 0 0 0 0 4h15a1 1 0 0 1 1 1v4h-3a2 2 0 0 0 0 4h3a1 1 0 0 0 1-1v-2a1 1 0 0 0-1-1',
    'M3 5v14a2 2 0 0 0 2 2h15a1 1 0 0 0 1-1v-4',
  ],
  ajustes: ['M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1', c(15, 6, 2), c(9, 12, 2), c(17, 18, 2)],
  documento: ['M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z', 'M14 3v5h5', 'M9 13h6M9 17h6'],
  grafica: ['M4 20V10M10 20V4M16 20v-7M22 20H2'],
  balanza: ['M12 3v18M7 21h10M5 7h14', 'M5 7l-3 7a3.2 3.2 0 0 0 6 0z', 'M19 7l-3 7a3.2 3.2 0 0 0 6 0z'],
  intercambio: ['M7 4 3 8l4 4M3 8h14', 'M17 20l4-4-4-4M21 16H7'],
  escudo: ['M12 3 4 6v6c0 4.5 3.2 8 8 9 4.8-1 8-4.5 8-9V6z', 'M9 12l2 2 4-4'],
  ancla: [c(12, 5, 2.2), 'M12 7.2V21M8 11h8M4 14c0 4 3.6 7 8 7s8-3 8-7M4 14l-1.5 1.5M20 14l1.5 1.5'],
  bolsa: ['M6 7h12l1 13H5z', 'M9 7a3 3 0 0 1 6 0'],
  cohete: ['M12 2c3 2 5 5 5 9l-2 4H9l-2-4c0-4 2-7 5-9z', 'M9 15l-2 4 3-1M15 15l2 4-3-1', c(12, 9, 1.6)],
  usuarios: [
    'M16 20v-1.5a3.5 3.5 0 0 0-3.5-3.5h-5A3.5 3.5 0 0 0 4 18.5V20',
    c(10, 8, 3.5),
    'M20 20v-1.5a3.5 3.5 0 0 0-2.5-3.3M15.5 4.7a3.5 3.5 0 0 1 0 6.6',
  ],
  usuario: [c(12, 8, 4), 'M4 21a8 8 0 0 1 16 0'],
  cambiar: ['M4 7h13l-3-3M20 17H7l3 3'],
  pulso: ['M3 12h4l3-8 4 16 3-8h4'],
  panel: ['M3 3h8v8H3zM13 3h8v5h-8zM13 12h8v9h-8zM3 15h8v6H3z'],
  activo: [
    'M2 18c1.5 1.5 3 1.5 4.5 0s3-1.5 4.5 0 3 1.5 4.5 0 3-1.5 4.5 0',
    'M12 3v11M12 4l6 9h-6M10 7l-5 6h5',
  ],
  salir: ['M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4', 'M16 17l5-5-5-5M21 12H9'],
  buscar: [c(11, 11, 7), 'M21 21l-4.3-4.3'],
  chevron: ['m9 6 6 6-6 6'],
  cerrar: ['M6 6l12 12M18 6 6 18'],
  calendario: ['M5 5h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z', 'M3 10h18M8 3v4M16 3v4'],
  llave: ['M14.7 6.3a4 4 0 0 0-5.4 5.4L3 18l3 3 6.3-6.3a4 4 0 0 0 5.4-5.4l-2.6 2.6-2.4-.6-.6-2.4z'],
  check: ['M5 12.5l4.5 4.5L19 7.5'],
  info: [c(12, 12, 9), 'M12 11v5M12 8h.01'],
  mas: ['M12 5v14M5 12h14'],
  carro: ['M5 16V12l2-5h10l2 5v4', 'M3 16h18v3H3z', 'M5 12h14', c(7.5, 19, 1.4), c(16.5, 19, 1.4)],
  caja: ['M12 3l8 4.5v9L12 21l-8-4.5v-9z', 'M4 7.5l8 4.5 8-4.5M12 12v9'],
};

/** Icono SVG en línea. Hereda el color (`currentColor`) y el tamaño (`font-size`) del contenedor. */
@Component({
  selector: 'app-icono',
  standalone: true,
  templateUrl: './icono.html',
  styleUrl: './icono.scss',
})
export class Icono {
  nombre = input.required<string>();
  trazos = computed(() => TRAZOS[this.nombre()] ?? TRAZOS['info']);
}
