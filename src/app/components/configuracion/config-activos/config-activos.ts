import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivoTarjeta } from '../../../../shared/components/activo-tarjeta/activo-tarjeta';
import { ActivoService } from '../../../core/activo.service';
import { ConfiguracionService } from '../../../core/configuracion.service';
import { GrupoService } from '../../../core/grupo.service';
import { t } from '../../../core/i18n/i18n';
import {
  ActivoModel,
  CampoDef,
  ComponenteActivoModel,
  TipoActivoModel,
} from '../../../../shared/models/config.model';

/** Activos del grupo: datos, capacidad legal certificada (obligatoria para activar) y lecturas iniciales (SA19). */
@Component({
  selector: 'app-config-activos',
  standalone: true,
  imports: [FormsModule, ActivoTarjeta],
  templateUrl: './config-activos.html',
  styleUrl: './config-activos.scss',
})
export class ConfigActivos implements OnInit {
  t = t;
  tipos = signal<TipoActivoModel[]>([]);
  activos = signal<ActivoModel[]>([]);
  seleccionado = signal<ActivoModel | null>(null);
  componentes = signal<ComponenteActivoModel[]>([]);
  error = signal<string | null>(null);
  mensaje = signal<string | null>(null);

  // creación
  tipoId = '';
  nombre = '';
  capacidad: number | null = null;
  valoresNuevo: Record<string, unknown> = {};
  cantidades: Record<string, number> = {};

  // edición
  edit = { capacidad: null as number | null, punto: '', reglas: '', contacto: '', descripcion: '' };
  subiendo = signal(false);
  valoresEdit: Record<string, unknown> = {};
  lecturas: Record<string, number> = {};

  constructor(
    private grupos: GrupoService,
    private config: ConfiguracionService,
    private activosSvc: ActivoService,
  ) {}

  async ngOnInit(): Promise<void> {
    await this.recargar();
  }

