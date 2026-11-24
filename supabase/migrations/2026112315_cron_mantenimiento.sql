-- 2026-11-23 · 15 · Tarea periódica: recordatorios, limpieza, expiración 911 y disparo del envío de correos (DF-34)
-- El programa (pg_cron) y los secretos (Vault) se configuran por entorno con scripts/configurar-cron.mjs:
-- no van en migraciones porque contienen claves.

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    begin
      create extension if not exists pg_net;
    exception when others then
      raise notice 'pg_net no se pudo activar: %', sqlerrm;
    end;
  end if;
end $$;

create function cron_mantenimiento() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_rec int; v_lim int; v_exp int; v_url text; v_key text; v_disparado boolean := false;
begin
  v_rec := recordatorios_acuse();
  v_lim := limpiar_borradores();
  v_exp := prioridad_911_expirar();

  -- Dispara la edge function que envía el correo pendiente (reintento único dentro de la función).
  if to_regclass('vault.decrypted_secrets') is not null and to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is not null
     and exists (select 1 from notificaciones where canal = 'correo' and estado_envio in ('pendiente', 'fallido') and reintentos < 2) then
    execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'shared_functions_url'$q$ into v_url;
    execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'shared_service_key'$q$ into v_key;
    if v_url is not null and v_key is not null then
      execute 'select net.http_post(url := $1, headers := $2, body := $3, timeout_milliseconds := 20000)'
        using v_url || '/enviar-notificaciones',
              jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
              '{}'::jsonb;
      v_disparado := true;
    end if;
  end if;
  return jsonb_build_object('recordatorios', v_rec, 'borradores_limpiados', v_lim,
                            'solicitudes_911_expiradas', v_exp, 'envio_disparado', v_disparado);
end $$;
revoke execute on function cron_mantenimiento() from public, anon, authenticated;
