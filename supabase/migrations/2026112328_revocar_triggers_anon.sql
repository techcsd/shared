-- Funciones de trigger: nadie debe poder ejecutarlas por la API (aviso del advisor de Supabase).
revoke execute on function public.auditar() from public, anon, authenticated;
revoke execute on function public.crear_perfil_para_usuario() from public, anon, authenticated;
revoke execute on function public.reservas_cargo_cancelacion() from public, anon, authenticated;
