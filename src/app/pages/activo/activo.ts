import { Component, Input, OnInit, signal } from '@angular/core';
import { ActivoContactosSeccion } from '../../components/activo/activo-contactos/activo-contactos';
import { ActivoDocumentos } from '../../components/activo/activo-documentos/activo-documentos';
import { ActivoEquipoSeccion } from '../../components/activo/activo-equipo/activo-equipo';
import { ActivoFicha } from '../../components/activo/activo-ficha/activo-ficha';
import { ActivoFotos } from '../../components/activo/activo-fotos/activo-fotos';
import { ActivoHistorial } from '../../components/activo/activo-historial/activo-historial';
import { ActivoResumen } from '../../components/activo/activo-resumen/activo-resumen';
import { ActivoValorSeccion } from '../../components/activo/activo-valor/activo-valor';
import { Icono } from '../../../shared/ui/icono/icono';
import { Vitrina } from '../../../shared/models/activo.model';
import { DetalleActivo } from '../../../shared/models/activo-entidad.model';
import { ActivoService } from '../../core/activo.service';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { t } from '../../core/i18n/i18n';

type Pestana = 'resumen' | 'ficha' | 'fotos' | 'documentos' | 'equipo' | 'valor' | 'contactos' | 'historial';

interface DefPestana {
  clave: Pestana;
  icono: string;
  etiqueta: ClaveI18n;
}

const PESTANAS: DefPestana[] = [
  { clave: 'resumen', icono: 'activo', etiqueta: 'activo.tab.resumen' },
  { clave: 'ficha', icono: 'lista', etiqueta: 'activo.tab.ficha' },
  { clave: 'fotos', icono: 'imagen', etiqueta: 'activo.tab.fotos' },
  { clave: 'documentos', icono: 'documento', etiqueta: 'activo.tab.documentos' },
  { clave: 'equipo', icono: 'caja', etiqueta: 'activo.tab.equipo' },
  { clave: 'valor', icono: 'moneda', etiqueta: 'activo.tab.valor' },
  { clave: 'contactos', icono: 'telefono', etiqueta: 'activo.tab.contactos' },
  { clave: 'historial', icono: 'historia', etiqueta: 'activo.tab.historial' },
];

/** «Nuestro activo»: ficha completa y editable (resumen, ficha técnica, fotos, documentos, equipo, valor, contactos, historial). */
@Component({
  selector: 'app-activo',
  standalone: true,
  imports: [
    Icono,
    ActivoResumen,
    ActivoFicha,
    ActivoFotos,
    ActivoDocumentos,
    ActivoEquipoSeccion,
    ActivoValorSeccion,
    ActivoContactosSeccion,
    ActivoHistorial,
  ],
  templateUrl: './activo.html',
  styleUrl: './activo.scss',
})
export class ActivoPage implements OnInit {
  t = t;
  /** Parámetros de la ruta: /activo?activo=<id>&editar=1&tab=fotos */
  @Input() activo?: string;
  @Input() editar?: string;
  @Input() tab?: string;

  vitrina = signal<Vitrina | null>(null);
  detalle = signal<DetalleActivo | null>(null);
  activoId = signal<string | null>(null);
  pestana = signal<Pestana>('resumen');
  editando = signal(false);
  cargando = signal(true);
  error = signal<string | null>(null);

  constructor(
    public grupos: GrupoService,
    private activos: ActivoService,
  ) {}

  async ngOnInit(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) {
      this.cargando.set(false);
      return;
    }
    const r = await this.activos.vitrina(g);
    if (r.error || !r.datos) {
      this.cargando.set(false);
      this.error.set(t('app.error.generico'));
      return;
    }
    this.vitrina.set(r.datos);
    const lista = r.datos.activos;
    const id = lista.find((a) => a.id === this.activo)?.id ?? lista[0]?.id ?? null;
    if (!id) {
      this.cargando.set(false);
      return;
    }
    if (this.tab && PESTANAS.some((p) => p.clave === this.tab)) this.pestana.set(this.tab as Pestana);
    await this.cargar(id);
    if (this.editar === '1' && this.detalle()?.permisos.editar) this.editando.set(true);
    this.cargando.set(false);
  }

  async cargar(id: string): Promise<void> {
    this.activoId.set(id);
    const d = await this.activos.detalle(id);
    if (d.error || !d.datos) {
      this.error.set(t('app.error.generico'));
      return;
    }
    this.error.set(null);
    this.detalle.set(d.datos);
  }

  /** Vuelve a leer el detalle después de guardar algo (sin parpadeo de «cargando»). */
  async recargar(): Promise<void> {
    const id = this.activoId();
    if (id) await this.cargar(id);
  }

  async elegirActivo(id: string): Promise<void> {
    this.editando.set(false);
    this.pestana.set('resumen');
    await this.cargar(id);
  }

  pestanas(): DefPestana[] {
    const d = this.detalle();
    // valor y mejoras son informativos pero solo los ven los socios
    return PESTANAS.filter((p) => p.clave !== 'valor' || d?.permisos.socio);
  }

  elegir(p: Pestana): void {
    this.pestana.set(p);
  }

  /** Flechas ← → entre pestañas (patrón de teclado de las pestañas accesibles). */
  teclas(ev: KeyboardEvent): void {
    const lista = this.pestanas();
    const i = lista.findIndex((p) => p.clave === this.pestana());
    let j = i;
    if (ev.key === 'ArrowRight') j = (i + 1) % lista.length;
    else if (ev.key === 'ArrowLeft') j = (i - 1 + lista.length) % lista.length;
    else return;
    ev.preventDefault();
    this.pestana.set(lista[j].clave);
    document.getElementById(`pest-${lista[j].clave}`)?.focus();
  }

  alternarEdicion(): void {
    this.editando.update((v) => !v);
  }
}
