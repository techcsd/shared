import { Component, OnInit, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { ActivoTarjeta } from '../../../shared/components/activo-tarjeta/activo-tarjeta';
import { Vitrina, VitrinaActivo } from '../../../shared/models/activo.model';
import { ActivoService } from '../../core/activo.service';
import { GrupoService } from '../../core/grupo.service';
import { t } from '../../core/i18n/i18n';

interface Dato {
  etiqueta: string;
  valor: string;
}

/** «Nuestro activo»: foto o ícono, descripción y todos los datos del activo del grupo. */
@Component({
  selector: 'app-activo',
  standalone: true,
  imports: [RouterLink, ActivoTarjeta],
  templateUrl: './activo.html',
  styleUrl: './activo.scss',
})
export class ActivoPage implements OnInit {
  t = t;
  vitrina = signal<Vitrina | null>(null);
  cargando = signal(true);
  error = signal<string | null>(null);

  constructor(
    public grupos: GrupoService,
    private activos: ActivoService,
  ) {}

  async ngOnInit(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) {
      this.cargando.set(false);
      return;
    }
    const r = await this.activos.vitrina(g);
    this.cargando.set(false);
    if (r.error || !r.datos) this.error.set(t('app.error.generico'));
    else this.vitrina.set(r.datos);
  }

  /** Datos propios del tipo (matrícula, eslora…) con las etiquetas de la definición del tipo. */
  datos(a: VitrinaActivo): Dato[] {
    const salida: Dato[] = [];
    for (const campo of a.tipo.definicion.campos ?? []) {
      const v = a.valores[campo.clave];
      if (v === undefined || v === null || v === '') continue;
      const texto = typeof v === 'boolean' ? (v ? t('activo.si') : t('activo.no')) : String(v);
      salida.push({ etiqueta: campo.etiqueta, valor: campo.unidad ? `${texto} ${campo.unidad}` : texto });
    }
    return salida;
  }

  /** Cuenta los componentes por etiqueta: «Motor ×2». */
  componentes(a: VitrinaActivo): string[] {
    const cuenta = new Map<string, number>();
    for (const c of a.componentes) cuenta.set(c.etiqueta, (cuenta.get(c.etiqueta) ?? 0) + 1);
    return [...cuenta.entries()].map(([e, n]) => (n > 1 ? `${e} ×${n}` : e));
  }

  dinero(monto: number | null, moneda: string): string {
    if (monto === null || monto === undefined) return '—';
    return `${Number(monto).toLocaleString('en-US', { maximumFractionDigits: 2 })} ${moneda}`;
  }

  estadoTexto(e: VitrinaActivo['estado']): string {
    return t(`activos.estado.${e}`);
  }
}
