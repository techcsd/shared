import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DisputaMensaje, DisputaModel } from '../../../shared/models/p4.model';
import { GobiernoService } from '../../core/gobierno.service';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { t } from '../../core/i18n/i18n';
import { claveError } from '../../core/reserva.service';

/** Desacuerdos (SA34): hilo directo; a los N días sin acuerdo se puede invitar a un mediador (solo lectura del caso). */
@Component({
  selector: 'app-disputas',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './disputas.html',
  styleUrl: '../p4-comun.scss',
})
export class DisputasPage implements OnInit {
  t = t;
  lista = signal<DisputaModel[]>([]);
  abierta = signal<string | null>(null);
  mensajes = signal<DisputaMensaje[]>([]);
  enlace = signal<string | null>(null);
  error = signal<string | null>(null);
  titulo = '';
  texto = '';
  mensaje = '';
  correo = '';
  nota = '';

  constructor(
    public grupos: GrupoService,
    private gob: GobiernoService,
  ) {}

  async ngOnInit(): Promise<void> {
    await this.cargar();
  }

  async cargar(): Promise<void> {
    this.lista.set(await this.gob.disputas());
    const a = this.abierta();
    if (a) this.mensajes.set(await this.gob.mensajesDisputa(a));
  }

  private async ejecutar(r: Promise<{ error: string | null }>): Promise<boolean> {
    this.error.set(null);
    const res = await r;
    if (res.error) this.error.set(res.error.includes('mediador_aun_no') ? t('dis.mediador_aun_no') : t(claveError(res.error) as ClaveI18n));
    await this.cargar();
    return !res.error;
  }

  async abrirNueva(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g || this.titulo.trim().length < 3) return;
    if (await this.ejecutar(this.gob.abrirDisputa(g, this.titulo, this.texto))) this.titulo = this.texto = '';
  }

  async ver(d: DisputaModel): Promise<void> {
    this.abierta.set(d.id);
    this.enlace.set(null);
    this.mensajes.set(await this.gob.mensajesDisputa(d.id));
  }

  async enviar(): Promise<void> {
    const a = this.abierta();
    if (!a || !this.mensaje.trim()) return;
    if (await this.ejecutar(this.gob.mensajeDisputa(a, this.mensaje))) this.mensaje = '';
  }

  async invitar(): Promise<void> {
    const a = this.abierta();
    if (!a) return;
    this.error.set(null);
    const r = await this.gob.invitarMediador(a, this.correo);
    if (r.error) {
      this.error.set(r.error.includes('mediador_aun_no') ? t('dis.mediador_aun_no') : t(claveError(r.error) as ClaveI18n));
      return;
    }
    this.enlace.set(`${location.origin}/mediar/${r.datos}`);
    this.correo = '';
    await this.cargar();
  }

  cerrar(resultado: 'acuerdo' | 'sin_acuerdo'): Promise<boolean> {
    return this.ejecutar(this.gob.cerrarDisputa(this.abierta()!, resultado, this.nota));
  }
}
