import { DecimalPipe } from '@angular/common';
import { Component, OnInit, computed, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivoModel, ComponenteActivoModel } from '../../../shared/models/config.model';
import { PlanEstado, PlanModel, ResultadoProgramar, ServicioModel, TareaModel } from '../../../shared/models/p4.model';
import { ConfiguracionService } from '../../core/configuracion.service';
import { GobiernoService } from '../../core/gobierno.service';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { t } from '../../core/i18n/i18n';
import { claveError } from '../../core/reserva.service';

type Pestana = 'tareas' | 'planes' | 'servicios';

/** Mantenimiento (SA26, SA17): tareas, planes con criterio fecha/horas/lo que ocurra primero, servicios y facturas. */
@Component({
  selector: 'app-mantenimiento',
  standalone: true,
  imports: [FormsModule, DecimalPipe],
  templateUrl: './mantenimiento.html',
  styleUrl: '../p4-comun.scss',
})
export class MantenimientoPage implements OnInit {
  t = t;
  tk = (k: string): string => t(k as ClaveI18n);
  hoy = new Date().toISOString().slice(0, 10);
  pestana = signal<Pestana>('tareas');
  planes = signal<PlanModel[]>([]);
  estados = signal<Record<string, PlanEstado | null>>({});
  tareas = signal<TareaModel[]>([]);
  servicios = signal<ServicioModel[]>([]);
  activos = signal<ActivoModel[]>([]);
  componentes = signal<ComponenteActivoModel[]>([]);
  cargando = signal(true);
  error = signal<string | null>(null);
  aviso = signal<string | null>(null);
  programando = signal<string | null>(null);
  conflicto = signal<ResultadoProgramar | null>(null);

  // formularios
  pActivo = '';
  pComponente = '';
  pNombre = '';
  pCriterio = '';
  pDias: number | null = null;
  pHoras: number | null = null;
  tTitulo = '';
  tVence = '';
  tProveedor = '';
  sTarea = '';
  sProveedor = '';
  sDescripcion = '';
  sCosto: number | null = null;
  sVence = '';
  sComponente = '';
  inicio = '';
  fin = '';

  esSocio = computed(() => this.grupos.esSocio());
  puedeRegistrar = computed(() => ['socio', 'admin_operativo'].includes(this.grupos.rol() ?? ''));
  alertas = computed(() => this.planes().filter((p) => this.estados()[p.id]?.vencido || this.estados()[p.id]?.por_vencer));
  abiertas = computed(() => this.tareas().filter((x) => ['pendiente', 'programada'].includes(x.estado)));

  constructor(
    public grupos: GrupoService,
    private gob: GobiernoService,
    private config: ConfiguracionService,
  ) {}

  async ngOnInit(): Promise<void> {
    await this.cargar();
  }

  async cargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    const [planes, tareas, servicios, activos] = await Promise.all([
      this.gob.planes(g),
      this.gob.tareas(g),
      this.gob.servicios(g),
      this.config.activos(g),
    ]);
    this.planes.set(planes);
    this.tareas.set(tareas);
    this.servicios.set(servicios);
    this.activos.set(activos);
    const est: Record<string, PlanEstado | null> = {};
    for (const p of planes) est[p.id] = await this.gob.estadoPlan(p.id);
    this.estados.set(est);
    if (!this.pActivo && activos[0]) {
      this.pActivo = activos[0].id;
      await this.cambiarActivo();
    }
    this.cargando.set(false);
  }

  async cambiarActivo(): Promise<void> {
    this.componentes.set(this.pActivo ? await this.config.componentes(this.pActivo) : []);
  }

  private mostrarError(msg: string): void {
    this.error.set(t(claveError(msg) as ClaveI18n));
  }

  nombrePlan(id: string | null): string {
    return this.planes().find((p) => p.id === id)?.nombre ?? '';
  }

  textoEstado(p: PlanModel): string {
    const e = this.estados()[p.id];
    if (!e) return '';
    const partes: string[] = [];
    if (e.vence_fecha) partes.push(`${t('man.fecha')}: ${e.vence_fecha} (${e.dias_restantes} d)`);
    if (e.vence_horas !== null) partes.push(`${t('man.horas')}: ${e.vence_horas} (${e.horas_restantes} h)`);
    return partes.join(' · ');
  }

  async crearPlan(): Promise<void> {
    this.error.set(null);
    const g = this.grupos.grupo()?.id;
    if (!g || !this.pNombre) return;
    const r = await this.gob.guardarPlan(g, {
      activo: this.pActivo,
      componente: this.pComponente || null,
      nombre: this.pNombre,
      criterio: this.pCriterio,
      dias: this.pDias,
      horas: this.pHoras,
    });
    if (r.error) return this.mostrarError(r.error);
    this.pNombre = '';
    await this.cargar();
  }

  async crearTarea(): Promise<void> {
    this.error.set(null);
    const g = this.grupos.grupo()?.id;
    if (!g || !this.tTitulo) return;
    const r = await this.gob.crearTarea(g, this.pActivo, this.tTitulo, this.tVence, this.tProveedor);
    if (r.error) return this.mostrarError(r.error);
    this.tTitulo = '';
    await this.cargar();
  }

  async programar(tarea: TareaModel): Promise<void> {
    this.error.set(null);
    this.conflicto.set(null);
    if (!this.inicio || !this.fin) return;
    const r = await this.gob.programarTarea(tarea.id, this.inicio, this.fin);
    if (r.error) return this.mostrarError(r.error);
    if (!r.datos?.ok) {
      this.conflicto.set(r.datos);
      return;
    }
    this.programando.set(null);
    this.aviso.set(t('man.programada'));
    await this.cargar();
  }

  usarSugerida(): void {
    const s = this.conflicto()?.sugerida;
    if (!s) return;
    const local = (d: string) => new Date(new Date(d).getTime() - new Date(d).getTimezoneOffset() * 60000).toISOString().slice(0, 16);
    this.inicio = local(s.inicio);
    this.fin = local(s.fin);
    this.conflicto.set(null);
  }

  async registrarServicio(): Promise<void> {
    this.error.set(null);
    const g = this.grupos.grupo()?.id;
    if (!g || !this.pActivo) return;
    const r = await this.gob.registrarServicio(g, {
      activo: this.pActivo,
      componente: this.sComponente || null,
      tarea: this.sTarea || null,
      proveedor: this.sProveedor,
      descripcion: this.sDescripcion,
      costo: this.sCosto,
      moneda: this.grupos.grupo()?.moneda ?? 'DOP',
      vencimiento: this.sVence,
    });
    if (r.error) return this.mostrarError(r.error);
    this.sProveedor = this.sDescripcion = this.sVence = this.sTarea = '';
    this.sCosto = null;
    this.aviso.set(t('man.servicio_ok'));
    await this.cargar();
  }
}
