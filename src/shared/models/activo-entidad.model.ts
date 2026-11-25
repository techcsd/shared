import { DefinicionTipo } from './config.model';

// Entidad completa del activo (migración 34): ficha, fotos, documentos, equipo, contactos, campos propios, valor e historial.
export type CondicionActivo = 'excelente' | 'buena' | 'regular' | 'atencion';
export type CondicionEquipo = 'nuevo' | 'bueno' | 'regular' | 'reparar' | 'faltante';
export type TipoDocumento = 'matricula' | 'seguro' | 'factura' | 'manual' | 'permiso' | 'inspeccion' | 'contrato' | 'otro';
export type CategoriaContacto = 'marina' | 'mecanico' | 'aseguradora' | 'emergencia' | 'proveedor' | 'otro';
export type TipoCampoPropio = 'texto' | 'numero' | 'fecha' | 'si_no' | 'seleccion';

export const CONDICIONES_ACTIVO: CondicionActivo[] = ['excelente', 'buena', 'regular', 'atencion'];
export const CONDICIONES_EQUIPO: CondicionEquipo[] = ['nuevo', 'bueno', 'regular', 'reparar', 'faltante'];
export const TIPOS_DOCUMENTO: TipoDocumento[] = ['matricula', 'seguro', 'factura', 'manual', 'permiso', 'inspeccion', 'contrato', 'otro'];
export const CATEGORIAS_CONTACTO: CategoriaContacto[] = ['marina', 'mecanico', 'aseguradora', 'emergencia', 'proveedor', 'otro'];
export const TIPOS_CAMPO_PROPIO: TipoCampoPropio[] = ['texto', 'numero', 'fecha', 'si_no', 'seleccion'];

export interface FichaActivo {
  activo_id: string;
  condicion: CondicionActivo | null;
  condicion_notas: string | null;
  condicion_actualizada_en: string | null;
  condicion_actualizada_por: string | null;
  ubicacion_texto: string | null;
  ubicacion_url: string | null;
}

export interface FotoActivo {
  id: string;
  ruta: string;
  descripcion: string | null;
  orden: number;
  es_portada: boolean;
}

export interface DocumentoActivo {
  id: string;
  tipo: TipoDocumento;
  titulo: string;
  ruta: string;
  mime: string | null;
  tamano_bytes: number | null;
  emitido_en: string | null;
  vence_en: string | null;
  notas: string | null;
}

export interface EquipoActivo {
  id: string;
  nombre: string;
  cantidad: number;
  condicion: CondicionEquipo;
  notas: string | null;
  orden: number;
}

export interface ContactoActivo {
  id: string;
  categoria: CategoriaContacto;
  nombre: string;
  telefono: string | null;
  correo: string | null;
  notas: string | null;
  orden: number;
}

export interface CampoPropio {
  id: string;
  etiqueta: string;
  tipo: TipoCampoPropio;
  unidad: string | null;
  opciones: string[] | null;
  valor: string | number | boolean | null;
  orden: number;
}

export interface ValorActivo {
  activo_id: string;
  precio_compra: number | null;
  moneda_compra: string | null;
  fecha_compra: string | null;
  valor_estimado: number | null;
  moneda_estimado: string | null;
  fecha_estimado: string | null;
}

export interface MejoraActivo {
  id: string;
  fecha: string;
  descripcion: string;
  costo: number;
  moneda: string;
  proveedor: string | null;
  notas: string | null;
}

export interface SocioPermiso {
  miembro_id: string;
  nombre: string;
  puede_editar: boolean;
  es_creador: boolean;
}

/** Todo el activo en una llamada (RPC `activo_detalle`). `valor`, `mejoras` y `socios` vienen en null si no hay permiso. */
export interface DetalleActivo {
  activo: {
    id: string;
    grupo_id: string;
    nombre: string;
    estado: 'borrador' | 'activo' | 'inactivo';
    descripcion: string | null;
    imagen_path: string | null;
    capacidad_legal: number | null;
    punto_encuentro: string | null;
    reglas_invitados: string | null;
    valores: Record<string, unknown>;
    tipo: { clave: string; nombre: string; definicion: DefinicionTipo };
  };
  grupo: { id: string; nombre: string; moneda: string };
  permisos: { editar: boolean; admin: boolean; socio: boolean };
  ficha: FichaActivo | null;
  condicion_por: string | null;
  fotos: FotoActivo[];
  documentos: DocumentoActivo[];
  equipo: EquipoActivo[];
  contactos: ContactoActivo[];
  campos: CampoPropio[];
  valor: ValorActivo | null;
  mejoras: MejoraActivo[] | null;
  socios: SocioPermiso[] | null;
}

export interface CambioHistorial {
  campo: string;
  antes: unknown;
  despues: unknown;
}

export interface EntradaHistorial {
  id: number;
  momento: string;
  tabla: string;
  accion: 'INSERT' | 'UPDATE' | 'DELETE';
  actor: string;
  titulo: string | null;
  cambios: CambioHistorial[];
}
