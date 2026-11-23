import { Injectable } from '@angular/core';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { ENV } from './env.generated';

/** Cliente Supabase con anon key (jamás service role). La seguridad real es RLS en la base. */
@Injectable({ providedIn: 'root' })
export class SupabaseService {
  readonly configurado = Boolean(ENV.supabaseUrl && ENV.supabaseAnonKey);
  readonly cliente: SupabaseClient;

  constructor() {
    // URL ficticia si falta configuración: la app arranca y muestra el aviso en vez de romperse.
    this.cliente = createClient(
      ENV.supabaseUrl || 'http://localhost:54321',
      ENV.supabaseAnonKey || 'sin-configurar',
      { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } },
    );
  }
}
