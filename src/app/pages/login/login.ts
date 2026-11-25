import { Component, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { BRAND } from '../../core/brand';
import { AuthService } from '../../core/auth.service';
import { t } from '../../core/i18n/i18n';
import { SupabaseService } from '../../core/supabase.service';

type Modo = 'entrar' | 'registro' | 'magico' | 'recuperar';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './login.html',
  styleUrl: './login.scss',
})
export class LoginPage {
  t = t;
  marca = BRAND;
  modo = signal<Modo>('entrar');
  correo = '';
  clave = '';
  verClave = signal(false);
  nombre = '';
  ocupado = signal(false);
  error = signal<string | null>(null);
  aviso = signal<string | null>(null);

  constructor(
    private auth: AuthService,
    private router: Router,
    private ruta: ActivatedRoute,
    public supabase: SupabaseService,
  ) {}

  cambiarModo(modo: Modo): void {
    this.modo.set(modo);
    this.error.set(null);
    this.aviso.set(null);
  }

  async enviar(): Promise<void> {
    this.ocupado.set(true);
    this.error.set(null);
    this.aviso.set(null);
    try {
      let resultado;
      switch (this.modo()) {
        case 'entrar':
          resultado = await this.auth.entrar(this.correo, this.clave);
          if (!resultado.error) {
            const volver = this.ruta.snapshot.queryParamMap.get('volver');
            await this.router.navigateByUrl(volver && volver.startsWith('/') ? volver : '/');
            return;
          }
          break;
        case 'registro':
          resultado = await this.auth.registrar(this.correo, this.clave, this.nombre);
          if (!resultado.error) {
            // Con confirmación de correo apagada Supabase abre sesión al registrar
            if (this.auth.autenticado()) {
              await this.router.navigateByUrl('/');
              return;
            }
            this.aviso.set(t('auth.revisa_correo'));
          }
          break;
        case 'magico':
          resultado = await this.auth.enlaceMagico(this.correo);
          if (!resultado.error) this.aviso.set(t('auth.revisa_correo'));
          break;
        case 'recuperar':
          resultado = await this.auth.recuperarClave(this.correo);
          if (!resultado.error) this.aviso.set(t('auth.revisa_correo'));
          break;
      }
      if (resultado.error) this.error.set(resultado.error);
    } catch {
      this.error.set(t('app.error.generico'));
    } finally {
      this.ocupado.set(false);
    }
  }
}
