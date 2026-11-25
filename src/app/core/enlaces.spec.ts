import { interpretarEnlace } from './enlaces';

const T = 'a'.repeat(64);

describe('interpretarEnlace', () => {
  it('extrae el token de un enlace de invitación', () => {
    expect(interpretarEnlace(`https://shared-csd.vercel.app/unirse/${T}`)).toEqual({ tipo: 'invitacion', token: T });
    expect(interpretarEnlace(`  /unirse/${T}?x=1  `)).toEqual({ tipo: 'invitacion', token: T });
  });
  it('extrae el token de un enlace de propuesta', () => {
    expect(interpretarEnlace(`https://x.app/propuesta/${T}#a`)).toEqual({ tipo: 'propuesta', token: T });
  });
  it('acepta solo el código', () => {
    expect(interpretarEnlace(T)).toEqual({ tipo: 'desconocido', token: T });
  });
  it('rechaza lo que no parece un enlace ni un código', () => {
    expect(interpretarEnlace('')).toBeNull();
    expect(interpretarEnlace('hola')).toBeNull();
    expect(interpretarEnlace('https://x.app/unirse/corto')).toBeNull();
    expect(interpretarEnlace('<script>alert(1)</script>')).toBeNull();
    expect(interpretarEnlace('https://x.app/otra/' + T)).toBeNull();
    expect(interpretarEnlace('https://x.app/unirse/%E0%A4%A')).toBeNull();
  });
});
