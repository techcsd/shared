import { Injectable } from '@angular/core';
import { Resultado } from './reserva.service';
import { SupabaseService } from './supabase.service';

export interface PropuestaModel {
  id: string;
  organizador_id: string;
  titulo: string;
  tipo_activo_id: string;
  descripcion: string | null;
  precio_objetivo: number;
  moneda: string;
  fecha_limite: string | null;
  estado: 'borrador' | 'abierta' | 'fondeada' | 'adquirida' | 'convertida' | 'cancelada' | 'expirada';
  cupos: number | null;
  directorio_visible: boolean;
  adquisicion_registrada_en: string | null;
  grupo_id: string | null;
}

export interface TotalesPropuesta {
  precio: number;
  comprometido: number;
  confirmado: number;
  declarado: number;
  porcentaje_fondeado: number;
  participantes: number;
}

export interface ParticipantePropuesta {
  id: string;
  usuario_id: string;
  estado: 'acepto' | 'salio';
  compromiso: number;
  acuse_adquisicion_en: string | null;
}

export interface AportePropuesta {
  id: string;
  participante_id: string;
  monto: number;
  nota: string | null;
  estado: 'declarado' | 'confirmado' | 'rechazado';
  acuse_aportante_en: string | null;
  reembolsado_en: string | null;
}

export interface FilaDirectorio {
  id: string;
  tipo: string;
  precio_objetivo: number;
  moneda: string;
  porcentaje_fondeado: number;
  cupos_libres: number | null;
  fecha_limite: string | null;
}

export interface ItemLanzamiento {
  clave: string;
  ok: boolean;
}

export interface Salud {
  errores_24h: number;
  errores_recientes: { momento: string; mensaje: string; ruta: string | null }[];
  notificaciones: Record<string, number>;
  fallos_correo: { momento: string; tipo: string; motivo: string | null; reintentos: number }[];
  reservas_por_dia: { dia: string; n: number }[];
  asistente_ms: { n: number; promedio: number | null; mediana: number | null };
  grupos: number;
  grupos_demo: number;
  propuestas_abiertas: number;
  directorio_habilitado: boolean;
}

/** Formación de grupos (propuestas de compra), directorio opcional, lanzamiento y salud. SIN custodia de dinero. */
@Injectable({ providedIn: 'root' })
export class FormacionService {
  constructor(private supabase: SupabaseService) {}

  private get db() {
    return this.supabase.cliente;
  }

  private r<T>(datos: T | null, error: { message: string } | null): Resultado<T> {
    return { datos: error ? null : datos, error: error?.message ?? null };
  }

  async propuestas(): Promise<PropuestaModel[]> {
    const { data } = await this.db
      .from('propuestas_compra')
      .select('id, organizador_id, titulo, tipo_activo_id, descripcion, precio_objetivo, moneda, fecha_limite, estado, cupos, directorio_visible, adquisicion_registrada_en, grupo_id')
      .order('creado_en', { ascending: false });
    return ((data ?? []) as PropuestaModel[]).map((p) => ({ ...p, precio_objetivo: Number(p.precio_objetivo) }));
  }

  async tiposSistema(): Promise<{ id: string; nombre: string }[]> {
    const { data } = await this.db.from('tipos_activo').select('id, nombre').eq('es_sistema', true).order('nombre');
    return (data ?? []) as { id: string; nombre: string }[];
  }

  async totales(id: string): Promise<TotalesPropuesta | null> {
    const { data } = await this.db.rpc('propuesta_totales', { p_prop: id });
    const f = ((data ?? []) as TotalesPropuesta[])[0];
    return f ? { ...f, precio: Number(f.precio), comprometido: Number(f.comprometido), confirmado: Number(f.confirmado), declarado: Number(f.declarado), porcentaje_fondeado: Number(f.porcentaje_fondeado) } : null;
  }

  async participantes(id: string): Promise<ParticipantePropuesta[]> {
    const { data } = await this.db.from('propuesta_participantes').select('id, usuario_id, estado, compromiso, acuse_adquisicion_en').eq('propuesta_id', id);
    return ((data ?? []) as ParticipantePropuesta[]).map((p) => ({ ...p, compromiso: Number(p.compromiso) }));
  }

  async aportes(id: string): Promise<AportePropuesta[]> {
    const { data } = await this.db
      .from('propuesta_aportes')
      .select('id, participante_id, monto, nota, estado, acuse_aportante_en, reembolsado_en')
      .eq('propuesta_id', id)
      .order('creado_en');
    return ((data ?? []) as AportePropuesta[]).map((a) => ({ ...a, monto: Number(a.monto) }));
  }

  async crear(p: { titulo: string; tipo: string; descripcion: string; precio: number; moneda: string; fecha: string | null; cupos: number | null }) {
    const { data, error } = await this.db.rpc('propuesta_crear', {
      p_titulo: p.titulo,
      p_tipo: p.tipo,
      p_descripcion: p.descripcion || null,
      p_precio: p.precio,
      p_moneda: p.moneda,
      p_fecha_limite: p.fecha || null,
      p_cupos: p.cupos,
    });
    return this.r<{ id: string; token: string }>(data as { id: string; token: string }, error);
  }

