import { signal } from '@angular/core';
import { EN } from './en';
import { ClaveI18n, ES } from './es';

export type Idioma = 'es' | 'en';

const CLAVE_ALMACEN = 'shared.idioma';

function idiomaInicial(): Idioma {
  try {
    const guardado = localStorage.getItem(CLAVE_ALMACEN);
    if (guardado === 'es' || guardado === 'en') return guardado;
  } catch {
    // sin almacenamiento: usar es
  }
  return 'es';
}

const _idioma = signal<Idioma>(idiomaInicial());
export const idioma = _idioma.asReadonly();

export function cambiarIdioma(nuevo: Idioma): void {
  _idioma.set(nuevo);
  try {
    localStorage.setItem(CLAVE_ALMACEN, nuevo);
  } catch {
    // ignorar
  }
}

/** Traduce una clave. Lee el signal de idioma, así que es reactivo en plantillas. */
export function t(clave: ClaveI18n, params?: Record<string, string | number>): string {
  const diccionario: Record<string, string> = _idioma() === 'en' ? EN : ES;
  let texto = diccionario[clave] ?? ES[clave] ?? clave;
  if (params) {
    for (const [k, v] of Object.entries(params)) texto = texto.replaceAll(`{${k}}`, String(v));
  }
  return texto;
}
