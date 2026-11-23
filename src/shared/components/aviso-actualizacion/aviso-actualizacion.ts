import { Component, OnDestroy, signal } from '@angular/core';
import { SwUpdate, VersionReadyEvent } from '@angular/service-worker';
import { Subscription, filter } from 'rxjs';
import { t } from '../../../app/core/i18n/i18n';

/** Aviso cuando el service worker tiene una versión nueva lista. */
@Component({
  selector: 'app-aviso-actualizacion',
  standalone: true,
  templateUrl: './aviso-actualizacion.html',
  styleUrl: './aviso-actualizacion.scss',
})
export class AvisoActualizacion implements OnDestroy {
  t = t;
  hayNueva = signal(false);
  private sub?: Subscription;

  constructor(private sw: SwUpdate) {
    if (sw.isEnabled) {
      this.sub = sw.versionUpdates
        .pipe(filter((e): e is VersionReadyEvent => e.type === 'VERSION_READY'))
        .subscribe(() => this.hayNueva.set(true));
    }
  }

  actualizar(): void {
    document.location.reload();
  }

  cerrar(): void {
    this.hayNueva.set(false);
  }

  ngOnDestroy(): void {
    this.sub?.unsubscribe();
  }
}
