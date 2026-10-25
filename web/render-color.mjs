// Normalized GenericRGB input -> normalized, clipped sRGB; alpha is unchanged.
// D50 matrices come from the host GenericRGB and sRGB ICC rXYZ/gXYZ/bXYZ tags.
export function genericRGBToSRGB({ red, green, blue, alpha = 1 }) {
  const decode = c => c <= 1 / 32 ? c / 16 : c ** 1.8;
  const r = decode(red), g = decode(green), b = decode(blue);
  const encode = c => Math.max(0, Math.min(1, c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055));
  return {
    red: encode(1.025252119206548 * r - 0.02656177063645277 * g + 0.0013006288137803468 * b),
    green: encode(0.019407870427636194 * r + 0.9480428846407374 * g + 0.03259330051315307 * b),
    blue: encode(-0.0017629181045961152 * r - 0.0014364515751175665 * g + 1.003214924435504 * b),
    alpha,
  };
}

// Color inputs display sRGB; persist the corresponding native GenericRGB components.
export function sRGBToGenericRGB({ red, green, blue, alpha = 1 }) {
  const decode = c => c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4;
  const r = decode(red), g = decode(green), b = decode(blue);
  const encode = c => Math.max(0, Math.min(1, c <= 1 / 512 ? c * 16 : c ** (1 / 1.8)));
  return {
    red: encode((0.97484917974770058) * r + (0.027309556109666448) * g + (-0.0021511098458263699) * b),
    green: encode((-0.020014545215952619) * r + (1.0541919927631223) * g + (-0.034223538833221212) * b),
    blue: encode((0.0016844140792443077) * r + (0.0015574332292298109) * g + (0.99674259518806707) * b),
    alpha,
  };
}
