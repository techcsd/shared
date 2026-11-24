import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { MiembroModel } from '../../../shared/models/grupo.model';
import { CapitanModel } from '../../../shared/models/p4.model';
import { GobiernoService } from '../../core/gobierno.service';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { t } from '../../core/i18n/i18n';
import { claveError } from '../../core/reserva.service';

/** Capitanes y licencias (SA28, DF-20): sin capitán con licencia vigente no hay check-in. */
@Component({
  selector: 'app-capitanes',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './capitanes.html',
  styleUrl: '../p4-comun.scss',
})
export class CapitanesPage implements OnInit {
  t = t;
  lista = signal<CapitanModel[]>([]);
  miembros = signal<MiembroModel[]>([]);
  error = signal<string | null>(null);
  hoy = new Date().toISOString().slice(0, 10);

  nombre = '';
  miembro = '';
  licencia = '';
  vence = '';
  anios: number | null = null;
  notas = '';

  constructor(
    public grupos: GrupoService,
    private gob: GobiernoService,
  ) {}

  async ngOnInit(): Promise<void> {
    await this.cargar();
  }

  async cargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    this.lista.set(await this.gob.capitanes(g));
    this.miembros.set(await this.grupos.miembros(g));
  }

  estado(c: CapitanModel): 'vencida' | 'pronto' | 'ok' | 'sin' {
    if (!c.licencia_vence) return 'sin';
    if (c.licencia_vence < this.hoy) return 'vencida';
    return new Date(c.licencia_vence).getTime() - Date.now() <= 30 * 86400000 ? 'pronto' : 'ok';
  }

  async guardar(): Promise<void> {
    this.error.set(null);
    const g = this.grupos.grupo()?.id;
    if (!g || this.nombre.trim().length < 2) return;
    const r = await this.gob.guardarCapitan(g, {
      id: null,
      nombre: this.nombre,
      miembro: this.miembro || null,
      licencia: this.licencia,
      vence: this.vence || null,
      anios: this.anios,
      notas: this.notas,
      estado: 'activo',
    });
    if (r.error) return void this.error.set(t(claveError(r.error) as ClaveI18n));
    this.nombre = this.licencia = this.vence = this.notas = '';
    this.anios = null;
    await this.cargar();
  }

  async renovar(c: CapitanModel, nueva: string): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g || !nueva) return;
    const r = await this.gob.guardarCapitan(g, {
      id: c.id,
      nombre: c.nombre,
      miembro: c.miembro_id,
      licencia: c.licencia_numero ?? '',
      vence: nueva,
      anios: c.experiencia_anios,
      notas: c.experiencia_notas ?? '',
      estado: c.estado,
    });
    if (r.error) return void this.error.set(t(claveError(r.error) as ClaveI18n));
    await this.cargar();
  }
}
