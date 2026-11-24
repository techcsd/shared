import { Injectable, computed, signal } from '@angular/core';
import { RealtimeChannel } from '@supabase/supabase-js';
import { NotificacionModel } from '../../shared/models/reserva.model';
import { AuthService } from './auth.service';
import { SupabaseService } from './supabase.service';

/** Notificaciones in-app (outbox canal «app») con Realtime. */
@Injectable({ providedIn: 'root' })
export class NotificacionService {
  private _lista = signal<NotificacionModel[]>([]);
  lista = this._lista.asReadonly();
  sinLeer = computed(() => this._lista().filter((n) => !n.leida_en).length);
  private canal: RealtimeChannel | null = null;

  constructor(
    private supabase: SupabaseService,
    private auth: AuthService,
  ) {}

  async cargar(): Promise<void> {
    const { data } = await this.supabase.cliente
      .from('notificaciones')
      .select('id, tipo, titulo, cuerpo, datos, leida_en, creado_en')
      .eq('canal', 'app')
      .order('creado_en', { ascending: false })
      .limit(50);
    this._lista.set((data ?? []) as NotificacionModel[]);
  }

  /** Empieza a escuchar; es idempotente. */
  iniciar(): void {
    const uid = this.auth.usuario()?.id;
    if (!uid || this.canal) return;
    void this.cargar();
    this.canal = this.supabase.cliente
      .channel(`notif-${uid}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'notificaciones', filter: `usuario_id=eq.${uid}` },
        () => void this.cargar(),
      )
      .subscribe();
  }

  detener(): void {
    if (this.canal) void this.supabase.cliente.removeChannel(this.canal);
    this.canal = null;
    this._lista.set([]);
  }

  async marcarLeida(id: string): Promise<void> {
    await this.supabase.cliente
      .from('notificaciones')
      .update({ leida_en: new Date().toISOString() })
      .eq('id', id);
    this._lista.update((l) =>
      l.map((n) => (n.id === id ? { ...n, leida_en: new Date().toISOString() } : n)),
    );
  }

  async marcarTodas(): Promise<void> {
    const pendientes = this._lista().filter((n) => !n.leida_en);
    await Promise.all(pendientes.map((n) => this.marcarLeida(n.id)));
  }
}
