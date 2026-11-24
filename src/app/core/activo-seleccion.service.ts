import { Injectable, computed, signal } from '@angular/core';
import { ActivoModel } from '../../shared/models/config.model';
import { ConfiguracionService } from './configuracion.service';
import { GrupoService } from './grupo.service';

const CLAVE = 'shared.activo_seleccionado';

/** Activo con el que se trabaja en calendario y reservas (el grupo puede tener N activos). */
@Injectable({ providedIn: 'root' })
export class ActivoSeleccionService {
  private _activos = signal<ActivoModel[]>([]);
  activos = this._activos.asReadonly();
  private _id = signal<string | null>(this.leer());
  cargado = signal(false);

  activo = computed<ActivoModel | null>(() => {
    const lista = this._activos();
    return lista.find((a) => a.id === this._id()) ?? lista[0] ?? null;
  });

  constructor(
    private config: ConfiguracionService,
    private grupos: GrupoService,
  ) {}

  private leer(): string | null {
    try {
      return localStorage.getItem(CLAVE);
    } catch {
      return null;
    }
  }

  async cargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    const todos = await this.config.activos(g);
    this._activos.set(todos.filter((a) => a.estado === 'activo'));
    this.cargado.set(true);
  }

  elegir(id: string): void {
    this._id.set(id);
    try {
      localStorage.setItem(CLAVE, id);
    } catch {
      // sin almacenamiento
    }
  }
}
