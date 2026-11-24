import { Component, OnInit, computed, signal, Input } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { ActivoSeleccionService } from '../../core/activo-seleccion.service';
import { ConfiguracionService } from '../../core/configuracion.service';
import { claveDia, fechaHoraZona, instanteDesdeZona, sumarDias } from '../../core/fechas';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { idioma, t } from '../../core/i18n/i18n';
import { MetricasService } from '../../core/metricas.service';
import { ReservaService, claveError } from '../../core/reserva.service';
import { DestinoModel } from '../../../shared/models/config.model';
import { MiembroModel } from '../../../shared/models/grupo.model';
import { ReservaModel, UsoReserva, parseRango } from '../../../shared/models/reserva.model';

/** Reservar en pocos pasos (SA1: < 1 min). El borrador se guarda 24 h; confirmar es instantáneo (SA3, DF-14). */
@Component({
  selector: 'app-reservar',
  standalone: true,
  imports: [FormsModule, RouterLink, DecimalPipe],
  templateUrl: './reservar.html',
  styleUrl: './reservar.scss',
})
export class ReservarPage implements OnInit {
  t = t;
  @Input() fecha = ''; // viene de ?fecha= (withComponentInputBinding)
  paso = signal(1);
  inicioMs = Date.now();
  ocupado = signal(false);
  error = signal<string | null>(null);

  diaSalida = '';
  horaSalida = '08:00';
  diaRegreso = '';
  horaRegreso = '16:00';
  uso: UsoReserva = 'personal';
  destino = '';
  personas = 2;
  responsable = '';
  invitadoNombre = '';
  invitadoCorreo = '';
  anfitrion = '';

  usos: UsoReserva[] = ['personal', 'familiar', 'negocios', 'invitado'];
  destinos = signal<DestinoModel[]>([]);
  miembros = signal<MiembroModel[]>([]);
  capacidad = signal<number | null>(null);
  fee = signal<{ monto: number; moneda: string } | null>(null);
  borradorId = signal<string | null>(null);
  borradores = signal<ReservaModel[]>([]);

  tz = computed(() => this.grupos.grupo()?.zona_horaria ?? 'America/Santo_Domingo');
  socios = computed(() =>
    this.miembros().filter((m) => m.rol === 'socio' && m.estado === 'activo'),
  );
  excede = computed(() => this.capacidad() !== null && this.personas > (this.capacidad() ?? 0));

  constructor(
    public grupos: GrupoService,
    public activos: ActivoSeleccionService,
    private reservas: ReservaService,
    private config: ConfiguracionService,
    private metricas: MetricasService,
    private router: Router,
  ) {}

  async ngOnInit(): Promise<void> {
    const hoy = claveDia(new Date(), this.tz());
    this.diaSalida = this.fecha && this.fecha >= hoy ? this.fecha : hoy;
    this.diaRegreso = this.diaSalida;
    const g = this.grupos.grupo()?.id;
    const yo = this.grupos.activa()?.id ?? '';
    this.responsable = yo;
    this.anfitrion = yo;
    await this.activos.cargar();
    if (g) {
      const [d, m, b] = await Promise.all([
        this.config.destinos(g),
        this.grupos.miembros(g),
        this.reservas.misReservas(g, yo),
      ]);
      this.destinos.set(d.filter((x) => x.activo));
      this.miembros.set(m);
      this.borradores.set(
        b.filter(
          (r) =>
            r.estado === 'borrador' &&
            r.borrador_expira_en &&
            new Date(r.borrador_expira_en) > new Date(),
        ),
      );
      if (this.destinos().length) this.destino = this.destinos()[0].id;
    }
    await this.actualizarCapacidad();
  }

  get inicio(): Date {
    return instanteDesdeZona(this.diaSalida, this.horaSalida, this.tz());
  }
  get fin(): Date {
    return instanteDesdeZona(this.diaRegreso, this.horaRegreso, this.tz());
  }

  usoTexto(u: UsoReserva): string {
    switch (u) {
      case 'personal':
        return t('uso.personal');
      case 'familiar':
        return t('uso.familiar');
      case 'negocios':
        return t('uso.negocios');
      case 'invitado':
        return t('uso.invitado');
    }
  }

  fechaHora(d: Date): string {
    return fechaHoraZona(d, this.tz(), idioma());
  }

  async actualizarCapacidad(): Promise<void> {
    const a = this.activos.activo();
    if (!a) return;
    this.capacidad.set(await this.reservas.capacidad(a.id, this.uso));
  }

