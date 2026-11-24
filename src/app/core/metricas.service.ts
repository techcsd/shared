import { Injectable } from '@angular/core';
import { AuthService } from './auth.service';
import { SupabaseService } from './supabase.service';

/** Eventos de cliente (p. ej. tiempo del asistente de reserva: meta «< 1 min», SA1). Nunca rompe la app. */
@Injectable({ providedIn: 'root' })
export class MetricasService {
  constructor(
    private supabase: SupabaseService,
    private auth: AuthService,
  ) {}

  async registrar(
    tipo: string,
    grupo: string | null,
    valorMs: number | null,
    meta: Record<string, unknown> = {},
  ): Promise<void> {
    const uid = this.auth.usuario()?.id;
    if (!uid) return;
    try {
      await this.supabase.cliente
        .from('eventos_cliente')
        .insert({
          usuario_id: uid,
          grupo_id: grupo,
          tipo,
          valor_ms: valorMs === null ? null : Math.round(valorMs),
          meta,
        });
    } catch {
      // silencioso a propósito: una métrica nunca debe fallar al usuario
    }
  }
}
