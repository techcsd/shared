import { Injectable } from '@angular/core';
import {
  CapitanModel,
  Dashboard,
  DisputaMensaje,
  DisputaModel,
  FilaReporte,
  PlanEstado,
  PlanModel,
  PolizaModel,
  ResultadoProgramar,
  SalidaSocioCaso,
  SalidaSocioOferta,
  ServicioModel,
  SiniestroModel,
  TareaModel,
} from '../../shared/models/p4.model';
import { ENV } from './env.generated';
import { Resultado } from './reserva.service';
import { SupabaseService } from './supabase.service';

export interface FiltroReporte {
  desde?: string;
  hasta?: string;
  miembro?: string;
  destino?: string;
  uso?: string;
  estado?: string;
}

/** Mantenimiento, seguro, capitanes, reportes, salida de socio y desacuerdos. La base decide; esto solo envía y muestra. */
@Injectable({ providedIn: 'root' })
export class GobiernoService {
  constructor(private supabase: SupabaseService) {}

  private get db() {
    return this.supabase.cliente;
  }

  private r<T>(datos: T | null, error: { message: string } | null): Resultado<T> {
    return { datos: error ? null : datos, error: error?.message ?? null };
  }

  // ---------------- mantenimiento
  async planes(grupo: string): Promise<PlanModel[]> {
    const { data } = await this.db.from('mantenimiento_planes').select('*').eq('grupo_id', grupo).order('nombre');
    return (data ?? []) as PlanModel[];
  }

  async estadoPlan(plan: string): Promise<PlanEstado | null> {
    const { data } = await this.db.rpc('plan_estado', { p_plan: plan });
    const f = ((data ?? []) as PlanEstado[])[0];
    return f ?? null;
  }

  async tareas(grupo: string): Promise<TareaModel[]> {
    const { data } = await this.db
      .from('mantenimiento_tareas')
      .select('id, plan_id, activo_id, componente_id, titulo, estado, vence_fecha, vence_horas, proveedor, notas, bloqueo_reserva_id')
      .eq('grupo_id', grupo)
      .order('creado_en', { ascending: false });
    return (data ?? []) as TareaModel[];
  }

  async servicios(grupo: string): Promise<ServicioModel[]> {
    const { data } = await this.db
      .from('servicios')
      .select('id, activo_id, componente_id, fecha, lectura, proveedor, descripcion, costo, moneda, gasto_id')
      .eq('grupo_id', grupo)
      .order('fecha', { ascending: false })
      .limit(100);
    return (data ?? []) as ServicioModel[];
  }

  async guardarPlan(
    grupo: string,
    p: { activo: string; componente: string | null; nombre: string; criterio: string; dias: number | null; horas: number | null },
  ) {
    const { data, error } = await this.db.rpc('plan_guardar', {
      p_grupo: grupo,
      p_id: null,
      p_activo: p.activo,
      p_componente: p.componente,
      p_nombre: p.nombre,
      p_criterio: p.criterio,
      p_dias: p.dias,
      p_horas: p.horas,
    });
    return this.r<string>(data as string, error);
  }

  async crearTarea(grupo: string, activo: string, titulo: string, venceFecha: string | null, proveedor: string) {
    const { data, error } = await this.db.rpc('tarea_crear', {
      p_grupo: grupo,
      p_activo: activo,
      p_titulo: titulo,
      p_componente: null,
      p_vence_fecha: venceFecha || null,
      p_vence_horas: null,
      p_proveedor: proveedor || null,
      p_notas: null,
    });
    return this.r<string>(data as string, error);
  }

  async programarTarea(tarea: string, inicio: string, fin: string): Promise<Resultado<ResultadoProgramar>> {
    const { data, error } = await this.db.rpc('tarea_programar', {
      p_tarea: tarea,
      p_inicio: new Date(inicio).toISOString(),
      p_fin: new Date(fin).toISOString(),
      p_motivo: null,
    });
    return this.r<ResultadoProgramar>(data as ResultadoProgramar, error);
  }

  async registrarServicio(
    grupo: string,
    s: {
      activo: string;
      componente: string | null;
      tarea: string | null;
      proveedor: string;
      descripcion: string;
      costo: number | null;
      moneda: string;
      vencimiento: string | null;
    },
  ) {
    const { data, error } = await this.db.rpc('servicio_registrar', {
      p_grupo: grupo,
      p_activo: s.activo,
      p_componente: s.componente,
      p_tarea: s.tarea,
      p_plan: null,
      p_fecha: null,
      p_lectura: null,
      p_proveedor: s.proveedor || null,
      p_descripcion: s.descripcion || null,
      p_costo: s.costo,
      p_moneda: s.moneda,
      p_categoria: 'mantenimiento',
      p_vencimiento: s.vencimiento || null,
      p_pagado_tipo: 'miembro',
      p_pagado_miembro: null,
    });
    return this.r<string>(data as string, error);
  }

