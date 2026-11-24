-- Reversa de 24 (borra casos de salida de socio y disputas).
drop function if exists disputa_cerrar(uuid, text, text), disputa_aceptar_mediacion(text), disputa_invitar_mediador(uuid, text),
  disputa_mensaje(uuid, text), disputa_abrir(uuid, text, text, uuid, text), es_mediador_de(uuid) cascade;
drop table if exists disputa_mediadores, disputa_mensajes, disputas cascade;
drop function if exists salida_socio_cancelar(uuid), salida_socio_cerrar(uuid), salida_socio_responder(uuid, boolean),
  salida_socio_ofertar(uuid, numeric, numeric, text), salida_socio_valorar(uuid, text), salida_socio_solicitar(uuid, text);
drop table if exists salida_socio_acuses, salida_socio_ofertas, salida_socio_casos cascade;
drop function if exists reporte_dashboard(uuid, int, int), reporte_salidas(uuid, date, date, uuid, uuid, text, text, int);
