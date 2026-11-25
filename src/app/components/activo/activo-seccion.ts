import { Directive, EventEmitter, Input, Output, signal } from '@angular/core';
import { DetalleActivo } from '../../../shared/models/activo-entidad.model';
import { ActivoService, errorActivo } from '../../core/activo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { idioma, t } from '../../core/i18n/i18n';
import { Resultado } from '../../core/reserva.service';
import { ToastService } from '../../core/toast.service';

/** Base de cada sección del activo: recibe el detalle, el modo de edición y avisa cuando algo cambió. */
@Directive()
export abstract class ActivoSeccion {
  t = t;
  @Input({ required: true }) d!: DetalleActivo;
  @Input() editando = false;
  @Output() cambio = new EventEmitter<void>();

  ocupado = signal(false);

  constructor(
    protected activos: ActivoService,
    protected toast: ToastService,
  ) {}

  /** Ejecuta una operación contra la base, avisa con un toast y pide recargar el detalle si salió bien. */
  protected async hacer(op: () => Promise<Resultado<unknown>>, ok = true): Promise<boolean> {
    this.ocupado.set(true);
    const r = await op();
    this.ocupado.set(false);
    if (r.error) {
      this.toast.error(errorActivo(r.error));
      return false;
    }
    if (ok) this.toast.ok(t('app.guardado'));
    this.cambio.emit();
    return true;
  }

  /** Traduce una clave construida en tiempo de ejecución (p. ej. «activo.cond.buena»). */
  tx(clave: string, params?: Record<string, string | number>): string {
    return t(clave as ClaveI18n, params);
  }

  errorTexto(e: string): string {
    return errorActivo(e);
  }

  /** Fecha corta legible (AAAA-MM-DD → «12 may 2026»). */
  fecha(iso: string | null | undefined): string {
    if (!iso) return '—';
    const d = new Date(iso.length === 10 ? `${iso}T12:00:00` : iso);
    return Number.isNaN(d.getTime()) ? iso : d.toLocaleDateString(idioma() === 'en' ? 'en-US' : 'es-DO', { day: 'numeric', month: 'short', year: 'numeric' });
  }

  dinero(monto: number | null | undefined, moneda: string | null | undefined): string {
    if (monto === null || monto === undefined) return '—';
    return `${Number(monto).toLocaleString('en-US', { maximumFractionDigits: 2 })} ${moneda ?? this.d.grupo.moneda}`;
  }
}
