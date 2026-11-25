export type TipoCampo = 'texto' | 'numero' | 'fecha' | 'booleano' | 'opcion';
export type MomentoChecklist = 'salida' | 'regreso' | 'seguridad';

export interface CampoDef {
  clave: string;
  etiqueta: string;
  tipo: TipoCampo;
  obligatorio?: boolean;
  unidad?: string;
  opciones?: string[];
}

export interface ComponenteDef {
  clave: string;
  etiqueta: string;
  cantidad_defecto: number;
  medidor: { tipo: 'horometro' | 'odometro'; unidad: string };
}

export interface ItemChecklist {
  clave: string;
  texto: string;
  obligatorio?: boolean;
}

export interface DefinicionTipo {
  campos?: CampoDef[];
  componentes?: ComponenteDef[];
  checklists?: Partial<Record<MomentoChecklist, ItemChecklist[]>>;
  categorias_gasto?: string[];
  terminologia?: Record<string, string>;
  limites_capacidad?: { socio?: number; invitado?: number };
}

export interface TipoActivoModel {
  id: string;
  grupo_id: string | null;
  clave: string;
  nombre: string;
  es_sistema: boolean;
  definicion: DefinicionTipo;
  prefijo_orden: string;
}

export interface ActivoModel {
  id: string;
  grupo_id: string;
  tipo_id: string;
  nombre: string;
  capacidad_legal: number | null;
  valores: Record<string, unknown>;
  punto_encuentro: string | null;
  reglas_invitados: string | null;
  contacto_invitados: string | null;
  descripcion: string | null;
  imagen_path: string | null;
  estado: 'borrador' | 'activo' | 'inactivo';
}

export interface ComponenteActivoModel {
  id: string;
  activo_id: string;
  clave: string;
  etiqueta: string;
  indice: number;
  unidad: string;
  lectura_inicial: number;
}

export interface DestinoModel {
  id: string;
  nombre: string;
  activo: boolean;
  orden: number;
}

export interface TarifaModel {
  id: string;
  destino_id: string | null;
  tipo: 'fee_destino' | 'hora';
  monto: number;
  moneda: string;
  vigente_desde: string;
  vigente_hasta: string | null;
}

export interface CorreoModel {
  id: string;
  correo: string;
  tipo: 'ordenes' | 'alertas' | 'invitados';
  activo: boolean;
}

export interface VersionEstatutoModel {
  id: string;
  numero: number;
  estado: 'pendiente' | 'vigente' | 'reemplazada' | 'rechazada';
  cambios: Record<string, unknown>;
  motivo: string | null;
  propuesta_por: string | null;
  creado_en: string;
  vigente_desde: string | null;
}

export interface AcuseModel {
  version_id: string;
  miembro_id: string;
  acepta: boolean;
  momento: string;
}
