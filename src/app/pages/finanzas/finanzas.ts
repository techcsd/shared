import { DecimalPipe } from '@angular/common';
import { Component, OnInit, computed, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  BalanceFila,
  DanoAcuerdo,
  DanoCaso,
  DanoMensaje,
  MovimientoCuenta,
  MovimientoFondo,
  PagoModel,
} from '../../../shared/models/finanzas.model';
import { MiembroModel } from '../../../shared/models/grupo.model';
import { AuthService } from '../../core/auth.service';
import { FinanzasService } from '../../core/finanzas.service';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { t } from '../../core/i18n/i18n';
import { PoliticaService } from '../../core/politica.service';
import { claveError } from '../../core/reserva.service';

type Pestana = 'balances' | 'cuenta' | 'pagos' | 'fondo' | 'danos';

/** Finanzas (solo socios): balances, estado de cuenta, pagos, fondo común y daños. Modo `registro`: nada bloquea. */
@Component({
  selector: 'app-finanzas',
  standalone: true,
  imports: [FormsModule, DecimalPipe],
  templateUrl: './finanzas.html',
  styleUrl: './finanzas.scss',
})
export class FinanzasPage implements OnInit {
  t = t;
  tk = (clave: string): string => t(clave as ClaveI18n);
  readonly pestanas: Pestana[] = ['balances', 'cuenta', 'pagos', 'fondo', 'danos'];
  pestana = signal<Pestana>('balances');
  miembros = signal<MiembroModel[]>([]);
  balances = signal<BalanceFila[]>([]);
  movimientos = signal<MovimientoCuenta[]>([]);
  pagos = signal<PagoModel[]>([]);
  fondo = signal<MovimientoFondo[]>([]);
  danos = signal<DanoCaso[]>([]);
  mensajes = signal<DanoMensaje[]>([]);
  acuerdos = signal<DanoAcuerdo[]>([]);
  casoAbierto = signal<string | null>(null);
  aporteMensual = signal(0);
  modo = signal('registro');
  cargando = signal(true);
  error = signal<string | null>(null);
  aviso = signal<string | null>(null);

  cuentaDe = '';
  // pago
  pAMiembro = '';
  pMonto: number | null = null;
  pMoneda = 'DOP';
  pTasa: number | null = null;
  pNota = '';
  rechazoMotivo = '';
  rechazando = signal<string | null>(null);
  // daño
  dTitulo = '';
  dDescripcion = '';
  dMensaje = '';
  dPresupuesto: number | null = null;
  dMoneda = 'DOP';
  dPagadoTipo: 'miembro' | 'fondo' | 'externo' = 'miembro';
  dPagador = '';
  dReparto: Record<string, number | null> = {};
  dNota = '';

  yo = computed(() => this.grupos.activa()?.id ?? null);
  monedaGrupo = computed(() => this.grupos.grupo()?.moneda ?? 'DOP');
  socios = computed(() => this.miembros().filter((m) => m.rol === 'socio' && m.estado === 'activo'));
  filasMiembros = computed(() => this.balances().filter((b) => b.cuenta_tipo === 'miembro'));
  filaFondo = computed(() => this.balances().filter((b) => b.cuenta_tipo === 'fondo'));
  filaExterno = computed(() => this.balances().filter((b) => b.cuenta_tipo === 'externo'));
  sumaTotal = computed(
    () => Math.round(this.balances().reduce((s, b) => s + b.balance, 0) * 100) / 100,
  );
  caso = computed(() => this.danos().find((d) => d.id === this.casoAbierto()) ?? null);
  saldoFondo = computed(() => this.filaFondo().reduce((s, b) => s + b.balance, 0));
  repartoSuma = computed(() => this.socios().reduce((s, m) => s + Number(this.dReparto[m.id] ?? 0), 0));
  yaRespondi = computed(() => {
    const c = this.caso();
    return !!c && this.acuerdos().some((a) => a.miembro_id === this.yo() && a.version === c.version);
  });

  constructor(
    public grupos: GrupoService,
    private finanzas: FinanzasService,
    private politicas: PoliticaService,
    private auth: AuthService,
  ) {}

  async ngOnInit(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    this.pMoneda = this.dMoneda = this.monedaGrupo();
    this.cuentaDe = this.yo() ?? '';
    this.miembros.set(await this.grupos.miembros(g));
    this.aporteMensual.set(Number(await this.politicas.valor(g, 'fondo.aporte_mensual')) || 0);
    this.modo.set(String((await this.politicas.valor(g, 'finanzas.modo')) ?? 'registro'));
    await this.recargar();
    this.cargando.set(false);
  }

