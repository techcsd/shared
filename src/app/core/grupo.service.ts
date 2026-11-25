import { Injectable, computed, signal } from '@angular/core';
import {
  GrupoModel,
  InvitacionModel,
  MembresiaModel,
  MiembroModel,
  RolMiembro,
  VistaPreviaInvitacion,
} from '../../shared/models/grupo.model';
import { AuthService } from './auth.service';
import { SupabaseService } from './supabase.service';

export interface InvitacionPendiente {
  invitacion_id: string;
  grupo_nombre: string;
  rol: RolMiembro;
  porcentaje: number;
  expira_en: string;
}

const CLAVE_GRUPO = 'shared.grupo_activo';

/** Grupos del usuario, grupo activo y rol en él. El grupo activo del cliente NO es una barrera: lo decide RLS. */
@Injectable({ providedIn: 'root' })
export class GrupoService {
  private _membresias = signal<MembresiaModel[]>([]);
  membresias = this._membresias.asReadonly();
  private _activoId = signal<string | null>(this.leerGuardado());
  cargado = signal(false);

  activa = computed<MembresiaModel | null>(() => {
    const lista = this._membresias();
    return lista.find((m) => m.grupo.id === this._activoId()) ?? lista[0] ?? null;
  });
  grupo = computed<GrupoModel | null>(() => this.activa()?.grupo ?? null);
  rol = computed<RolMiembro | null>(() => this.activa()?.rol ?? null);
  esSocio = computed(() => this.rol() === 'socio');
  /** El grupo activo se ve como administrador de plataforma (sin ser miembro): se actúa como socio solo con «Entrar como». */
  vistaAdmin = computed(() => this.activa()?.vistaAdmin === true);
  esAdminPlataforma = signal(false);
  modoDemo = computed(() => this.grupo()?.modo_demo ?? false);

  constructor(
    private supabase: SupabaseService,
    private auth: AuthService,
  ) {}

  private leerGuardado(): string | null {
    try {
      return localStorage.getItem(CLAVE_GRUPO);
    } catch {
      return null;
    }
  }

  seleccionar(grupoId: string): void {
    this._activoId.set(grupoId);
    try {
      localStorage.setItem(CLAVE_GRUPO, grupoId);
    } catch {
      // sin almacenamiento
    }
  }

  async cargar(): Promise<void> {
    const uid = this.auth.usuario()?.id;
    if (!uid) {
      this._membresias.set([]);
      this.cargado.set(true);
      return;
    }
    const { data, error } = await this.supabase.cliente
      .from('miembros')
      .select(
        'id, rol, porcentaje, grupo:grupos(id, nombre, moneda, zona_horaria, prefijo, estado, modo_demo)',
      )
      .eq('usuario_id', uid)
      .eq('estado', 'activo');
    if (error) throw error;
    const lista = ((data ?? []) as unknown as MembresiaModel[]).filter((m) => m.grupo);
    this._membresias.set(lista.concat(await this.gruposComoAdmin(lista)));
    this.cargado.set(true);
  }

  /** Un administrador de plataforma puede abrir cualquier grupo (la base se lo permite por RLS). */
  private async gruposComoAdmin(propios: MembresiaModel[]): Promise<MembresiaModel[]> {
    try {
      const { data: esAdmin } = await this.supabase.cliente.rpc('es_admin_plataforma');
      this.esAdminPlataforma.set(esAdmin === true);
      if (esAdmin !== true) return [];
      const { data } = await this.supabase.cliente
        .from('grupos')
        .select('id, nombre, moneda, zona_horaria, prefijo, estado, modo_demo')
        .order('nombre');
      const mios = new Set(propios.map((m) => m.grupo.id));
      return ((data ?? []) as unknown as GrupoModel[])
        .filter((g) => !mios.has(g.id))
        .map((g) => ({ id: '', rol: 'socio' as RolMiembro, porcentaje: 0, grupo: g, vistaAdmin: true }));
    } catch {
      this.esAdminPlataforma.set(false);
      return [];
    }
  }

