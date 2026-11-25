import { Component, OnDestroy, OnInit, signal } from '@angular/core';
import { Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { ActivoTarjeta } from '../../../shared/components/activo-tarjeta/activo-tarjeta';
import { ActivoResumen } from '../../../shared/models/activo.model';
import { ActivoService } from '../../core/activo.service';
import { AuthService } from '../../core/auth.service';
import { GrupoService } from '../../core/grupo.service';
import { t } from '../../core/i18n/i18n';
import { NotificacionService } from '../../core/notificacion.service';

/** Cascarón de la app: encabezado con grupo y campana, banner demo y menú inferior (SA17). */
@Component({
  selector: 'app-shell',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive, ActivoTarjeta],
  templateUrl: './shell.html',
  styleUrl: './shell.scss',
})
export class Shell implements OnInit, OnDestroy {
  t = t;
  /** Activo del grupo actual (foto o ícono en el encabezado). */
  activo = signal<ActivoResumen | null>(null);
  constructor(
    private activos: ActivoService,
    public grupos: GrupoService,
    public notif: NotificacionService,
    public auth: AuthService,
    private router: Router,
  ) {}

  ngOnInit(): void {
    this.notif.iniciar();
    const g = this.grupos.grupo()?.id;
    if (g) void this.activos.resumenes([g]).then((r) => this.activo.set(r[g] ?? null));
  }

  ngOnDestroy(): void {
    this.notif.detener();
  }
}
