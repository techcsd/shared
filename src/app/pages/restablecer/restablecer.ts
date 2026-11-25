import { Component, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { t } from '../../core/i18n/i18n';

/** Destino del enlace de recuperación: Supabase ya dejó una sesión temporal, solo se fija la clave nueva. */
@Component({
  selector: 'app-restablecer',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './restablecer.html',
  styleUrl: './restablecer.scss',
})
export class RestablecerPage {
  t = t;
  clave = '';
  verClave = signal(false);
  ocupado = signal(false);
  error = signal<string | null>(null);

  constructor(
    private auth: AuthService,
    private router: Router,
  ) {}

  async guardar(): Promise<void> {
    this.ocupado.set(true);
    this.error.set(null);
    const r = await this.auth.cambiarClave(this.clave);
    this.ocupado.set(false);
    if (r.error) this.error.set(r.error);
    else await this.router.navigateByUrl('/');
  }
}
