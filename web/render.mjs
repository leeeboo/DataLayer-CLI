import { accents, catalog, bounds } from './model.mjs';

export const escapeXML = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' }[c]));
export function color(value, fallback) {
  return value ? `rgba(${value.red * 255},${value.green * 255},${value.blue * 255},${value.alpha})` : fallback;
}
function font(value) {
  if (value === 'menloBold') return 'Menlo,Consolas,monospace';
  if (value === 'avenirNextCondensedHeavy') return 'Avenir Next Condensed,Arial Narrow,sans-serif';
  if (value === 'futuraCondensedExtraBold') return 'Futura,Arial Narrow,sans-serif';
  return 'Helvetica Neue,Arial,sans-serif';
}
function text(x, y, value, size, fill, family, anchor = 'start') {
  return `<text x="${x}" y="${y}" fill="${fill}" font-size="${size}" font-family="${font(family)}" font-weight="${family === 'helveticaNeue' ? 400 : 700}" text-anchor="${anchor}" dominant-baseline="middle">${escapeXML(value)}</text>`;
}
export function gaugeSVG(element, layout, width, height) {
  const g = catalog[element.kind], c = element.customization, box = bounds(element, width, height);
  const accent = accents[element.frame.style.accentColor ?? layout.style.accentColor];
  const valueColor = color(c.valueColor, accent), labelColor = color(c.labelColor, '#bdccd5'), unitColor = color(c.unitColor, '#cedae1');
  const track = color(c.trackColor, 'rgba(255,255,255,.14)');
  const opacity = element.frame.style.panelOpacity ?? layout.style.panelOpacity;
  const label = c.labelOverride?.trim() || g.titles.en;
  let value = g.value;
  if (c.valuePrecision != null && value && !value.includes(':') && Number.isFinite(Number(value))) value = Number(value).toFixed(c.valuePrecision);
  if (element.kind === 'weather' && c.manualWeatherTemperatureCelsius != null) value = String(c.manualWeatherTemperatureCelsius);
  const unit = c.unitOverride?.trim() || g.unit;
  const scale = element.frame.style.textScale * layout.style.metricScale;
  const w = g.width, h = g.height;
  let content = c.showsPanel ? `<rect width="${w}" height="${h}" rx="${element.kind === 'speed' ? 20 : 12}" fill="rgba(9,15,20,${opacity})" ${c.showsPanelBorder !== false ? 'stroke="rgba(255,255,255,.16)" stroke-width="1"' : ''}/>` : '';
  if (element.kind === 'speed') {
    const minimum = c.gaugeMinimum ?? 0, maximum = c.gaugeMaximum ?? 24;
    const progress = Math.max(0, Math.min(1, (Number(g.value) - minimum) / (maximum - minimum)));
    const d = 'M 53 196 A 133 133 0 1 1 367 196';
    content += `<path d="${d}" fill="none" stroke="${track}" stroke-width="${c.lineWidth}" stroke-linecap="round"/><path d="${d}" fill="none" stroke="${valueColor}" stroke-width="${c.lineWidth}" stroke-linecap="round" pathLength="100" stroke-dasharray="${progress * 100} 100"/>`;
    if (c.showGaugeTicks ?? layout.style.showGaugeTicks) for (let n = 0; n <= 10; n++) {
      const a = (145 + n * 25) * Math.PI / 180;
      content += `<line x1="${210 + 125 * Math.cos(a)}" y1="${137 + 125 * Math.sin(a)}" x2="${210 + 116 * Math.cos(a)}" y2="${137 + 116 * Math.sin(a)}" stroke="${labelColor}" stroke-width="2"/>`;
    }
    if (c.showsLabel) content += text(210, 93, label, 20 * c.labelScale * scale, labelColor, c.labelFont, 'middle');
    content += text(210, 151, value, 64 * c.valueScale * scale, valueColor, c.valueFont, 'middle');
    if (c.showsUnit) content += text(210, 204, unit, 25 * c.unitScale * scale, unitColor, c.unitFont, 'middle');
  } else if (element.kind === 'route') {
    content += `<path d="M 28 190 C 84 210 94 147 130 150 S 176 184 218 129 S 244 45 288 34 S 345 74 350 44" fill="none" stroke="${valueColor}" stroke-width="${c.lineWidth}" stroke-linejoin="round" stroke-linecap="round"/><circle cx="28" cy="190" r="7" fill="#151c20" stroke="${valueColor}" stroke-width="3"/><circle cx="350" cy="44" r="7" fill="${valueColor}"/>`;
  } else if (element.kind === 'altitudeProfile') {
    if (c.altitudeShowsGrid !== false) for (let n = 1; n < 4; n++) content += `<path d="M 40 ${n * 110} H 800" stroke="${color(c.altitudeGridColor, track)}"/>`;
    const d = 'M 40 390 L 120 310 L 200 340 L 280 180 L 360 220 L 440 120 L 520 200 L 600 150 L 680 270 L 800 220';
    if (c.altitudeShowsFill !== false) content += `<path d="${d} L 800 440 L 40 440 Z" fill="${color(c.altitudeFillColor, accent)}" opacity="${c.altitudeFillOpacity ?? 0.18}"/>`;
    content += `<path d="${d}" fill="none" stroke="${valueColor}" stroke-width="${c.lineWidth}"/>`;
    if (c.showsLabel) content += text(40, 35, label, 24 * c.labelScale * scale, labelColor, c.labelFont);
    if (c.altitudeShowsCursor !== false) content += `<circle cx="440" cy="120" r="${c.altitudeCursorSize ?? 14}" fill="${color(c.altitudeCursorColor, '#fff')}"/>`;
  } else if (element.kind === 'topProgress') {
    const barColor = color(c.progressBarColor, valueColor);
    content += `<rect x="5" y="24" width="1640" height="${c.lineWidth}" rx="3" fill="${track}"/><rect x="5" y="24" width="690" height="${c.lineWidth}" rx="3" fill="${barColor}"/>`;
    if (c.showsLabel) content += text(8, 9, label, 16 * c.labelScale * scale, labelColor, c.labelFont);
    if (c.showsUnit) content += text(820, 46, `${value} ${unit}`, 18 * c.valueScale * scale, valueColor, c.valueFont, 'middle');
  } else if (element.kind === 'timeDate') {
    if (c.showsLabel) content += text(14, 16, label, 14 * c.labelScale * scale, labelColor, c.labelFont);
    content += text(14, 51, value, 32 * c.valueScale * scale, valueColor, c.valueFont);
    if (c.showsUnit) content += text(14, 92, unit, 19 * c.unitScale * scale, unitColor, c.unitFont);
  } else {
    if (c.showsLabel) content += text(10, 16, label, 11 * c.labelScale * scale, labelColor, c.labelFont);
    const valueY = c.showsLabel ? 43 : 31;
    const icon = c.showsIcon ? c.iconOverride?.trim() || (element.kind === 'weather' ? '☀' : '•') : '';
    if (icon) content += text(9, valueY, icon, 18 * c.iconScale * scale, color(c.iconColor, valueColor), c.iconFont);
    content += text(icon ? 33 : 10, valueY, value, 27 * c.valueScale * scale, valueColor, c.valueFont);
    if (c.showsUnit) content += text(150, 64, unit, 12 * c.unitScale * scale, unitColor, c.unitFont, 'end');
  }
  return `<g transform="translate(${box.x} ${box.y}) scale(${box.width / w} ${box.height / h})">${content}</g>`;
}
