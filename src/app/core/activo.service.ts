import { Injectable } from '@angular/core';
import { ActivoResumen, Vitrina, VistaActivoPublica } from '../../shared/models/activo.model';
import {
  DetalleActivo,
  DocumentoActivo,
  EntradaHistorial,
  FotoActivo,
  TipoDocumento,
} from '../../shared/models/activo-entidad.model';
import { t } from './i18n/i18n';
import { MAX_BYTES_IMAGEN, MIME_IMAGEN, reducirImagen } from './imagen';
import { Resultado } from './reserva.service';
import { SupabaseService } from './supabase.service';

const BUCKET = 'activos';
const BUCKET_DOCS = 'activo-documentos';
const MIME_DOCUMENTO = ['application/pdf', 'image/jpeg', 'image/png', 'image/webp'];
const MAX_BYTES_DOCUMENTO = 15 * 1024 * 1024;

export type TablaLista =
  | 'activo_equipo'
  | 'activo_contactos'
  | 'activo_campos'
  | 'activo_mejoras'
  | 'activo_documentos'
  | 'activo_fotos';

/** El activo como entidad: vitrina, detalle editable, galería, documentos privados e historial. Toda regla vive en la base. */
@Injectable({ providedIn: 'root' })
export class ActivoService {
  constructor(private supabase: SupabaseService) {}

  private get db() {
    return this.supabase.cliente;
  }

  /** URL pública de la foto (bucket público, ruta con uuid no adivinable; ver DF-106). */
  urlImagen(path: string | null | undefined): string | null {
    if (!path) return null;
    return this.db.storage.from(BUCKET).getPublicUrl(path).data.publicUrl;
  }

  async vitrina(grupo: string): Promise<Resultado<Vitrina>> {
    const { data, error } = await this.db.rpc('activo_vitrina', { p_grupo: grupo });
    return { datos: error ? null : (data as Vitrina), error: error?.message ?? null };
  }

  /** Primer activo (no inactivo) de cada grupo, para tarjetas y encabezado. */
  async resumenes(grupos: string[]): Promise<Record<string, ActivoResumen>> {
    const salida: Record<string, ActivoResumen> = {};
    if (grupos.length === 0) return salida;
    const { data } = await this.db
      .from('activos')
      .select(
        'id, grupo_id, nombre, descripcion, imagen_path, capacidad_legal, tipo:tipos_activo(clave, nombre)',
      )
      .in('grupo_id', grupos)
      .neq('estado', 'inactivo')
      .order('creado_en');
    for (const f of (data ?? []) as unknown as (Omit<ActivoResumen, 'tipo_clave' | 'tipo_nombre' | 'condicion'> & {
      tipo: { clave: string; nombre: string } | null;
    })[]) {
      if (salida[f.grupo_id]) continue;
      salida[f.grupo_id] = {
        id: f.id,
        grupo_id: f.grupo_id,
        nombre: f.nombre,
        descripcion: f.descripcion,
        imagen_path: f.imagen_path,
        capacidad_legal: f.capacidad_legal,
        tipo_clave: f.tipo?.clave ?? '',
        tipo_nombre: f.tipo?.nombre ?? '',
        condicion: null,
      };
    }
    const ids = Object.values(salida).map((a) => a.id);
    if (ids.length) {
      const { data: fichas } = await this.db.from('activo_ficha').select('activo_id, condicion').in('activo_id', ids);
      for (const f of (fichas ?? []) as { activo_id: string; condicion: string | null }[]) {
        const a = Object.values(salida).find((x) => x.id === f.activo_id);
        if (a) a.condicion = f.condicion;
      }
    }
    return salida;
  }

  async vistaPorToken(token: string): Promise<VistaActivoPublica | null> {
    const { data } = await this.db.rpc('activo_vista_por_token', { p_token: token });
    return (data as VistaActivoPublica | null) ?? null;
  }

  async vistaPorInvitacion(id: string): Promise<VistaActivoPublica | null> {
    const { data } = await this.db.rpc('activo_vista_por_invitacion', { p_invitacion: id });
    return (data as VistaActivoPublica | null) ?? null;
  }

  // ---------------------------------------------------------------- entidad completa (mig. 34)
  async detalle(activo: string): Promise<Resultado<DetalleActivo>> {
    const { data, error } = await this.db.rpc('activo_detalle', { p_activo: activo });
    return { datos: error ? null : (data as DetalleActivo), error: error?.message ?? null };
  }

