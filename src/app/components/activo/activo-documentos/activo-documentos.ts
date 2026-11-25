import { Component, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Icono } from '../../../../shared/ui/icono/icono';
import { DocumentoActivo, TIPOS_DOCUMENTO, TipoDocumento } from '../../../../shared/models/activo-entidad.model';
import { ActivoSeccion } from '../activo-seccion';

/** Documentos del activo (matrícula, seguro, facturas, manuales…): archivo privado con URL firmada y vencimiento opcional. */
@Component({
  selector: 'app-activo-documentos',
  standalone: true,
  imports: [FormsModule, Icono],
  templateUrl: './activo-documentos.html',
})
export class ActivoDocumentos extends ActivoSeccion {
  tipos = TIPOS_DOCUMENTO;
  subiendo = signal(false);
  archivo: File | null = null;
  nuevo = { tipo: 'matricula' as TipoDocumento, titulo: '', emitido: '', vence: '', notas: '' };
  abriendo = signal<string | null>(null);

  /** Cuenta regresiva: ok, pronto (≤ 30 días) o vencido. */
  estadoVence(doc: DocumentoActivo): 'sin' | 'ok' | 'pronto' | 'vencido' {
    if (!doc.vence_en) return 'sin';
    const dias = this.dias(doc.vence_en);
    return dias < 0 ? 'vencido' : dias <= 30 ? 'pronto' : 'ok';
  }

  textoVence(doc: DocumentoActivo): string {
    if (!doc.vence_en) return '';
    const dias = this.dias(doc.vence_en);
    if (dias < 0) return this.t('activo.doc.vencido', { fecha: this.fecha(doc.vence_en) });
    if (dias === 0) return this.t('activo.doc.vence_hoy');
    return this.t('activo.doc.vence_en', { dias, fecha: this.fecha(doc.vence_en) });
  }

  private dias(iso: string): number {
    const hoy = new Date();
    hoy.setHours(0, 0, 0, 0);
    const v = new Date(`${iso}T00:00:00`);
    return Math.round((v.getTime() - hoy.getTime()) / 86_400_000);
  }

  tamano(b: number | null): string {
    if (!b) return '';
    return b >= 1_048_576 ? `${(b / 1_048_576).toFixed(1)} MB` : `${Math.max(1, Math.round(b / 1024))} KB`;
  }

  elegir(ev: Event): void {
    const input = ev.target as HTMLInputElement;
    this.archivo = input.files?.[0] ?? null;
    if (this.archivo && !this.nuevo.titulo.trim()) this.nuevo.titulo = this.archivo.name.replace(/\.[^.]+$/, '').slice(0, 120);
  }

  async subir(): Promise<void> {
    if (!this.archivo || this.nuevo.titulo.trim().length < 2) return;
    this.subiendo.set(true);
    const r = await this.activos.subirDocumento(this.d.activo.grupo_id, this.d.activo.id, this.archivo, {
      tipo: this.nuevo.tipo,
      titulo: this.nuevo.titulo.trim(),
      emitido_en: this.nuevo.emitido || null,
      vence_en: this.nuevo.vence || null,
      notas: this.nuevo.notas.trim() || null,
    });
    this.subiendo.set(false);
    if (r.error) {
      this.toast.error(this.errorTexto(r.error));
      return;
    }
    this.archivo = null;
    this.nuevo = { tipo: 'matricula', titulo: '', emitido: '', vence: '', notas: '' };
    this.toast.ok(this.t('app.guardado'));
    this.cambio.emit();
  }

  /** Abre el archivo con una URL firmada de 5 minutos (el bucket es privado). */
  async abrir(doc: DocumentoActivo): Promise<void> {
    this.abriendo.set(doc.id);
    const ventana = window.open('', '_blank');
    const url = await this.activos.urlDocumento(doc.ruta);
    this.abriendo.set(null);
    if (!url) {
      ventana?.close();
      this.toast.error(this.t('activo.e.doc_abrir'));
      return;
    }
    if (ventana) {
      ventana.opener = null;
      ventana.location.href = url;
    } else {
      window.location.href = url;
    }
  }

  async actualizarVence(doc: DocumentoActivo, valor: string): Promise<void> {
    const v = valor || null;
    if (v === doc.vence_en) return;
    await this.hacer(() => this.activos.guardarFila('activo_documentos', this.d.activo.grupo_id, this.d.activo.id, { vence_en: v }, doc.id));
  }

  async quitar(doc: DocumentoActivo): Promise<void> {
    await this.hacer(() => this.activos.borrarDocumento(doc));
  }
}
