import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { GrupoService } from '../../core/grupo.service';
import { cambiarIdioma, t } from '../../core/i18n/i18n';

@Component({
  selector: 'app-perfil',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './perfil.html',
  styleUrl: './perfil.scss',
})
export class PerfilPage implements OnInit {
  t = t;
  nombre = '';
  telefono = '';
  idioma: 'es' | 'en' = 'es';
  mensaje = signal<string | null>(null);
  error = signal<string | null>(null);

  constructor(
    private auth: AuthService,
    private grupos: GrupoService,
    private router: Router,
  ) {}

  async ngOnInit(): Promise<void> {
    const p = await this.auth.perfil();
    if (p) {
      this.nombre = p.nombre;
      this.telefono = p.telefono ?? '';
      this.idioma = p.idioma;
    }
  }

  async guardar(): Promise<void> {
    this.mensaje.set(null);
    this.error.set(null);
    const r = await this.auth.actualizarPerfil({
      nombre: this.nombre,
      telefono: this.telefono.trim() || null,
      idioma: this.idioma,
    });
    if (r.error) this.error.set(r.error);
    else {
      cambiarIdioma(this.idioma);
      this.mensaje.set(t('app.guardado'));
    }
  }

  async salirDeTodo(): Promise<void> {
    await this.auth.salirDeTodo();
    await this.router.navigateByUrl('/login');
  }

  async salir(): Promise<void> {
    await this.auth.salir();
    this.grupos.limpiar();
    await this.router.navigateByUrl('/login');
  }
}