  async historial(activo: string, limite = 120): Promise<Resultado<EntradaHistorial[]>> {
    const { data, error } = await this.db.rpc('activo_historial', { p_activo: activo, p_limite: limite });
    return { datos: error ? null : ((data ?? []) as EntradaHistorial[]), error: error?.message ?? null };
  }

  /** Campos propios del activo (descripción, encuentro, reglas y los valores de la ficha del tipo). */
  async guardarActivo(id: string, cambios: Record<string, unknown>): Promise<Resultado<null>> {
    const { data, error } = await this.db.from('activos').update(cambios).eq('id', id).select('id');
    if (error) return { datos: null, error: error.message };
    // la RLS no da error cuando no hay permiso: simplemente no actualiza nada
    if (!data || data.length === 0) return { datos: null, error: 'row-level security' };
    return { datos: null, error: null };
  }

  /** Ficha (condición y ubicación) y valor: una fila por activo. */
  async guardarUnica(
    tabla: 'activo_ficha' | 'activo_valor',
    activo: string,
    grupo: string,
    datos: Record<string, unknown>,
  ): Promise<Resultado<null>> {
    const { error } = await this.db
      .from(tabla)
      .upsert({ activo_id: activo, grupo_id: grupo, ...datos }, { onConflict: 'activo_id' });
    return { datos: null, error: error?.message ?? null };
  }

  /** Alta o edición de una fila de lista (equipo, contactos, campos propios, mejoras, documentos, fotos). */
  async guardarFila(
    tabla: TablaLista,
    grupo: string,
    activo: string,
    fila: Record<string, unknown>,
    id?: string,
  ): Promise<Resultado<string>> {
    if (id) {
      const { data, error } = await this.db.from(tabla).update(fila).eq('id', id).select('id');
      if (error) return { datos: null, error: error.message };
      if (!data || data.length === 0) return { datos: null, error: 'row-level security' };
      return { datos: id, error: null };
    }
    const { data, error } = await this.db
      .from(tabla)
      .insert({ grupo_id: grupo, activo_id: activo, ...fila })
      .select('id')
      .single();
    return { datos: error ? null : (data as { id: string }).id, error: error?.message ?? null };
  }

  async borrarFila(tabla: TablaLista, id: string): Promise<Resultado<null>> {
    const { data, error } = await this.db.from(tabla).delete().eq('id', id).select('id');
    if (error) return { datos: null, error: error.message };
    if (!data || data.length === 0) return { datos: null, error: 'row-level security' };
    return { datos: null, error: null };
  }

  async reordenar(
    tabla: 'activo_fotos' | 'activo_equipo' | 'activo_contactos' | 'activo_campos',
    ids: string[],
  ): Promise<Resultado<null>> {
    const { error } = await this.db.rpc('activo_reordenar', { p_tabla: tabla, p_ids: ids });
    return { datos: null, error: error?.message ?? null };
  }

  async permisoEditar(grupo: string, miembro: string, permitir: boolean): Promise<Resultado<null>> {
    const { error } = await this.db.rpc('activo_permiso_editar', {
      p_grupo: grupo,
      p_miembro: miembro,
      p_permitir: permitir,
    });
    return { datos: null, error: error?.message ?? null };
  }

  // ---------------------------------------------------------------- galería
  /** Reduce la foto en el navegador, la sube al bucket público `activos` y la agrega a la galería. */
  async subirFoto(grupo: string, activo: string, archivo: File, orden: number): Promise<Resultado<string>> {
    if (!MIME_IMAGEN.includes(archivo.type)) return { datos: null, error: 'imagen_tipo_invalido' };
    let reducida;
    try {
      reducida = await reducirImagen(archivo);
    } catch {
      return { datos: null, error: 'imagen_ilegible' };
    }
    if (reducida.blob.size > MAX_BYTES_IMAGEN) return { datos: null, error: 'imagen_muy_grande' };
    const ruta = `${grupo}/${activo}-${crypto.randomUUID()}.${reducida.extension}`;
    const sub = await this.db.storage.from(BUCKET).upload(ruta, reducida.blob, {
      contentType: reducida.blob.type,
      cacheControl: '31536000',
    });
    if (sub.error) return { datos: null, error: sub.error.message };
    const r = await this.guardarFila('activo_fotos', grupo, activo, { ruta, orden });
    if (r.error) {
      await this.db.storage.from(BUCKET).remove([ruta]);
      return { datos: null, error: r.error };
    }
    return { datos: ruta, error: null };
  }

