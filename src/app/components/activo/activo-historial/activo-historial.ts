import { Component, OnChanges, SimpleChanges, signal } from '@angular/core';
import { Icono } from '../../../../shared/ui/icono/icono';
import { EntradaHistorial } from '../../../../shared/models/activo-entidad.model';
import { idioma } from '../../../core/i18n/i18n';
import { ActivoSeccion } from '../activo-seccion';

/** Historial del activo: quién cambió qué y cuándo (desde la auditoría inmutable), legible para los socios. */
@Component({
  selector: 'app-activo-historial',
  standalone: true,
  imports: [Icono],
  templateUrl: './activo-historial.html',
})
export class ActivoHistorial extends ActivoSeccion implements OnChanges {
  entradas = signal<EntradaHistorial[] | null>(null);
  error = signal(false);

  async ngOnChanges(ch: SimpleChanges): Promise<void> {
    // se recarga al abrir la pestaña y cada vez que el detalle cambia (después de guardar algo)
    if (!ch['d']) return;
    const r = await this.activos.historial(this.d.activo.id);
    this.error.set(!!r.error);
    this.entradas.set(r.datos ?? []);
  }

  frase(e: EntradaHistorial): string {
    const base = this.tx(`activo.h.${e.accion}`, { actor: e.actor, que: this.tx(`activo.h.tabla.${e.tabla}`) });
    return e.titulo ? `${base} «${e.titulo.length > 60 ? e.titulo.slice(0, 57) + '…' : e.titulo}»` : base;
  }

  icono(e: EntradaHistorial): string {
    return e.accion === 'INSERT' ? 'mas' : e.accion === 'DELETE' ? 'papelera' : 'lapiz';
  }

  campo(c: string): string {
    const k = `activo.h.campo.${c}`;
    const v = this.tx(k);
    return v === k ? c.replaceAll('_', ' ') : v;
  }

  valor(v: unknown): string {
    if (v === null || v === undefined || v === '') return '—';
    if (typeof v === 'boolean') return v ? this.t('activo.si') : this.t('activo.no');
    if (typeof v === 'object') return JSON.stringify(v).slice(0, 80);
    const s = String(v);
    return s.length > 80 ? `${s.slice(0, 77)}…` : s;
  }

  cuando(iso: string): string {
    return new Date(iso).toLocaleString(idioma() === 'en' ? 'en-US' : 'es-DO', { dateStyle: 'medium', timeStyle: 'short' });
  }
}
