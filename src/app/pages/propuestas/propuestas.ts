import { DecimalPipe } from '@angular/common';
import { Component, OnInit, computed, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import {
  AportePropuesta,
  FilaDirectorio,
  FormacionService,
  ParticipantePropuesta,
  PropuestaModel,
  TotalesPropuesta,
} from '../../core/formacion.service';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { t } from '../../core/i18n/i18n';
import { claveError } from '../../core/reserva.service';

/** Propuestas de compra (SB9, SC10): juntar un grupo para comprar un activo. La app NO custodia dinero: solo registra. */
@Component({
  selector: 'app-propuestas',
  standalone: true,
  imports: [FormsModule, DecimalPipe],
  templateUrl: './propuestas.html',
  styleUrl: '../p4-comun.scss',
})
export class PropuestasPage implements OnInit {
  t = t;
  tk = (k: string): string => t(k as ClaveI18n);
  lista = signal<PropuestaModel[]>([]);
  tipos = signal<{ id: string; nombre: string }[]>([]);
  abierta = signal<PropuestaModel | null>(null);
  totales = signal<TotalesPropuesta | null>(null);
  participantes = signal<ParticipantePropuesta[]>([]);
  aportes = signal<AportePropuesta[]>([]);
  directorio = signal<FilaDirectorio[]>([]);
  solicitudes = signal<{ id: string; usuario_id: string; mensaje: string | null; estado: string }[]>([]);
  dirHabilitado = signal(false);
  enlace = signal<string | null>(null);
  error = signal<string | null>(null);
  aviso = signal<string | null>(null);
  pestana = signal<'mias' | 'directorio'>('mias');

  titulo = '';
  tipo = '';
  descripcion = '';
  precio: number | null = null;
  moneda = 'DOP';
  fecha = '';
  cupos: number | null = null;
  compromiso: number | null = null;
  monto: number | null = null;
  notaAporte = '';
  notaAdquisicion = '';
  nombreGrupo = '';
  prefijo = '';
  motivo = '';
  mensajeSolicitud = '';

  yo = computed(() => this.auth.usuario()?.id ?? null);
  soyOrganizador = computed(() => this.abierta()?.organizador_id === this.yo());
  miParticipante = computed(() => this.participantes().find((p) => p.usuario_id === this.yo()) ?? null);
  misAportes = computed(() => this.aportes().filter((a) => a.participante_id === this.miParticipante()?.id));

  constructor(
    private form: FormacionService,
    private auth: AuthService,
    private router: Router,
    public grupos: GrupoService,
  ) {}

  async ngOnInit(): Promise<void> {
    this.tipos.set(await this.form.tiposSistema());
    this.tipo = this.tipos()[0]?.id ?? '';
    this.dirHabilitado.set(await this.form.directorioHabilitado());
    await this.cargar();
  }

  async cargar(): Promise<void> {
    this.lista.set(await this.form.propuestas());
    if (this.dirHabilitado()) this.directorio.set(await this.form.directorio());
    const a = this.abierta();
    if (a) await this.ver(this.lista().find((p) => p.id === a.id) ?? null);
  }

  private mostrarError(msg: string): void {
    this.error.set(msg.includes('demasiadas_solicitudes') ? t('prop.demasiadas') : t(claveError(msg) as ClaveI18n));
  }

  private async ejecutar(r: Promise<{ error: string | null }>): Promise<boolean> {
    this.error.set(null);
    this.aviso.set(null);
    const res = await r;
    if (res.error) this.mostrarError(res.error);
    await this.cargar();
    return !res.error;
  }

  async ver(p: PropuestaModel | null): Promise<void> {
    this.abierta.set(p);
    this.enlace.set(null);
    if (!p) return;
    this.totales.set(await this.form.totales(p.id));
    this.participantes.set(await this.form.participantes(p.id));
    this.aportes.set(await this.form.aportes(p.id));
    this.solicitudes.set(this.soyOrganizador() ? await this.form.solicitudes(p.id) : []);
  }

  async crear(): Promise<void> {
    this.error.set(null);
    if (this.titulo.trim().length < 3 || !this.precio || !this.tipo) return;
    const r = await this.form.crear({
      titulo: this.titulo, tipo: this.tipo, descripcion: this.descripcion, precio: this.precio,
      moneda: this.moneda, fecha: this.fecha || null, cupos: this.cupos,
    });
    if (r.error || !r.datos) return this.mostrarError(r.error ?? '');
    this.enlace.set(`${location.origin}/propuesta/${r.datos.token}`);
    this.titulo = this.descripcion = '';
    this.precio = null;
    await this.cargar();
  }

  abrir(p: PropuestaModel) { return this.ejecutar(this.form.abrir(p.id)); }
  comprometer(p: PropuestaModel) { return this.ejecutar(this.form.comprometer(p.id, this.compromiso ?? 0)); }
  async declarar(p: PropuestaModel): Promise<void> {
    if (await this.ejecutar(this.form.declarar(p.id, this.monto ?? 0, this.notaAporte))) this.monto = null;
  }
  confirmar(a: AportePropuesta, ok: boolean) { return this.ejecutar(this.form.confirmar(a.id, ok)); }
  acusarAporte(a: AportePropuesta) { return this.ejecutar(this.form.acusarAporte(a.id)); }
  reembolsar(a: AportePropuesta) { return this.ejecutar(this.form.reembolsar(a.id, this.motivo)); }
  registrarAdquisicion(p: PropuestaModel) { return this.ejecutar(this.form.registrarAdquisicion(p.id, this.notaAdquisicion)); }
  acusarAdquisicion(p: PropuestaModel) { return this.ejecutar(this.form.acusarAdquisicion(p.id)); }
  cancelar(p: PropuestaModel) { return this.ejecutar(this.form.cancelar(p.id, this.motivo)); }
  directorioVisible(p: PropuestaModel, v: boolean) { return this.ejecutar(this.form.visibleEnDirectorio(p.id, v)); }
  responder(id: string, ok: boolean) { return this.ejecutar(this.form.responderSolicitud(id, ok)); }
  solicitar(f: FilaDirectorio) { return this.ejecutar(this.form.solicitar(f.id, this.mensajeSolicitud)); }
  reportar(f: FilaDirectorio) { return this.ejecutar(this.form.reportar(f.id, this.motivo || 'Contenido sospechoso')); }

  async contrato(p: PropuestaModel, ev: Event): Promise<void> {
    const f = (ev.target as HTMLInputElement).files?.[0];
    if (!f) return;
    this.error.set(null);
    const r = await this.form.subirContrato(p.id, f);
    if (r.error) this.mostrarError(r.error);
    else this.aviso.set(t('prop.contrato_ok'));
  }

  async convertir(p: PropuestaModel): Promise<void> {
    this.error.set(null);
    const r = await this.form.convertir(p.id, this.nombreGrupo, this.prefijo);
    if (r.error) return this.mostrarError(r.error);
    await this.grupos.cargar();
    await this.router.navigateByUrl('/grupos');
  }

  nombreParticipante(id: string): string {
    return id === this.yo() ? t('gas.yo') : id.slice(0, 6);
  }

  participanteDe(a: AportePropuesta): string {
    const p = this.participantes().find((x) => x.id === a.participante_id);
    return p ? this.nombreParticipante(p.usuario_id) : '—';
  }
}
