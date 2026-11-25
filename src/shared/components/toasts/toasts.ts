import { Component } from '@angular/core';
import { ToastService } from '../../../app/core/toast.service';

/** Contenedor de avisos breves; vive en la raíz de la app. */
@Component({
  selector: 'app-toasts',
  standalone: true,
  templateUrl: './toasts.html',
  styleUrl: './toasts.scss',
})
export class Toasts {
  constructor(public toast: ToastService) {}
}
