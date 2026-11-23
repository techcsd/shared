import { TestBed } from '@angular/core/testing';
import { CalendarioPage } from './calendario';

describe('CalendarioPage', () => {
  it('muestra el título en español', async () => {
    await TestBed.configureTestingModule({ imports: [CalendarioPage] }).compileComponents();
    const fixture = TestBed.createComponent(CalendarioPage);
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('h1').textContent).toContain('Calendario');
  });
});
