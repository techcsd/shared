import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { AdminBitacora, AdminGrupo, AdminMiembro, AdminService, AdminUsuario, RespuestaAdmin } from '../../core/admin.service';
import { t } from '../../core/i18n/i18n';
import { estadoGrupoTexto, rolTexto } from '../../core/i18n/textos';
import { ClaveI18n } from '../../core/i18n/es';
import { EstadoGrupo, RolMiembro } from '../../../shared/models/grupo.model';

type Pestana = 'usuarios' | 'grupos' | 'plataforma';

/** Panel de administración de la plataforma: usuarios, grupos y ajustes. Sin lógica de negocio: todo vive en la base y en la edge function. */
@Component({
  selector: 'app-admin',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './admin.html',
  styleUrl: '../p4-comun.scss',
})
export class AdminPage implements OnInit {
  t = t;
  readonly roles: RolMiembro[] = ['socio', 'admin_operativo', 'capitan', 'mediador'];

  pestana = signal<Pestana>('usuarios');
  usuarios = signal<AdminUsuario[]>([]);
  grupos = signal<AdminGrupo[]>([]);
  bitacora = signal<AdminBitacora[]>([]);
  directorio = signal(false);
  denegado = signal(false);
  ocupado = signal(false);
  error = signal<string | null>(null);
  aviso = signal<string | null>(null);

  // crear usuario
  nCorreo = '';
  nNombre = '';
  nClave = '';

  // cambiar contraseña / borrar (una fila a la vez)
  claveDe = signal<string | null>(null);
  claveNueva = '';
  borrarDe = signal<string | null>(null);

  // gestión de un grupo
  grupoSel = signal<AdminGrupo | null>(null);
  miembros = signal<AdminMiembro[]>([]);
  agUsuario = '';
  agRol: RolMiembro = 'socio';
  agPct = 0;
  edicion: Record<string, number> = {};

  constructor(private admin: AdminService) {}

  async ngOnInit(): Promise<void> {
    await this.recargar();
  }

  async recargar(): Promise<void> {
    const [u, g, b] = await Promise.all([this.admin.usuarios(), this.admin.grupos(), this.admin.bitacora(30)]);
    if (u.error || g.error) {
      this.denegado.set(true);
      return;
    }
    this.usuarios.set(u.datos ?? []);
    this.grupos.set(g.datos ?? []);
    this.bitacora.set(b.datos ?? []);
    this.directorio.set(await this.admin.directorioHabilitado());
    const sel = this.grupoSel();
    if (sel) {
      const actual = (g.datos ?? []).find((x) => x.id === sel.id) ?? null;
      this.grupoSel.set(actual);
      if (actual) await this.cargarMiembros(actual.id);
    }
  }

  rolTexto(r: string): string {
    return rolTexto(r as RolMiembro);
  }

  estadoGrupo(e: string): string {
    return estadoGrupoTexto(e as EstadoGrupo);
  }

  // ---------------- mensajes
  private claveMotivo(m: string): ClaveI18n {
    switch (m) {
      case 'es_el_mismo':
        return 'admin.err.es_el_mismo';
      case 'ultimo_admin_plataforma':
        return 'admin.err.ultimo_admin_plataforma';
      case 'tiene_movimientos':
        return 'admin.err.tiene_movimientos';
      case 'socio_en_grupo_activo':
        return 'admin.err.socio_en_grupo_activo';
      case 'organiza_propuestas':
        return 'admin.err.organiza_propuestas';
      default:
        return 'admin.err.tiene_datos';
    }
  }

  private mensajeError(e: string, motivos?: string[]): string {
    if (motivos?.length) return `${t('admin.err.no_borrable')} ${motivos.map((m) => t(this.claveMotivo(m))).join('; ')}.`;
    const x = e.toLowerCase();
    if (x.includes('solo_admin_plataforma')) return t('admin.err.denegado');
    if (x.includes('porcentaje_pendiente')) return t('admin.err.pendiente');
    if (x.includes('porcentajes_invalidos') || x.includes('check_violation')) return t('admin.err.porcentajes');
    if (x.includes('porcentaje_invalido')) return t('admin.err.porcentaje');
    if (x.includes('ultimo_admin')) return t('admin.err.ultimo_admin');
    if (x.includes('no_existe') || x.includes('no_encontrado')) return t('admin.err.no_existe');
    if (x.includes('correo_existe')) return t('admin.err.correo_existe');
    if (x.includes('clave_invalida')) return t('admin.err.clave');
    if (x.includes('correo_invalido')) return t('admin.err.correo');
    if (x.includes('nombre_invalido')) return t('admin.err.nombre');
    if (x.includes('es_el_mismo')) return t('admin.err.es_el_mismo');
    if (x === 'red') return t('admin.err.red');
    return t('app.error.generico');
  }

