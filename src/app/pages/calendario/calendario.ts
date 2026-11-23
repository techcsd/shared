import { Component } from '@angular/core';
import { BRAND } from '../../core/brand';
import { t } from '../../core/i18n/i18n';
import { SupabaseService } from '../../core/supabase.service';

@Component({
  selector: 'app-calendario',
  standalone: true,
  templateUrl: './calendario.html',
  styleUrl: './calendario.scss',
})
export class CalendarioPage {
  t = t;
  marca = BRAND;
  constructor(public supabase: SupabaseService) {}
}
