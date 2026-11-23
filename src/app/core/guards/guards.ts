import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { RolMiembro, rolPermitido } from '../../../shared/models/grupo.model';
import { AuthService } from '../auth.service';
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
  const router = inject(Router);
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
