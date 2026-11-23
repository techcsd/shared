import { POLITICAS_CATALOGO } from './politicas-catalogo';
import { aClave, validarDefinicionTipo, validarPolitica } from './validar';

const def = (clave: string) => POLITICAS_CATALOGO.find((p) => p.clave === clave)!;

describe('validarPolitica', () => {
  it('acepta y rechaza enteros con rango y null', () => {
    const d = def('reservas.dias_max_seguidos');
    expect(validarPolitica(d, 5)).toBeNull();
    expect(validarPolitica(d, null)).toBeNull(); // nullable = sin tope
    expect(validarPolitica(d, 0)).toContain('Mínimo');
    expect(validarPolitica(d, 1.5)).toContain('entero');
    expect(validarPolitica(d, 'x')).toContain('número');
  });
  it('enum y lista', () => {
    expect(validarPolitica(def('combustible.modelo'), 'consumido')).toBeNull();
    expect(validarPolitica(def('combustible.modelo'), 'gratis')).not.toBeNull();
    expect(validarPolitica(def('seguro.alerta_dias'), [30, 7])).toBeNull();
    expect(validarPolitica(def('seguro.alerta_dias'), [30, 0])).not.toBeNull();
    expect(validarPolitica(def('temporada_alta.periodos'), ['navidad'])).toBeNull();
    expect(validarPolitica(def('temporada_alta.periodos'), ['otra'])).not.toBeNull();
  });
  it('no admite null si no es nullable', () => {
    expect(validarPolitica(def('reservas.acuse_requerido'), null)).not.toBeNull();
  });
  it('el catálogo tiene defaults válidos', () => {
    for (const p of POLITICAS_CATALOGO) expect(validarPolitica(p, p.defecto)).toBeNull();
  });
});

describe('validarDefinicionTipo', () => {
  it('detecta claves repetidas, cantidades y opciones', () => {
    const errores = validarDefinicionTipo({
      campos: [
        { clave: 'a', etiqueta: 'A', tipo: 'texto' },
        { clave: 'a', etiqueta: 'B', tipo: 'opcion' },
      ],
      componentes: [
        {
          clave: 'm',
          etiqueta: 'M',
          cantidad_defecto: 0,
          medidor: { tipo: 'horometro', unidad: 'h' },
        },
      ],
    });
    expect(errores.length).toBe(3);
  });
  it('una definición correcta no da errores', () => {
    expect(
      validarDefinicionTipo({
        campos: [{ clave: 'matricula', etiqueta: 'Matrícula', tipo: 'texto' }],
        componentes: [
          {
            clave: 'horometro',
            etiqueta: 'Horómetro',
            cantidad_defecto: 1,
            medidor: { tipo: 'horometro', unidad: 'h' },
          },
        ],
      }),
    ).toEqual([]);
  });
});

describe('aClave', () => {
  it('normaliza a una clave válida', () => {
    expect(aClave('Número de Matrícula')).toBe('numero_de_matricula');
    expect(aClave('1 motor')).toBe('x_1_motor');
  });
});