  private async correr(
    accion: () => Promise<RespuestaAdmin | { error: string | null }>,
    ok: ClaveI18n,
    despues?: () => void,
  ): Promise<boolean> {
    this.ocupado.set(true);
    this.error.set(null);
    this.aviso.set(null);
    const r = await accion();
    this.ocupado.set(false);
    if (r.error) {
      this.error.set(this.mensajeError(r.error, (r as RespuestaAdmin).motivos));
      return false;
    }
    this.aviso.set(t(ok));
    despues?.();
    await this.recargar();
    return true;
  }

  // ---------------- usuarios
  async crear(): Promise<void> {
    await this.correr(() => this.admin.crearUsuario(this.nCorreo, this.nClave, this.nNombre), 'admin.u.creado', () => {
      this.nCorreo = '';
      this.nNombre = '';
      this.nClave = '';
    });
  }

  async guardarClave(u: AdminUsuario): Promise<void> {
    await this.correr(() => this.admin.cambiarClave(u.id, this.claveNueva), 'admin.u.clave_cambiada', () => {
      this.claveDe.set(null);
      this.claveNueva = '';
    });
  }

  async bloquear(u: AdminUsuario): Promise<void> {
    await this.correr(() => this.admin.bloquear(u.id, !u.bloqueado), u.bloqueado ? 'admin.u.desbloqueo_ok' : 'admin.u.bloqueo_ok');
  }

  async borrar(u: AdminUsuario): Promise<void> {
    await this.correr(() => this.admin.borrar(u.id), 'admin.u.borrado', () => this.borrarDe.set(null));
  }

  async alternarAdmin(u: AdminUsuario): Promise<void> {
    await this.correr(() => this.admin.asignarAdmin(u.id, !u.es_admin), 'admin.u.admin_ok');
  }

  // ---------------- grupos
  async gestionar(g: AdminGrupo): Promise<void> {
    this.grupoSel.set(g);
    this.error.set(null);
    this.aviso.set(null);
    await this.cargarMiembros(g.id);
  }

  private async cargarMiembros(grupo: string): Promise<void> {
    const r = await this.admin.miembros(grupo);
    const lista = r.datos ?? [];
    this.miembros.set(lista);
    this.edicion = {};
    for (const m of lista) if (m.estado === 'activo' && m.rol === 'socio') this.edicion[m.usuario_id] = m.porcentaje;
  }

  activos(): AdminMiembro[] {
    return this.miembros().filter((m) => m.estado === 'activo');
  }

  sociosActivos(): AdminMiembro[] {
    return this.activos().filter((m) => m.rol === 'socio');
  }

  sumaEdicion(): number {
    return Math.round(this.sociosActivos().reduce((a, m) => a + Number(this.edicion[m.usuario_id] ?? 0), 0) * 100) / 100;
  }

  disponibles(): AdminUsuario[] {
    const dentro = new Set(this.activos().map((m) => m.usuario_id));
    return this.usuarios().filter((u) => !dentro.has(u.id));
  }

  async agregar(): Promise<void> {
    const g = this.grupoSel();
    if (!g || !this.agUsuario) return;
    const pct = this.agRol === 'socio' ? Number(this.agPct) : 0;
    await this.correr(() => this.admin.guardarMiembro(g.id, this.agUsuario, this.agRol, pct), 'admin.g.agregado', () => {
      this.agUsuario = '';
      this.agPct = 0;
    });
  }

  async guardarReparto(): Promise<void> {
    const g = this.grupoSel();
    if (!g) return;
    const items = this.sociosActivos().map((m) => ({ usuario_id: m.usuario_id, porcentaje: Number(this.edicion[m.usuario_id] ?? 0) }));
    await this.correr(() => this.admin.fijarPorcentajes(g.id, items), 'admin.g.reparto_ok');
  }

  async quitar(m: AdminMiembro): Promise<void> {
    const g = this.grupoSel();
    if (!g) return;
    await this.correr(() => this.admin.quitarMiembro(g.id, m.usuario_id), 'admin.g.quitado');
  }

  // ---------------- plataforma
  async alternarDirectorio(): Promise<void> {
    await this.correr(() => this.admin.directorio(!this.directorio()), 'admin.p.guardado');
  }
}
