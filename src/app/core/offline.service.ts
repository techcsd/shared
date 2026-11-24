import { Injectable, signal } from '@angular/core';
import { SupabaseService } from './supabase.service';

const PREFIJO = 'shared.cache.';
const COLA = 'shared.cola';

/** Únicas acciones que pueden esperar sin conexión: registrar un gasto o corregir una lectura.
 *  NUNCA reservar ni confirmar: el choque de reservas exige el servidor (F4 del PROMPT-5). */
export const ACCIONES_OFFLINE = ['gasto_registrar', 'lectura_corregir'] as const;
export type AccionOffline = (typeof ACCIONES_OFFLINE)[number];

interface ItemCola {
  rpc: AccionOffline;
  args: Record<string, unknown>;
  en: number;
}

/** Lectura offline del calendario y de la última orden + cola de acciones simples (se sincroniza al volver la red). */
@Injectable({ providedIn: 'root' })
export class OfflineService {
  private _pendientes = signal(this.leerCola().length);
  pendientes = this._pendientes.asReadonly();
  private _desdeCache = signal(false);
  /** Verdadero cuando lo que se muestra viene de la copia local (sin conexión). */
  desdeCache = this._desdeCache.asReadonly();

  constructor(private supabase: SupabaseService) {
    if (typeof window !== 'undefined') {
      window.addEventListener('online', () => void this.sincronizar());
    }
  }

  // ---------------- copia local de lectura
  guardar(clave: string, datos: unknown): void {
    try {
      localStorage.setItem(PREFIJO + clave, JSON.stringify({ en: Date.now(), datos }));
    } catch {
      // sin almacenamiento (modo privado, cuota): la app funciona igual
    }
  }

  leer<T>(clave: string): T | null {
    try {
      const raw = localStorage.getItem(PREFIJO + clave);
      return raw ? (JSON.parse(raw).datos as T) : null;
    } catch {
      return null;
    }
  }

  marcarCache(v: boolean): void {
    this._desdeCache.set(v);
  }

  limpiarTodo(): void {
    try {
      for (const k of Object.keys(localStorage)) if (k.startsWith(PREFIJO) || k === COLA) localStorage.removeItem(k);
    } catch {
      // nada
    }
    this._pendientes.set(0);
  }

  // ---------------- cola de acciones simples
  private leerCola(): ItemCola[] {
    try {
      return JSON.parse(localStorage.getItem(COLA) ?? '[]') as ItemCola[];
    } catch {
      return [];
    }
  }

  private escribirCola(c: ItemCola[]): void {
    try {
      localStorage.setItem(COLA, JSON.stringify(c));
    } catch {
      // nada
    }
    this._pendientes.set(c.length);
  }

  /** Verdadero si el fallo parece de red (no de reglas de negocio). */
  esFalloDeRed(mensaje: string | null | undefined): boolean {
    return !!mensaje && /failed to fetch|networkerror|network request failed|load failed/i.test(mensaje);
  }

  encolar(rpc: string, args: Record<string, unknown>): boolean {
    if (!(ACCIONES_OFFLINE as readonly string[]).includes(rpc)) return false;
    this.escribirCola([...this.leerCola(), { rpc: rpc as AccionOffline, args, en: Date.now() }]);
    return true;
  }

  /** Envía lo pendiente en orden; si una acción falla por reglas del servidor se descarta (ya no vale); si falla la red, se detiene. */
  async sincronizar(): Promise<{ enviados: number; descartados: number }> {
    const cola = this.leerCola();
    let enviados = 0;
    let descartados = 0;
    const resto: ItemCola[] = [];
    for (let i = 0; i < cola.length; i++) {
      const item = cola[i];
      const { error } = await this.supabase.cliente.rpc(item.rpc, item.args);
      if (!error) enviados++;
      else if (this.esFalloDeRed(error.message)) {
        resto.push(...cola.slice(i));
        break;
      } else descartados++;
    }
    this.escribirCola(resto);
    return { enviados, descartados };
  }
}
