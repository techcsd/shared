import { PoliticaCatalogo } from './politicas-catalogo';
import { DefinicionTipo } from '../../shared/models/config.model';

// Validación espejo de la base (la base manda: estas funciones solo dan feedback inmediato).

/** Devuelve el motivo del error o null si el valor es válido para la política. */
export function validarPolitica(def: PoliticaCatalogo, valor: unknown): string | null {
  if (valor === null) return def.nullable ? null : 'No admite vacío';
  switch (def.tipo) {
    case 'booleano':
      return typeof valor === 'boolean' ? null : 'Debe ser sí o no';
    case 'entero':
    case 'numero': {
      if (typeof valor !== 'number' || Number.isNaN(valor)) return 'Debe ser un número';
      if (def.tipo === 'entero' && !Number.isInteger(valor)) return 'Debe ser entero';
      if (def.minimo !== undefined && valor < def.minimo) return `Mínimo ${def.minimo}`;
      if (def.maximo !== undefined && valor > def.maximo) return `Máximo ${def.maximo}`;
      return null;
    }
    case 'enum':
      return typeof valor === 'string' && def.opciones?.includes(valor)
        ? null
        : 'Opción no permitida';
    case 'lista': {
      if (!Array.isArray(valor) || valor.length > 20) return 'Debe ser una lista (máx. 20)';
      for (const item of valor) {
        if (def.opciones) {
          if (typeof item !== 'string' || !def.opciones.includes(item))
            return 'Elemento no permitido';
        } else if (
          typeof item !== 'number' ||
          !Number.isInteger(item) ||
          item < (def.minimo ?? 0) ||
          item > (def.maximo ?? 1e9)
        ) {
          return `Cada elemento debe ser entero entre ${def.minimo ?? 0} y ${def.maximo ?? 1e9}`;
        }
      }
      return null;
    }
  }
}

const CLAVE = /^[a-z][a-z0-9_]{0,39}$/;

/** Errores de una definición de tipo de activo (vacío = válida). */
export function validarDefinicionTipo(d: DefinicionTipo): string[] {
  const errores: string[] = [];
  const claves = new Set<string>();
  for (const c of d.campos ?? []) {
    if (!CLAVE.test(c.clave)) errores.push(`Campo «${c.etiqueta || c.clave}»: clave inválida`);
    if (claves.has(c.clave)) errores.push(`Campo repetido: ${c.clave}`);
    claves.add(c.clave);
    if (!c.etiqueta?.trim()) errores.push(`Campo ${c.clave}: falta la etiqueta`);
    if (c.tipo === 'opcion' && !(c.opciones?.length ?? 0))
      errores.push(`Campo ${c.clave}: necesita opciones`);
  }
  const comp = new Set<string>();
  for (const c of d.componentes ?? []) {
    if (!CLAVE.test(c.clave)) errores.push(`Componente «${c.etiqueta || c.clave}»: clave inválida`);
    if (comp.has(c.clave)) errores.push(`Componente repetido: ${c.clave}`);
    comp.add(c.clave);
    if (!c.etiqueta?.trim()) errores.push(`Componente ${c.clave}: falta la etiqueta`);
    if (!Number.isInteger(c.cantidad_defecto) || c.cantidad_defecto < 1 || c.cantidad_defecto > 20)
      errores.push(`Componente ${c.clave}: cantidad entre 1 y 20`);
    if (!c.medidor?.unidad?.trim()) errores.push(`Componente ${c.clave}: falta la unidad`);
  }
  for (const [momento, items] of Object.entries(d.checklists ?? {})) {
    const vistos = new Set<string>();
    for (const i of items ?? []) {
      if (!CLAVE.test(i.clave)) errores.push(`Checklist ${momento}: clave inválida (${i.clave})`);
      if (vistos.has(i.clave)) errores.push(`Checklist ${momento}: ítem repetido ${i.clave}`);
      vistos.add(i.clave);
      if (!i.texto?.trim()) errores.push(`Checklist ${momento}: ítem sin texto`);
    }
  }
  for (const k of ['socio', 'invitado'] as const) {
    const v = d.limites_capacidad?.[k];
    if (v !== undefined && (!Number.isInteger(v) || v < 1)) errores.push(`Límite ${k}: entero ≥ 1`);
  }
  return errores;
}

/** Convierte un texto en una clave válida (a-z, 0-9, _). */
export function aClave(texto: string): string {
  const base = texto
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  const conLetra = /^[a-z]/.test(base) ? base : `x_${base}`;
  return conLetra.slice(0, 40).replace(/_+$/, '') || 'x';
}