  async crear(datos: {
    nombre: string;
    moneda: string;
    zonaHoraria: string;
    prefijo: string;
    porcentaje: number;
  }): Promise<{ id: string | null; error: string | null }> {
    const { data, error } = await this.supabase.cliente.rpc('crear_grupo', {
      p_nombre: datos.nombre,
      p_moneda: datos.moneda,
      p_zona_horaria: datos.zonaHoraria,
      p_prefijo: datos.prefijo,
      p_porcentaje: datos.porcentaje,
    });
    if (error) return { id: null, error: error.message };
    await this.cargar();
    this.seleccionar(data as string);
    return { id: data as string, error: null };
  }

  async miembros(grupoId: string): Promise<MiembroModel[]> {
    const { data } = await this.supabase.cliente
      .from('miembros')
      .select('id, usuario_id, rol, porcentaje, estado, perfil:perfiles(nombre, correo)')
      .eq('grupo_id', grupoId)
      .order('desde');
    return (data ?? []) as unknown as MiembroModel[];
  }

  async invitaciones(grupoId: string): Promise<InvitacionModel[]> {
    const { data } = await this.supabase.cliente
      .from('invitaciones_miembro')
      .select('id, correo, rol, porcentaje, estado, expira_en')
      .eq('grupo_id', grupoId)
      .order('creado_en', { ascending: false });
    return (data ?? []) as InvitacionModel[];
  }

  /** Devuelve el token (se muestra una sola vez) o el error. */
  async invitar(
    grupoId: string,
    correo: string,
    rol: RolMiembro,
    porcentaje: number,
  ): Promise<{ token: string | null; error: string | null }> {
    const { data, error } = await this.supabase.cliente.rpc('invitar_miembro', {
      p_grupo: grupoId,
      p_correo: correo,
      p_rol: rol,
      p_porcentaje: porcentaje,
    });
    return { token: error ? null : (data as string), error: error?.message ?? null };
  }

  async cancelarInvitacion(id: string): Promise<string | null> {
    const { error } = await this.supabase.cliente.rpc('cancelar_invitacion', { p_invitacion: id });
    return error?.message ?? null;
  }

  /** Invitaciones pendientes dirigidas al correo de mi sesión (la base no devuelve nada de otros). */
  async invitacionesPendientes(): Promise<InvitacionPendiente[]> {
    const { data } = await this.supabase.cliente.rpc('invitaciones_pendientes_mias');
    return ((data ?? []) as InvitacionPendiente[]).map((i) => ({ ...i, porcentaje: Number(i.porcentaje) }));
  }

  async aceptarPorId(id: string): Promise<{ grupoId: string | null; error: string | null }> {
    const { data, error } = await this.supabase.cliente.rpc('aceptar_invitacion_por_id', { p_invitacion: id });
    if (error) return { grupoId: null, error: error.message };
    if (!data) return { grupoId: null, error: 'invitacion_expirada' };
    await this.cargar();
    this.seleccionar(data as string);
    return { grupoId: data as string, error: null };
  }

  async previsualizar(token: string): Promise<VistaPreviaInvitacion | null> {
    const { data } = await this.supabase.cliente.rpc('previsualizar_invitacion', {
      p_token: token,
    });
    const fila = Array.isArray(data) ? data[0] : data;
    return (fila as VistaPreviaInvitacion) ?? null;
  }

  async aceptar(token: string): Promise<{ grupoId: string | null; error: string | null }> {
    const { data, error } = await this.supabase.cliente.rpc('aceptar_invitacion', {
      p_token: token,
    });
    if (error) return { grupoId: null, error: error.message };
    if (!data) return { grupoId: null, error: 'invitacion_expirada' };
    await this.cargar();
    this.seleccionar(data as string);
    return { grupoId: data as string, error: null };
  }

  limpiar(): void {
    this._membresias.set([]);
    this.esAdminPlataforma.set(false);
    this.cargado.set(false);
  }
}
