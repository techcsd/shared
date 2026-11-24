export interface PlanModel {
  id: string;
  activo_id: string;
  componente_id: string | null;
  nombre: string;
  criterio: 'fecha' | 'horas' | 'primero' | null;
  intervalo_dias: number | null;
  intervalo_horas: number | null;
  ultima_fecha: string;
  ultima_lectura: number;
  alerta_dias: number;
  alerta_horas: number;
  activo: boolean;
}

export interface PlanEstado {
  criterio: string;
  vence_fecha: string | null;
  vence_horas: number | null;
  lectura: number | null;
  dias_restantes: number | null;
  horas_restantes: number | null;
  vencido: boolean;
  por_vencer: boolean;
  disparador: string | null;
}

export interface TareaModel {
  id: string;
  plan_id: string | null;
  activo_id: string;
  componente_id: string | null;
  titulo: string;
  estado: 'pendiente' | 'programada' | 'hecha' | 'cancelada';
  vence_fecha: string | null;
  vence_horas: number | null;
  proveedor: string | null;
  notas: string | null;
  bloqueo_reserva_id: string | null;
}

export interface ServicioModel {
  id: string;
  activo_id: string;
  componente_id: string | null;
  fecha: string;
  lectura: number | null;
  proveedor: string | null;
  descripcion: string | null;
  costo: number | null;
  moneda: string | null;
  gasto_id: string | null;
}

export interface ResultadoProgramar {
  ok: boolean;
  bloqueo_id?: string;
  conflictos?: { reserva_id: string; orden: string | null; inicio: string; fin: string }[];
  sugerida?: { inicio: string; fin: string };
}

export interface PolizaModel {
  id: string;
  activo_id: string;
  aseguradora: string;
  numero: string | null;
  cobertura: string | null;
  vigente_desde: string;
  vigente_hasta: string;
  deducible: number;
  moneda: string;
}

export interface SiniestroModel {
  id: string;
  activo_id: string;
  poliza_id: string | null;
  fecha: string;
  descripcion: string;
  estado: 'abierto' | 'en_proceso' | 'cerrado';
  caso_dano_id: string | null;
}

export interface CapitanModel {
  id: string;
  miembro_id: string | null;
  nombre: string;
  licencia_numero: string | null;
  licencia_vence: string | null;
  experiencia_anios: number | null;
  experiencia_notas: string | null;
  estado: 'activo' | 'inactivo';
}

export interface FilaReporte {
  reserva_id: string;
  orden: string | null;
  fecha: string;
  miembro: string | null;
  destino: string | null;
  uso: string;
  estado: string;
  personas: number | null;
  duracion_horas: number;
  horas_motor: number;
  combustible_consumido: number | null;
  fee: number;
  gastos_individuales: number;
  moneda: string;
}

export interface Dashboard {
  salidas: number;
  dias_usados: number;
  horas_duracion: number;
  horas_por_componente: { etiqueta: string; unidad: string; horas: number }[];
  combustible_consumido: number;
  fees: number;
  danos: number;
  gastos_comunes: number;
  costo_total: number;
  por_miembro: { miembro_id: string; nombre: string; porcentaje: number; salidas: number; horas: number; costo: number }[];
  por_mes: { mes: string; salidas: number; costo: number }[];
}

export interface SalidaSocioCaso {
  id: string;
  miembro_id: string;
  porcentaje: number;
  estado: 'abierto' | 'oferta' | 'aceptado' | 'cerrado' | 'cancelado';
  preferencia_hasta: string;
  valoracion_nota: string | null;
  nota: string | null;
}

export interface SalidaSocioOferta {
  id: string;
  caso_id: string;
  miembro_id: string;
  porcentaje: number;
  valor: number;
  moneda: string;
  estado: 'vigente' | 'retirada';
}

export interface DisputaModel {
  id: string;
  grupo_id: string;
  titulo: string;
  ref_tipo: string | null;
  estado: 'abierta' | 'cerrada';
  resultado: 'acuerdo' | 'sin_acuerdo' | null;
  creado_en: string;
}

export interface DisputaMensaje {
  id: string;
  autor_nombre: string | null;
  rol: 'socio' | 'mediador' | 'sistema';
  texto: string;
  creado_en: string;
}
