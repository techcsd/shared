import { Injectable } from '@angular/core';
import {
  ActivoModel,
  ComponenteActivoModel,
  CorreoModel,
  DefinicionTipo,
  DestinoModel,
  TarifaModel,
  TipoActivoModel,
} from '../../shared/models/config.model';
import { SupabaseService } from './supabase.service';

export interface Resultado<T = null> {
  datos: T | null;
  error: string | null;
}

/** Acceso a la configuración del grupo (tipos, activos, destinos, tarifas, correos). La base valida y aplica RLS. */
@Injectable({ providedIn: 'root' })
export class ConfiguracionService {
  constructor(private supabase: SupabaseService) {}

  private get db() {
    return this.supabase.cliente;
  }

  private res<T>(datos: T | null, error: { message: string } | null): Resultado<T> {
    return { datos: error ? null : datos, error: error?.message ?? null };
  }

  // ---- grupo
  async actualizarGrupo(grupo: string, nombre: string, zona: string, prefijo: string) {
    const { error } = await this.db.rpc('actualizar_grupo', {
      p_grupo: grupo,
      p_nombre: nombre,
      p_zona_horaria: zona,
      p_prefijo: prefijo,
    });
    return this.res<null>(null, error);
  }

  // ---- tipos de activo
  async tipos(grupo: string): Promise<TipoActivoModel[]> {
    const { data } = await this.db
      .from('tipos_activo')
      .select('id, grupo_id, clave, nombre, es_sistema, definicion, prefijo_orden')
      .or(`grupo_id.is.null,grupo_id.eq.${grupo}`)
      .order('es_sistema', { ascending: false })
      .order('nombre');
    return (data ?? []) as TipoActivoModel[];
  }

  async clonarTipo(tipo: string, grupo: string, nombre: string, clave: string) {
    const { data, error } = await this.db.rpc('clonar_tipo_activo', {
      p_tipo: tipo,
      p_grupo: grupo,
      p_nombre: nombre,
      p_clave: clave,
    });
    return this.res<string>(data as string, error);
  }

  async guardarTipo(id: string, nombre: string, prefijo: string, definicion: DefinicionTipo) {
    const { error } = await this.db
      .from('tipos_activo')
      .update({ nombre, prefijo_orden: prefijo.toUpperCase(), definicion })
      .eq('id', id);
    return this.res<null>(null, error);
  }

  // ---- activos
  async activos(grupo: string): Promise<ActivoModel[]> {
    const { data } = await this.db
      .from('activos')
      .select('*')
      .eq('grupo_id', grupo)
      .order('creado_en');
    return (data ?? []) as ActivoModel[];
  }

  async crearActivo(
    grupo: string,
    tipo: string,
    nombre: string,
    capacidad: number | null,
    valores: Record<string, unknown>,
    cantidades: Record<string, number>,
  ) {
    const { data, error } = await this.db.rpc('crear_activo', {
      p_grupo: grupo,
      p_tipo: tipo,
      p_nombre: nombre,
      p_capacidad_legal: capacidad,
      p_valores: valores,
      p_cantidades: cantidades,
    });
    return this.res<string>(data as string, error);
  }

  async actualizarActivo(id: string, cambios: Partial<ActivoModel>) {
    const { error } = await this.db.from('activos').update(cambios).eq('id', id);
    return this.res<null>(null, error);
  }

  async componentes(activo: string): Promise<ComponenteActivoModel[]> {
    const { data } = await this.db
      .from('activo_componentes')
      .select('id, activo_id, clave, etiqueta, indice, unidad, lectura_inicial')
      .eq('activo_id', activo)
      .order('clave')
      .order('indice');
    return (data ?? []) as ComponenteActivoModel[];
  }

  async fijarLecturaInicial(id: string, valor: number) {
    const { error } = await this.db
      .from('activo_componentes')
      .update({ lectura_inicial: valor })
      .eq('id', id);
    return this.res<null>(null, error);
  }

  // ---- destinos y tarifas
  async destinos(grupo: string): Promise<DestinoModel[]> {
    const { data } = await this.db
      .from('destinos')
      .select('id, nombre, activo, orden')
      .eq('grupo_id', grupo)
      .order('orden')
      .order('nombre');
    return (data ?? []) as DestinoModel[];
  }

  async crearDestino(grupo: string, nombre: string, orden: number) {
    const { error } = await this.db
      .from('destinos')
      .insert({ grupo_id: grupo, nombre: nombre.trim(), orden });
    return this.res<null>(null, error);
  }

  async cambiarDestino(id: string, cambios: Partial<DestinoModel>) {
    const { error } = await this.db.from('destinos').update(cambios).eq('id', id);
    return this.res<null>(null, error);
  }

  async tarifas(grupo: string): Promise<TarifaModel[]> {
    const { data } = await this.db
      .from('tarifas')
      .select('id, destino_id, tipo, monto, moneda, vigente_desde, vigente_hasta')
      .eq('grupo_id', grupo)
      .order('vigente_desde', { ascending: false });
    return (data ?? []) as TarifaModel[];
  }

  /** Fija el fee vigente de un destino: cierra el anterior (si empezó antes de hoy) y abre uno nuevo desde hoy. */
  async fijarFee(grupo: string, destino: string, monto: number, moneda: string) {
    const hoy = new Date().toISOString().slice(0, 10);
    const ayer = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
    const { data: abiertas } = await this.db
      .from('tarifas')
      .select('id, vigente_desde')
      .eq('grupo_id', grupo)
      .eq('destino_id', destino)
      .eq('tipo', 'fee_destino')
      .is('vigente_hasta', null);
    for (const t of (abiertas ?? []) as { id: string; vigente_desde: string }[]) {
      if (t.vigente_desde >= hoy) {
        const { error } = await this.db.from('tarifas').update({ monto, moneda }).eq('id', t.id);
        return this.res<null>(null, error);
      }
      const { error } = await this.db
        .from('tarifas')
        .update({ vigente_hasta: ayer })
        .eq('id', t.id);
      if (error) return this.res<null>(null, error);
    }
    const { error } = await this.db
      .from('tarifas')
      .insert({
        grupo_id: grupo,
        destino_id: destino,
        tipo: 'fee_destino',
        monto,
        moneda,
        vigente_desde: hoy,
      });
    return this.res<null>(null, error);
  }

  // ---- correos
  async correos(grupo: string): Promise<CorreoModel[]> {
    const { data } = await this.db
      .from('grupo_correos')
      .select('id, correo, tipo, activo')
      .eq('grupo_id', grupo)
      .order('correo');
    return (data ?? []) as CorreoModel[];
  }

  async agregarCorreo(grupo: string, correo: string, tipo: CorreoModel['tipo']) {
    const { error } = await this.db
      .from('grupo_correos')
      .insert({ grupo_id: grupo, correo: correo.trim(), tipo });
    return this.res<null>(null, error);
  }

  async quitarCorreo(id: string) {
    const { error } = await this.db.from('grupo_correos').delete().eq('id', id);
    return this.res<null>(null, error);
  }
}
