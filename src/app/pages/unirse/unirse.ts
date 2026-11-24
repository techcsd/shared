import { Component, OnInit, signal, Input } from '@angular/core';
import { Router } from '@angular/router';
import { GrupoService } from '../../core/grupo.service';
import { t } from '../../core/i18n/i18n';
import { rolTexto } from '../../core/i18n/textos';
import { VistaPreviaInvitacion } from '../../../shared/models/grupo.model';

/** Aceptación de invitación por enlace: /unirse/:token (requiere sesión con el correo invitado). */
@Component({
  selector: 'app-unirse',
  standalone: true,
  templateUrl: './unirse.html',
  styleUrl: './unirse.scss',
})
export class UnirsePage implements OnInit {
  t = t;
  rolTexto = rolTexto;
  @Input() token = ''; // viene de la ruta (withComponentInputBinding)
  cargando = signal(true);
  vista = signal<VistaPreviaInvitacion | null>(null);
  error = signal<string | null>(null);
  ocupado = signal(false);

  constructor(
    private grupos: GrupoService,
    private router: Router,
  ) {}

  async ngOnInit(): Promise<void> {
    const vista = await this.grupos.previsualizar(this.token);
    this.cargando.set(false);
    if (!vista) this.error.set(t('unirse.invalida'));
    else if (vista.estado === 'expirada') this.error.set(t('unirse.expirada'));
    else if (vista.estado !== 'pendiente') this.error.set(t('unirse.usada'));
    else this.vista.set(vista);
  }

  async aceptar(): Promise<void> {
    this.ocupado.set(true);
    const r = await this.grupos.aceptar(this.token);
    this.ocupado.set(false);
    if (r.error === 'invitacion_expirada') this.error.set(t('unirse.expirada'));
    else if (r.error) this.error.set(t('unirse.invalida'));
    else await this.router.navigateByUrl('/');
  }
}