  private async recargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    const [tp, ac] = await Promise.all([this.config.tipos(g), this.config.activos(g)]);
    this.tipos.set(tp);
    this.activos.set(ac);
    if (!this.tipoId && tp.length) this.elegirTipo(tp[0].id);
    const sel = this.seleccionado();
    if (sel) {
      const act = ac.find((x) => x.id === sel.id);
      if (act) await this.abrir(act);
    }
  }

  tipo(id: string): TipoActivoModel | undefined {
    return this.tipos().find((x) => x.id === id);
  }

  camposDe(tipoId: string): CampoDef[] {
    return this.tipo(tipoId)?.definicion.campos ?? [];
  }

  componentesDe(tipoId: string) {
    return this.tipo(tipoId)?.definicion.componentes ?? [];
  }

  elegirTipo(id: string): void {
    this.tipoId = id;
    this.valoresNuevo = {};
    this.cantidades = {};
    for (const c of this.componentesDe(id)) this.cantidades[c.clave] = c.cantidad_defecto;
  }

  estadoTexto(e: ActivoModel['estado']): string {
    switch (e) {
      case 'borrador':
        return t('activos.estado.borrador');
      case 'activo':
        return t('activos.estado.activo');
      case 'inactivo':
        return t('activos.estado.inactivo');
    }
  }

  /** Quita valores vacíos para no mandar «» a la base. */
  private limpiar(v: Record<string, unknown>): Record<string, unknown> {
    const salida: Record<string, unknown> = {};
    for (const [k, val] of Object.entries(v)) {
      if (val !== '' && val !== null && val !== undefined) salida[k] = val;
    }
    return salida;
  }

  async crear(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g || !this.tipoId) return;
    this.error.set(null);
    this.mensaje.set(null);
    const r = await this.config.crearActivo(
      g,
      this.tipoId,
      this.nombre,
      this.capacidad ? Number(this.capacidad) : null,
      this.limpiar(this.valoresNuevo),
      this.cantidades,
    );
    if (r.error) {
      this.error.set(r.error);
      return;
    }
    this.nombre = '';
    this.capacidad = null;
    this.valoresNuevo = {};
    this.mensaje.set(t('app.guardado'));
    await this.recargar();
    const nuevo = this.activos().find((a) => a.id === r.datos);
    if (nuevo) await this.abrir(nuevo);
  }

  async abrir(a: ActivoModel): Promise<void> {
    this.seleccionado.set(a);
    this.edit = {
      capacidad: a.capacidad_legal,
      punto: a.punto_encuentro ?? '',
      reglas: a.reglas_invitados ?? '',
      contacto: a.contacto_invitados ?? '',
      descripcion: a.descripcion ?? '',
    };
    this.valoresEdit = { ...a.valores };
    const comps = await this.config.componentes(a.id);
    this.componentes.set(comps);
    this.lecturas = {};
    for (const c of comps) this.lecturas[c.id] = Number(c.lectura_inicial);
    this.error.set(null);
    this.mensaje.set(null);
  }

  async guardar(activar: boolean | null = null): Promise<void> {
    const a = this.seleccionado();
    if (!a) return;
    this.error.set(null);
    this.mensaje.set(null);
    const cambios: Partial<ActivoModel> = {
      capacidad_legal: this.edit.capacidad ? Number(this.edit.capacidad) : null,
      punto_encuentro: this.edit.punto.trim() || null,
      reglas_invitados: this.edit.reglas.trim() || null,
      contacto_invitados: this.edit.contacto.trim() || null,
      descripcion: this.edit.descripcion.trim() || null,
      valores: this.limpiar(this.valoresEdit),
    };
    if (activar === true) cambios.estado = 'activo';
    if (activar === false) cambios.estado = 'inactivo';
    const r = await this.config.actualizarActivo(a.id, cambios);
    if (r.error) {
      this.error.set(this.traducir(r.error));
      return;
    }
    for (const c of this.componentes()) {
      const nuevo = Number(this.lecturas[c.id] ?? 0);
      if (nuevo !== Number(c.lectura_inicial)) {
        const rl = await this.config.fijarLecturaInicial(c.id, nuevo);
        if (rl.error) {
          this.error.set(rl.error);
          return;
        }
      }
    }
    this.mensaje.set(t('app.guardado'));
    await this.recargar();
  }

  /** Elige una foto: se reduce en el navegador y se sube al bucket `activos` (solo socios). */
  async elegirFoto(ev: Event): Promise<void> {
    const input = ev.target as HTMLInputElement;
    const archivo = input.files?.[0];
    const a = this.seleccionado();
    input.value = '';
    if (!archivo || !a) return;
    this.error.set(null);
    this.mensaje.set(null);
    this.subiendo.set(true);
    const r = await this.activosSvc.subirImagen(a.grupo_id, a.id, archivo, a.imagen_path);
    this.subiendo.set(false);
    if (r.error) {
      this.error.set(this.errorImagen(r.error));
      return;
    }
    await this.recargar();
    this.mensaje.set(t('app.guardado'));
  }

  async quitarFoto(): Promise<void> {
    const a = this.seleccionado();
    if (!a) return;
    this.error.set(null);
    this.subiendo.set(true);
    const r = await this.activosSvc.quitarImagen(a.id, a.imagen_path);
    this.subiendo.set(false);
    if (r.error) this.error.set(r.error);
    else {
      await this.recargar();
      this.mensaje.set(t('app.guardado'));
    }
  }

  private errorImagen(c: string): string {
    if (c === 'imagen_tipo_invalido') return t('activo.error.tipo');
    if (c === 'imagen_ilegible') return t('activo.error.ilegible');
    if (c === 'imagen_muy_grande') return t('activo.error.grande');
    return c;
  }

  private traducir(msg: string): string {
    if (msg.includes('activos_capacidad_para_activar')) return t('activos.error.capacidad');
    return msg;
  }
}
