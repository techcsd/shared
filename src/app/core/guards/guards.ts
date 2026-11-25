import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { RolMiembro, rolPermitido } from '../../../shared/models/grupo.model';
import { AuthService } from '../auth.service';
import { FormacionService } from '../formacion.service';
import { GrupoService } from '../grupo.service';

/** Exige sesión; si no hay, manda a /login conservando el destino. */
export const authGuard: CanActivateFn = async (_ruta, estado) => {
  const auth = inject(AuthService);
  const router = inject(Router);
  await auth.listo;
  if (auth.autenticado()) return true;
  return router.createUrlTree(['/login'], { queryParams: { volver: estado.url } });
};

/** Exige un grupo activo; si el usuario no tiene ninguno, manda a /grupos. */
export const grupoGuard: CanActivateFn = async () => {
  const grupos = inject(GrupoService);
  const auth = inject(AuthService);
  const router = inject(Router);
  // Angular evalúa los guards de una ruta en paralelo: hay que esperar la sesión aquí también.
  await auth.listo;
  if (!auth.autenticado()) return true; // authGuard redirige a /login
  if (!grupos.cargado()) {
    try {
      await grupos.cargar();
    } catch {
      return router.createUrlTree(['/grupos']);
    }
  }
  return grupos.activa() ? true : router.createUrlTree(['/grupos']);
};

/** Restringe una ruta a ciertos roles (SA16). Finanzas y acuerdos: solo `socio`. */
export function rolGuard(permitidos: RolMiembro[]): CanActivateFn {
  return () => {
    const grupos = inject(GrupoService);
    const router = inject(Router);
    return rolPermitido(grupos.rol(), permitidos) ? true : router.createUrlTree(['/mas']);
  };
}

/** Solo administradores de plataforma (la base lo vuelve a exigir en cada RPC). No requiere grupo. */
export const adminPlataformaGuard: CanActivateFn = async () => {
  const auth = inject(AuthService);
  const formacion = inject(FormacionService);
  const router = inject(Router);
  await auth.listo;
  if (!auth.autenticado()) return true; // authGuard redirige a /login
  return (await formacion.esAdminPlataforma()) ? true : router.createUrlTree(['/']);
};
