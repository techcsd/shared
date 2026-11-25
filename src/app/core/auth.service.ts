import { Injectable, computed, signal } from '@angular/core';
import { Session, User } from '@supabase/supabase-js';
import { t } from './i18n/i18n';
import { OfflineService } from './offline.service';
import { SupabaseService } from './supabase.service';

export interface ResultadoAuth {
  error: string | null;
}

const CLAVE_ADMIN = 'shared.admin_sesion'; // sesión del admin mientras «entra como» (solo esta pestaña)
const CLAVE_IMPERSONA = 'shared.impersonando'; // quién se está viendo (para el banner aunque se recargue)

export interface Impersonado {
  id: string;
  nombre: string;
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private _impersonando = signal<Impersonado | null>(AuthService.leerImpersona());
  /** Si no es null, el administrador de plataforma está viendo la app como otro usuario («Entrar como»). */
  impersonando = this._impersonando.asReadonly();
  /** ¿Se puede volver a la cuenta del admin? (si se cerró la pestaña, la copia de su sesión ya no existe) */
  puedeVolver(): boolean {
    try {
      return sessionStorage.getItem(CLAVE_ADMIN) !== null;
    } catch {
      return false;
    }
  }

  private static leerImpersona(): Impersonado | null {
    try {
      const raw = localStorage.getItem(CLAVE_IMPERSONA);
      return raw ? (JSON.parse(raw) as Impersonado) : null;
    } catch {
      return null;
    }
  }

  private _sesion = signal<Session | null>(null);
  sesion = this._sesion.asReadonly();
  usuario = computed<User | null>(() => this._sesion()?.user ?? null);
  autenticado = computed(() => this._sesion() !== null);

  /** Se resuelve cuando ya se leyó la sesión guardada (los guards esperan esto). */
  readonly listo: Promise<void>;

  constructor(
    private supabase: SupabaseService,
    private offline: OfflineService,
  ) {
    this.listo = supabase.cliente.auth
      .getSession()
      .then(({ data }) => this._sesion.set(data.session))
      .catch(() => this._sesion.set(null));
    supabase.cliente.auth.onAuthStateChange((_evento, sesion) => this._sesion.set(sesion));
  }

  private resultado(error: { message: string; code?: string } | null): ResultadoAuth {
    if (!error) return { error: null };
    const c = error.code ?? '';
    const m = error.message.toLowerCase();
    if (c === 'weak_password' || (m.includes('password') && (m.includes('character') || m.includes('weak'))))
      return { error: t('auth.clave_debil') };
    if (c === 'user_already_exists') return { error: t('auth.ya_existe') };
    if (c === 'invalid_credentials') return { error: t('auth.credenciales') };
    if (c === 'over_email_send_rate_limit' || c === 'over_request_rate_limit')
      return { error: t('auth.limite') };
    return { error: error.message };
  }

  async entrar(correo: string, clave: string): Promise<ResultadoAuth> {
    const { error } = await this.supabase.cliente.auth.signInWithPassword({
      email: correo.trim(),
      password: clave,
    });
    return this.resultado(error);
  }

  async registrar(correo: string, clave: string, nombre: string): Promise<ResultadoAuth> {
    const { error } = await this.supabase.cliente.auth.signUp({
      email: correo.trim(),
      password: clave,
      options: { data: { nombre: nombre.trim() }, emailRedirectTo: location.origin },
    });
    return this.resultado(error);
  }

  async enlaceMagico(correo: string): Promise<ResultadoAuth> {
    const { error } = await this.supabase.cliente.auth.signInWithOtp({
      email: correo.trim(),
      options: { emailRedirectTo: location.origin },
    });
    return this.resultado(error);
  }

  async recuperarClave(correo: string): Promise<ResultadoAuth> {
    const { error } = await this.supabase.cliente.auth.resetPasswordForEmail(correo.trim(), {
      redirectTo: `${location.origin}/restablecer`,
    });
    return this.resultado(error);
  }

