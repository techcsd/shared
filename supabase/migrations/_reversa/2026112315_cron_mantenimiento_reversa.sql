select cron.unschedule('shared-mantenimiento') where to_regclass('cron.job') is not null;
drop function if exists cron_mantenimiento();
