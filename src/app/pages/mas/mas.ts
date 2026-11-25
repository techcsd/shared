import { Component, OnInit, computed, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { Icono } from '../../../shared/ui/icono/icono';
import { RolMiembro } from '../../../shared/models/grupo.model';
import { AuthService } from '../../core/auth.service';
import { FormacionService } from '../../core/formacion.service';
import { GrupoService } from '../../core/grupo.service';
import { ClaveI18n } from '../../core/i18n/es';
import { t } from '../../core/i18n/i18n';
import { NotificacionService } from '../../core/notificacion.service';

type Seccion = 'operacion' | 'grupo' | 'gobierno' | 'formacion' | 'plataforma' | 'cuenta';

interface Entrada {
  ruta: string;
  etiqueta: ClaveI18n;
  /** Una línea que explica para qué sirve la pantalla. */
  detalle: ClaveI18n;
  icono: string;
  seccion: Seccion;
  soloSocio: boolean;
  /** Va en los accesos rápidos (se ve arriba cuando no se está buscando). */
  rapida?: boolean;
  soloAdminPlataforma?: boolean;
}

interface GrupoDeEntradas {
  seccion: Seccion;
  titulo: ClaveI18n;
  entradas: Entrada[];
}

const TITULOS: Record<Seccion, ClaveI18n> = {
  operacion: 'mas.sec.operacion',
  grupo: 'mas.sec.grupo',
  gobierno: 'mas.sec.gobierno',
  formacion: 'mas.sec.formacion',
  plataforma: 'mas.sec.plataforma',
  cuenta: 'mas.sec.cuenta',
};

const ROLES: Record<RolMiembro, ClaveI18n> = {
  socio: 'rol.socio',
  admin_operativo: 'rol.admin_operativo',
  capitan: 'rol.capitan',
  mediador: 'rol.mediador',
};

/** Quita acentos y mayúsculas para que «operacion» encuentre «Operación». */
const normalizar = (s: string): string =>
  s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .trim();

/** «Más»: lo que no cabe en el menú inferior. Las entradas solo-socio se ocultan al resto (SA16). */
@Component({
  selector: 'app-mas',
  standalone: true,
  imports: [RouterLink, Icono],
  templateUrl: './mas.html',
  styleUrl: './mas.scss',
})
export class MasPage implements OnInit {
  esAdminPlataforma = signal(false);
  consulta = signal('');
  t = t;

  readonly entradas: Entrada[] = [
    { ruta: '/mas/notificaciones', etiqueta: 'mas.notificaciones', detalle: 'mas.d.notificaciones', icono: 'campana', seccion: 'operacion', soloSocio: false, rapida: true },
    { ruta: '/mas/operacion', etiqueta: 'mas.operacion', detalle: 'mas.d.operacion', icono: 'timon', seccion: 'operacion', soloSocio: false, rapida: true },
    { ruta: '/mas/prioridad-911', etiqueta: 'mas.prioridad_911', detalle: 'mas.d.prioridad_911', icono: 'alerta', seccion: 'operacion', soloSocio: false, rapida: true },
    { ruta: '/mas/finanzas', etiqueta: 'mas.finanzas', detalle: 'mas.d.finanzas', icono: 'cartera', seccion: 'operacion', soloSocio: true, rapida: true },
    { ruta: '/mas/reportes', etiqueta: 'mas.reportes', detalle: 'mas.d.reportes', icono: 'grafica', seccion: 'operacion', soloSocio: false },
    { ruta: '/mas/seguro', etiqueta: 'mas.seguro', detalle: 'mas.d.seguro', icono: 'escudo', seccion: 'operacion', soloSocio: false },
    { ruta: '/mas/capitanes', etiqueta: 'mas.capitanes', detalle: 'mas.d.capitanes', icono: 'ancla', seccion: 'operacion', soloSocio: false },
    { ruta: '/mas/grupo', etiqueta: 'mas.grupo', detalle: 'mas.d.grupo', icono: 'usuarios', seccion: 'grupo', soloSocio: false },
    { ruta: '/mas/configuracion', etiqueta: 'mas.configuracion', detalle: 'mas.d.configuracion', icono: 'ajustes', seccion: 'grupo', soloSocio: true },
    { ruta: '/mas/estatuto', etiqueta: 'mas.estatuto', detalle: 'mas.d.estatuto', icono: 'documento', seccion: 'grupo', soloSocio: true },
    { ruta: '/mas/disputas', etiqueta: 'mas.disputas', detalle: 'mas.d.disputas', icono: 'balanza', seccion: 'gobierno', soloSocio: true },
    { ruta: '/mas/salida-socio', etiqueta: 'mas.salida_socio', detalle: 'mas.d.salida_socio', icono: 'intercambio', seccion: 'gobierno', soloSocio: true },
    { ruta: '/mas/propuestas', etiqueta: 'mas.propuestas', detalle: 'mas.d.propuestas', icono: 'bolsa', seccion: 'formacion', soloSocio: false },
    { ruta: '/mas/lanzamiento', etiqueta: 'mas.lanzamiento', detalle: 'mas.d.lanzamiento', icono: 'cohete', seccion: 'formacion', soloSocio: true },
    { ruta: '/admin', etiqueta: 'mas.admin', detalle: 'mas.d.admin', icono: 'panel', seccion: 'plataforma', soloSocio: false, soloAdminPlataforma: true },
    { ruta: '/mas/salud', etiqueta: 'mas.salud', detalle: 'mas.d.salud', icono: 'pulso', seccion: 'plataforma', soloSocio: false, soloAdminPlataforma: true },
    { ruta: '/mas/perfil', etiqueta: 'mas.perfil', detalle: 'mas.d.perfil', icono: 'usuario', seccion: 'cuenta', soloSocio: false },
    { ruta: '/grupos', etiqueta: 'mas.cambiar_grupo', detalle: 'mas.d.cambiar_grupo', icono: 'cambiar', seccion: 'cuenta', soloSocio: false },
  ];

  /** Entradas que esta persona puede ver (mismas reglas de siempre). */
  visibles = computed(() =>
    this.entradas.filter(
      (e) =>
        (!e.soloSocio || this.grupos.esSocio()) &&
        (!e.soloAdminPlataforma || this.esAdminPlataforma()),
    ),
  );

  buscando = computed(() => normalizar(this.consulta()) !== '');

  /** Accesos rápidos: las más usadas, solo cuando no se está buscando. */
  rapidas = computed(() => (this.buscando() ? [] : this.visibles().filter((e) => e.rapida)));

  /** Secciones con sus entradas (al buscar, filtradas; sin buscar, sin las rápidas). */
  secciones = computed<GrupoDeEntradas[]>(() => {
    const q = normalizar(this.consulta());
    const lista = this.visibles().filter((e) => {
      if (q === '') return !e.rapida;
      return normalizar(`${t(e.etiqueta)} ${t(e.detalle)}`).includes(q);
    });
    const orden: Seccion[] = ['operacion', 'grupo', 'gobierno', 'formacion', 'plataforma', 'cuenta'];
    return orden
      .map((seccion) => ({
        seccion,
        titulo: TITULOS[seccion],
        entradas: lista.filter((e) => e.seccion === seccion),
      }))
      .filter((g) => g.entradas.length > 0);
  });

  /** Con «Cuenta» siempre al final y «Cerrar sesión» solo cuando no se busca o coincide. */
  mostrarSalir = computed(() => {
    const q = normalizar(this.consulta());
    return q === '' || normalizar(`${t('mas.salir')} ${t('mas.salir_desc')}`).includes(q);
  });

  sinResultados = computed(
    () => this.buscando() && this.secciones().length === 0 && !this.mostrarSalir(),
  );

  nombre = computed(() => {
    const u = this.auth.usuario();
    const n = u?.user_metadata?.['nombre'];
    if (typeof n === 'string' && n.trim() !== '') return n.trim();
    return (u?.email ?? '').split('@')[0] || '—';
  });

  iniciales = computed(() => {
    // Solo letras y números: «Felipe (demo)» → «FD», no «F(».
    const partes = this.nombre()
      .split(/\s+/)
      .map((p) => p.replace(/[^\p{L}\p{N}]/gu, ''))
      .filter(Boolean);
    const letras = partes.length > 1 ? partes[0][0] + partes[1][0] : (partes[0] ?? '?').slice(0, 2);
    return letras.toUpperCase();
  });

  rol = computed(() => {
    if (this.grupos.vistaAdmin()) return t('mas.rol_admin_plataforma');
    const r = this.grupos.rol();
    return r ? t(ROLES[r]) : null;
  });

  constructor(
    public grupos: GrupoService,
    public notif: NotificacionService,
    private auth: AuthService,
    private formacion: FormacionService,
    private router: Router,
  ) {}

  async ngOnInit(): Promise<void> {
    this.esAdminPlataforma.set(await this.formacion.esAdminPlataforma());
  }

  escribir(evento: Event): void {
    this.consulta.set((evento.target as HTMLInputElement).value);
  }

  limpiar(): void {
    this.consulta.set('');
  }

  /** Número que se muestra como insignia en la entrada (hoy solo avisos sin leer). */
  insignia(e: Entrada): number {
    return e.ruta === '/mas/notificaciones' ? this.notif.sinLeer() : 0;
  }

  async salir(): Promise<void> {
    await this.auth.salir();
    this.grupos.limpiar();
    await this.router.navigateByUrl('/login');
  }
}
