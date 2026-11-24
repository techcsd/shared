import { Component, OnDestroy, OnInit } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { GrupoService } from '../../core/grupo.service';
import { t } from '../../core/i18n/i18n';
import { NotificacionService } from '../../core/notificacion.service';

/** Cascarón de la app: encabezado con grupo y campana, banner demo y menú inferior (SA17). */
@Component({
  selector: 'app-shell',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  templateUrl: './shell.html',
  styleUrl: './shell.scss',
})
export class Shell implements OnInit, OnDestroy {
  t = t;
  constructor(
    public grupos: GrupoService,
    public notif: NotificacionService,
  ) {}

  ngOnInit(): void {
    this.notif.iniciar();
  }

  ngOnDestroy(): void {
    this.notif.detener();
  }
}
