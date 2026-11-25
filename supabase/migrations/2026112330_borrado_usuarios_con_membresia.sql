-- 2026-11-25 · 30 · Borrar un usuario de Auth que aún tiene filas en `miembros`.
-- GoTrue borra como `supabase_auth_admin` (sin permisos sobre las tablas de negocio) y el trigger diferido
-- `validar_porcentajes` corre con el rol de la sesión: fallaba con «permission denied» y el borrado entero se
-- revertía. Pasa a `security definer` (solo lee y lanza excepciones; search_path ya fijo).
alter function validar_porcentajes() security definer;