  async recargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    const [b, p, f, d] = await Promise.all([
      this.finanzas.balances(g),
      this.finanzas.pagos(g),
      this.finanzas.movimientosFondo(g),
      this.finanzas.danos(g),
    ]);
    this.balances.set(b);
    this.pagos.set(p);
    this.fondo.set(f);
    this.danos.set(d);
    await this.cargarCuenta();
    if (this.casoAbierto()) await this.cargarCaso(this.casoAbierto()!);
  }

  async cargarCuenta(): Promise<void> {
    if (this.cuentaDe) this.movimientos.set(await this.finanzas.estadoCuenta(this.cuentaDe));
  }

  acepto(miembro: string, version: number): boolean {
    return this.acuerdos().some((a) => a.miembro_id === miembro && a.version === version && a.acepta);
  }

  nombre(id: string | null): string {
    return this.miembros().find((m) => m.id === id)?.perfil?.nombre ?? '—';
  }

  private mostrarError(msg: string): void {
    this.error.set(t(claveError(msg) as ClaveI18n));
  }

  // ---- pagos
  puedeConfirmar(p: PagoModel): boolean {
    return (
      p.estado === 'pendiente' &&
      p.de_miembro !== this.yo() &&
      (p.a_tipo === 'fondo' || p.a_miembro === this.yo())
    );
  }

  destinoPago(p: PagoModel): string {
    return p.a_tipo === 'fondo' ? t('fin.fondo') : this.nombre(p.a_miembro);
  }

  async pagar(): Promise<void> {
    this.error.set(null);
    const g = this.grupos.grupo()?.id;
    if (!g || !this.pMonto) return;
    const r = await this.finanzas.registrarPago(
      g,
      this.pAMiembro || null,
      this.pMonto,
      this.pMoneda,
      this.pNota,
      this.pMoneda !== this.monedaGrupo() ? this.pTasa : null,
    );
    if (r.error) return this.mostrarError(r.error);
    this.pMonto = null;
    this.pNota = '';
    this.aviso.set(t('fin.pago_registrado'));
    await this.recargar();
  }

  async confirmarPago(p: PagoModel): Promise<void> {
    this.error.set(null);
    const r = await this.finanzas.confirmarPago(p.id);
    if (r.error) this.mostrarError(r.error);
    await this.recargar();
  }

  async rechazarPago(): Promise<void> {
    const id = this.rechazando();
    if (!id) return;
    const r = await this.finanzas.rechazarPago(id, this.rechazoMotivo);
    if (r.error) return this.mostrarError(r.error);
    this.rechazando.set(null);
    this.rechazoMotivo = '';
    await this.recargar();
  }

  async reiniciarDemo(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g || !window.confirm(t('fin.reiniciar_demo_confirmar'))) return;
    this.error.set(null);
    const r = await this.finanzas.reiniciarDemo(g);
    if (r.error) return this.mostrarError(r.error);
    this.aviso.set(t('fin.reiniciar_demo_ok'));
    await this.recargar();
  }

  // ---- fondo
  async generarAportes(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    const r = await this.finanzas.generarAportes(g);
    if (r.error) return this.mostrarError(r.error);
    this.aviso.set(t('fin.aportes_generados', { n: r.datos ?? 0 }));
    await this.recargar();
  }

  // ---- daños
  async abrirCaso(): Promise<void> {
    this.error.set(null);
    const g = this.grupos.grupo()?.id;
    if (!g || this.dTitulo.trim().length < 2) return;
    const r = await this.finanzas.abrirDano(g, this.dTitulo.trim(), this.dDescripcion, null);
    if (r.error) return this.mostrarError(r.error);
    this.dTitulo = '';
    this.dDescripcion = '';
    await this.recargar();
    if (r.datos) await this.verCaso(r.datos);
  }

  async verCaso(id: string): Promise<void> {
    this.casoAbierto.set(id);
    await this.cargarCaso(id);
  }

  async cargarCaso(id: string): Promise<void> {
    this.mensajes.set(await this.finanzas.mensajesDano(id));
    this.acuerdos.set(await this.finanzas.acuerdosDano(id));
  }

  repartirIgual(): void {
    const s = this.socios();
    if (!this.dPresupuesto || !s.length) return;
    const centavos = Math.round(this.dPresupuesto * 100);
    const base = Math.floor(centavos / s.length);
    let resto = centavos - base * s.length;
    for (const m of s) {
      this.dReparto[m.id] = (base + (resto-- > 0 ? 1 : 0)) / 100;
    }
  }

  async proponer(): Promise<void> {
    this.error.set(null);
    const c = this.caso();
    if (!c || !this.dPresupuesto) return;
    const propuesta = this.socios()
      .filter((m) => Number(this.dReparto[m.id] ?? 0) > 0)
      .map((m) => ({ miembro_id: m.id, monto: Number(this.dReparto[m.id]) }));
    const r = await this.finanzas.proponerDano(
      c.id,
      this.dPresupuesto,
      this.dMoneda,
      this.dPagadoTipo,
      this.dPagador || this.yo(),
      propuesta,
    );
    if (r.error) return this.mostrarError(r.error);
    this.aviso.set(t('fin.propuesta_enviada'));
    await this.recargar();
  }

  async responder(acepta: boolean): Promise<void> {
    this.error.set(null);
    const c = this.caso();
    if (!c) return;
    const r = await this.finanzas.responderDano(c.id, acepta, this.dNota);
    if (r.error) return this.mostrarError(r.error);
    this.dNota = '';
    await this.recargar();
  }

  async enviarMensaje(): Promise<void> {
    const c = this.caso();
    if (!c || !this.dMensaje.trim()) return;
    const r = await this.finanzas.mensajeDano(c.id, this.dMensaje.trim());
    if (r.error) return this.mostrarError(r.error);
    this.dMensaje = '';
    await this.cargarCaso(c.id);
  }

  async subirFoto(ev: Event): Promise<void> {
    const f = (ev.target as HTMLInputElement).files?.[0];
    const g = this.grupos.grupo()?.id;
    const u = this.auth.usuario()?.id;
    const c = this.caso();
    if (!f || !g || !u || !c) return;
    const r = await this.finanzas.subirEvidencia(g, u, 'dano', c.id, f, 'foto');
    if (r.error) this.mostrarError(r.error);
    else this.aviso.set(t('op.foto_ok'));
  }

  async subirComprobante(ev: Event, p: PagoModel): Promise<void> {
    const f = (ev.target as HTMLInputElement).files?.[0];
    const g = this.grupos.grupo()?.id;
    const u = this.auth.usuario()?.id;
    if (!f || !g || !u) return;
    const r = await this.finanzas.subirEvidencia(g, u, 'pago', p.id, f, 'comprobante');
    if (r.error) this.mostrarError(r.error);
    else this.aviso.set(t('fin.comprobante_ok'));
  }
}
