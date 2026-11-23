import { cambiarIdioma, t } from './i18n';

describe('t()', () => {
  afterEach(() => cambiarIdioma('es'));

  it('traduce en es y en', () => {
    expect(t('app.cargando')).toBe('Cargando…');
    cambiarIdioma('en');
    expect(t('app.cargando')).toBe('Loading…');
  });

  it('reemplaza parámetros', () => {
    expect(t('app.vacio', { x: 1 })).toBe('Todavía no hay nada aquí.');
  });
});