  async cambiarClave(clave: string): Promise<ResultadoAuth> {
    const { error } = await this.supabase.cliente.auth.updateUser({ password: clave });
    return this.resultado(error);
  }

  /**
   * «Entrar como» (admin de plataforma): guarda la sesión del admin SOLO en esta pestaña (sessionStorage) y canjea el
   * token de un solo uso por la sesión del usuario. Ninguno de los tokens se registra ni se envía a otro lado.
   */
  async entrarComo(tokenHash: string, usuario: Impersonado): Promise<ResultadoAuth> {
    const { data } = await this.supabase.cliente.auth.getSession();
    const ses = data.session;
    if (!ses) return { error: 'no_autenticado' };
    try {
      sessionStorage.setItem(
        CLAVE_ADMIN,
        JSON.stringify({ access_token: ses.access_token, refresh_token: ses.refresh_token }),
      );
    } catch {
      return { error: 'sin_almacenamiento' };
    }
    this.offline.limpiarTodo();
    const { error } = await this.supabase.cliente.auth.verifyOtp({ token_hash: tokenHash, type: 'magiclink' });
    if (error) {
      this.olvidarImpersona();
      return this.resultado(error);
    }
    try {
      localStorage.setItem(CLAVE_IMPERSONA, JSON.stringify(usuario));
    } catch {
      // sin almacenamiento: el banner igual se muestra mientras dure la pestaña
    }
    this._impersonando.set(usuario);
    return { error: null };
  }

  /** Restaura la sesión del admin. Si ya no existe la copia (se cerró la pestaña), cierra sesión. */
  async volverACuentaAdmin(): Promise<ResultadoAuth> {
    let guardada: { access_token: string; refresh_token: string } | null = null;
    try {
      const raw = sessionStorage.getItem(CLAVE_ADMIN);
      guardada = raw ? JSON.parse(raw) : null;
    } catch {
      guardada = null;
    }
    this.offline.limpiarTodo();
    if (!guardada) {
      await this.salir();
      return { error: 'sesion_admin_perdida' };
    }
    const { error } = await this.supabase.cliente.auth.setSession(guardada);
    this.olvidarImpersona();
    if (error) {
      await this.supabase.cliente.auth.signOut();
      return this.resultado(error);
    }
    return { error: null };
  }

  private olvidarImpersona(): void {
    try {
      sessionStorage.removeItem(CLAVE_ADMIN);
      localStorage.removeItem(CLAVE_IMPERSONA);
    } catch {
      // sin almacenamiento
    }
    this._impersonando.set(null);
  }

  async salir(): Promise<void> {
    this.offline.limpiarTodo();
    this.olvidarImpersona();
    await this.supabase.cliente.auth.signOut();
  }

  /** Cierra la sesión en TODOS los dispositivos (invalida los refresh tokens). */
  async salirDeTodo(): Promise<void> {
    this.offline.limpiarTodo();
    this.olvidarImpersona();
    await this.supabase.cliente.auth.signOut({ scope: 'global' });
  }

  async actualizarPerfil(datos: {
    nombre: string;
    telefono: string | null;
    idioma: 'es' | 'en';
  }): Promise<ResultadoAuth> {
    const id = this.usuario()?.id;
    if (!id) return { error: 'no_autenticado' };
    const { error } = await this.supabase.cliente.from('perfiles').update(datos).eq('id', id);
    return this.resultado(error);
  }

  async perfil(): Promise<{ nombre: string; telefono: string | null; idioma: 'es' | 'en' } | null> {
    const id = this.usuario()?.id;
    if (!id) return null;
    const { data } = await this.supabase.cliente
      .from('perfiles')
      .select('nombre, telefono, idioma')
      .eq('id', id)
      .maybeSingle();
    return data as { nombre: string; telefono: string | null; idioma: 'es' | 'en' } | null;
  }
}
