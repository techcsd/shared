import { DecimalPipe } from '@angular/common';
import { Component, Input, OnInit, computed, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import {
  ComponenteActivoModel,
  DefinicionTipo,
  ItemChecklist,
} from '../../../shared/models/config.model';
import {
  FaltanteItem,
  GastoModel,
  IncidenciaModel,
  LecturaVigente,
  OperacionModel,
  ResultadoCheckout,
} from '../../../shared/models/finanzas.model';
import { MiembroModel } from '../../../shared/models/grupo.model';
import { parseRango } from '../../../shared/models/reserva.model';
import { AuthService } from '../../core/auth.service';
import { ConfiguracionService } from '../../core/configuracion.service';
import { fechaHoraZona } from '../../core/fechas';
import { FinanzasService } from '../../core/finanzas.service';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { idioma, t } from '../../core/i18n/i18n';
import { OperacionService, RespuestaChecklist, RespuestaGuardada } from '../../core/operacion.service';
import { ReservaService, claveError } from '../../core/reserva.service';

interface ItemConMomento extends ItemChecklist {
  momento: 'seguridad' | 'salida' | 'regreso';
}

/** Operación de una salida: check-in (salir), check-out (regresar) y resumen. Mobile-first, un solo flujo. */
@Component({
  selector: 'app-operacion',
  standalone: true,
  imports: [FormsModule, RouterLink, DecimalPipe],
  templateUrl: './operacion.html',
  styleUrl: './operacion.scss',
})
export class OperacionPage implements OnInit {
  t = t;
  @Input() id = ''; // id de la reserva (parámetro de ruta)

  reserva = signal<Awaited<ReturnType<ReservaService['detalle']>>>(null);
  operacion = signal<OperacionModel | null>(null);
  componentes = signal<ComponenteActivoModel[]>([]);
  def = signal<DefinicionTipo>({});
  miembros = signal<MiembroModel[]>([]);
  lecturas = signal<LecturaVigente[]>([]);
  respuestas = signal<RespuestaGuardada[]>([]);
  incidencias = signal<IncidenciaModel[]>([]);
  gastosViaje = signal<GastoModel[]>([]);
  resumen = signal<ResultadoCheckout['resumen'] | null>(null);
  faltan = signal<FaltanteItem[]>([]);
  cargando = signal(true);
  enviando = signal(false);
  error = signal<string | null>(null);
  aviso = signal<string | null>(null);

  // --- formulario de salida
  capitanMiembro = '';
  capitanNombre = '';
  combustible: number | null = null;
  nota = '';
  lect: Record<string, number | null> = {};
  ck: Record<string, boolean> = {};
  ckNota: Record<string, string> = {};
  // --- formulario de regreso
  ckR: Record<string, boolean> = {};
  ckNotaR: Record<string, string> = {};
  lectFin: Record<string, number | null> = {};
  combustibleFinal: number | null = null;
  combustibleAgregado: number | null = null;
  observaciones = '';
  incidenciaTexto = '';
  motivo = '';
  // --- gasto del viaje
  gCategoria = '';
  gMonto: number | null = null;
  gMoneda = 'DOP';
  gPagador = '';
  gProveedor = '';
  gFoto: File | null = null;
  // --- corrección de lectura
  corrComp = '';
  corrMomento: 'inicio' | 'fin' = 'fin';
  corrValor: number | null = null;
  corrMotivo = '';

  tz = computed(() => this.grupos.grupo()?.zona_horaria ?? 'America/Santo_Domingo');
  yo = computed(() => this.grupos.activa()?.id ?? null);
  fase = computed<'salida' | 'regreso' | 'cerrada' | 'otra'>(() => {
    const e = this.reserva()?.estado;
    return e === 'confirmada'
      ? 'salida'
      : e === 'en_curso'
        ? 'regreso'
        : e === 'finalizada'
          ? 'cerrada'
          : 'otra';
  });
  puedeOperar = computed(
    () =>
      this.reserva()?.reservado_por === this.yo() ||
      ['admin_operativo', 'capitan'].includes(this.grupos.rol() ?? ''),
  );
  puedeGastos = computed(() => ['socio', 'admin_operativo'].includes(this.grupos.rol() ?? ''));
  puedeCorregir = computed(() => ['socio', 'admin_operativo'].includes(this.grupos.rol() ?? ''));
  itemsSalida = computed<ItemConMomento[]>(() => [
    ...(this.def().checklists?.seguridad ?? []).map((i) => ({ ...i, momento: 'seguridad' as const })),
    ...(this.def().checklists?.salida ?? []).map((i) => ({ ...i, momento: 'salida' as const })),
  ]);
  itemsRegreso = computed<ItemConMomento[]>(() =>
    (this.def().checklists?.regreso ?? []).map((i) => ({ ...i, momento: 'regreso' as const })),
  );
  categorias = computed(() => this.def().categorias_gasto ?? []);
  personas = computed(() =>
    this.miembros().filter((m) => m.estado === 'activo' && m.rol !== 'mediador'),
  );
  pagadores = computed(() =>
    this.miembros().filter(
      (m) => m.estado === 'activo' && ['socio', 'admin_operativo'].includes(m.rol),
    ),
  );
  unidadCombustible = computed(() => this.operacion()?.combustible_unidad ?? 'gal');
  consumo = computed(() => {
    const o = this.operacion();
    if (!o || this.combustibleFinal === null) return null;
    return o.combustible_inicial + (this.combustibleAgregado ?? 0) - this.combustibleFinal;
  });

  constructor(
    public grupos: GrupoService,
    private reservas: ReservaService,
    private ops: OperacionService,
    private config: ConfiguracionService,
    private finanzas: FinanzasService,
    private auth: AuthService,
  ) {}

  async ngOnInit(): Promise<void> {
    await this.cargar();
  }

  async cargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    const r = await this.reservas.detalle(this.id);
    this.reserva.set(r);
    if (!r || !g) {
      this.cargando.set(false);
      return;
    }
    this.gMoneda = this.grupos.grupo()?.moneda ?? 'DOP';
    this.miembros.set(await this.grupos.miembros(g));
    const [activos, tipos, comps, op] = await Promise.all([
      this.config.activos(g),
      this.config.tipos(g),
      this.config.componentes(r.activo_id),
      this.ops.deReserva(r.id),
    ]);
    const activo = activos.find((a) => a.id === r.activo_id);
    this.def.set(tipos.find((x) => x.id === activo?.tipo_id)?.definicion ?? {});
    this.componentes.set(comps);
    this.operacion.set(op);
    if (op) {
      this.lecturas.set(await this.ops.lecturas(op.id));
      this.respuestas.set(await this.ops.checklist(op.id));
      this.incidencias.set(await this.ops.incidencias(op.id));
      this.gastosViaje.set(this.puedeGastos() ? await this.finanzas.gastosDeReserva(r.id) : []);
      if (this.fase() === 'cerrada' && this.grupos.esSocio()) {
        const l = await this.ops.liquidacion(op.id);
        this.resumen.set((l?.['resumen'] as ResultadoCheckout['resumen']) ?? null);
      }
      this.combustibleFinal ??= op.combustible_final;
    } else if (this.fase() === 'salida') {
      for (const c of comps) {
        const ult = await this.ops.ultimaFinal(c.id);
        this.lect[c.id] ??= ult ?? c.lectura_inicial;
      }
      this.capitanMiembro = this.yo() ?? '';
    }
    this.cargando.set(false);
  }

  nombre(id: string | null): string {
    return this.miembros().find((m) => m.id === id)?.perfil?.nombre ?? '—';
  }

  fh(d: string | Date): string {
    return fechaHoraZona(new Date(d), this.tz(), idioma());
  }

  rangoTexto(): string {
    const r = this.reserva();
    if (!r) return '';
    const { inicio, fin } = parseRango(r.rango);
    return `${this.fh(inicio)} → ${this.fh(fin)}`;
  }

  lecturaDe(comp: string, momento: 'inicio' | 'fin'): number | null {
    return this.lecturas().find((l) => l.componente_id === comp && l.momento === momento)?.valor ?? null;
  }

  horas(comp: string): number | null {
    const i = this.lecturaDe(comp, 'inicio');
    const f = this.lecturaDe(comp, 'fin');
    return i !== null && f !== null ? Math.round((f - i) * 10) / 10 : null;
  }

  respuestaDe(clave: string): RespuestaGuardada | undefined {
    return this.respuestas().find((x) => x.clave === clave);
  }

  faltaTexto(f: FaltanteItem): string {
    const clave = `op.falta.${f.codigo}` as ClaveI18n;
    return `${t(clave)}${f.detalle ? ': ' + f.detalle : ''}`;
  }

  private checklist(
    items: ItemConMomento[],
    ck: Record<string, boolean>,
    notas: Record<string, string>,
  ): RespuestaChecklist[] {
    // Solo se envía lo contestado: marcado, o desmarcado con explicación. Lo demás queda como «falta».
    return items
      .filter((i) => !!ck[i.clave] || !!notas[i.clave]?.trim())
      .map((i) => ({
        clave: i.clave,
        momento: i.momento,
        cumple: !!ck[i.clave],
        nota: notas[i.clave] || undefined,
      }));
  }

  private mostrarError(msg: string): void {
    this.error.set(t(claveError(msg) as ClaveI18n));
  }

  async salir(): Promise<void> {
    this.error.set(null);
    this.faltan.set([]);
    this.enviando.set(true);
    const r = this.reserva();
    const res = await this.ops.checkin({
      reserva: this.id,
      capitanMiembro: this.capitanMiembro || null,
      capitanNombre: this.capitanNombre.trim(),
      destino: r?.destino_id ?? null,
      combustible: this.combustible,
      lecturas: this.componentes()
        .filter((c) => this.lect[c.id] !== null && this.lect[c.id] !== undefined)
        .map((c) => ({ componente_id: c.id, valor: Number(this.lect[c.id]) })),
      checklist: this.checklist(this.itemsSalida(), this.ck, this.ckNota),
      nota: this.nota,
    });
    this.enviando.set(false);
    if (res.error) return this.mostrarError(res.error);
    if (!res.datos?.ok) {
      this.faltan.set(res.datos?.faltan ?? []);
      return;
    }
    this.aviso.set(t('op.salida_ok'));
    await this.cargar();
  }

  async agregarGasto(): Promise<void> {
    this.error.set(null);
    const g = this.grupos.grupo()?.id;
    const u = this.auth.usuario()?.id;
    if (!g || !u || !this.gMonto || !this.gCategoria) {
      this.error.set(t('gas.faltan_datos'));
      return;
    }
    this.enviando.set(true);
    const res = await this.finanzas.registrarGasto(g, {
      alcance: 'individual',
      categoria: this.gCategoria,
      monto: this.gMonto,
      moneda: this.gMoneda,
      pagadoTipo: 'miembro',
      pagadoMiembro: this.gPagador || this.yo(),
      proveedor: this.gProveedor,
      reserva: this.id,
    });
    if (res.error) {
      this.enviando.set(false);
      return this.mostrarError(res.error);
    }
    if (this.gFoto && res.datos) {
      await this.finanzas.subirEvidencia(g, u, 'gasto', res.datos, this.gFoto, 'factura');
    }
    this.gMonto = null;
    this.gProveedor = '';
    this.gFoto = null;
    this.enviando.set(false);
    this.gastosViaje.set(await this.finanzas.gastosDeReserva(this.id));
  }

  elegirFoto(ev: Event, destino: 'gasto' | 'operacion'): void {
    const f = (ev.target as HTMLInputElement).files?.[0] ?? null;
    if (destino === 'gasto') {
      this.gFoto = f;
      return;
    }
    const g = this.grupos.grupo()?.id;
    const u = this.auth.usuario()?.id;
    const op = this.operacion();
    if (!f || !g || !u || !op) return;
    void this.finanzas.subirEvidencia(g, u, 'operacion', op.id, f, 'foto').then((r) => {
      this.aviso.set(r.error ? null : t('op.foto_ok'));
      if (r.error) this.mostrarError(r.error);
    });
  }

  async regresar(): Promise<void> {
    this.error.set(null);
    this.faltan.set([]);
    this.enviando.set(true);
    const incs = this.incidenciaTexto.trim()
      ? [{ tipo: 'incidencia' as const, descripcion: this.incidenciaTexto.trim() }]
      : [];
    const res = await this.ops.checkout({
      reserva: this.id,
      lecturas: this.componentes()
        .filter((c) => this.lectFin[c.id] !== null && this.lectFin[c.id] !== undefined)
        .map((c) => ({ componente_id: c.id, valor: Number(this.lectFin[c.id]) })),
      combustibleFinal: this.combustibleFinal,
      combustibleAgregado: this.combustibleAgregado,
      checklist: this.checklist(this.itemsRegreso(), this.ckR, this.ckNotaR),
      incidencias: incs,
      observaciones: this.observaciones,
      motivo: this.motivo,
    });
    this.enviando.set(false);
    if (res.error) return this.mostrarError(res.error);
    this.incidenciaTexto = '';
    if (!res.datos?.cerrada) {
      this.faltan.set(res.datos?.faltan ?? []);
      this.incidencias.set(await this.ops.incidencias(this.operacion()!.id));
      return;
    }
    this.resumen.set(res.datos.resumen ?? null);
    this.aviso.set(t('op.cierre_ok'));
    await this.cargar();
  }

  async corregir(): Promise<void> {
    const op = this.operacion();
    if (!op || !this.corrComp || this.corrValor === null) return;
    this.error.set(null);
    const r = await this.ops.corregirLectura(
      op.id,
      this.corrComp,
      this.corrMomento,
      Number(this.corrValor),
      this.corrMotivo,
    );
    if (r.error) return this.mostrarError(r.error);
    this.corrValor = null;
    this.corrMotivo = '';
    this.aviso.set(t('op.correccion_ok'));
    this.lecturas.set(await this.ops.lecturas(op.id));
  }
}
