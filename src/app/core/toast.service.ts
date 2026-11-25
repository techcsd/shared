import { Injectable, signal } from '@angular/core';

export interface Aviso {
  id: number;
  texto: string;
  tipo: 'ok' | 'error';
}

/** Avisos breves (guardado, error) que no bloquean la pantalla. */
@Injectable({ providedIn: 'root' })
export class ToastService {
  private _items = signal<Aviso[]>([]);
  items = this._items.asReadonly();
  private seq = 0;

  ok(texto: string): void {
    this.mostrar(texto, 'ok');
  }

  error(texto: string): void {
    this.mostrar(texto, 'error');
  }

  cerrar(id: number): void {
    this._items.update((l) => l.filter((x) => x.id !== id));
  }

  private mostrar(texto: string, tipo: 'ok' | 'error'): void {
    const id = ++this.seq;
    this._items.update((l) => [...l.slice(-2), { id, texto, tipo }]);
    setTimeout(() => this.cerrar(id), tipo === 'error' ? 6000 : 3000);
  }
}
