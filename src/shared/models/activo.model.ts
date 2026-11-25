import { DefinicionTipo } from './config.model';

/** Un activo tal como lo muestra la vitrina (RPC `activo_vitrina`, solo miembros y admin de plataforma). */
export interface VitrinaActivo {
  id: string;
  nombre: string;
  estado: 'borrador' | 'activo' | 'inactivo';
  descripcion: string | null;
  imagen_path: string | null;
  capacidad_legal: number | null;
  punto_encuentro: string | null;
  reglas_invitados: string | null;
  valores: Record<string, unknown>;
  tipo: { clave: string; nombre: string; definicion: DefinicionTipo };
  componentes: { etiqueta: string; unidad: string; indice: number }[];
  poliza_vigente: boolean;
}

export interface Vitrina {
  grupo: { id: string; nombre: string; moneda: string };
  activos: VitrinaActivo[];
  destinos: { nombre: string; fee: number | null }[];
  tarifa_hora: { monto: number; moneda: string } | null;
  capitanes: number;
}

/** Subconjunto no sensible para quien aún no es miembro (vista previa de invitación). */
export interface VistaActivoPublica {
  grupo_nombre: string;
  activos: {
    nombre: string;
    descripcion: string | null;
    imagen_path: string | null;
    capacidad_legal: number | null;
    punto_encuentro: string | null;
    tipo: { clave: string; nombre: string };
  }[];
}

/** Resumen de un activo para listas y encabezado (se lee de la tabla `activos`, protegida por RLS). */
export interface ActivoResumen {
  id: string;
  grupo_id: string;
  nombre: string;
  descripcion: string | null;
  imagen_path: string | null;
  capacidad_legal: number | null;
  tipo_clave: string;
  tipo_nombre: string;
}
