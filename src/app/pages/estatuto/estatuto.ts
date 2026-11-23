import { Component, OnInit, computed, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/auth.service';
import { GrupoService } from '../../core/grupo.service';
import { t } from '../../core/i18n/i18n';
import { PoliticaService, PoliticaVigente } from '../../core/politica.service';
import { PoliticaCatalogo } from '../../core/politicas-catalogo';
import { validarPolitica } from '../../core/validar';
import { AcuseModel, VersionEstatutoModel } from '../../../shared/models/config.model';
import { MiembroModel } from '../../../shared/models/grupo.model';

/** Estatuto del grupo: políticas vigentes, propuestas pendientes y acuses de cada socio (no es firma legal). */
@Component({
  selector: 'app-estatuto',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './estatuto.html',
  styleUrl: './estatuto.scss',
})
export class EstatutoPage implements OnInit {
  t = t;
  politicas = signal<PoliticaVigente[]>([]);
  versiones = signal<VersionEstatutoModel[]>([]);
  acuses = signal<AcuseModel[]>([]);
  miembros = signal<MiembroModel[]>([]);
  cargando = signal(true);
  error = signal<string | null>(null);
  mensaje = signal<string | null>(null);

  /** Borrador de cambios (clave → valor ya parseado) y errores de validación por clave. */
  borrador = signal<Record<string, unknown>>({});
  erroresCampo = signal<Record<string, string>>({});
  motivo = '';

  categorias = computed(() => {
    const grupos = new Map<string, PoliticaVigente[]>();
    for (const p of this.politicas()) {
      grupos.set(p.def.categoria, [...(grupos.get(p.def.categoria) ?? []), p]);
    }
    return [...grupos.entries()].map(([nombre, items]) => ({ nombre, items }));
  });
  pendiente = computed(() => this.versiones().find((v) => v.estado === 'pendiente') ?? null);
  vigente = computed(() => this.versiones().find((v) => v.estado === 'vigente') ?? null);
  hayBorrador = computed(() => Object.keys(this.borrador()).length > 0);
  hayErrores = computed(() => Object.keys(this.erroresCampo()).length > 0);

  constructor(
    public grupos: GrupoService,
    private politica: PoliticaService,
    private auth: AuthService,
  ) {}

  async ngOnInit(): Promise<void> {
    await this.recargar();
  }

  async recargar(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g) return;
    this.cargando.set(true);
    const [pol, ver, acu, mie] = await Promise.all([
      this.politica.vigentes(g),
      this.politica.versiones(g),
      this.politica.acuses(g),
      this.grupos.miembros(g),
    ]);
    this.politicas.set(pol);
    this.versiones.set(ver);
    this.acuses.set(acu);
    this.miembros.set(mie);
    this.cargando.set(false);
  }

  etiqueta(clave: string): string {
    return this.politica.definicion(clave)?.etiqueta ?? clave;
  }

  mostrar(v: unknown): string {
    if (v === null || v === undefined) return '—';
    if (typeof v === 'boolean') return v ? t('estatuto.si') : t('estatuto.no');
    if (Array.isArray(v)) return v.join(', ');
    return String(v);
  }

  textoLista(v: unknown): string {
    return Array.isArray(v) ? v.join(', ') : '';
  }

  valorActual(p: PoliticaVigente): unknown {
    const b = this.borrador();
    return p.def.clave in b ? b[p.def.clave] : p.valor;
  }

  /** Interpreta lo escrito en la pantalla, valida contra el catálogo y actualiza el borrador. */
  cambiar(p: PoliticaVigente, crudo: string | boolean): void {
    const def: PoliticaCatalogo = p.def;
    let valor: unknown;
    switch (def.tipo) {
      case 'booleano':
        valor = Boolean(crudo);
        break;
      case 'entero':
      case 'numero':
        valor = String(crudo).trim() === '' ? null : Number(crudo);
        break;
      case 'lista':
        valor = String(crudo)
          .split(',')
          .map((s) => s.trim())
          .filter((s) => s !== '')
          .map((s) => (def.opciones ? s : Number(s)));
        break;
      default:
        valor = crudo;
    }
    const errores = { ...this.erroresCampo() };
    const nuevo = { ...this.borrador() };
    const problema = validarPolitica(def, valor);
    if (JSON.stringify(valor) === JSON.stringify(p.valor)) {
      delete nuevo[def.clave];
      delete errores[def.clave];
    } else if (problema) {
      errores[def.clave] = problema;
      delete nuevo[def.clave];
    } else {
      nuevo[def.clave] = valor;
      delete errores[def.clave];
    }
    this.borrador.set(nuevo);
    this.erroresCampo.set(errores);
  }

  async proponer(): Promise<void> {
    const g = this.grupos.grupo()?.id;
    if (!g || !this.hayBorrador() || this.hayErrores()) return;
    this.error.set(null);
    const err = await this.politica.proponer(g, this.borrador(), this.motivo);
    if (err) {
      this.error.set(err);
      return;
    }
    this.borrador.set({});
    this.motivo = '';
    this.mensaje.set(t('estatuto.propuesta_creada'));
    await this.recargar();
  }

  async responder(v: VersionEstatutoModel, acepta: boolean): Promise<void> {
    this.error.set(null);
    const err = await this.politica.responder(v.id, acepta);
    if (err) this.error.set(err);
    await this.recargar();
  }

  async retirar(v: VersionEstatutoModel): Promise<void> {
    const err = await this.politica.retirar(v.id);
    if (err) this.error.set(err);
    await this.recargar();
  }

  socios(): MiembroModel[] {
    return this.miembros().filter((m) => m.rol === 'socio' && m.estado === 'activo');
  }

  acepto(v: VersionEstatutoModel, m: MiembroModel): boolean | null {
    const a = this.acuses().find((x) => x.version_id === v.id && x.miembro_id === m.id);
    return a ? a.acepta : null;
  }

  yaRespondi(v: VersionEstatutoModel): boolean {
    const yo = this.miembros().find((m) => m.usuario_id === this.auth.usuario()?.id);
    return !!yo && this.acuse(v, yo) !== null;
  }

  private acuse(v: VersionEstatutoModel, m: MiembroModel): boolean | null {
    return this.acepto(v, m);
  }

  esMio(v: VersionEstatutoModel): boolean {
    return v.propuesta_por === this.auth.usuario()?.id;
  }

  cambiosTexto(v: VersionEstatutoModel): { clave: string; valor: string }[] {
    return Object.entries(v.cambios).map(([clave, valor]) => ({
      clave: this.etiqueta(clave),
      valor: this.mostrar(valor),
    }));
  }
}
