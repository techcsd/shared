import { Component, OnInit, computed, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { fechaHoraZona } from '../../core/fechas';
import { GrupoService } from '../../core/grupo.service';
import { idioma, t } from '../../core/i18n/i18n';
import { ReservaService } from '../../core/reserva.service';
import { ReservaModel, codigoOrden, parseRango } from '../../../shared/models/reserva.model';

/** Mis salidas: próximas, borradores y historial de quien reserva. */
@Component({
  selector: 'app-mis-salidas',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './mis-salidas.html',
  styleUrl: './mis-salidas.scss',
})
export class MisSalidasPage implements OnInit {
  t = t;
  lista = signal<ReservaModel[]>([]);
  cargando = signal(true);
  tz = computed(() => this.grupos.grupo()?.zona_horaria ?? 'America/Santo_Domingo');
  proximas = computed(() =>
    this.lista().filter((r) => ['confirmada', 'en_curso'].includes(r.estado)),
  );
  borradores = computed(() =>
    this.lista().filter(
      (r) =>
        r.estado === 'borrador' &&
        r.borrador_expira_en &&
        new Date(r.borrador_expira_en) > new Date(),
    ),
  );
  historial = computed(() =>
    this.lista().filter((r) => ['finalizada', 'cancelada'].includes(r.estado)),
  );

  constructor(
    public grupos: GrupoService,
    private reservas: ReservaService,
  ) {}

  async ngOnInit(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    const yo = this.grupos.activa()?.id;
    if (g && yo) this.lista.set(await this.reservas.misReservas(g, yo));
    this.cargando.set(false);
  }

  cuando(r: ReservaModel): string {
    const { inicio, fin } = parseRango(r.rango);
    return `${fechaHoraZona(inicio, this.tz(), idioma())} → ${fechaHoraZona(fin, this.tz(), idioma())}`;
  }

  codigo(r: ReservaModel): string {
    return codigoOrden(r) ?? '—';
  }
}
