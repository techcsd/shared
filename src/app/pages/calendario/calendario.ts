import { Component, OnDestroy, OnInit, computed, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { RealtimeChannel } from '@supabase/supabase-js';
import { ActivoSeleccionService } from '../../core/activo-seleccion.service';
import {
  CeldaDia,
  claveDia,
  cuadriculaMes,
  fechaHoraZona,
  horaZona,
  instanteDesdeZona,
  mesDe,
  nombreDia,
  nombreMes,
  sumarDias,
  sumarMeses,
} from '../../core/fechas';
import { GrupoService } from '../../core/grupo.service';
import { idioma, t } from '../../core/i18n/i18n';
import { GobiernoService } from '../../core/gobierno.service';
import { ReservaService, claveError } from '../../core/reserva.service';
import { MiembroModel } from '../../../shared/models/grupo.model';
import { ReservaModel, codigoOrden, parseRango } from '../../../shared/models/reserva.model';
import { ClaveI18n } from '../../core/i18n/es';

type Vista = 'mes' | 'semana' | 'dia';
type Clase = 'mia' | 'otro' | 'mantenimiento' | 'preparacion';

interface Item {
  reserva: ReservaModel;
  clase: Clase;
  inicio: Date;
  fin: Date;
  etiqueta: string;
}

/** Calendario: pantalla principal (SA15). Disponible · mío · de otro socio · mantenimiento/preparación. */
@Component({
  selector: 'app-calendario',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './calendario.html',
  styleUrl: './calendario.scss',
})
export class CalendarioPage implements OnInit, OnDestroy {
  t = t;
  vista = signal<Vista>('mes');
  diaSel = signal<string>('');
  items = signal<Item[]>([]);
  miembros = signal<MiembroModel[]>([]);
  cargando = signal(true);
  error = signal<string | null>(null);
  canal: RealtimeChannel | null = null;

  // bloqueos
  mostrarBloqueo = signal(false);
  bloqueoTipo: 'mantenimiento' | 'preparacion' = 'mantenimiento';
  bloqueoDesde = '';
  bloqueoHasta = '';
  bloqueoHoraDesde = '08:00';
  bloqueoHoraHasta = '18:00';
  bloqueoMotivo = '';

  readonly cabecera: ClaveI18n[] = [
    'cal.dia.lun',
    'cal.dia.mar',
    'cal.dia.mie',
    'cal.dia.jue',
    'cal.dia.vie',
    'cal.dia.sab',
    'cal.dia.dom',
  ];

  tz = computed(() => this.grupos.grupo()?.zona_horaria ?? 'America/Santo_Domingo');
  mes = computed(() => mesDe(this.diaSel() || claveDia(new Date(), this.tz())));
  celdas = computed<CeldaDia[]>(() => cuadriculaMes(this.mes()));
  diasSemana = computed(() => {
    const d = this.diaSel();
    if (!d) return [];
    const base = new Date(d + 'T00:00:00Z');
    const lunes = sumarDias(d, -((base.getUTCDay() + 6) % 7));
    return Array.from({ length: 7 }, (_, i) => sumarDias(lunes, i));
  });
  titulo = computed(() => {
    const v = this.vista();
    if (v === 'mes') return nombreMes(this.mes(), idioma());
    if (v === 'dia') return nombreDia(this.diaSel(), idioma());
    const s = this.diasSemana();
    return s.length ? `${nombreDia(s[0], idioma())} – ${nombreDia(s[6], idioma())}` : '';
  });
  delDia = computed(() => {
    const mapa = new Map<string, Item[]>();
    for (const it of this.items()) {
      const a = claveDia(it.inicio, this.tz());
      const b = claveDia(new Date(it.fin.getTime() - 1), this.tz());
      for (let d = a; d <= b; d = sumarDias(d, 1)) mapa.set(d, [...(mapa.get(d) ?? []), it]);
    }
    return mapa;
  });
  yo = computed(() => this.grupos.activa()?.id ?? null);
  puedeReservar = computed(() => this.grupos.esSocio());
  puedeBloquear = computed(() => ['socio', 'admin_operativo'].includes(this.grupos.rol() ?? ''));

  constructor(
    public grupos: GrupoService,
    public activos: ActivoSeleccionService,
    private reservas: ReservaService,
    private router: Router,
    private gob: GobiernoService,
  ) {}

  tareasVencidas = signal<string[]>([]);

  async ngOnInit(): Promise<void> {
    this.diaSel.set(claveDia(new Date(), this.tz()));
    await this.activos.cargar();
    const g = this.grupos.grupo()?.id;
    if (g) {
      this.miembros.set(await this.grupos.miembros(g));
      const hoy = new Date().toISOString().slice(0, 10);
      this.tareasVencidas.set(
        (await this.gob.tareas(g)).filter((x) => x.estado === 'pendiente' && !!x.vence_fecha && x.vence_fecha <= hoy).map((x) => x.titulo),
      );
      this.canal = this.reservas.suscribir(g, () => void this.recargar());
    }
    await this.recargar();
  }

  ngOnDestroy(): void {
    this.reservas.desuscribir(this.canal);
  }

  private ventana(): { desde: Date; hasta: Date } {
    const v = this.vista();
    let primero: string;
    let ultimo: string;
    if (v === 'mes') {
      const c = this.celdas();
      primero = c[0].clave;
      ultimo = c[c.length - 1].clave;
    } else if (v === 'semana') {
      const s = this.diasSemana();
      primero = s[0];
      ultimo = s[6];
    } else {
      primero = ultimo = this.diaSel();
    }
    return {
      desde: instanteDesdeZona(primero, '00:00', this.tz()),
      hasta: instanteDesdeZona(sumarDias(ultimo, 1), '00:00', this.tz()),
    };
  }

  async recargar(): Promise<void> {
    const act = this.activos.activo();
    if (!act || !this.diaSel()) {
      this.items.set([]);
      this.cargando.set(false);
      return;
    }
    const { desde, hasta } = this.ventana();
    const lista = await this.reservas.enVentana(act.id, desde, hasta);
    this.items.set(lista.map((r) => this.aItem(r)));
    this.cargando.set(false);
  }

  private nombreMiembro(id: string | null): string {
    const m = this.miembros().find((x) => x.id === id);
    return m?.perfil?.nombre ?? '—';
  }

  private aItem(r: ReservaModel): Item {
    const { inicio, fin } = parseRango(r.rango);
    let clase: Clase;
    let etiqueta: string;
    if (r.tipo_bloqueo) {
      clase = r.tipo_bloqueo === 'preparacion' ? 'preparacion' : 'mantenimiento';
      etiqueta = r.tipo_bloqueo === 'preparacion' ? t('cal.preparacion') : t('cal.mantenimiento');
    } else if (r.reservado_por === this.yo()) {
      clase = 'mia';
      etiqueta = t('cal.mia');
    } else {
      clase = 'otro';
      etiqueta = this.nombreMiembro(r.reservado_por);
    }
    return { reserva: r, clase, inicio, fin, etiqueta };
  }

  hora(d: Date): string {
    return horaZona(d, this.tz());
  }
  fechaHora(d: Date): string {
    return fechaHoraZona(d, this.tz(), idioma());
  }
  codigo(r: ReservaModel): string | null {
    return codigoOrden(r);
  }
  numero(clave: string): number {
    return Number(clave.slice(8, 10));
  }
  esHoy(clave: string): boolean {
    return clave === claveDia(new Date(), this.tz());
  }
  clasesDe(clave: string): Clase[] {
    return [...new Set((this.delDia().get(clave) ?? []).map((i) => i.clase))];
  }
  itemsDe(clave: string): Item[] {
    return (this.delDia().get(clave) ?? [])
      .slice()
      .sort((a, b) => a.inicio.getTime() - b.inicio.getTime());
  }
  nombreDiaTxt(clave: string): string {
    return nombreDia(clave, idioma());
  }
  claseTexto(c: Clase): string {
    switch (c) {
      case 'mia':
        return t('cal.mia');
      case 'otro':
        return t('cal.otro');
      case 'mantenimiento':
        return t('cal.mantenimiento');
      case 'preparacion':
        return t('cal.preparacion');
    }
  }

  elegirActivo(id: string): void {
    this.activos.elegir(id);
    void this.recargar();
  }

  cambiarVista(v: Vista): void {
    this.vista.set(v);
    void this.recargar();
  }

  mover(n: number): void {
    const v = this.vista();
    const d = this.diaSel();
    if (v === 'mes') this.diaSel.set(sumarMeses(this.mes(), n) + '-01');
    else this.diaSel.set(sumarDias(d, v === 'semana' ? 7 * n : n));
    void this.recargar();
  }

  hoy(): void {
    this.diaSel.set(claveDia(new Date(), this.tz()));
    void this.recargar();
  }

  elegirDia(clave: string): void {
    this.diaSel.set(clave);
    if (this.vista() === 'mes' && !this.celdas().find((c) => c.clave === clave)?.delMes)
      void this.recargar();
  }

  reservarEn(clave: string): void {
    void this.router.navigate(['/reservar'], { queryParams: { fecha: clave } });
  }

  async bloquear(): Promise<void> {
    const act = this.activos.activo();
    if (!act || !this.bloqueoDesde || !this.bloqueoHasta) return;
    this.error.set(null);
    const r = await this.reservas.crearBloqueo(
      act.id,
      instanteDesdeZona(this.bloqueoDesde, this.bloqueoHoraDesde, this.tz()),
      instanteDesdeZona(this.bloqueoHasta, this.bloqueoHoraHasta, this.tz()),
      this.bloqueoTipo,
      this.bloqueoMotivo,
    );
    if (r.error) this.error.set(t(claveError(r.error) as ClaveI18n));
    else {
      this.mostrarBloqueo.set(false);
      this.bloqueoMotivo = '';
      await this.recargar();
    }
  }

  async quitarBloqueo(id: string): Promise<void> {
    const err = await this.reservas.quitarBloqueo(id);
    if (err) this.error.set(err);
    await this.recargar();
  }
}
