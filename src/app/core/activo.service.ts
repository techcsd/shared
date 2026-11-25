import { Injectable } from '@angular/core';
import { ActivoResumen, Vitrina, VistaActivoPublica } from '../../shared/models/activo.model';
import { MAX_BYTES_IMAGEN, MIME_IMAGEN, reducirImagen } from './imagen';
import { Resultado } from './reserva.service';
import { SupabaseService } from './supabase.service';

const BUCKET = 'activos';

/** Vitrina del activo: resúmenes, foto (Storage) y vistas previas seguras. Toda regla vive en la base. */
@Injectable({ providedIn: 'root' })
export class ActivoService {
  constructor(private supabase: SupabaseService) {}

  private get db() {
    return this.supabase.cliente;
  }

  /** URL pública de la foto (bucket público, ruta con uuid no adivinable; ver DF-105). */
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
    for (const f of (data ?? []) as unknown as (Omit<ActivoResumen, 'tipo_clave' | 'tipo_nombre'> & {
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
      };
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

  /** Reduce, sube y guarda la foto del activo; borra la anterior. La RLS de Storage exige ser socio (o admin). */
  async subirImagen(
    grupo: string,
    activo: string,
    archivo: File,
    anterior: string | null,
  ): Promise<Resultado<string>> {
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
    const { error } = await this.db.from('activos').update({ imagen_path: ruta }).eq('id', activo);
    if (error) {
      await this.db.storage.from(BUCKET).remove([ruta]);
      return { datos: null, error: error.message };
    }
    if (anterior) await this.db.storage.from(BUCKET).remove([anterior]);
    return { datos: ruta, error: null };
  }

  async quitarImagen(activo: string, anterior: string | null): Promise<Resultado<null>> {
    const { error } = await this.db.from('activos').update({ imagen_path: null }).eq('id', activo);
    if (error) return { datos: null, error: error.message };
    if (anterior) await this.db.storage.from(BUCKET).remove([anterior]);
    return { datos: null, error: null };
  }
}
