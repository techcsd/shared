import { Injectable } from '@angular/core';
import {
  BalanceFila,
  DanoAcuerdo,
  DanoCaso,
  DanoMensaje,
  EvidenciaModel,
  GastoModel,
  MovimientoCuenta,
  MovimientoFondo,
  NuevoGasto,
  PagoModel,
} from '../../shared/models/finanzas.model';
import { Resultado } from './reserva.service';
import { SupabaseService } from './supabase.service';

const COLS_GASTO =
  'id, alcance, categoria, descripcion, monto, moneda, tasa, monto_grupo, moneda_grupo, pagado_por_tipo, pagado_por_miembro, proveedor, fecha, vencimiento, reserva_id, estado, cargado_por, validado_por, motivo_estado, creado_en';

/** Gastos, libro mayor, pagos, daños y fondo. Finanzas solo `socio`; todo cálculo vive en la base. */
@Injectable({ providedIn: 'root' })
export class FinanzasService {
  constructor(private supabase: SupabaseService) {}

  private get db() {
    return this.supabase.cliente;
  }

  private r<T>(datos: T | null, error: { message: string } | null): Resultado<T> {
    return { datos: error ? null : datos, error: error?.message ?? null };
  }

  // ---- gastos
  async gastos(grupo: string): Promise<GastoModel[]> {
    const { data } = await this.db
      .from('gastos')
      .select(COLS_GASTO)
      .eq('grupo_id', grupo)
      .order('fecha', { ascending: false })
      .order('creado_en', { ascending: false })
      .limit(300);
    return ((data ?? []) as GastoModel[]).map((g) => ({
      ...g,
      monto: Number(g.monto),
      monto_grupo: Number(g.monto_grupo),
      tasa: Number(g.tasa),
    }));
  }

  async gastosDeReserva(reserva: string): Promise<GastoModel[]> {
    const { data } = await this.db
      .from('gastos')
      .select(COLS_GASTO)
      .eq('reserva_id', reserva)
      .order('creado_en');
    return ((data ?? []) as GastoModel[]).map((g) => ({
      ...g,
      monto: Number(g.monto),
      monto_grupo: Number(g.monto_grupo),
      tasa: Number(g.tasa),
    }));
  }

  async registrarGasto(grupo: string, g: NuevoGasto): Promise<Resultado<string>> {
    const { data, error } = await this.db.rpc('gasto_registrar', {
      p_grupo: grupo,
      p_alcance: g.alcance,
      p_categoria: g.categoria,
      p_monto: g.monto,
      p_moneda: g.moneda,
      p_pagado_tipo: g.pagadoTipo,
      p_pagado_miembro: g.pagadoTipo === 'miembro' ? (g.pagadoMiembro ?? null) : null,
      p_proveedor: g.proveedor || null,
      p_descripcion: g.descripcion || null,
      p_reserva: g.alcance === 'individual' ? (g.reserva ?? null) : null,
      p_fecha: g.fecha || null,
      p_vencimiento: g.vencimiento || null,
      p_tasa: g.tasa ?? null,
    });
    return this.r<string>(data as string, error);
  }

  async validarGasto(id: string) {
    const { error } = await this.db.rpc('gasto_validar', { p_gasto: id });
    return this.r<null>(null, error);
  }

  async disputarGasto(id: string, motivo: string) {
    const { error } = await this.db.rpc('gasto_disputar', { p_gasto: id, p_motivo: motivo });
    return this.r<null>(null, error);
  }

  async anularGasto(id: string, motivo: string) {
    const { error } = await this.db.rpc('gasto_anular', { p_gasto: id, p_motivo: motivo });
    return this.r<null>(null, error);
  }

  // ---- balances y estado de cuenta
  async balances(grupo: string): Promise<BalanceFila[]> {
    const { data } = await this.db.rpc('balances_grupo', { p_grupo: grupo });
    return ((data ?? []) as BalanceFila[]).map((f) => ({
      ...f,
      confirmado: Number(f.confirmado),
      provisional: Number(f.provisional),
      balance: Number(f.balance),
    }));
  }

  async estadoCuenta(miembro: string): Promise<MovimientoCuenta[]> {
    const { data } = await this.db.rpc('estado_cuenta', { p_miembro: miembro });
    return ((data ?? []) as MovimientoCuenta[]).map((m) => ({
      ...m,
      debe: Number(m.debe),
      haber: Number(m.haber),
      saldo: Number(m.saldo),
    }));
  }

  // ---- pagos
  async pagos(grupo: string): Promise<PagoModel[]> {
    const { data } = await this.db
      .from('pagos')
      .select(
        'id, de_miembro, a_tipo, a_miembro, monto, moneda, monto_grupo, moneda_grupo, nota, estado, motivo_rechazo, creado_en',
      )
      .eq('grupo_id', grupo)
      .order('creado_en', { ascending: false })
      .limit(200);
    return ((data ?? []) as PagoModel[]).map((p) => ({ ...p, monto: Number(p.monto) }));
  }

  async registrarPago(
    grupo: string,
    aMiembro: string | null,
    monto: number,
    moneda: string,
    nota: string,
    tasa?: number | null,
  ): Promise<Resultado<string>> {
    const { data, error } = await this.db.rpc('pago_registrar', {
      p_grupo: grupo,
      p_a_miembro: aMiembro,
      p_monto: monto,
      p_moneda: moneda,
      p_nota: nota || null,
      p_tasa: tasa ?? null,
    });
    return this.r<string>(data as string, error);
  }

  async confirmarPago(id: string) {
    const { error } = await this.db.rpc('pago_confirmar', { p_pago: id });
    return this.r<null>(null, error);
  }

