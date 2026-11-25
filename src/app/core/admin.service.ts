import { Injectable } from '@angular/core';
import { ENV } from './env.generated';
import { Resultado } from './reserva.service';
import { SupabaseService } from './supabase.service';

export interface AdminUsuario {
  id: string;
  correo: string | null;
  nombre: string;
  creado_en: string;
  ultimo_acceso: string | null;
  bloqueado: boolean;
  es_admin: boolean;
  grupos: { grupo_id: string; nombre: string; rol: string; porcentaje: number }[];
}

export interface AdminGrupo {
  id: string;
  nombre: string;
  moneda: string;
  estado: string;
  modo_demo: boolean;
  creado_en: string;
  activo: string | null;
  miembros: number;
  suma_porcentajes: number;
  movimientos: number;
}

export interface AdminMiembro {
  miembro_id: string;
  usuario_id: string;
  correo: string | null;
  nombre: string;
  rol: string;
  porcentaje: number;
  estado: string;
  desde: string;
}

export interface AdminBitacora {
  momento: string;
  accion: string;
  objetivo: string | null;
  actor: string | null;
  detalle: Record<string, unknown>;
}

export interface RespuestaAdmin {
  ok?: boolean;
  id?: string;
  error?: string;
  motivos?: string[];
}

/** Administración de la plataforma (solo administrador de plataforma). Las reglas viven en la base y en la edge function. */
@Injectable({ providedIn: 'root' })
export class AdminService {
  constructor(private supabase: SupabaseService) {}

  private get db() {
    return this.supabase.cliente;
  }

  private r<T>(datos: T | null, error: { message: string } | null): Resultado<T> {
    return { datos: error ? null : datos, error: error?.message ?? null };
  }

  async usuarios(): Promise<Resultado<AdminUsuario[]>> {
    const { data, error } = await this.db.rpc('admin_usuarios_listar');
    return this.r<AdminUsuario[]>(
      ((data ?? []) as AdminUsuario[]).map((u) => ({ ...u, grupos: u.grupos.map((g) => ({ ...g, porcentaje: Number(g.porcentaje) })) })),
      error,
    );
  }

  async grupos(): Promise<Resultado<AdminGrupo[]>> {
    const { data, error } = await this.db.rpc('admin_grupos_listar');
    return this.r<AdminGrupo[]>(
      ((data ?? []) as AdminGrupo[]).map((g) => ({ ...g, suma_porcentajes: Number(g.suma_porcentajes), miembros: Number(g.miembros), movimientos: Number(g.movimientos) })),
      error,
    );
  }

  async miembros(grupo: string): Promise<Resultado<AdminMiembro[]>> {
    const { data, error } = await this.db.rpc('admin_grupo_miembros', { p_grupo: grupo });
    return this.r<AdminMiembro[]>(((data ?? []) as AdminMiembro[]).map((m) => ({ ...m, porcentaje: Number(m.porcentaje) })), error);
  }

  async guardarMiembro(grupo: string, usuario: string, rol: string, porcentaje: number): Promise<Resultado<string>> {
    const { data, error } = await this.db.rpc('admin_miembro_guardar', {
      p_grupo: grupo,
      p_usuario: usuario,
      p_rol: rol,
      p_porcentaje: porcentaje,
    });
    return this.r<string>(data as string, error);
  }

  async fijarPorcentajes(grupo: string, items: { usuario_id: string; porcentaje: number }[]): Promise<Resultado<null>> {
    const { error } = await this.db.rpc('admin_porcentajes_fijar', { p_grupo: grupo, p_items: items });
    return this.r<null>(null, error);
  }

  async quitarMiembro(grupo: string, usuario: string): Promise<Resultado<null>> {
    const { error } = await this.db.rpc('admin_miembro_quitar', { p_grupo: grupo, p_usuario: usuario });
    return this.r<null>(null, error);
  }

  async asignarAdmin(usuario: string, esAdmin: boolean): Promise<Resultado<null>> {
    const { error } = await this.db.rpc('admin_plataforma_asignar', { p_usuario: usuario, p_admin: esAdmin });
    return this.r<null>(null, error);
  }

  async directorio(habilitado: boolean): Promise<Resultado<null>> {
    const { error } = await this.db.rpc('admin_directorio_set', { p_habilitado: habilitado });
    return this.r<null>(null, error);
  }

  async bitacora(limite = 30): Promise<Resultado<AdminBitacora[]>> {
    const { data, error } = await this.db.rpc('admin_bitacora_listar', { p_limite: limite });
    return this.r<AdminBitacora[]>((data ?? []) as AdminBitacora[], error);
  }

  async directorioHabilitado(): Promise<boolean> {
    const { data } = await this.db.rpc('directorio_habilitado');
    return data === true;
  }

  // ---- operaciones sobre Auth (edge function `admin-usuarios`)
  private async llamar(cuerpo: Record<string, unknown>): Promise<RespuestaAdmin> {
    const { data: ses } = await this.db.auth.getSession();
    try {
      const resp = await fetch(`${ENV.supabaseUrl}/functions/v1/admin-usuarios`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${ses.session?.access_token ?? ''}`,
          apikey: ENV.supabaseAnonKey,
        },
        body: JSON.stringify(cuerpo),
      });
      const j = (await resp.json().catch(() => ({}))) as RespuestaAdmin;
      return resp.ok ? { ...j, ok: true } : { ...j, ok: false, error: j.error ?? `http_${resp.status}` };
    } catch {
      return { ok: false, error: 'red' };
    }
  }

  crearUsuario(email: string, password: string, nombre: string): Promise<RespuestaAdmin> {
    return this.llamar({ accion: 'crear', email, password, nombre });
  }

  cambiarClave(usuario: string, password: string): Promise<RespuestaAdmin> {
    return this.llamar({ accion: 'clave', usuario_id: usuario, password });
  }

  bloquear(usuario: string, bloquear: boolean): Promise<RespuestaAdmin> {
    return this.llamar({ accion: 'bloquear', usuario_id: usuario, bloquear });
  }

  borrar(usuario: string): Promise<RespuestaAdmin> {
    return this.llamar({ accion: 'borrar', usuario_id: usuario });
  }
}
