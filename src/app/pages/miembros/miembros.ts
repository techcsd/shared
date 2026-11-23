import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { GrupoService } from '../../core/grupo.service';
import { t } from '../../core/i18n/i18n';
import { estadoInvitacionTexto, rolTexto } from '../../core/i18n/textos';
import { InvitacionModel, MiembroModel, RolMiembro } from '../../../shared/models/grupo.model';

/** Miembros del grupo e invitaciones (solo los socios invitan; la base lo exige también). */
@Component({
  selector: 'app-miembros',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './miembros.html',
  styleUrl: './miembros.scss',
})
export class MiembrosPage implements OnInit {
  t = t;
  rolTexto = rolTexto;
  estadoInvitacionTexto = estadoInvitacionTexto;
  roles: RolMiembro[] = ['socio', 'admin_operativo', 'capitan', 'mediador'];

  miembros = signal<MiembroModel[]>([]);
  invitaciones = signal<InvitacionModel[]>([]);
  enlace = signal<string | null>(null);
  copiado = signal(false);
  error = signal<string | null>(null);
  ocupado = signal(false);

  correo = '';
  rol: RolMiembro = 'socio';
  porcentaje = 50;

  constructor(public grupos: GrupoService) {}

  async ngOnInit(): Promise<void> {
    await this.recargar();
  }

  private async recargar(): Promise<void> {
    const id = this.grupos.grupo()?.id;
    if (!id) return;
    this.miembros.set(await this.grupos.miembros(id));
    if (this.grupos.esSocio()) this.invitaciones.set(await this.grupos.invitaciones(id));
  }

  async invitar(): Promise<void> {
    const id = this.grupos.grupo()?.id;
    if (!id) return;
    this.ocupado.set(true);
    this.error.set(null);
    this.enlace.set(null);
    this.copiado.set(false);
    const r = await this.grupos.invitar(
      id,
      this.correo,
      this.rol,
      this.rol === 'socio' ? Number(this.porcentaje) : 0,
    );
    this.ocupado.set(false);
    if (r.error || !r.token) {
      this.error.set(r.error ?? t('app.error.generico'));
      return;
    }
    this.enlace.set(`${location.origin}/unirse/${r.token}`);
    this.correo = '';
    await this.recargar();
  }

  async cancelar(id: string): Promise<void> {
    const err = await this.grupos.cancelarInvitacion(id);
    if (err) this.error.set(err);
    await this.recargar();
  }

  async copiar(): Promise<void> {
    const e = this.enlace();
    if (!e) return;
    try {
      await navigator.clipboard.writeText(e);
      this.copiado.set(true);
    } catch {
      this.copiado.set(false);
    }
  }
}
