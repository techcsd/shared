import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ConfiguracionService } from '../../../core/configuracion.service';
import { GrupoService } from '../../../core/grupo.service';
import { t } from '../../../core/i18n/i18n';
import { aClave, validarDefinicionTipo } from '../../../core/validar';
import {
  CampoDef,
  ComponenteDef,
  DefinicionTipo,
  ItemChecklist,
  MomentoChecklist,
  TipoActivoModel,
} from '../../../../shared/models/config.model';

const MOMENTOS: MomentoChecklist[] = ['salida', 'regreso', 'seguridad'];
const OPCIONAL = '(opcional) ';

interface CampoEdicion extends CampoDef {
  opcionesTexto: string;
}

/** Tipos de activo: clonar plantillas y editar campos, componentes con medidor, checklists y categorías (SB2). */
@Component({
  selector: 'app-config-tipos',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './config-tipos.html',
  styleUrl: './config-tipos.scss',
})
export class ConfigTipos implements OnInit {
  t = t;
  momentos = MOMENTOS;
  tipos = signal<TipoActivoModel[]>([]);
  editando = signal<TipoActivoModel | null>(null);
  error = signal<string | null>(null);
  mensaje = signal<string | null>(null);

  // estado de clonación
  origen = '';
  nombreClon = '';

  // estado de edición
  nombre = '';
  prefijo = 'ORD';
  campos: CampoEdicion[] = [];
  componentes: ComponenteDef[] = [];
  checklists: Record<MomentoChecklist, string> = { salida: '', regreso: '', seguridad: '' };
  categoriasTexto = '';
  limiteSocio: number | null = null;
  limiteInvitado: number | null = null;
  private clavesChecklistPrevias: Record<string, string> = {};

  constructor(
    private grupos: GrupoService,
    private config: ConfiguracionService,
  ) {}

  async ngOnInit(): Promise<void> {
    await this.recargar();
  }

  private async recargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    const lista = await this.config.tipos(g);
    this.tipos.set(lista);
    if (!this.origen && lista.length) this.origen = lista[0].id;
  }

  momentoTexto(m: MomentoChecklist): string {
    switch (m) {
      case 'salida':
        return t('tipos.checklist.salida');
      case 'regreso':
        return t('tipos.checklist.regreso');
      case 'seguridad':
        return t('tipos.checklist.seguridad');
    }
  }

  async clonar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g || !this.origen || !this.nombreClon.trim()) return;
    this.error.set(null);
    const r = await this.config.clonarTipo(
      this.origen,
      g,
      this.nombreClon,
      aClave(this.nombreClon),
    );
    if (r.error) {
      this.error.set(r.error);
      return;
    }
    this.nombreClon = '';
    await this.recargar();
    const nuevo = this.tipos().find((x) => x.id === r.datos);
    if (nuevo) this.editar(nuevo);
  }

  editar(tipo: TipoActivoModel): void {
    const d = tipo.definicion;
    this.nombre = tipo.nombre;
    this.prefijo = tipo.prefijo_orden;
    this.campos = (d.campos ?? []).map((c) => ({
      ...c,
      opcionesTexto: (c.opciones ?? []).join(', '),
    }));
    this.componentes = (d.componentes ?? []).map((c) => ({ ...c, medidor: { ...c.medidor } }));
    this.clavesChecklistPrevias = {};
    for (const m of MOMENTOS) {
      const items = d.checklists?.[m] ?? [];
      this.checklists[m] = items
        .map((i) => (i.obligatorio === false ? OPCIONAL : '') + i.texto)
        .join('\n');
      for (const i of items) this.clavesChecklistPrevias[`${m}|${i.texto}`] = i.clave;
    }
    this.categoriasTexto = (d.categorias_gasto ?? []).join(', ');
    this.limiteSocio = d.limites_capacidad?.socio ?? null;
    this.limiteInvitado = d.limites_capacidad?.invitado ?? null;
    this.error.set(null);
    this.mensaje.set(null);
    this.editando.set(tipo);
  }

  cerrar(): void {
    this.editando.set(null);
  }

  agregarCampo(): void {
    this.campos = [
      ...this.campos,
      { clave: '', etiqueta: '', tipo: 'texto', obligatorio: false, opcionesTexto: '' },
    ];
  }

  quitarCampo(i: number): void {
    this.campos = this.campos.filter((_, j) => j !== i);
  }

  agregarComponente(): void {
    this.componentes = [
      ...this.componentes,
      { clave: '', etiqueta: '', cantidad_defecto: 1, medidor: { tipo: 'horometro', unidad: 'h' } },
    ];
  }

  quitarComponente(i: number): void {
    this.componentes = this.componentes.filter((_, j) => j !== i);
  }

  /** Arma la definición desde el formulario. Las claves nuevas se derivan de la etiqueta. */
  construir(): DefinicionTipo {
    const campos: CampoDef[] = this.campos.map((c) => {
      const campo: CampoDef = {
        clave: c.clave || aClave(c.etiqueta),
        etiqueta: c.etiqueta.trim(),
        tipo: c.tipo,
        obligatorio: !!c.obligatorio,
      };
      if (c.tipo === 'opcion') {
        campo.opciones = c.opcionesTexto
          .split(',')
          .map((s) => s.trim())
          .filter(Boolean);
      }
      if (c.unidad?.trim()) campo.unidad = c.unidad.trim();
      return campo;
    });
    const componentes = this.componentes.map((c) => ({
      ...c,
      clave: c.clave || aClave(c.etiqueta),
      etiqueta: c.etiqueta.trim(),
      cantidad_defecto: Number(c.cantidad_defecto),
      medidor: { tipo: c.medidor.tipo, unidad: c.medidor.unidad.trim() },
    }));
    const checklists: Partial<Record<MomentoChecklist, ItemChecklist[]>> = {};
    for (const m of MOMENTOS) {
      const usadas = new Set<string>();
      checklists[m] = this.checklists[m]
        .split('\n')
        .map((l) => l.trim())
        .filter(Boolean)
        .map((linea) => {
          const opcional = linea.toLowerCase().startsWith(OPCIONAL);
          const texto = opcional ? linea.slice(OPCIONAL.length).trim() : linea;
          let clave = this.clavesChecklistPrevias[`${m}|${texto}`] ?? aClave(texto);
          let n = 2;
          const base = clave;
          while (usadas.has(clave)) clave = `${base.slice(0, 36)}_${n++}`;
          usadas.add(clave);
          return { clave, texto, obligatorio: !opcional };
        });
    }
    const def: DefinicionTipo = {
      campos,
      componentes,
      checklists,
      categorias_gasto: this.categoriasTexto
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean),
      terminologia: this.editando()?.definicion.terminologia ?? {},
      limites_capacidad: {},
    };
    if (this.limiteSocio) def.limites_capacidad!.socio = Number(this.limiteSocio);
    if (this.limiteInvitado) def.limites_capacidad!.invitado = Number(this.limiteInvitado);
    return def;
  }

  async guardar(): Promise<void> {
    const tipo = this.editando();
    if (!tipo) return;
    this.error.set(null);
    this.mensaje.set(null);
    const def = this.construir();
    const problemas = validarDefinicionTipo(def);
    if (problemas.length) {
      this.error.set(problemas.join(' · '));
      return;
    }
    const r = await this.config.guardarTipo(tipo.id, this.nombre, this.prefijo, def);
    if (r.error) {
      this.error.set(r.error);
      return;
    }
    this.mensaje.set(t('app.guardado'));
    await this.recargar();
    const actualizado = this.tipos().find((x) => x.id === tipo.id);
    if (actualizado) this.editando.set(actualizado);
  }
}