  async rechazarPago(id: string, motivo: string) {
    const { error } = await this.db.rpc('pago_rechazar', { p_pago: id, p_motivo: motivo });
    return this.r<null>(null, error);
  }

  // ---- fondo común
  async movimientosFondo(grupo: string): Promise<MovimientoFondo[]> {
    const { data } = await this.db
      .from('fondo_movimientos')
      .select('id, momento, debe, haber, moneda, origen_tipo, nota')
      .eq('grupo_id', grupo)
      .order('id', { ascending: false })
      .limit(200);
    return ((data ?? []) as MovimientoFondo[]).map((m) => ({
      ...m,
      debe: Number(m.debe),
      haber: Number(m.haber),
    }));
  }

  async generarAportes(grupo: string): Promise<Resultado<number>> {
    const { data, error } = await this.db.rpc('fondo_generar_aportes_manual', { p_grupo: grupo });
    return this.r<number>(data as number, error);
  }

  // ---- daños
  async danos(grupo: string): Promise<DanoCaso[]> {
    const { data } = await this.db
      .from('danos_casos')
      .select(
        'id, reserva_id, titulo, descripcion, presupuesto, moneda, pagado_por_tipo, pagado_por_miembro, propuesta, version, estado, creado_en',
      )
      .eq('grupo_id', grupo)
      .order('creado_en', { ascending: false });
    return (data ?? []) as DanoCaso[];
  }

  async mensajesDano(caso: string): Promise<DanoMensaje[]> {
    const { data } = await this.db
      .from('danos_mensajes')
      .select('id, autor_id, tipo, texto, creado_en')
      .eq('caso_id', caso)
      .order('creado_en');
    return (data ?? []) as DanoMensaje[];
  }

  async acuerdosDano(caso: string): Promise<DanoAcuerdo[]> {
    const { data } = await this.db
      .from('danos_acuerdos')
      .select('miembro_id, version, acepta')
      .eq('caso_id', caso);
    return (data ?? []) as DanoAcuerdo[];
  }

  async abrirDano(
    grupo: string,
    titulo: string,
    descripcion: string,
    reserva: string | null,
  ): Promise<Resultado<string>> {
    const { data, error } = await this.db.rpc('dano_abrir', {
      p_grupo: grupo,
      p_titulo: titulo,
      p_descripcion: descripcion || null,
      p_reserva: reserva,
      p_incidencia: null,
    });
    return this.r<string>(data as string, error);
  }

  async proponerDano(
    caso: string,
    presupuesto: number,
    moneda: string,
    pagadoTipo: 'miembro' | 'fondo' | 'externo',
    pagadoMiembro: string | null,
    propuesta: { miembro_id: string; monto: number }[],
    tasa?: number | null,
  ) {
    const { error } = await this.db.rpc('dano_proponer', {
      p_caso: caso,
      p_presupuesto: presupuesto,
      p_moneda: moneda,
      p_pagado_tipo: pagadoTipo,
      p_pagado_miembro: pagadoTipo === 'miembro' ? pagadoMiembro : null,
      p_propuesta: propuesta,
      p_tasa: tasa ?? null,
    });
    return this.r<null>(null, error);
  }

  async responderDano(caso: string, acepta: boolean, nota: string) {
    const { error } = await this.db.rpc('dano_responder', {
      p_caso: caso,
      p_acepta: acepta,
      p_nota: nota || null,
    });
    return this.r<null>(null, error);
  }

  async mensajeDano(caso: string, texto: string) {
    const { error } = await this.db.rpc('dano_mensaje', { p_caso: caso, p_texto: texto });
    return this.r<null>(null, error);
  }

  async reiniciarDemo(grupo: string) {
    const { error } = await this.db.rpc('demo_reiniciar_operacion', { p_grupo: grupo });
    return this.r<null>(null, error);
  }

  // ---- evidencias (fotos, facturas, comprobantes) en Storage privado
  async subirEvidencia(
    grupo: string,
    usuario: string,
    refTipo: EvidenciaModel['ref_tipo'],
    refId: string,
    archivo: File,
    tipo: 'foto' | 'factura' | 'comprobante' | 'otro' = 'foto',
  ): Promise<Resultado<string>> {
    const nombre = archivo.name.replace(/[^a-zA-Z0-9._-]/g, '_').slice(-80);
    const carpeta = ['operacion', 'incidencia'].includes(refTipo)
      ? `op/${refId}`
      : `fin/${usuario}`;
    const ruta = `${grupo}/${carpeta}/${Date.now()}_${nombre}`;
    const sub = await this.db.storage.from('evidencias').upload(ruta, archivo, {
      contentType: archivo.type || undefined,
    });
    if (sub.error) return { datos: null, error: sub.error.message };
    const { data, error } = await this.db.rpc('evidencia_registrar', {
      p_grupo: grupo,
      p_ref_tipo: refTipo,
      p_ref_id: refId,
      p_ruta: ruta,
      p_tipo: tipo,
      p_mime: archivo.type || null,
    });
    return this.r<string>(data as string, error);
  }

  async evidencias(refTipo: string, refId: string): Promise<EvidenciaModel[]> {
    const { data } = await this.db
      .from('evidencias')
      .select('id, ref_tipo, ref_id, tipo, ruta, mime')
      .eq('ref_tipo', refTipo)
      .eq('ref_id', refId);
    return (data ?? []) as EvidenciaModel[];
  }

  async urlFirmada(ruta: string): Promise<string | null> {
    const { data } = await this.db.storage.from('evidencias').createSignedUrl(ruta, 600);
    return data?.signedUrl ?? null;
  }
}
