export interface FaltanteItem {
  codigo: string;
  detalle: string;
  componente_id?: string;
  momento?: string;
  clave?: string;
}

export interface ResultadoCheckin {
  ok: boolean;
  faltan?: FaltanteItem[];
  operacion_id?: string;
}

export interface ResumenLiquidacion {
  orden: string | null;
  horas_por_componente: {
    componente_id: string;
    etiqueta: string;
    unidad: string;
    inicio: number;
    fin: number;
    horas: number;
  }[];
  combustible_consumido: number | null;
  gastos_individuales: number;
  fee: number;
  fee_destino_a: string;
}

export interface ResultadoCheckout {
  ok: boolean;
  cerrada: boolean;
  faltan: FaltanteItem[];
  resumen?: ResumenLiquidacion;
}

export interface OperacionModel {
  id: string;
  reserva_id: string;
  activo_id: string;
  capitan_miembro: string | null;
  capitan_nombre: string | null;
  salida_real: string;
  regreso_real: string | null;
  combustible_inicial: number;
  combustible_final: number | null;
  combustible_unidad: string;
  observaciones: string | null;
  cerrada_en: string | null;
}

export interface LecturaVigente {
  id: number;
  componente_id: string;
  momento: 'inicio' | 'fin';
  valor: number;
  motivo: string | null;
}

export interface IncidenciaModel {
  id: string;
  tipo: 'observacion' | 'incidencia' | 'dano';
  descripcion: string;
  creado_en: string;
}

export type AlcanceGasto = 'comun' | 'individual' | 'dano';
export type EstadoGasto = 'registrado' | 'validado' | 'disputado' | 'anulado';

export interface GastoModel {
  id: string;
  alcance: AlcanceGasto;
  categoria: string;
  descripcion: string | null;
  monto: number;
  moneda: string;
  tasa: number;
  monto_grupo: number;
  moneda_grupo: string;
  pagado_por_tipo: 'miembro' | 'fondo' | 'externo';
  pagado_por_miembro: string | null;
  proveedor: string | null;
  fecha: string;
  vencimiento: string | null;
  reserva_id: string | null;
  estado: EstadoGasto;
  cargado_por: string;
  validado_por: string | null;
  motivo_estado: string | null;
  creado_en: string;
}

export interface NuevoGasto {
  alcance: 'comun' | 'individual';
  categoria: string;
  monto: number;
  moneda: string;
  pagadoTipo: 'miembro' | 'fondo' | 'externo';
  pagadoMiembro?: string | null;
  proveedor?: string;
  descripcion?: string;
  reserva?: string | null;
  fecha?: string | null;
  vencimiento?: string | null;
  tasa?: number | null;
}

export interface BalanceFila {
  cuenta_tipo: 'miembro' | 'fondo' | 'externo';
  miembro_id: string | null;
  nombre: string;
  rol: string | null;
  moneda: string;
  confirmado: number;
  provisional: number;
  balance: number;
}

export interface MovimientoCuenta {
  id: number;
  momento: string;
  origen_tipo: string;
  origen_id: string;
  nota: string | null;
  debe: number;
  haber: number;
  monto_original: number | null;
  moneda_original: string | null;
  tasa: number | null;
  moneda: string;
  provisional: boolean;
  saldo: number;
  comprobantes: number;
}

export interface PagoModel {
  id: string;
  de_miembro: string;
  a_tipo: 'miembro' | 'fondo';
  a_miembro: string | null;
  monto: number;
  moneda: string;
  monto_grupo: number;
  moneda_grupo: string;
  nota: string | null;
  estado: 'pendiente' | 'confirmado' | 'rechazado';
  motivo_rechazo: string | null;
  creado_en: string;
}

export interface DanoCaso {
  id: string;
  reserva_id: string | null;
  titulo: string;
  descripcion: string | null;
  presupuesto: number | null;
  moneda: string | null;
  pagado_por_tipo: string | null;
  pagado_por_miembro: string | null;
  propuesta: { miembro_id: string; monto: number }[];
  version: number;
  estado: 'en_revision' | 'acordado' | 'rechazado';
  creado_en: string;
}

export interface DanoMensaje {
  id: string;
  autor_id: string | null;
  tipo: string;
  texto: string | null;
  creado_en: string;
}

export interface DanoAcuerdo {
  miembro_id: string;
  version: number;
  acepta: boolean;
}

export interface MovimientoFondo {
  id: number;
  momento: string;
  debe: number;
  haber: number;
  moneda: string;
  origen_tipo: string;
  nota: string | null;
}

export interface EvidenciaModel {
  id: string;
  ref_tipo: string;
  ref_id: string;
  tipo: string;
  ruta: string;
  mime: string | null;
}
