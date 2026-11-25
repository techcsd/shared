import { Component } from '@angular/core';
import { Router } from '@angular/router';
import { AuthService } from '../../../app/core/auth.service';
import { GrupoService } from '../../../app/core/grupo.service';
import { t } from '../../../app/core/i18n/i18n';

/** Aviso de «Entrar como»: vive en la raíz de la app para verse también sin grupo (pantalla de bienvenida). */
@Component({
  selector: 'app-banner-impersonar',
  standalone: true,
  templateUrl: './banner-impersonar.html',
  styleUrl: './banner-impersonar.scss',
})
export class BannerImpersonar {
  t = t;
  constructor(
    public auth: AuthService,
    private grupos: GrupoService,
    private router: Router,
  ) {}

  /** Vuelve a la cuenta del administrador (o cierra sesión si la copia de su sesión se perdió). */
  async volver(): Promise<void> {
    const r = await this.auth.volverACuentaAdmin();
    this.grupos.limpiar();
    await this.router.navigateByUrl(r.error ? '/login' : '/admin');
  }
}