  async vistaPrevia(token: string): Promise<{ id: string; titulo: string; precio_objetivo: number; moneda: string; organizador: string } | null> {
    const { data } = await this.db.rpc('propuesta_vista_previa', { p_token: token });
    return (data as never) ?? null;
  }

  private async rpc(nombre: string, args: Record<string, unknown>): Promise<Resultado<string>> {
    const { data, error } = await this.db.rpc(nombre, args);
    return this.r<string>((data as string) ?? null, error);
  }

  abrir(id: string) { return this.rpc('propuesta_abrir', { p_prop: id }); }
  unirse(token: string) { return this.rpc('propuesta_unirse', { p_token: token }); }
  comprometer(id: string, monto: number) { return this.rpc('propuesta_comprometer', { p_prop: id, p_monto: monto }); }
  declarar(id: string, monto: number, nota: string) { return this.rpc('propuesta_aporte_declarar', { p_prop: id, p_monto: monto, p_nota: nota || null }); }
  confirmar(aporte: string, ok: boolean) { return this.rpc('propuesta_aporte_confirmar', { p_aporte: aporte, p_confirmar: ok }); }
  acusarAporte(aporte: string) { return this.rpc('propuesta_aporte_acusar', { p_aporte: aporte }); }
  registrarAdquisicion(id: string, nota: string) { return this.rpc('propuesta_registrar_adquisicion', { p_prop: id, p_nota: nota }); }
  acusarAdquisicion(id: string) { return this.rpc('propuesta_acusar_adquisicion', { p_prop: id }); }
  convertir(id: string, nombre: string, prefijo: string) { return this.rpc('propuesta_convertir', { p_prop: id, p_nombre_grupo: nombre, p_prefijo: prefijo, p_zona: 'America/Santo_Domingo' }); }
  cancelar(id: string, motivo: string) { return this.rpc('propuesta_cancelar', { p_prop: id, p_motivo: motivo }); }
  reembolsar(aporte: string, nota: string) { return this.rpc('propuesta_reembolsar', { p_aporte: aporte, p_nota: nota }); }
  visibleEnDirectorio(id: string, visible: boolean) { return this.rpc('propuesta_directorio_visible', { p_prop: id, p_visible: visible }); }
  evidencia(id: string, ruta: string) { return this.rpc('propuesta_evidencia_registrar', { p_prop: id, p_ruta: ruta, p_tipo: 'contrato' }); }

  async subirContrato(propuesta: string, archivo: File): Promise<Resultado<string>> {
    const nombre = archivo.name.replace(/[^a-zA-Z0-9._-]/g, '_').slice(-80);
    const ruta = `propuestas/${propuesta}/${Date.now()}_${nombre}`;
    const sub = await this.db.storage.from('evidencias').upload(ruta, archivo, { contentType: archivo.type || undefined });
    if (sub.error) return { datos: null, error: sub.error.message };
    return this.evidencia(propuesta, ruta);
  }

  // ---- directorio
  async directorioHabilitado(): Promise<boolean> {
    const { data } = await this.db.rpc('directorio_habilitado');
    return data === true;
  }

  async directorio(): Promise<FilaDirectorio[]> {
    const { data } = await this.db.rpc('directorio_listar');
    return ((data ?? []) as FilaDirectorio[]).map((f) => ({ ...f, precio_objetivo: Number(f.precio_objetivo), porcentaje_fondeado: Number(f.porcentaje_fondeado) }));
  }

  solicitar(id: string, mensaje: string) { return this.rpc('directorio_solicitar', { p_prop: id, p_mensaje: mensaje || null }); }

  async solicitudes(id: string): Promise<{ id: string; usuario_id: string; mensaje: string | null; estado: string }[]> {
    const { data } = await this.db.from('directorio_solicitudes').select('id, usuario_id, mensaje, estado').eq('propuesta_id', id);
    return (data ?? []) as never;
  }

  responderSolicitud(id: string, aprobar: boolean) { return this.rpc('directorio_responder', { p_solicitud: id, p_aprobar: aprobar }); }
  reportar(id: string, motivo: string) { return this.rpc('directorio_reportar', { p_prop: id, p_motivo: motivo }); }

  // ---- lanzamiento y salud
  async checklist(grupo: string): Promise<Resultado<ItemLanzamiento[]>> {
    const { data, error } = await this.db.rpc('grupo_checklist_lanzamiento', { p_grupo: grupo });
    return this.r<ItemLanzamiento[]>(data as ItemLanzamiento[], error);
  }

  async pasarAReal(grupo: string): Promise<Resultado<{ ok: boolean; faltan: string[] }>> {
    const { data, error } = await this.db.rpc('grupo_pasar_a_real', { p_grupo: grupo });
    return this.r<{ ok: boolean; faltan: string[] }>(data as { ok: boolean; faltan: string[] }, error);
  }

  async esAdminPlataforma(): Promise<boolean> {
    const { data } = await this.db.rpc('es_admin_plataforma');
    return data === true;
  }

  async salud(): Promise<Resultado<Salud>> {
    const { data, error } = await this.db.rpc('salud_sistema');
    return this.r<Salud>(data as Salud, error);
  }
}
