import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { AvisoActualizacion } from '../shared/components/aviso-actualizacion/aviso-actualizacion';
import { ConexionService } from './core/conexion.service';
import { t } from './core/i18n/i18n';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, AvisoActualizacion],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App {
  t = t;
  constructor(public conexion: ConexionService) {}
}
