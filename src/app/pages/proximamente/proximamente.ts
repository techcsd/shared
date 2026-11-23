import { Component, Input } from '@angular/core';
import { ClaveI18n } from '../../core/i18n/es';
import { t } from '../../core/i18n/i18n';

/** Pantalla «próximamente» reutilizable: el título viene de `data.titulo` de la ruta (clave i18n). */
@Component({
  selector: 'app-proximamente',
  standalone: true,
  templateUrl: './proximamente.html',
  styleUrl: './proximamente.scss',
})
export class ProximamentePage {
  t = t;
  @Input() titulo: ClaveI18n = 'app.proximamente';
}
