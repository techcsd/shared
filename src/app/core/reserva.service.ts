import { Injectable } from '@angular/core';
import { RealtimeChannel } from '@supabase/supabase-js';
import {
  EventoAuditoria,
  ReservaModel,
  TemporadaModel,
  UsoReserva,
} from '../../shared/models/reserva.model';
import { SupabaseService } from './supabase.service';

export interface DatosBorrador {
  activo: string;
  inicio: Date;
  fin: Date;
  uso: UsoReserva;
  destino: string | null;
  personas: number;
  responsableMiembro?: string | null;
  invitadoNombre?: string;
  invitadoCorreo?: string;
  anfitrion?: string | null;
  notas?: string;
}

export interface Resultado<T> {
  datos: T | null;
  error: string | null;
}

/** Traduce el mensaje de la base a una clave de i18n (la base es la autoridad; la UI solo informa). */
export function claveError(msg: string): string {
  const k = [
    'horario_ocupado',
    'capacidad_excedida',
    'dias_max_superados',
    'multi_dia_no_permitido',
    'cuota_excedida',
    'temporada_alta_prioridad',
    'fecha_pasada',
    'rango_invalido',
    'rango_muy_largo',
    'borrador_expirado',
    'invitado_requiere_nombre_y_correo',
    'transicion_invalida',
    'solo_titular_decide',
    'solo_quien_reserva',
    'solo_socios_reservan',
    'sin_permiso',
    'activo_no_disponible',
  ].find((x) => msg.includes(x));
  return k ? `error.${k}` : 'app.error.generico';
}

@Injectable({ providedIn: 'root' })
export class ReservaService {
  constructor(private supabase: SupabaseService) {}

  private get db() {
    return this.supabase.cliente;
  }

  private res<T>(datos: T | null, error: { message: string } | null): Resultado<T> {
    return { datos: error ? null : datos, error: error?.message ?? null };
  }

  /** Reservas y bloqueos que tocan la ventana (para pintar el calendario). */
  async enVentana(activo: string, desde: Date, hasta: Date): Promise<ReservaModel[]> {
    const { data } = await this.db
      .from('reservas')
      .select(
        'id, grupo_id, activo_id, rango, estado, tipo_bloqueo, motivo_bloqueo, uso, destino_id, personas, reservado_por, responsable_miembro, responsable_invitado, borrador_expira_en, cancelada_en, cancelacion_tardia, cargo_cancelacion, motivo_cancelacion, creado_en, orden:ordenes(codigo)',
      )
      .eq('activo_id', activo)
      .in('estado', ['confirmada', 'en_curso', 'finalizada', 'bloqueada_mantenimiento'])
      .overlaps('rango', `[${desde.toISOString()},${hasta.toISOString()})`)
      .order('rango');
    return (data ?? []) as unknown as ReservaModel[];
  }

  async misReservas(grupo: string, miMiembro: string): Promise<ReservaModel[]> {
    const { data } = await this.db
      .from('reservas')
      .select(
        'id, grupo_id, activo_id, rango, estado, tipo_bloqueo, motivo_bloqueo, uso, destino_id, personas, reservado_por, responsable_miembro, responsable_invitado, borrador_expira_en, cancelada_en, cancelacion_tardia, cargo_cancelacion, motivo_cancelacion, creado_en, orden:ordenes(codigo)',
      )
      .eq('grupo_id', grupo)
      .eq('reservado_por', miMiembro)
      .order('creado_en', { ascending: false })
      .limit(100);
    return (data ?? []) as unknown as ReservaModel[];
  }

  async detalle(id: string) {
    const { data } = await this.db
      .from('reservas')
      .select(
        '*, orden:ordenes(codigo, creado_en), activo:activos(nombre), destino:destinos(nombre), invitado:invitados(nombre, correo)',
      )
      .eq('id', id)
      .maybeSingle();
    return data as unknown as
      | (ReservaModel & {
          orden: { codigo: string; creado_en: string } | null;
          activo: { nombre: string } | null;
          destino: { nombre: string } | null;
          invitado: { nombre: string; correo: string } | null;
        })
      | null;
  }

  async acuses(reserva: string): Promise<{ miembro_id: string; momento: string }[]> {
    const { data } = await this.db
      .from('reserva_acuses')
      .select('miembro_id, momento')
      .eq('reserva_id', reserva);
    return (data ?? []) as { miembro_id: string; momento: string }[];
  }

  async costo(reserva: string): Promise<{ fee: number; moneda: string } | null> {
    const { data } = await this.db
      .from('reserva_costos')
      .select('fee, moneda')
      .eq('reserva_id', reserva)
      .maybeSingle();
    return data as { fee: number; moneda: string } | null;
  }

  /** Cronología legible desde la auditoría inmutable (la ven los socios). */
  async cronologia(reserva: string): Promise<EventoAuditoria[]> {
    const { data } = await this.db
      .from('auditoria')
      .select('id, tabla, accion, antes, despues, actor, momento, motivo')
      .or(
        `and(tabla.eq.reservas,registro_id.eq.${reserva}),and(tabla.eq.reserva_acuses,despues->>reserva_id.eq.${reserva}),and(tabla.eq.ordenes,despues->>reserva_id.eq.${reserva})`,
      )
      .order('momento')
      .order('id');
    return (data ?? []) as EventoAuditoria[];
  }

