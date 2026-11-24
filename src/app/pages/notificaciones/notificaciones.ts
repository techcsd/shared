import { Component, OnInit } from '@angular/core';
import { Router } from '@angular/router';
import { NotificacionService } from '../../core/notificacion.service';
import { t } from '../../core/i18n/i18n';
import { NotificacionModel } from '../../../shared/models/reserva.model';

/** Notificaciones in-app (Realtime). */
@Component({
  selector: 'app-notificaciones',
  standalone: true,
  templateUrl: './notificaciones.html',
  styleUrl: './notificaciones.scss',
})
export class NotificacionesPage implements OnInit {
  t = t;
  constructor(
    public notif: NotificacionService,
    private router: Router,
  ) {}

  ngOnInit(): void {
    this.notif.iniciar();
    void this.notif.cargar();
  }

  fecha(s: string): string {
    return new Date(s).toLocaleString();
  }

  async abrir(n: NotificacionModel): Promise<void> {
    await this.notif.marcarLeida(n.id);
    const rid = n.datos['reserva_id'];
    if (n.tipo.startsWith('prioridad_911')) await this.router.navigateByUrl('/mas/prioridad-911');
    else if (typeof rid === 'string') await this.router.navigate(['/reserva', rid]);
  }
}
