import { DecimalPipe } from '@angular/common';
import { Component, OnInit, computed, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { GastoModel } from '../../../shared/models/finanzas.model';
import { MiembroModel } from '../../../shared/models/grupo.model';
import { ReservaModel, codigoOrden } from '../../../shared/models/reserva.model';
import { AuthService } from '../../core/auth.service';
import { ConfiguracionService } from '../../core/configuracion.service';
import { FinanzasService } from '../../core/finanzas.service';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { t } from '../../core/i18n/i18n';
import { ReservaService, claveError } from '../../core/reserva.service';

type Filtro = 'todos' | 'provisional' | 'validado' | 'vencen';

/** Gastos (SA10, SA11): lista filtrable, alta rápida con foto, validación por otro socio (DF-12) y vencimientos. */
@Component({
  selector: 'app-gastos',
  standalone: true,
  imports: [FormsModule, DecimalPipe],
  templateUrl: './gastos.html',
  styleUrl: './gastos.scss',
})
export class GastosPage implements OnInit {
  t = t;
  tk = (clave: string): string => t(clave as ClaveI18n);
  gastos = signal<GastoModel[]>([]);
  miembros = signal<MiembroModel[]>([]);
  salidas = signal<ReservaModel[]>([]);
  categorias = signal<string[]>([]);
  filtro = signal<Filtro>('todos');
  cargando = signal(true);
  guardando = signal(false);
  error = signal<string | null>(null);
  abierto = signal(false);
  accion = signal<{ id: string; tipo: 'disputar' | 'anular' } | null>(null);
  motivo = '';

  // formulario
  alcance: 'comun' | 'individual' = 'comun';
  categoria = '';
  monto: number | null = null;
  moneda = 'DOP';
  tasa: number | null = null;
  pagadoTipo: 'miembro' | 'fondo' | 'externo' = 'miembro';
  pagador = '';
  proveedor = '';
  descripcion = '';
  reserva = '';
  vencimiento = '';
  foto: File | null = null;

  yo = computed(() => this.grupos.activa()?.id ?? null);
  puedeCargar = computed(() => ['socio', 'admin_operativo'].includes(this.grupos.rol() ?? ''));
  monedaGrupo = computed(() => this.grupos.grupo()?.moneda ?? 'DOP');
  pagadores = computed(() =>
    this.miembros().filter((m) => m.estado === 'activo' && ['socio', 'admin_operativo'].includes(m.rol)),
  );
  filtrados = computed(() => {
    const f = this.filtro();
    const limite = Date.now() + 7 * 86400000;
    return this.gastos().filter((g) => {
      if (f === 'provisional') return ['registrado', 'disputado'].includes(g.estado);
      if (f === 'validado') return g.estado === 'validado';
      if (f === 'vencen') return !!g.vencimiento && g.estado !== 'anulado' && new Date(g.vencimiento).getTime() <= limite;
      return true;
    });
  });
  totalProvisional = computed(() =>
    this.gastos()
      .filter((g) => ['registrado', 'disputado'].includes(g.estado))
      .reduce((s, g) => s + g.monto_grupo, 0),
  );
  otraMoneda = computed(() => this.moneda !== this.monedaGrupo());

  constructor(
    public grupos: GrupoService,
    private finanzas: FinanzasService,
    private reservas: ReservaService,
    private config: ConfiguracionService,
    private auth: AuthService,
  ) {}

  async ngOnInit(): Promise<void> {
    this.moneda = this.monedaGrupo();
    await this.cargar();
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    this.miembros.set(await this.grupos.miembros(g));
    this.salidas.set(await this.reservas.recientes(g));
    const [activos, tipos] = await Promise.all([this.config.activos(g), this.config.tipos(g)]);
    const cats = new Set<string>();
    for (const a of activos) {
      tipos.find((x) => x.id === a.tipo_id)?.definicion.categorias_gasto?.forEach((c) => cats.add(c));
    }
    this.categorias.set([...cats]);
  }

  async cargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (g) this.gastos.set(await this.finanzas.gastos(g));
    this.cargando.set(false);
  }

  nombre(id: string | null): string {
    if (!id) return '—';
    return this.miembros().find((m) => m.id === id)?.perfil?.nombre ?? '—';
  }

  pagadoPor(g: GastoModel): string {
    return g.pagado_por_tipo === 'miembro'
      ? this.nombre(g.pagado_por_miembro)
      : t(`gas.pagador.${g.pagado_por_tipo}` as ClaveI18n);
  }

  codigo(r: ReservaModel): string {
    return codigoOrden(r) ?? '—';
  }

  vence(g: GastoModel): 'vencido' | 'pronto' | null {
    if (!g.vencimiento || g.estado === 'anulado') return null;
    const d = new Date(g.vencimiento).getTime();
    if (d < Date.now() - 86400000) return 'vencido';
    return d <= Date.now() + 7 * 86400000 ? 'pronto' : null;
  }

  puedeValidar(g: GastoModel): boolean {
    return (
      this.grupos.esSocio() &&
      ['registrado', 'disputado'].includes(g.estado) &&
      g.alcance !== 'dano' &&
      g.cargado_por !== this.yo()
    );
  }

  puedeDisputar(g: GastoModel): boolean {
    return this.grupos.esSocio() && g.estado === 'registrado' && g.alcance !== 'dano';
  }

  puedeAnular(g: GastoModel): boolean {
    if (g.estado === 'anulado' || g.alcance === 'dano') return false;
    return this.grupos.esSocio() || (g.cargado_por === this.yo() && g.estado !== 'validado');
  }

  elegirFoto(ev: Event): void {
    this.foto = (ev.target as HTMLInputElement).files?.[0] ?? null;
  }

  private mostrarError(msg: string): void {
    this.error.set(t(claveError(msg) as ClaveI18n));
  }

  async guardar(): Promise<void> {
    this.error.set(null);
    const g = this.grupos.grupo()?.id;
    const u = this.auth.usuario()?.id;
    if (!g || !u || !this.monto || !this.categoria) {
      this.error.set(t('gas.faltan_datos'));
      return;
    }
    if (this.alcance === 'individual' && !this.reserva) {
      this.error.set(t('gas.elige_salida'));
      return;
    }
    this.guardando.set(true);
    const res = await this.finanzas.registrarGasto(g, {
      alcance: this.alcance,
      categoria: this.categoria,
      monto: this.monto,
      moneda: this.moneda,
      pagadoTipo: this.pagadoTipo,
      pagadoMiembro: this.pagador || this.yo(),
      proveedor: this.proveedor,
      descripcion: this.descripcion,
      reserva: this.reserva || null,
      vencimiento: this.vencimiento || null,
      tasa: this.otraMoneda() ? this.tasa : null,
    });
    if (res.error) {
      this.guardando.set(false);
      return this.mostrarError(res.error);
    }
    if (this.foto && res.datos) {
      const sub = await this.finanzas.subirEvidencia(g, u, 'gasto', res.datos, this.foto, 'factura');
      if (sub.error) this.mostrarError(sub.error);
    }
    this.monto = null;
    this.proveedor = '';
    this.descripcion = '';
    this.vencimiento = '';
    this.foto = null;
    this.guardando.set(false);
    this.abierto.set(false);
    await this.cargar();
  }

  async validar(g: GastoModel): Promise<void> {
    this.error.set(null);
    const r = await this.finanzas.validarGasto(g.id);
    if (r.error) this.mostrarError(r.error);
    await this.cargar();
  }

  async confirmarAccion(): Promise<void> {
    const a = this.accion();
    if (!a) return;
    this.error.set(null);
    const r =
      a.tipo === 'disputar'
        ? await this.finanzas.disputarGasto(a.id, this.motivo)
        : await this.finanzas.anularGasto(a.id, this.motivo);
    if (r.error) return this.mostrarError(r.error);
    this.accion.set(null);
    this.motivo = '';
    await this.cargar();
  }
}
