import { Component, Input, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DisputaMensaje, DisputaModel } from '../../../shared/models/p4.model';
import { GobiernoService } from '../../core/gobierno.service';
import { t } from '../../core/i18n/i18n';

/** Vista del mediador (SA34): solo lectura del caso al que fue invitado + sus propios mensajes. Nada más del grupo. */
@Component({
  selector: 'app-mediar',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './mediar.html',
  styleUrl: '../p4-comun.scss',
})
export class MediarPage implements OnInit {
  t = t;
  @Input() token = '';
  caso = signal<DisputaModel | null>(null);
  mensajes = signal<DisputaMensaje[]>([]);
  error = signal<string | null>(null);
  mensaje = '';

  constructor(private gob: GobiernoService) {}

  async ngOnInit(): Promise<void> {
    const r = await this.gob.aceptarMediacion(this.token);
    if (r.error) {
      // ya aceptada antes (o cerrada): se intenta mostrar lo que RLS permita
      this.error.set(t('dis.mediacion_invalida'));
    }
    await this.cargar();
  }

  async cargar(): Promise<void> {
    const lista = await this.gob.disputas();
    this.caso.set(lista[0] ?? null);
    if (lista[0]) {
      this.error.set(null);
      this.mensajes.set(await this.gob.mensajesDisputa(lista[0].id));
    }
  }

  async enviar(): Promise<void> {
    const c = this.caso();
    if (!c || !this.mensaje.trim()) return;
    const r = await this.gob.mensajeDisputa(c.id, this.mensaje);
    if (r.error) this.error.set(t('dis.mediacion_invalida'));
    this.mensaje = '';
    await this.cargar();
  }
}