  async portada(foto: string): Promise<Resultado<null>> {
    const { error } = await this.db.rpc('activo_foto_portada', { p_foto: foto });
    return { datos: null, error: error?.message ?? null };
  }

  async borrarFoto(foto: FotoActivo): Promise<Resultado<null>> {
    const r = await this.borrarFila('activo_fotos', foto.id);
    if (r.error) return r;
    await this.db.storage.from(BUCKET).remove([foto.ruta]);
    return { datos: null, error: null };
  }

  // ---------------------------------------------------------------- documentos (bucket PRIVADO, URL firmada)
  async subirDocumento(
    grupo: string,
    activo: string,
    archivo: File,
    meta: { tipo: TipoDocumento; titulo: string; emitido_en: string | null; vence_en: string | null; notas: string | null },
  ): Promise<Resultado<string>> {
    if (!MIME_DOCUMENTO.includes(archivo.type)) return { datos: null, error: 'documento_tipo_invalido' };
    if (archivo.size > MAX_BYTES_DOCUMENTO) return { datos: null, error: 'documento_muy_grande' };
    const ext =
      archivo.type === 'application/pdf' ? 'pdf' : archivo.type === 'image/png' ? 'png' : archivo.type === 'image/webp' ? 'webp' : 'jpg';
    const ruta = `${grupo}/${activo}-${crypto.randomUUID()}.${ext}`;
    const sub = await this.db.storage.from(BUCKET_DOCS).upload(ruta, archivo, { contentType: archivo.type });
    if (sub.error) return { datos: null, error: sub.error.message };
    const r = await this.guardarFila('activo_documentos', grupo, activo, {
      ...meta,
      ruta,
      mime: archivo.type,
      tamano_bytes: archivo.size,
    });
    if (r.error) {
      await this.db.storage.from(BUCKET_DOCS).remove([ruta]);
      return { datos: null, error: r.error };
    }
    return { datos: ruta, error: null };
  }

  /** URL firmada de corta vida: solo los miembros del grupo pueden pedirla (política de Storage). */
  async urlDocumento(ruta: string): Promise<string | null> {
    const { data, error } = await this.db.storage.from(BUCKET_DOCS).createSignedUrl(ruta, 300);
    return error ? null : data.signedUrl;
  }

  async borrarDocumento(doc: DocumentoActivo): Promise<Resultado<null>> {
    const r = await this.borrarFila('activo_documentos', doc.id);
    if (r.error) return r;
    await this.db.storage.from(BUCKET_DOCS).remove([doc.ruta]);
    return { datos: null, error: null };
  }
}

/** Traduce el mensaje de la base o de Storage a un texto para el usuario. */
export function errorActivo(msg: string): string {
  const k: [string, Parameters<typeof t>[0]][] = [
    ['row-level security', 'activo.e.sin_permiso'],
    ['sin_permiso', 'activo.e.sin_permiso'],
    ['valor_invalido', 'activo.e.valor_invalido'],
    ['opciones_requeridas', 'activo.e.opciones'],
    ['opciones_invalidas', 'activo.e.opciones'],
    ['duplicate key', 'activo.e.duplicado'],
    ['demasiadas_fotos', 'activo.e.max_fotos'],
    ['demasiados_documentos', 'activo.e.max_docs'],
    ['demasiado_equipo', 'activo.e.max_equipo'],
    ['demasiados_campos', 'activo.e.max_campos'],
    ['imagen_tipo_invalido', 'activo.error.tipo'],
    ['imagen_ilegible', 'activo.error.ilegible'],
    ['imagen_muy_grande', 'activo.error.grande'],
    ['documento_tipo_invalido', 'activo.e.doc_tipo'],
    ['documento_muy_grande', 'activo.e.doc_grande'],
    ['creador_siempre_edita', 'activo.e.creador'],
    ['check constraint', 'activo.e.dato_invalido'],
    ['violates check', 'activo.e.dato_invalido'],
    ['Payload too large', 'activo.e.doc_grande'],
    ['exceeded the maximum', 'activo.e.doc_grande'],
  ];
  const hit = k.find(([frag]) => msg.includes(frag));
  return hit ? t(hit[1]) : t('app.error.generico');
}
