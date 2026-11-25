import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { ActivoTarjeta } from '../../../../shared/components/activo-tarjeta/activo-tarjeta';
import { VistaActivoPublica } from '../../../../shared/models/activo.model';
import { ActivoService } from '../../../core/activo.service';
import { interpretarEnlace } from '../../../core/enlaces';
import { FormacionService } from '../../../core/formacion.service';
import { GrupoService, InvitacionPendiente } from '../../../core/grupo.service';
import { t } from '../../../core/i18n/i18n';
import { rolTexto } from '../../../core/i18n/textos';

/** «Tengo una invitación»: pegar un enlace/código y aceptar las invitaciones pendientes a mi correo. */
@Component({
  selector: 'app-acceso-invitacion',
  standalone: true,
  imports: [FormsModule, ActivoTarjeta],
  templateUrl: './acceso-invitacion.html',
  styleUrl: './acceso-invitacion.scss',
})
export class AccesoInvitacion implements OnInit {
  t = t;
  rolTexto = rolTexto;
  texto = '';
  pendientes = signal<InvitacionPendiente[]>([]);
  vistas = signal<Record<string, VistaActivoPublica | null>>({});
  ocupado = signal(false);
  error = signal<string | null>(null);

  constructor(
    private grupos: GrupoService,
    private formacion: FormacionService,
    private router: Router,
    private activos: ActivoService,
  ) {}

  async ngOnInit(): Promise<void> {
    try {
      const lista = await this.grupos.invitacionesPendientes();
      this.pendientes.set(lista);
      const vistas: Record<string, VistaActivoPublica | null> = {};
      await Promise.all(lista.map(async (i) => (vistas[i.invitacion_id] = await this.activos.vistaPorInvitacion(i.invitacion_id))));
      this.vistas.set(vistas);
    } catch {
      this.pendientes.set([]);
    }
  }

  async abrir(): Promise<void> {
    this.error.set(null);
    const e = interpretarEnlace(this.texto);
    if (!e) {
      this.error.set(t('bienvenida.enlace_invalido'));
      return;
    }
    this.ocupado.set(true);
    // Se comprueba que exista (y sea para mi correo) antes de navegar, para dar un error claro aquí mismo.
    if (e.tipo !== 'propuesta' && (await this.grupos.previsualizar(e.token))) {
      this.ocupado.set(false);
      await this.router.navigateByUrl(`/unirse/${e.token}`);
      return;
    }
    if (e.tipo !== 'invitacion' && (await this.formacion.vistaPrevia(e.token))) {
      this.ocupado.set(false);
      await this.router.navigateByUrl(`/propuesta/${e.token}`);
      return;
    }
    this.ocupado.set(false);
    this.error.set(t('bienvenida.enlace_no_existe'));
  }

  async aceptar(i: InvitacionPendiente): Promise<void> {
    this.ocupado.set(true);
    this.error.set(null);
    const r = await this.grupos.aceptarPorId(i.invitacion_id);
    this.ocupado.set(false);
    if (r.error) {
      this.error.set(r.error === 'invitacion_expirada' ? t('unirse.expirada') : t('unirse.invalida'));
      this.pendientes.set(await this.grupos.invitacionesPendientes());
    } else await this.router.navigateByUrl('/');
  }
}
