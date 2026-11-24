import { Injectable } from '@angular/core';
import {
  IncidenciaModel,
  LecturaVigente,
  OperacionModel,
  ResultadoCheckin,
  ResultadoCheckout,
} from '../../shared/models/finanzas.model';
import { Resultado } from './reserva.service';
import { SupabaseService } from './supabase.service';

export interface RespuestaChecklist {
  clave: string;
  momento?: string;
  cumple: boolean;
  nota?: string;
}

export interface DatosCheckin {
  reserva: string;
  capitanMiembro: string | null;
  capitanNombre: string;
  destino: string | null;
  combustible: number | null;
  lecturas: { componente_id: string; valor: number }[];
  checklist: RespuestaChecklist[];
  nota?: string;
}

export interface DatosCheckout {
  reserva: string;
  lecturas: { componente_id: string; valor: number }[];
  combustibleFinal: number | null;
  combustibleAgregado: number | null;
  checklist: RespuestaChecklist[];
  incidencias: { tipo: 'observacion' | 'incidencia' | 'dano'; descripcion: string }[];
  observaciones?: string;
  motivo?: string;
}

export interface RespuestaGuardada {
  momento: string;
  clave: string;
  texto: string;
  cumple: boolean;
  nota: string | null;
}

/** Salida (check-in) y regreso (check-out). Las reglas viven en la base; esto solo envía y muestra. */
@Injectable({ providedIn: 'root' })
export class OperacionService {
  constructor(private supabase: SupabaseService) {}

  private get db() {
    return this.supabase.cliente;
  }

  async deReserva(reserva: string): Promise<OperacionModel | null> {
    const { data } = await this.db
      .from('operaciones')
      .select(
        'id, reserva_id, activo_id, capitan_miembro, capitan_nombre, salida_real, regreso_real, combustible_inicial, combustible_final, combustible_unidad, observaciones, cerrada_en',
      )
      .eq('reserva_id', reserva)
      .maybeSingle();
    return (data as OperacionModel | null) ?? null;
  }

  async lecturas(operacion: string): Promise<LecturaVigente[]> {
    const { data } = await this.db
      .from('lecturas_vigentes')
      .select('id, componente_id, momento, valor, motivo')
      .eq('operacion_id', operacion);
    return ((data ?? []) as LecturaVigente[]).map((l) => ({ ...l, valor: Number(l.valor) }));
  }

  /** Última lectura final conocida del componente (sugerencia para la lectura inicial). */
  async ultimaFinal(componente: string): Promise<number | null> {
    const { data } = await this.db
      .from('lecturas_vigentes')
      .select('valor')
      .eq('componente_id', componente)
      .eq('momento', 'fin')
      .order('id', { ascending: false })
      .limit(1);
    const v = (data ?? [])[0] as { valor: number } | undefined;
    return v ? Number(v.valor) : null;
  }

  async checklist(operacion: string): Promise<RespuestaGuardada[]> {
    const { data } = await this.db
      .from('checklist_vigente')
      .select('momento, clave, texto, cumple, nota')
      .eq('operacion_id', operacion);
    return (data ?? []) as RespuestaGuardada[];
  }

  async incidencias(operacion: string): Promise<IncidenciaModel[]> {
    const { data } = await this.db
      .from('incidencias')
      .select('id, tipo, descripcion, creado_en')
      .eq('operacion_id', operacion)
      .order('creado_en');
    return (data ?? []) as IncidenciaModel[];
  }

  async checkin(d: DatosCheckin): Promise<Resultado<ResultadoCheckin>> {
    const { data, error } = await this.db.rpc('checkin_registrar', {
      p_reserva: d.reserva,
      p_capitan_miembro: d.capitanMiembro,
      p_capitan_nombre: d.capitanNombre || null,
      p_destino: d.destino,
      p_combustible: d.combustible,
      p_lecturas: d.lecturas,
      p_checklist: d.checklist,
      p_nota: d.nota ?? null,
    });
    return { datos: error ? null : (data as ResultadoCheckin), error: error?.message ?? null };
  }

  async checkout(d: DatosCheckout): Promise<Resultado<ResultadoCheckout>> {
    const { data, error } = await this.db.rpc('checkout_registrar', {
      p_reserva: d.reserva,
      p_lecturas: d.lecturas,
      p_combustible_final: d.combustibleFinal,
      p_combustible_agregado: d.combustibleAgregado,
      p_checklist: d.checklist,
      p_incidencias: d.incidencias,
      p_observaciones: d.observaciones ?? null,
      p_motivo: d.motivo ?? null,
    });
    return { datos: error ? null : (data as ResultadoCheckout), error: error?.message ?? null };
  }

  async corregirLectura(
    operacion: string,
    componente: string,
    momento: 'inicio' | 'fin',
    valor: number,
    motivo: string,
  ): Promise<Resultado<null>> {
    const { error } = await this.db.rpc('lectura_corregir', {
      p_operacion: operacion,
      p_componente: componente,
      p_momento: momento,
      p_valor: valor,
      p_motivo: motivo,
    });
    return { datos: null, error: error?.message ?? null };
  }

  async liquidacion(operacion: string): Promise<Record<string, unknown> | null> {
    const { data } = await this.db
      .from('liquidaciones')
      .select('fee_monto, fee_moneda, fee_destino, resumen, liquidada_en')
      .eq('operacion_id', operacion)
      .maybeSingle();
    return (data as Record<string, unknown> | null) ?? null;
  }
}
