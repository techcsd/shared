import { ErrorHandler, Injectable } from '@angular/core';
import { SupabaseService } from './supabase.service';

/** Manejo global de errores: consola + registro en `errores_cliente` (silencioso si falla). */
@Injectable()
export class RegistroErrores implements ErrorHandler {
  private enviados = 0;
  private readonly maximoPorSesion = 20;

  constructor(private supabase: SupabaseService) {}

  handleError(error: unknown): void {
    console.error(error);
    void this.registrar(error);
  }

  private async registrar(error: unknown): Promise<void> {
    if (!this.supabase.configurado || this.enviados >= this.maximoPorSesion) return;
    this.enviados++;
    try {
      const { data } = await this.supabase.cliente.auth.getSession();
      const usuario = data.session?.user.id;
      if (!usuario) return; // la tabla solo acepta usuarios autenticados
      const e = error instanceof Error ? error : new Error(String(error));
      await this.supabase.cliente.from('errores_cliente').insert({
        usuario_id: usuario,
        mensaje: e.message.slice(0, 1000),
        pila: (e.stack ?? '').slice(0, 4000),
        ruta: location.pathname,
        agente: navigator.userAgent.slice(0, 300),
      });
    } catch {
      // nunca lanzar desde el manejador de errores
    }
  }
}
