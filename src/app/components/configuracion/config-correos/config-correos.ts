import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ConfiguracionService } from '../../../core/configuracion.service';
import { GrupoService } from '../../../core/grupo.service';
import { t } from '../../../core/i18n/i18n';
import { CorreoModel } from '../../../../shared/models/config.model';

/** Correos de notificación del grupo (SA17-Configuración). */
@Component({
  selector: 'app-config-correos',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './config-correos.html',
  styleUrl: './config-correos.scss',
})
export class ConfigCorreos implements OnInit {
  t = t;
  correos = signal<CorreoModel[]>([]);
  correo = '';
  tipo: CorreoModel['tipo'] = 'ordenes';
  error = signal<string | null>(null);

  constructor(
    private grupos: GrupoService,
    private config: ConfiguracionService,
  ) {}

  async ngOnInit(): Promise<void> {
    await this.recargar();
  }

  private async recargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (g) this.correos.set(await this.config.correos(g));
  }

  tipoTexto(tipo: CorreoModel['tipo']): string {
    switch (tipo) {
      case 'ordenes':
        return t('config.correo.ordenes');
      case 'alertas':
        return t('config.correo.alertas');
      case 'invitados':
        return t('config.correo.invitados');
    }
  }

  async agregar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    this.error.set(null);
    const r = await this.config.agregarCorreo(g, this.correo, this.tipo);
    if (r.error) this.error.set(r.error);
    else this.correo = '';
    await this.recargar();
  }

  async quitar(c: CorreoModel): Promise<void> {
    const r = await this.config.quitarCorreo(c.id);
    if (r.error) this.error.set(r.error);
    await this.recargar();
  }
}