  async capacidad(activo: string, uso: UsoReserva): Promise<number | null> {
    const { data } = await this.db.rpc('capacidad_efectiva', { p_activo: activo, p_uso: uso });
    return (data as number | null) ?? null;
  }

  async feeEstimado(grupo: string, destino: string | null, inicio: Date, fin: Date) {
    const { data } = await this.db.rpc('fee_estimado', {
      p_grupo: grupo,
      p_destino: destino,
      p_inicio: inicio.toISOString(),
      p_fin: fin.toISOString(),
    });
    const fila = Array.isArray(data) ? data[0] : data;
    return (fila as { monto: number; moneda: string } | undefined) ?? null;
  }

  async crearBorrador(d: DatosBorrador): Promise<Resultado<string>> {
    const { data, error } = await this.db.rpc('reserva_crear_borrador', {
      p_activo: d.activo,
      p_inicio: d.inicio.toISOString(),
      p_fin: d.fin.toISOString(),
      p_uso: d.uso,
      p_destino: d.destino,
      p_personas: d.personas,
      p_responsable_miembro: d.responsableMiembro ?? null,
      p_invitado_nombre: d.invitadoNombre ?? null,
      p_invitado_correo: d.invitadoCorreo ?? null,
      p_anfitrion: d.anfitrion ?? null,
      p_notas: d.notas ?? null,
    });
    return this.res<string>(data as string, error);
  }

  async confirmar(reserva: string): Promise<Resultado<string>> {
    const { data, error } = await this.db.rpc('reserva_confirmar', { p_reserva: reserva });
    const fila = Array.isArray(data) ? data[0] : data;
    return this.res<string>((fila as { orden: string } | null)?.orden ?? null, error);
  }

  async cancelar(
    reserva: string,
    motivo: string,
  ): Promise<Resultado<{ tardia: boolean; cargo: number }>> {
    const { data, error } = await this.db.rpc('reserva_cancelar', {
      p_reserva: reserva,
      p_motivo: motivo || null,
    });
    const fila = Array.isArray(data) ? data[0] : data;
    return this.res<{ tardia: boolean; cargo: number }>(
      fila as { tardia: boolean; cargo: number } | null,
      error,
    );
  }

  async iniciar(reserva: string) {
    const { error } = await this.db.rpc('reserva_iniciar', { p_reserva: reserva });
    return error?.message ?? null;
  }

  async finalizar(reserva: string) {
    const { error } = await this.db.rpc('reserva_finalizar', { p_reserva: reserva });
    return error?.message ?? null;
  }

  async marcarEnterado(reserva: string) {
    const { error } = await this.db.rpc('reserva_marcar_enterado', { p_reserva: reserva });
    return error?.message ?? null;
  }

  async crearBloqueo(
    activo: string,
    inicio: Date,
    fin: Date,
    tipo: 'mantenimiento' | 'preparacion',
    motivo: string,
  ) {
    const { data, error } = await this.db.rpc('bloqueo_crear', {
      p_activo: activo,
      p_inicio: inicio.toISOString(),
      p_fin: fin.toISOString(),
      p_tipo: tipo,
      p_motivo: motivo || null,
    });
    return this.res<string>(data as string, error);
  }

  async quitarBloqueo(id: string) {
    const { error } = await this.db.rpc('bloqueo_quitar', { p_bloqueo: id });
    return error?.message ?? null;
  }

  // ---- temporada alta
  async temporadas(grupo: string): Promise<TemporadaModel[]> {
    const { data } = await this.db
      .from('temporadas')
      .select('id, periodo, anio, desde, hasta, miembro_prioridad, libre_desde')
      .eq('grupo_id', grupo)
      .order('desde');
    return (data ?? []) as TemporadaModel[];
  }

  async generarTemporada(
    grupo: string,
    periodo: string,
    anio: number,
    desde: string,
    hasta: string,
  ) {
    const { error } = await this.db.rpc('temporada_generar', {
      p_grupo: grupo,
      p_periodo: periodo,
      p_anio: anio,
      p_desde: desde,
      p_hasta: hasta,
    });
    return error?.message ?? null;
  }

  async quitarTemporada(id: string) {
    const { error } = await this.db.rpc('temporada_quitar', { p_temporada: id });
    return error?.message ?? null;
  }

  /** Realtime: avisa cuando cambia cualquier reserva del grupo. */
  suscribir(grupo: string, alCambiar: () => void): RealtimeChannel {
    return this.db
      .channel(`reservas-${grupo}-${Math.random().toString(36).slice(2, 8)}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'reservas', filter: `grupo_id=eq.${grupo}` },
        alCambiar,
      )
      .subscribe();
  }

  desuscribir(canal: RealtimeChannel | null): void {
    if (canal) void this.db.removeChannel(canal);
  }
}