  // ---------------- seguro
  async polizas(grupo: string): Promise<PolizaModel[]> {
    const { data } = await this.db.from('polizas_seguro').select('*').eq('grupo_id', grupo).order('vigente_hasta', { ascending: false });
    return ((data ?? []) as PolizaModel[]).map((p) => ({ ...p, deducible: Number(p.deducible) }));
  }

  async siniestros(grupo: string): Promise<SiniestroModel[]> {
    const { data } = await this.db.from('siniestros').select('*').eq('grupo_id', grupo).order('creado_en', { ascending: false });
    return (data ?? []) as SiniestroModel[];
  }

  async guardarPoliza(
    grupo: string,
    p: { activo: string; aseguradora: string; numero: string; cobertura: string; desde: string; hasta: string; deducible: number; moneda: string },
  ) {
    const { data, error } = await this.db.rpc('poliza_guardar', {
      p_grupo: grupo,
      p_id: null,
      p_activo: p.activo,
      p_aseguradora: p.aseguradora,
      p_numero: p.numero || null,
      p_cobertura: p.cobertura || null,
      p_desde: p.desde,
      p_hasta: p.hasta,
      p_deducible: p.deducible,
      p_moneda: p.moneda,
    });
    return this.r<string>(data as string, error);
  }

  async abrirSiniestro(grupo: string, activo: string, descripcion: string) {
    const { data, error } = await this.db.rpc('siniestro_abrir', {
      p_grupo: grupo,
      p_activo: activo,
      p_descripcion: descripcion,
      p_operacion: null,
    });
    return this.r<string>(data as string, error);
  }

  async estadoSiniestro(id: string, estado: string) {
    const { error } = await this.db.rpc('siniestro_estado', { p_siniestro: id, p_estado: estado });
    return this.r<null>(null, error);
  }

  // ---------------- capitanes
  async capitanes(grupo: string): Promise<CapitanModel[]> {
    const { data } = await this.db.from('capitanes').select('*').eq('grupo_id', grupo).order('nombre');
    return (data ?? []) as CapitanModel[];
  }

  async guardarCapitan(
    grupo: string,
    c: { id: string | null; nombre: string; miembro: string | null; licencia: string; vence: string | null; anios: number | null; notas: string; estado: string },
  ) {
    const { data, error } = await this.db.rpc('capitan_guardar', {
      p_grupo: grupo,
      p_id: c.id,
      p_nombre: c.nombre,
      p_miembro: c.miembro,
      p_licencia: c.licencia || null,
      p_vence: c.vence || null,
      p_anios: c.anios,
      p_notas: c.notas || null,
      p_estado: c.estado,
    });
    return this.r<string>(data as string, error);
  }

  // ---------------- reportes
  async dashboard(grupo: string, anio: number, mes: number | null): Promise<Resultado<Dashboard>> {
    const { data, error } = await this.db.rpc('reporte_dashboard', { p_grupo: grupo, p_anio: anio, p_mes: mes });
    return this.r<Dashboard>(data as Dashboard, error);
  }

  async reporteSalidas(grupo: string, f: FiltroReporte): Promise<Resultado<FilaReporte[]>> {
    const { data, error } = await this.db.rpc('reporte_salidas', {
      p_grupo: grupo,
      p_desde: f.desde || null,
      p_hasta: f.hasta || null,
      p_miembro: f.miembro || null,
      p_destino: f.destino || null,
      p_uso: f.uso || null,
      p_estado: f.estado || null,
      p_limite: 5000,
    });
    const filas = ((data ?? []) as FilaReporte[]).map((x) => ({
      ...x,
      fee: Number(x.fee),
      gastos_individuales: Number(x.gastos_individuales),
      horas_motor: Number(x.horas_motor),
      duracion_horas: Number(x.duracion_horas),
    }));
    return this.r<FilaReporte[]>(filas, error);
  }

