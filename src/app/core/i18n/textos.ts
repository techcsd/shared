import { EstadoGrupo, RolMiembro } from '../../../shared/models/grupo.model';
import { t } from './i18n';

// Mapas con claves literales para que verify:i18n las valide.
export function rolTexto(rol: RolMiembro): string {
  switch (rol) {
    case 'socio':
      return t('rol.socio');
    case 'admin_operativo':
      return t('rol.admin_operativo');
    case 'capitan':
      return t('rol.capitan');
    case 'mediador':
      return t('rol.mediador');
  }
}

export function estadoGrupoTexto(estado: EstadoGrupo): string {
  switch (estado) {
    case 'formacion':
      return t('grupos.estado.formacion');
    case 'activo':
      return t('grupos.estado.activo');
    case 'archivado':
      return t('grupos.estado.archivado');
  }
}

export function estadoInvitacionTexto(
  estado: 'pendiente' | 'aceptada' | 'cancelada' | 'expirada',
): string {
  switch (estado) {
    case 'pendiente':
      return t('miembros.estado.pendiente');
    case 'aceptada':
      return t('miembros.estado.aceptada');
    case 'cancelada':
      return t('miembros.estado.cancelada');
    case 'expirada':
      return t('miembros.estado.expirada');
  }
}
