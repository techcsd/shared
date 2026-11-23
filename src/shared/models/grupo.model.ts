export type RolMiembro = 'socio' | 'admin_operativo' | 'capitan' | 'mediador';
export type EstadoGrupo = 'formacion' | 'activo' | 'archivado';

export interface GrupoModel {
  id: string;
  nombre: string;
  moneda: string;
  zona_horaria: string;
  prefijo: string;
  estado: EstadoGrupo;
  modo_demo: boolean;
}

/** Pertenencia del usuario actual a un grupo. */
export interface MembresiaModel {
  id: string;
  rol: RolMiembro;
  porcentaje: number;
  grupo: GrupoModel;
}

export interface MiembroModel {
  id: string;
  usuario_id: string;
  rol: RolMiembro;
  porcentaje: number;
  estado: string;
  perfil: { nombre: string; correo: string | null } | null;
}

export interface InvitacionModel {
  id: string;
  correo: string;
  rol: RolMiembro;
  porcentaje: number;
  estado: 'pendiente' | 'aceptada' | 'cancelada' | 'expirada';
  expira_en: string;
}

export interface VistaPreviaInvitacion {
  grupo_nombre: string;
  rol: RolMiembro;
  porcentaje: number;
  estado: 'pendiente' | 'aceptada' | 'cancelada' | 'expirada';
  expira_en: string;
}

/** ¿El rol puede ver la pantalla? (SA16: finanzas y acuerdos solo `socio`). */
export function rolPermitido(rol: RolMiembro | null, permitidos: RolMiembro[]): boolean {
  return rol !== null && permitidos.includes(rol);
}