  /** Descarga el reporte (xlsx o pdf) generado por la edge function con los mismos filtros. */
  async exportar(grupo: string, formato: 'xlsx' | 'pdf', f: FiltroReporte): Promise<Resultado<Blob>> {
    const { data: ses } = await this.db.auth.getSession();
    const resp = await fetch(`${ENV.supabaseUrl}/functions/v1/exportar-reporte`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${ses.session?.access_token ?? ''}`,
        apikey: ENV.supabaseAnonKey,
      },
      body: JSON.stringify({ grupo, formato, ...f }),
    });
    if (!resp.ok) return { datos: null, error: await resp.text() };
    return { datos: await resp.blob(), error: null };
  }

  // ---------------- salida o venta de un socio
  async casosSalida(grupo: string): Promise<SalidaSocioCaso[]> {
    const { data } = await this.db.from('salida_socio_casos').select('*').eq('grupo_id', grupo).order('creado_en', { ascending: false });
    return ((data ?? []) as SalidaSocioCaso[]).map((c) => ({ ...c, porcentaje: Number(c.porcentaje) }));
  }

  async ofertasSalida(caso: string): Promise<SalidaSocioOferta[]> {
    const { data } = await this.db.from('salida_socio_ofertas').select('*').eq('caso_id', caso).eq('estado', 'vigente');
    return ((data ?? []) as SalidaSocioOferta[]).map((o) => ({ ...o, porcentaje: Number(o.porcentaje), valor: Number(o.valor) }));
  }

  async solicitarSalida(grupo: string, nota: string) {
    const { data, error } = await this.db.rpc('salida_socio_solicitar', { p_grupo: grupo, p_nota: nota || null });
    return this.r<string>(data as string, error);
  }

  async valorarSalida(caso: string, texto: string) {
    const { error } = await this.db.rpc('salida_socio_valorar', { p_caso: caso, p_valoracion: texto });
    return this.r<null>(null, error);
  }

  async ofertarSalida(caso: string, porcentaje: number, valor: number, moneda: string) {
    const { data, error } = await this.db.rpc('salida_socio_ofertar', {
      p_caso: caso,
      p_porcentaje: porcentaje,
      p_valor: valor,
      p_moneda: moneda,
    });
    return this.r<string>(data as string, error);
  }

  async responderSalida(caso: string, acepta: boolean) {
    const { error } = await this.db.rpc('salida_socio_responder', { p_caso: caso, p_acepta: acepta });
    return this.r<null>(null, error);
  }

  async cerrarSalida(caso: string) {
    const { error } = await this.db.rpc('salida_socio_cerrar', { p_caso: caso });
    return this.r<null>(null, error);
  }

  async cancelarSalida(caso: string) {
    const { error } = await this.db.rpc('salida_socio_cancelar', { p_caso: caso });
    return this.r<null>(null, error);
  }

  // ---------------- desacuerdos y mediador
  async disputas(): Promise<DisputaModel[]> {
    const { data } = await this.db
      .from('disputas')
      .select('id, grupo_id, titulo, ref_tipo, estado, resultado, creado_en')
      .order('creado_en', { ascending: false });
    return (data ?? []) as DisputaModel[];
  }

  async mensajesDisputa(disputa: string): Promise<DisputaMensaje[]> {
    const { data } = await this.db
      .from('disputa_mensajes')
      .select('id, autor_nombre, rol, texto, creado_en')
      .eq('disputa_id', disputa)
      .order('creado_en');
    return (data ?? []) as DisputaMensaje[];
  }

  async abrirDisputa(grupo: string, titulo: string, texto: string) {
    const { data, error } = await this.db.rpc('disputa_abrir', {
      p_grupo: grupo,
      p_titulo: titulo,
      p_ref_tipo: null,
      p_ref_id: null,
      p_texto: texto,
    });
    return this.r<string>(data as string, error);
  }

  async mensajeDisputa(disputa: string, texto: string) {
    const { error } = await this.db.rpc('disputa_mensaje', { p_disputa: disputa, p_texto: texto });
    return this.r<null>(null, error);
  }

  async invitarMediador(disputa: string, correo: string) {
    const { data, error } = await this.db.rpc('disputa_invitar_mediador', { p_disputa: disputa, p_correo: correo });
    return this.r<string>(data as string, error);
  }

  async aceptarMediacion(token: string) {
    const { data, error } = await this.db.rpc('disputa_aceptar_mediacion', { p_token: token });
    return this.r<string>(data as string, error);
  }

  async cerrarDisputa(disputa: string, resultado: 'acuerdo' | 'sin_acuerdo', nota: string) {
    const { error } = await this.db.rpc('disputa_cerrar', { p_disputa: disputa, p_resultado: resultado, p_nota: nota || null });
    return this.r<null>(null, error);
  }
}
