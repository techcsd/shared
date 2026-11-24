import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { AvisoActualizacion } from '../shared/components/aviso-actualizacion/aviso-actualizacion';
import { ConexionService } from './core/conexion.service';
import { t } from './core/i18n/i18n';
import { OfflineService } from './core/offline.service';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, AvisoActualizacion],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App {
  t = t;
  constructor(
    public conexion: ConexionService,
    public offline: OfflineService,
  ) {
    // al abrir la app con red, se envía lo que quedó pendiente (gastos y correcciones de lectura)
    if (conexion.enLinea()) void offline.sincronizar();
  }
}
