-- Reversa solo para entornos de desarrollo: la auditoría es inmutable por diseño.
drop function if exists auditar() cascade;
alter table auditoria disable trigger auditoria_sin_update_delete;
alter table auditoria disable trigger auditoria_sin_truncate;
drop table if exists auditoria;
drop function if exists auditoria_inmutable();
