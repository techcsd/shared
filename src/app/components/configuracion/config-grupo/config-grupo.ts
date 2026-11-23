import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ConfiguracionService } from '../../../core/configuracion.service';
import { GrupoService } from '../../../core/grupo.service';
import { t } from '../../../core/i18n/i18n';
import { PoliticaService } from '../../../core/politica.service';

/** Datos del grupo y modelo de tarifa (SA20). El modelo de tarifa es una política: cambiarlo pasa por el estatuto. */
@Component({
  selector: 'app-config-grupo',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './config-grupo.html',
  styleUrl: './config-grupo.scss',
})
export class ConfigGrupo implements OnInit {
  t = t;
  nombre = '';
  zona = '';
  prefijo = '';
  modeloActual = signal<string>('destino');
  modeloNuevo = 'destino';
  mensaje = signal<string | null>(null);
  error = signal<string | null>(null);

  constructor(
    public grupos: GrupoService,
    private config: ConfiguracionService,
    private politica: PoliticaService,
  ) {}

  async ngOnInit(): Promise<void> {
    const g = this.grupos.grupo();
    if (!g) return;
    this.nombre = g.nombre;
    this.zona = g.zona_horaria;
    this.prefijo = g.prefijo;
    const v = (await this.politica.valor(g.id, 'tarifa.modelo')) as string | null;
    this.modeloActual.set(v ?? 'destino');
    this.modeloNuevo = this.modeloActual();
  }

  async guardar(): Promise<void> {
    const g = this.grupos.grupo();
    if (!g) return;
    this.mensaje.set(null);
    this.error.set(null);
    const r = await this.config.actualizarGrupo(g.id, this.nombre, this.zona, this.prefijo);
    if (r.error) this.error.set(r.error);
    else {
      await this.grupos.cargar();
      this.mensaje.set(t('app.guardado'));
    }
  }

  async proponerModelo(): Promise<void> {
    const g = this.grupos.grupo();
    if (!g || this.modeloNuevo === this.modeloActual()) return;
    this.mensaje.set(null);
    this.error.set(null);
    const err = await this.politica.proponer(g.id, { 'tarifa.modelo': this.modeloNuevo }, '');
    if (err) this.error.set(err);
    else {
      this.mensaje.set(t('estatuto.propuesta_creada'));
      const v = (await this.politica.valor(g.id, 'tarifa.modelo')) as string | null;
      this.modeloActual.set(v ?? 'destino');
    }
  }
}
