import { Injectable } from '@angular/core';
import { RealtimeChannel } from '@supabase/supabase-js';
import {
  Mensaje911Model,
  Motivo911,
  Solicitud911Model,
  Urgencia911,
  UsoReserva,
} from '../../shared/models/reserva.model';
import { SupabaseService } from './supabase.service';

@Injectable({ providedIn: 'root' })
export class Prioridad911Service {
  constructor(private supabase: SupabaseService) {}

  private get db() {
    return this.supabase.cliente;
  }

  async solicitudes(grupo: string): Promise<Solicitud911Model[]> {
    const { data } = await this.db
      .from('solicitudes_911')
      .select(
        'id, reserva_id, titular_id, solicitante_id, motivo, urgencia, alternativa, rango, uso, personas, estado, contra_rango, expira_en, creado_en, resuelta_en',
      )
      .eq('grupo_id', grupo)
      .order('creado_en', { ascending: false });
    return (data ?? []) as Solicitud911Model[];
  }

  async mensajes(grupo: string): Promise<Mensaje911Model[]> {
    const { data } = await this.db
      .from('solicitudes_911_mensajes')
      .select('id, solicitud_id, autor_id, tipo, texto, creado_en')
      .eq('grupo_id', grupo)
      .order('creado_en');
    return (data ?? []) as Mensaje911Model[];
  }

  async solicitar(d: {
    reserva: string;
    motivo: Motivo911;
    urgencia: Urgencia911;
    alternativa: string;
    uso: UsoReserva;
    personas: number;
    mensaje: string;
  }): Promise<string | null> {
    const { error } = await this.db.rpc('prioridad_911_solicitar', {
      p_reserva: d.reserva,
      p_motivo: d.motivo,
      p_urgencia: d.urgencia,
      p_alternativa: d.alternativa || null,
      p_uso: d.uso,
      p_destino: null,
      p_personas: d.personas,
      p_mensaje: d.mensaje || null,
    });
    return error?.message ?? null;
  }

  async responder(
    solicitud: string,
    accion: 'acepta' | 'rechaza' | 'contrapropone',
    mensaje: string,
    contra?: { inicio: Date; fin: Date },
  ): Promise<string | null> {
    const { error } = await this.db.rpc('prioridad_911_responder', {
      p_solicitud: solicitud,
      p_accion: accion,
      p_mensaje: mensaje || null,
      p_contra_inicio: contra?.inicio.toISOString() ?? null,
      p_contra_fin: contra?.fin.toISOString() ?? null,
    });
    return error?.message ?? null;
  }

  async responderContra(
    solicitud: string,
    acepta: boolean,
    mensaje: string,
  ): Promise<string | null> {
    const { error } = await this.db.rpc('prioridad_911_responder_contra', {
      p_solicitud: solicitud,
      p_acepta: acepta,
      p_mensaje: mensaje || null,
    });
    return error?.message ?? null;
  }

  suscribir(grupo: string, alCambiar: () => void): RealtimeChannel {
    return this.db
      .channel(`p911-${grupo}-${Math.random().toString(36).slice(2, 8)}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'solicitudes_911', filter: `grupo_id=eq.${grupo}` },
        alCambiar,
      )
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'solicitudes_911_mensajes',
          filter: `grupo_id=eq.${grupo}`,
        },
        alCambiar,
      )
      .subscribe();
  }

  desuscribir(canal: RealtimeChannel | null): void {
    if (canal) void this.db.removeChannel(canal);
  }
}
