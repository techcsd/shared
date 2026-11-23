import { Component } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { GrupoService } from '../../core/grupo.service';
import { t } from '../../core/i18n/i18n';

/** Cascarón de la app: encabezado con grupo, banner demo y menú inferior (SA17). */
@Component({
  selector: 'app-shell',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  templateUrl: './shell.html',
  styleUrl: './shell.scss',
})
export class Shell {
  t = t;
  constructor(public grupos: GrupoService) {}
}
