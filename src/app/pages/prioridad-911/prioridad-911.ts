import { Component, OnDestroy, OnInit, computed, signal, Input } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { RealtimeChannel } from '@supabase/supabase-js';
import { AuthService } from '../../core/auth.service';
import { fechaHoraZona, instanteDesdeZona, claveDia } from '../../core/fechas';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { idioma, t } from '../../core/i18n/i18n';
import { Prioridad911Service } from '../../core/prioridad911.service';
import { ReservaService, claveError } from '../../core/reserva.service';
import { MiembroModel } from '../../../shared/models/grupo.model';
import {
  Estado911,
  Mensaje911Model,
  Motivo911,
  ReservaModel,
  Solicitud911Model,
  Urgencia911,
  parseRango,
} from '../../../shared/models/reserva.model';

/** Prioridad 911: pedir, nunca quitar (SA8). Solicitud, respuesta del titular e historial. */
@Component({
  selector: 'app-prioridad-911',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './prioridad-911.html',
  styleUrl: './prioridad-911.scss',
})
export class Prioridad911Page implements OnInit, OnDestroy {
  t = t;
  @Input() reserva = ''; // ?reserva= (withComponentInputBinding)
  solicitudes = signal<Solicitud911Model[]>([]);
  mensajes = signal<Mensaje911Model[]>([]);
  miembros = signal<MiembroModel[]>([]);
  objetivo = signal<(ReservaModel & { orden?: { codigo: string } | null }) | null>(null);
  error = signal<string | null>(null);
  mensaje = signal<string | null>(null);
  canal: RealtimeChannel | null = null;

  motivos: Motivo911[] = ['cumpleanos', 'evento_familiar', 'cliente', 'negocio'];
  urgencias: Urgencia911[] = ['baja', 'media', 'alta'];
  motivo: Motivo911 = 'evento_familiar';
  urgencia: Urgencia911 = 'media';
  alternativa = '';
  texto = '';
  personas = 2;

  // respuesta del titular
  respuestaTexto: Record<string, string> = {};
  contraDia: Record<string, string> = {};
  contraDesde: Record<string, string> = {};
  contraHasta: Record<string, string> = {};

  yo = computed(() => this.grupos.activa()?.id ?? null);
  tz = computed(() => this.grupos.grupo()?.zona_horaria ?? 'America/Santo_Domingo');

  constructor(
    public grupos: GrupoService,
    private svc: Prioridad911Service,
    private reservas: ReservaService,
    private auth: AuthService,
  ) {}

  async ngOnInit(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    this.miembros.set(await this.grupos.miembros(g));
    await this.cargar();
    this.canal = this.svc.suscribir(g, () => void this.cargar());
    if (this.reserva) {
      const r = await this.reservas.detalle(this.reserva);
      this.objetivo.set(r as never);
    }
  }

  ngOnDestroy(): void {
    this.svc.desuscribir(this.canal);
  }

  async cargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    const [s, m] = await Promise.all([this.svc.solicitudes(g), this.svc.mensajes(g)]);
    this.solicitudes.set(s);
    this.mensajes.set(m);
  }

  nombre(id: string | null): string {
    return this.miembros().find((m) => m.id === id)?.perfil?.nombre ?? '—';
  }

  rangoTxt(r: string): string {
    const { inicio, fin } = parseRango(r);
    return `${fechaHoraZona(inicio, this.tz(), idioma())} → ${fechaHoraZona(fin, this.tz(), idioma())}`;
  }

  fh(s: string): string {
    return fechaHoraZona(new Date(s), this.tz(), idioma());
  }

  mensajesDe(id: string): Mensaje911Model[] {
    return this.mensajes().filter((m) => m.solicitud_id === id);
  }

  esTitular(s: Solicitud911Model): boolean {
    return s.titular_id === this.yo();
  }
  esSolicitante(s: Solicitud911Model): boolean {
    return s.solicitante_id === this.yo();
  }

  estadoTexto(e: Estado911): string {
    const mapa: Record<Estado911, ClaveI18n> = {
      pendiente: 'p911.estado.pendiente',
      aceptada: 'p911.estado.aceptada',
      rechazada: 'p911.estado.rechazada',
      contrapropuesta: 'p911.estado.contrapropuesta',
      aceptada_contra: 'p911.estado.aceptada_contra',
      rechazada_contra: 'p911.estado.rechazada_contra',
      expirada: 'p911.estado.expirada',
    };
    return t(mapa[e]);
  }
  motivoTexto(m: Motivo911): string {
    const mapa: Record<Motivo911, ClaveI18n> = {
      cumpleanos: 'p911.motivo.cumpleanos',
      evento_familiar: 'p911.motivo.evento_familiar',
      cliente: 'p911.motivo.cliente',
      negocio: 'p911.motivo.negocio',
    };
    return t(mapa[m]);
  }
  urgenciaTexto(u: Urgencia911): string {
    const mapa: Record<Urgencia911, ClaveI18n> = {
      baja: 'p911.urgencia.baja',
      media: 'p911.urgencia.media',
      alta: 'p911.urgencia.alta',
    };
    return t(mapa[u]);
  }
  tipoMensajeTexto(tipo: string): string {
    const mapa: Record<string, ClaveI18n> = {
      solicitud: 'p911.msg.solicitud',
      acepta: 'p911.msg.acepta',
      rechaza: 'p911.msg.rechaza',
      contrapropone: 'p911.msg.contrapropone',
      acepta_contra: 'p911.msg.acepta_contra',
      rechaza_contra: 'p911.msg.rechaza_contra',
      expiracion: 'p911.msg.expiracion',
    };
    return mapa[tipo] ? t(mapa[tipo]) : tipo;
  }

  private err(msg: string | null): boolean {
    if (!msg) return false;
    this.error.set(t(claveError(msg) as ClaveI18n));
    return true;
  }

  async solicitar(): Promise<void> {
    const o = this.objetivo();
    if (!o) return;
    this.error.set(null);
    const e = await this.svc.solicitar({
      reserva: o.id,
      motivo: this.motivo,
      urgencia: this.urgencia,
      alternativa: this.alternativa,
      uso: 'personal',
      personas: Number(this.personas),
      mensaje: this.texto,
    });
    if (this.err(e)) return;
    this.objetivo.set(null);
    this.mensaje.set(t('p911.enviada'));
    await this.cargar();
  }

  async responder(s: Solicitud911Model, accion: 'acepta' | 'rechaza'): Promise<void> {
    this.error.set(null);
    if (this.err(await this.svc.responder(s.id, accion, this.respuestaTexto[s.id] ?? ''))) return;
    await this.cargar();
  }

  async contraproponer(s: Solicitud911Model): Promise<void> {
    const dia = this.contraDia[s.id];
    if (!dia) return;
    this.error.set(null);
    const inicio = instanteDesdeZona(dia, this.contraDesde[s.id] || '08:00', this.tz());
    const fin = instanteDesdeZona(dia, this.contraHasta[s.id] || '16:00', this.tz());
    if (
      this.err(
        await this.svc.responder(s.id, 'contrapropone', this.respuestaTexto[s.id] ?? '', {
          inicio,
          fin,
        }),
      )
    )
      return;
    await this.cargar();
  }

  async responderContra(s: Solicitud911Model, acepta: boolean): Promise<void> {
    this.error.set(null);
    if (this.err(await this.svc.responderContra(s.id, acepta, this.respuestaTexto[s.id] ?? '')))
      return;
    await this.cargar();
  }

  hoy(): string {
    return claveDia(new Date(), this.tz());
  }
}
