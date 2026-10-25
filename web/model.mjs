// The browser edits the existing Codable document; it does not run the native renderer.
export const accents = { telemetryGreen: '#75f794', electricBlue: '#73d1ff', amber: '#ffc259', hotRed: '#ff616b', cleanWhite: '#f5faff' };
export const fonts = {
  helveticaNeue: 'Helvetica Neue', helveticaNeueBold: 'Helvetica Neue Bold', menloBold: 'Menlo Bold',
  avenirNextCondensedHeavy: 'Avenir Next Condensed', futuraCondensedExtraBold: 'Futura Condensed',
};
// Default positions and sizes follow OverlayLayout.swift / OverlayRenderer.swift.
export const gauges = [
  ['speed', 'Speed', '速度', '速度', '速度', 0.025, 0.682, 420, 238, 'telemetryGreen', '32.4', 'km/h'],
  ['pace', 'Pace', '配速', '配速', 'ペース', 0.255, 0.814, 160, 74, 'electricBlue', '4:38', '/km'],
  ['heartRate', 'Heart rate', '心率', '心率', '心拍数', 0.443, 0.814, 160, 74, 'hotRed', '148', 'bpm'],
  ['cadence', 'Cadence', '步频', '步頻', 'ケイデンス', 0.537, 0.814, 160, 74, 'telemetryGreen', '176', 'spm'],
  ['calories', 'Calories', '热量', '熱量', 'カロリー', 0.631, 0.814, 160, 74, 'amber', '428', 'kcal'],
  ['ascent', 'Ascent', '累计爬升', '累計爬升', '累積上昇', 0.537, 0.704, 160, 74, 'telemetryGreen', '286', 'm'],
  ['strideLength', 'Stride length', '步幅', '步幅', 'ストライド', 0.725, 0.814, 160, 74, 'electricBlue', '1.24', 'm'],
  ['power', 'Power', '功率', '功率', 'パワー', 0.819, 0.814, 160, 74, 'cleanWhite', '248', 'W'],
  ['verticalOscillation', 'Vertical oscillation', '垂直振幅', '垂直振幅', '上下動', 0.631, 0.704, 160, 74, 'electricBlue', '8.2', 'cm'],
  ['groundContactTime', 'Ground contact time', '触地时间', '觸地時間', '接地時間', 0.725, 0.704, 160, 74, 'telemetryGreen', '238', 'ms'],
  ['groundContactTimePercent', 'Ground contact %', '触地时间占比', '觸地時間占比', '接地時間比率', 0.819, 0.594, 160, 74, 'telemetryGreen', '42', '%'],
  ['groundContactTimeBalance', 'Ground contact balance', '触地平衡', '觸地平衡', '接地バランス', 0.631, 0.484, 160, 74, 'hotRed', '50 / 50', '%'],
  ['verticalRatio', 'Vertical ratio', '垂直步幅比', '垂直步幅比', '上下動比', 0.725, 0.484, 160, 74, 'electricBlue', '6.6', '%'],
  ['respirationRate', 'Respiration rate', '呼吸频率', '呼吸頻率', '呼吸数', 0.819, 0.484, 160, 74, 'cleanWhite', '32', '/min'],
  ['stepSpeedLoss', 'Step speed loss', '步速损失', '步速損失', '速度低下率', 0.631, 0.374, 160, 74, 'amber', '3.8', '%'],
  ['formPower', 'Form power', '姿态功率', '姿態功率', 'フォームパワー', 0.819, 0.704, 160, 74, 'cleanWhite', '72', 'W'],
  ['airPower', 'Air power', '空气阻力功率', '空氣阻力功率', 'エアパワー', 0.631, 0.594, 160, 74, 'amber', '12', 'W'],
  ['legSpringStiffness', 'Leg spring stiffness', '腿部弹簧刚度', '腿部彈簧剛度', '脚ばね剛性', 0.725, 0.594, 160, 74, 'hotRed', '11.2', 'kN/m'],
  ['weather', 'Weather', '天气', '天氣', '天気', 0.631, 0.704, 136, 76, 'electricBlue', '21', '°C'],
  ['distance', 'Distance value', '距离数值', '距離數值', '距離の数値', 0.349, 0.814, 160, 74, 'amber', '12.8', 'km'],
  ['route', 'GPS route', 'GPS 路线', 'GPS 路線', 'GPS ルート', 0.776, 0.682, 382, 238, 'telemetryGreen', '', ''],
  ['altitudeProfile', 'Altitude profile', '海拔曲线', '海拔曲線', '標高グラフ', 0.358, 0.663, 840, 520, 'electricBlue', '286', 'm'],
  ['topProgress', 'Top progress', '顶部进度', '頂部進度', '距離プログレス', 0.070, 0.035, 1650, 58, 'cleanWhite', '12.8', 'km'],
  ['timeDate', 'Time & date', '时间与日期', '時間與日期', '時刻と日付', 0.792, 0.720, 300, 118, 'cleanWhite', '07:32:18', '2026-10-25'],
].map(([kind, en, zh, tw, ja, x, y, width, height, accent, value, unit]) => ({ kind, titles: { en, 'zh-CN': zh, 'zh-TW': tw, ja }, x, y, width, height, accent, value, unit }));
export const catalog = Object.fromEntries(gauges.map(g => [g.kind, g]));
export const clone = value => JSON.parse(JSON.stringify(value));
export const swiftDate = () => Date.now() / 1000 - 978307200;
export const uid = () => globalThis.crypto.randomUUID();
export const customizationDefaults = {
  showsLabel: true, showsUnit: true, showsIcon: false, showsPanel: true,
  labelFont: 'helveticaNeueBold', valueFont: 'menloBold', unitFont: 'helveticaNeueBold', iconFont: 'helveticaNeueBold',
  lineWidth: 1, lengthScale: 1, labelScale: 1, valueScale: 1, unitScale: 1, iconScale: 1,
};
export const styleDefaults = { accentColor: 'telemetryGreen', panelOpacity: 0.64, metricScale: 1, showGaugeTicks: true };
export function createElement(kind) {
  const g = catalog[kind]; if (typeof kind !== 'string' || !Object.hasOwn(catalog, kind)) invalid('errorChoice', { field: 'kind' });
  const customization = { ...customizationDefaults };
  if (kind === 'speed') Object.assign(customization, { valuePrecision: 1, gaugeMinimum: 0, gaugeMaximum: 24, lineWidth: 12 });
  else if (kind === 'topProgress') Object.assign(customization, { showsPanel: false, showGaugeTicks: false, valuePrecision: 1, lineWidth: 6, progressInsetScale: 0.82, progressKnobScale: 0.86, progressValueMarginScale: 1, progressTickCount: 48 });
  else if (kind === 'timeDate') Object.assign(customization, { showsLabel: false, showsPanel: false, showGaugeTicks: false, valueScale: 1.08, unitScale: 1.04 });
  else if (kind === 'route') customization.lineWidth = 5.5;
  else if (kind === 'altitudeProfile') customization.lineWidth = 4;
  else Object.assign(customization, { labelScale: 0.92, valueScale: 1.04, unitScale: 0.94 });
  if (kind === 'weather') Object.assign(customization, { showsIcon: true, iconScale: 1.12 });
  const frame = { x: g.x, y: g.y, scale: kind === 'altitudeProfile' ? 0.65 : 1, isVisible: true, style: { textScale: 1 } };
  if (!['speed', 'route'].includes(kind)) frame.style.accentColor = g.accent;
  if (kind === 'topProgress') frame.style.panelOpacity = 0.42;
  return { id: uid(), kind, frame, customization };
}
export function createDocument(name = 'Weekend ride', empty = false) {
  const now = swiftDate();
  return { id: uid(), name, createdAt: now, updatedAt: now, layout: { style: { ...styleDefaults }, elements: empty ? [] : ['topProgress', 'speed', 'pace', 'distance', 'heartRate', 'cadence', 'route', 'timeDate'].map(createElement) } };
}
function invalid(code, details = {}) { throw Object.assign(new Error(code), { code, details }); }
const object = (value, path) => { if (!value || typeof value !== 'object' || Array.isArray(value)) invalid('errorObject', { field: path }); };
const number = (value, min, max, path) => { if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) invalid('errorNumber', { field: path, min, max }); };
const boolean = (value, path) => { if (typeof value !== 'boolean') invalid('errorBoolean', { field: path }); };
const string = (value, path) => { if (typeof value !== 'string') invalid('errorText', { field: path }); };
const choice = (value, options, path) => { if (typeof value !== 'string' || !Object.hasOwn(options, value)) invalid('errorChoice', { field: path }); };
const optional = (obj, key, check) => { if (obj[key] != null) check(obj[key], key); };
const ranges = {
  valuePrecision: [0, 3], gaugeMinimum: [0, 120], gaugeMaximum: [1, 180], lineWidth: [0.25, 64], lengthScale: [0.1, 4],
  progressInsetScale: [0, 2], progressKnobScale: [0.25, 3], progressValueMarginScale: [0, 4], progressTickCount: [0, 160],
  weatherIconSpacingScale: [0, 3], manualWeatherTemperatureCelsius: [-100, 100], manualWeatherHumidityPercent: [0, 100],
  altitudeWidthScale: [0.25, 4], altitudeHeightScale: [0.25, 4], altitudeAxisLabelScale: [0.5, 4], altitudeCursorSize: [2, 64],
  altitudeFillOpacity: [0, 1], altitudeGridOpacity: [0, 1], altitudeVerticalPadding: [0, 1], altitudeMinimumRangeMeters: [0.1, 10000], altitudeGridRows: [0, 12], altitudeGridColumns: [0, 16],
};
for (const key of ['labelScale', 'valueScale', 'unitScale', 'iconScale', 'progressStartScale', 'progressCurrentScale', 'progressEndScale']) ranges[key] = [0.05, 20];
export function validateCustomization(c) {
  object(c, 'customization');
  for (const [key, value] of Object.entries(customizationDefaults)) {
    if (c[key] == null) invalid('errorRequired', { field: `customization.${key}` });
    if (typeof value === 'boolean') boolean(c[key], key);
  }
  for (const [key, range] of Object.entries(ranges)) optional(c, key, value => number(value, ...range, key));
  for (const key of ['valuePrecision', 'progressTickCount', 'manualWeatherTemperatureCelsius', 'manualWeatherHumidityPercent', 'altitudeGridRows', 'altitudeGridColumns']) optional(c, key, value => { if (!Number.isInteger(value)) invalid('errorInteger', { field: key }); });
  for (const key of ['labelFont', 'valueFont', 'unitFont', 'iconFont', 'progressStartFont', 'progressCurrentFont', 'progressEndFont']) optional(c, key, value => choice(value, fonts, key));
  for (const key of ['labelOverride', 'unitOverride', 'iconOverride']) optional(c, key, value => string(value, key));
  optional(c, 'distanceUnit', value => choice(value, { m: true, km: true, mi: true }, 'distanceUnit'));
  for (const key of ['showsPanelBorder', 'showGaugeTicks', 'showsWeatherHumidity', 'altitudeShowsFill', 'altitudeShowsGrid', 'altitudeShowsCursor', 'altitudeShowsMinMax', 'altitudeShowsDistanceLabels']) optional(c, key, value => boolean(value, key));
  for (const key of ['labelColor', 'valueColor', 'unitColor', 'iconColor', 'trackColor', 'progressBarColor', 'progressStartColor', 'progressCurrentColor', 'progressEndColor', 'altitudeRemainingColor', 'altitudeFillColor', 'altitudeGridColor', 'altitudeCursorColor']) if (c[key] != null) {
    const value = c[key];
    object(value, key); for (const channel of ['red', 'green', 'blue', 'alpha']) number(value[channel], 0, 1, `${key}.${channel}`);
  }
  if (c.gaugeMinimum != null && c.gaugeMaximum != null && c.gaugeMaximum <= c.gaugeMinimum) invalid('errorRange');
}
export function validateLayout(layout) {
  object(layout, 'layout'); object(layout.style, 'layout.style');
  choice(layout.style.accentColor, accents, 'layout.style.accentColor');
  number(layout.style.panelOpacity, 0, 1, 'panelOpacity'); number(layout.style.metricScale, 0.1, 4, 'metricScale'); boolean(layout.style.showGaugeTicks, 'showGaugeTicks');
  if (!Array.isArray(layout.elements) || layout.elements.length > 256) invalid('errorGauges');
  const ids = new Set();
  for (const e of layout.elements) {
    object(e, 'element'); string(e.id, 'element.id');
    if (!e.id.trim() || ids.has(e.id.trim())) invalid('errorIDs'); ids.add(e.id.trim());
    choice(e.kind, catalog, 'kind'); object(e.frame, 'frame');
    number(e.frame.x, -1, 2, 'x'); number(e.frame.y, -1, 2, 'y'); number(e.frame.scale, 0.1, 4, 'scale'); boolean(e.frame.isVisible, 'isVisible');
    object(e.frame.style, 'frame.style'); number(e.frame.style.textScale, 0.1, 4, 'textScale');
    optional(e.frame.style, 'accentColor', value => choice(value, accents, 'accentColor')); optional(e.frame.style, 'panelOpacity', value => number(value, 0, 1, 'panelOpacity'));
    validateCustomization(e.customization);
  }
}
export function presets(document) { return Array.isArray(document.presets) ? document.presets : [document]; }
export function validateDocument(document) {
  object(document, 'document'); const list = presets(document);
  if (list.length < 1 || list.length > 100) invalid('errorPresets');
  const ids = new Set();
  for (const p of list) {
    object(p, 'preset'); string(p.id, 'preset.id'); string(p.name, 'preset.name');
    if (!p.id.trim() || ids.has(p.id.trim()) || !p.name.trim()) invalid('errorIDs'); ids.add(p.id.trim());
    number(p.createdAt, -1e12, 1e12, 'createdAt'); number(p.updatedAt, -1e12, 1e12, 'updatedAt'); validateLayout(p.layout);
  }
  optional(document, 'defaultPresetID', value => { if (!ids.has(value)) invalid('errorDefault'); });
  return document;
}
export function parseJSON(text) {
  return JSON.parse(text, (key, value) => {
    if (['__proto__', 'prototype', 'constructor'].includes(key)) invalid('errorProperty');
    if (typeof value === 'number' && !Number.isFinite(value)) invalid('errorFinite');
    return value;
  });
}
export function parseDocument(text) {
  if (new TextEncoder().encode(text).length > 5 * 1024 * 1024) invalid('fileHelp');
  return validateDocument(parseJSON(text));
}
export function exportDocument(document, presetID) {
  const copy = clone(document);
  if (Array.isArray(copy.presets)) copy.defaultPresetID = presetID;
  return JSON.stringify(validateDocument(copy), null, 2) + '\n';
}
export function bounds(element, width, height) {
  const g = catalog[element.kind], c = element.customization;
  const scale = Math.max(0.28, Math.min(width / 1920, height / 1080)) * element.frame.scale;
  return { x: element.frame.x * width, y: element.frame.y * height,
    width: g.width * scale * (element.kind === 'altitudeProfile' ? c.altitudeWidthScale ?? 1 : c.lengthScale),
    height: g.height * scale * (element.kind === 'altitudeProfile' ? c.altitudeHeightScale ?? 1 : 1) };
}
export class History {
  constructor(value) { this.entries = [clone(value)]; this.index = 0; }
  push(value) {
    if (JSON.stringify(value) === JSON.stringify(this.entries[this.index])) return false;
    this.entries.splice(this.index + 1); this.entries.push(clone(value));
    if (this.entries.length > 80) this.entries.shift(); this.index = this.entries.length - 1; return true;
  }
  undo() { if (this.index > 0) this.index--; return clone(this.entries[this.index]); }
  redo() { if (this.index < this.entries.length - 1) this.index++; return clone(this.entries[this.index]); }
}
