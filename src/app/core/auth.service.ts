import { Injectable, computed, signal } from '@angular/core';
import { Session, User } from '@supabase/supabase-js';
import { SupabaseService } from './supabase.service';

export interface ResultadoAuth {
  error: string | null;
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private _sesion = signal<Session | null>(null);
  sesion = this._sesion.asReadonly();
  usuario = computed<User | null>(() => this._sesion()?.user ?? null);
  autenticado = computed(() => this._sesion() !== null);

  /** Se resuelve cuando ya se leyó la sesión guardada (los guards esperan esto). */
  readonly listo: Promise<void>;

  constructor(private supabase: SupabaseService) {
    this.listo = supabase.cliente.auth
      .getSession()
      .then(({ data }) => this._sesion.set(data.session))
      .catch(() => this._sesion.set(null));
    supabase.cliente.auth.onAuthStateChange((_evento, sesion) => this._sesion.set(sesion));
  }

  private resultado(error: { message: string } | null): ResultadoAuth {
    return { error: error ? error.message : null };
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

  async salir(): Promise<void> {
    await this.supabase.cliente.auth.signOut();
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