  async elegirUso(u: UsoReserva): Promise<void> {
    this.uso = u;
    await this.actualizarCapacidad();
  }

  pasoValido(): boolean {
    switch (this.paso()) {
      case 1:
        return !!this.diaSalida && !!this.diaRegreso && this.fin > this.inicio;
      case 2:
        return !!this.uso;
      default:
        return (
          this.personas >= 1 &&
          !this.excede() &&
          (this.uso !== 'invitado' ||
            (this.invitadoNombre.trim().length > 1 && /\S+@\S+/.test(this.invitadoCorreo)))
        );
    }
  }

  siguiente(): void {
    if (this.pasoValido() && this.paso() < 3) this.paso.update((p) => p + 1);
  }

  async atras(): Promise<void> {
    if (this.paso() === 4) await this.descartarBorrador();
    this.paso.update((p) => Math.max(1, p - 1));
  }

  /** Paso 3 → 4: crea el borrador (la base valida políticas y capacidad) y muestra el resumen con fee. */
  async verResumen(): Promise<void> {
    const a = this.activos.activo();
    const g = this.grupos.grupo()?.id;
    if (!a || !g || !this.pasoValido()) return;
    this.ocupado.set(true);
    this.error.set(null);
    const r = await this.reservas.crearBorrador({
      activo: a.id,
      inicio: this.inicio,
      fin: this.fin,
      uso: this.uso,
      destino: this.destino || null,
      personas: Number(this.personas),
      responsableMiembro: this.uso === 'invitado' ? null : this.responsable || null,
      invitadoNombre: this.invitadoNombre,
      invitadoCorreo: this.invitadoCorreo,
      anfitrion: this.anfitrion || null,
    });
    if (r.error || !r.datos) {
      this.ocupado.set(false);
      this.error.set(t(claveError(r.error ?? '') as ClaveI18n));
      return;
    }
    this.borradorId.set(r.datos);
    this.fee.set(await this.reservas.feeEstimado(g, this.destino || null, this.inicio, this.fin));
    this.ocupado.set(false);
    this.paso.set(4);
  }

  async confirmar(): Promise<void> {
    const id = this.borradorId();
    const g = this.grupos.grupo()?.id ?? null;
    if (!id) return;
    this.ocupado.set(true);
    this.error.set(null);
    const r = await this.reservas.confirmar(id);
    if (r.error) {
      this.ocupado.set(false);
      this.error.set(t(claveError(r.error) as ClaveI18n));
      return;
    }
    // métrica de la meta «< 1 min» (SA1): del inicio del asistente a la confirmación
    void this.metricas.registrar('reserva_asistente_ms', g, Date.now() - this.inicioMs, {
      uso: this.uso,
      orden: r.datos,
    });
    await this.router.navigate(['/reserva', id]);
  }

  async descartarBorrador(): Promise<void> {
    const id = this.borradorId();
    if (id) await this.reservas.cancelar(id, '');
    this.borradorId.set(null);
  }

  /** Retomar un borrador guardado (24 h): salta al resumen. */
  async retomar(b: ReservaModel): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    const { inicio, fin } = parseRango(b.rango);
    this.diaSalida = claveDia(inicio, this.tz());
    this.diaRegreso = claveDia(fin, this.tz());
    this.uso = b.uso ?? 'personal';
    this.personas = b.personas ?? 1;
    this.destino = b.destino_id ?? '';
    this.borradorId.set(b.id);
    this.fee.set(await this.reservas.feeEstimado(g, b.destino_id, inicio, fin));
    await this.actualizarCapacidad();
    this.paso.set(4);
  }

  async descartar(b: ReservaModel): Promise<void> {
    await this.reservas.cancelar(b.id, '');
    this.borradores.update((l) => l.filter((x) => x.id !== b.id));
  }

  resumenInicio(): string {
    const id = this.borradorId();
    const b = this.borradores().find((x) => x.id === id);
    const { inicio, fin } = b ? parseRango(b.rango) : { inicio: this.inicio, fin: this.fin };
    return `${this.fechaHora(inicio)} → ${this.fechaHora(fin)}`;
  }

  mismoDia(): void {
    if (this.diaRegreso < this.diaSalida) this.diaRegreso = this.diaSalida;
  }

  mañana(): void {
    this.diaSalida = sumarDias(claveDia(new Date(), this.tz()), 1);
    this.diaRegreso = this.diaSalida;
  }
}
