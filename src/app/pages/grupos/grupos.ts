import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { GrupoService } from '../../core/grupo.service';
import { t } from '../../core/i18n/i18n';
import { estadoGrupoTexto, rolTexto } from '../../core/i18n/textos';

/** Selector de grupo + crear grupo (sin lógica de negocio: todo vive en GrupoService y en la base). */
@Component({
  selector: 'app-grupos',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './grupos.html',
  styleUrl: './grupos.scss',
})
export class GruposPage implements OnInit {
  t = t;
  rolTexto = rolTexto;
  estadoGrupoTexto = estadoGrupoTexto;

  nombre = '';
  moneda = 'DOP';
  zonaHoraria = 'America/Santo_Domingo';
  prefijo = 'ORD';
  porcentaje = 100;
  ocupado = signal(false);
  error = signal<string | null>(null);

  constructor(
    public grupos: GrupoService,
    private auth: AuthService,
    private router: Router,
  ) {}

  async ngOnInit(): Promise<void> {
    await this.auth.listo;
    try {
      await this.grupos.cargar();
    } catch {
      this.error.set(t('app.error.generico'));
    }
  }

  async abrir(id: string): Promise<void> {
    this.grupos.seleccionar(id);
    await this.router.navigateByUrl('/');
  }

  async crear(): Promise<void> {
    this.ocupado.set(true);
    this.error.set(null);
    const r = await this.grupos.crear({
      nombre: this.nombre,
      moneda: this.moneda,
      zonaHoraria: this.zonaHoraria,
      prefijo: this.prefijo,
      porcentaje: Number(this.porcentaje),
    });
    this.ocupado.set(false);
    if (r.error) this.error.set(r.error);
    else await this.router.navigateByUrl('/mas/grupo');
  }

  async salir(): Promise<void> {
    await this.auth.salir();
    this.grupos.limpiar();
    await this.router.navigateByUrl('/login');
  }
}
