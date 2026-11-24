import { Component, OnInit, signal, Input } from '@angular/core';
import { fechaHoraZona } from '../../core/fechas';
import { ENV } from '../../core/env.generated';
import { idioma, t } from '../../core/i18n/i18n';

interface VistaInvitado {
  activo: string;
  invitado: string;
  personas: number;
  inicio: string;
  fin: string;
  zona_horaria: string;
  destino: string | null;
  punto_encuentro: string | null;
  reglas: string | null;
  contacto: string | null;
}

/** Página pública del invitado (sin cuenta): solo fecha, horario, punto de encuentro, reglas y contacto (SC8). */
@Component({
  selector: 'app-invitado',
  standalone: true,
  templateUrl: './invitado.html',
  styleUrl: './invitado.scss',
})
export class InvitadoPage implements OnInit {
  t = t;
  @Input() token = ''; // de la ruta /g/:token
  cargando = signal(true);
  vista = signal<VistaInvitado | null>(null);
  error = signal<string | null>(null);

  async ngOnInit(): Promise<void> {
    try {
      const r = await fetch(
        `${ENV.supabaseUrl}/functions/v1/guest-view?token=${encodeURIComponent(this.token)}`,
      );
      if (r.ok) this.vista.set((await r.json()) as VistaInvitado);
      else if (r.status === 429) this.error.set(t('inv.demasiados'));
      else this.error.set(t('inv.no_encontrado'));
    } catch {
      this.error.set(t('app.error.generico'));
    }
    this.cargando.set(false);
  }

  fh(s: string, tz: string): string {
    return fechaHoraZona(new Date(s), tz, idioma());
  }
}
