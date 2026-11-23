import { Injectable, signal } from '@angular/core';

/** Indicador de conexión (red del navegador). */
@Injectable({ providedIn: 'root' })
export class ConexionService {
  private _enLinea = signal(typeof navigator === 'undefined' ? true : navigator.onLine);
  enLinea = this._enLinea.asReadonly();

  constructor() {
    if (typeof window !== 'undefined') {
      window.addEventListener('online', () => this._enLinea.set(true));
      window.addEventListener('offline', () => this._enLinea.set(false));
    }
  }
}
