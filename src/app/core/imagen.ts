/** Tipos de imagen aceptados para la foto del activo (el bucket `activos` aplica la misma lista). */
export const MIME_IMAGEN = ['image/jpeg', 'image/png', 'image/webp'];
export const MAX_BYTES_IMAGEN = 5 * 1024 * 1024;

/** Reduce una foto a un lado máximo y la recodifica (webp, o jpeg si el navegador no sabe webp). */
export async function reducirImagen(
  archivo: File,
  maxLado = 1600,
): Promise<{ blob: Blob; extension: 'webp' | 'jpg' }> {
  const bitmap = await createImageBitmap(archivo);
  const escala = Math.min(1, maxLado / Math.max(bitmap.width, bitmap.height));
  const ancho = Math.max(1, Math.round(bitmap.width * escala));
  const alto = Math.max(1, Math.round(bitmap.height * escala));
  const lienzo = document.createElement('canvas');
  lienzo.width = ancho;
  lienzo.height = alto;
  const ctx = lienzo.getContext('2d');
  if (!ctx) throw new Error('canvas_no_disponible');
  ctx.drawImage(bitmap, 0, 0, ancho, alto);
  bitmap.close();
  const aBlob = (tipo: string, calidad: number) =>
    new Promise<Blob | null>((ok) => lienzo.toBlob(ok, tipo, calidad));
  const webp = await aBlob('image/webp', 0.82);
  if (webp && webp.type === 'image/webp') return { blob: webp, extension: 'webp' };
  const jpg = await aBlob('image/jpeg', 0.85);
  if (!jpg) throw new Error('no_se_pudo_codificar');
  return { blob: jpg, extension: 'jpg' };
}
