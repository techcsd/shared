import { DecimalPipe } from '@angular/common';
import { Component, OnInit, computed, signal, Input } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { fechaHoraZona } from '../../core/fechas';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { idioma, t } from '../../core/i18n/i18n';
import { PoliticaService } from '../../core/politica.service';
import { ReservaModel, EventoAuditoria, parseRango } from '../../../shared/models/reserva.model';
import { MiembroModel } from '../../../shared/models/grupo.model';
import { ReservaService, claveError } from '../../core/reserva.service';

interface LineaTiempo {
  momento: string;
  texto: string;
}

/** Detalle de orden: cronología (auditoría), avisos/acuses, costos y acciones (SA17). */
@Component({
  selector: 'app-reserva-detalle',
  standalone: true,
  imports: [FormsModule, RouterLink, DecimalPipe],
  templateUrl: './reserva-detalle.html',
  styleUrl: './reserva-detalle.scss',
})
export class ReservaDetallePage implements OnInit {
  t = t;
  @Input() id = ''; // viene de la ruta (withComponentInputBinding)
  reserva = signal<Awaited<ReturnType<ReservaService['detalle']>>>(null);
  miembros = signal<MiembroModel[]>([]);
  acuses = signal<{ miembro_id: string; momento: string }[]>([]);
  costo = signal<{ fee: number; moneda: string } | null>(null);
  eventos = signal<EventoAuditoria[]>([]);
  cargando = signal(true);
  error = signal<string | null>(null);
  confirmandoCancelar = signal(false);
  motivoCancelacion = '';
  horasSinCargo = signal(48);
  pctTardio = signal(0);

  tz = computed(() => this.grupos.grupo()?.zona_horaria ?? 'America/Santo_Domingo');
  yo = computed(() => this.grupos.activa()?.id ?? null);
  esTitular = computed(() => this.reserva()?.reservado_por === this.yo());
  rango = computed(() => (this.reserva() ? parseRango(this.reserva()!.rango) : null));
  vigente = computed(() => ['confirmada', 'en_curso'].includes(this.reserva()?.estado ?? ''));
  socios = computed(() =>
    this.miembros().filter((m) => m.rol === 'socio' && m.estado === 'activo'),
  );
  yaEnterado = computed(() => this.acuses().some((a) => a.miembro_id === this.yo()));
  puedeEnterado = computed(
    () => this.grupos.esSocio() && !this.esTitular() && this.vigente() && !this.yaEnterado(),
  );
  puede911 = computed(
    () => this.grupos.esSocio() && !this.esTitular() && this.reserva()?.estado === 'confirmada',
  );
  puedeOperar = computed(
    () => this.esTitular() || ['admin_operativo', 'capitan'].includes(this.grupos.rol() ?? ''),
  );

  /** Cargo que se verá antes de confirmar la cancelación (DF-09). */
  previsualizacion = computed(() => {
    const r = this.reserva();
    const rg = this.rango();
    if (!r || !rg || r.estado !== 'confirmada') return { tardia: false, cargo: 0 };
    const limite = rg.inicio.getTime() - this.horasSinCargo() * 3600000;
    const tardia = Date.now() > limite;
    const fee = this.costo()?.fee ?? 0;
    return { tardia, cargo: tardia ? Math.round(fee * this.pctTardio()) / 100 : 0 };
  });

  linea = computed<LineaTiempo[]>(() =>
    this.eventos().map((e) => ({
      momento: fechaHoraZona(new Date(e.momento), this.tz(), idioma()),
      texto: this.textoEvento(e),
    })),
  );

  constructor(
    public grupos: GrupoService,
    private reservas: ReservaService,
    private politicas: PoliticaService,
    private router: Router,
  ) {}

  async ngOnInit(): Promise<void> {
    await this.cargar();
  }

  async cargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    const r = await this.reservas.detalle(this.id);
    this.reserva.set(r);
    if (g) this.miembros.set(await this.grupos.miembros(g));
    if (r) {
      this.acuses.set(await this.reservas.acuses(r.id));
      if (this.grupos.esSocio()) {
        this.costo.set(await this.reservas.costo(r.id));
        this.eventos.set(await this.reservas.cronologia(r.id));
      }
      if (g) {
        this.horasSinCargo.set(
          Number(await this.politicas.valor(g, 'cancelacion.horas_sin_cargo')) || 48,
        );
        this.pctTardio.set(
          Number(await this.politicas.valor(g, 'cancelacion.cargo_tardio_pct')) || 0,
        );
      }
    }
    this.cargando.set(false);
  }

  nombre(id: string | null): string {
    const m = this.miembros().find((x) => x.id === id);
    return m?.perfil?.nombre ?? '—';
  }

  nombreUsuario(uid: string | null): string {
    const m = this.miembros().find((x) => x.usuario_id === uid);
    return m?.perfil?.nombre ?? t('det.sistema');
  }

  parseFecha(s: string): Date {
    return new Date(s);
  }

  fh(d: Date): string {
    return fechaHoraZona(d, this.tz(), idioma());
  }

  estadoTexto(e: ReservaModel['estado']): string {
    const mapa: Record<ReservaModel['estado'], ClaveI18n> = {
      borrador: 'estado.borrador',
      confirmada: 'estado.confirmada',
      en_curso: 'estado.en_curso',
      finalizada: 'estado.finalizada',
      cancelada: 'estado.cancelada',
      bloqueada_mantenimiento: 'estado.bloqueada',
    };
    return t(mapa[e]);
  }

  private textoEvento(e: EventoAuditoria): string {
    const quien = this.nombreUsuario(e.actor);
    if (e.tabla === 'ordenes')
      return t('det.ev.orden', { quien, codigo: String(e.despues?.['codigo'] ?? '') });
    if (e.tabla === 'reserva_acuses') {
      return t('det.ev.enterado', { quien: this.nombre(String(e.despues?.['miembro_id'] ?? '')) });
    }
    if (e.accion === 'INSERT') return t('det.ev.creada', { quien });
    const antes = String(e.antes?.['estado'] ?? '');
    const despues = String(e.despues?.['estado'] ?? '');
    if (antes !== despues) {
      return (
        t('det.ev.estado', {
          quien,
          desde: this.estadoTexto(antes as ReservaModel['estado']),
          hasta: this.estadoTexto(despues as ReservaModel['estado']),
        }) + (e.motivo ? ` — ${e.motivo}` : '')
      );
    }
    return t('det.ev.edicion', { quien });
  }

  async enterado(): Promise<void> {
    this.error.set(null);
    const err = await this.reservas.marcarEnterado(this.id);
    if (err) this.error.set(t(claveError(err) as ClaveI18n));
    await this.cargar();
  }

  async cancelar(): Promise<void> {
    this.error.set(null);
    const r = await this.reservas.cancelar(this.id, this.motivoCancelacion);
    if (r.error) {
      this.error.set(t(claveError(r.error) as ClaveI18n));
      return;
    }
    this.confirmandoCancelar.set(false);
    await this.cargar();
  }

  async cambiar(accion: 'iniciar' | 'finalizar'): Promise<void> {
    this.error.set(null);
    const err =
      accion === 'iniciar'
        ? await this.reservas.iniciar(this.id)
        : await this.reservas.finalizar(this.id);
    if (err) this.error.set(t(claveError(err) as ClaveI18n));
    await this.cargar();
  }

  volver(): void {
    void this.router.navigateByUrl('/calendario');
  }
}
