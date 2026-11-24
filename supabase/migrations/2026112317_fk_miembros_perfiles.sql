-- 2026-11-23 · 17 · PostgREST necesita una FK para embeber `perfil:perfiles(...)` desde miembros.
alter table miembros add constraint miembros_usuario_perfil_fk
  foreign key (usuario_id) references perfiles (id) on delete cascade;
