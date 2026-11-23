import { Injectable } from '@angular/core';
import { AcuseModel, VersionEstatutoModel } from '../../shared/models/config.model';
import { POLITICAS_CATALOGO, PoliticaCatalogo } from './politicas-catalogo';
import { SupabaseService } from './supabase.service';

export interface PoliticaVigente {
  def: PoliticaCatalogo;
  valor: unknown;
  esDefecto: boolean;
}

/** Espejo en Angular de `politica(grupo, clave)`; la base es la autoridad. */
@Injectable({ providedIn: 'root' })
export class PoliticaService {
  readonly catalogo = POLITICAS_CATALOGO;

  constructor(private supabase: SupabaseService) {}

  definicion(clave: string): PoliticaCatalogo | undefined {
    return this.catalogo.find((p) => p.clave === clave);
  }

  /** Valores vigentes del grupo (con DEFAULT del catálogo donde no hay cambio aceptado). */
  async vigentes(grupo: string): Promise<PoliticaVigente[]> {
    const { data } = await this.supabase.cliente.rpc('politicas_del_grupo', { p_grupo: grupo });
    const filas = (data ?? []) as { clave: string; valor: unknown; es_defecto: boolean }[];
    const mapa = new Map(filas.map((f) => [f.clave, f]));
    return this.catalogo.map((def) => {
      const f = mapa.get(def.clave);
      return { def, valor: f ? f.valor : def.defecto, esDefecto: f ? f.es_defecto : true };
    });
  }

  async valor(grupo: string, clave: string): Promise<unknown> {
    const { data } = await this.supabase.cliente.rpc('politica', {
      p_grupo: grupo,
      p_clave: clave,
    });
    return data;
  }

  async versiones(grupo: string): Promise<VersionEstatutoModel[]> {
    const { data } = await this.supabase.cliente
      .from('estatuto_versiones')
      .select('id, numero, estado, cambios, motivo, propuesta_por, creado_en, vigente_desde')
      .eq('grupo_id', grupo)
      .order('numero', { ascending: false });
    return (data ?? []) as VersionEstatutoModel[];
  }

  async acuses(grupo: string): Promise<AcuseModel[]> {
    const { data } = await this.supabase.cliente
      .from('estatuto_acuses')
      .select('version_id, miembro_id, acepta, momento')
      .eq('grupo_id', grupo);
    return (data ?? []) as AcuseModel[];
  }

  async proponer(grupo: string, cambios: Record<string, unknown>, motivo: string) {
    const { error } = await this.supabase.cliente.rpc('proponer_cambio_politica', {
      p_grupo: grupo,
      p_cambios: cambios,
      p_motivo: motivo || null,
    });
    return error?.message ?? null;
  }

  async responder(version: string, acepta: boolean) {
    const { error } = await this.supabase.cliente.rpc('aceptar_version', {
      p_version: version,
      p_acepta: acepta,
    });
    return error?.message ?? null;
  }

  async retirar(version: string) {
    const { error } = await this.supabase.cliente.rpc('cancelar_version', { p_version: version });
    return error?.message ?? null;
  }
}
