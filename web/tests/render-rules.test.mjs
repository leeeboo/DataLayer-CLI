import test from 'node:test';
import assert from 'node:assert/strict';
import { createDocument, createElement, gauges, clone } from '../model.mjs';
import * as renderer from '../render.mjs';
import { genericRGBToSRGB, sRGBToGenericRGB } from '../render-color.mjs';

const layout = (...elements) => ({ ...createDocument('Native regression', true).layout, elements });
const svg = (element, preview) => renderer.gaugeSVG(element, layout(element), 1920, 1080, preview);
const texts = markup => [...markup.matchAll(/<text\b([^>]*)>(.*?)<\/text>/gs)].map(([, attrs, value]) => ({ attrs, value: value.replace(/\uFE0E/g, '') }));
const attribute = (markup, key) => markup.match(new RegExp(`\\b${key}="([^"]*)"`))?.[1];
const close = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-6, `${actual} != ${expected}`);
function cssChannels(source) {
  const c = genericRGBToSRGB(source); return [c.red * 255, c.green * 255, c.blue * 255, c.alpha];
}
const cssColor = source => `rgba(${cssChannels(source).join(',')})`;
const sample = {
  elapsed: 2568, speedMetersPerSecond: 3.6, distanceMeters: 12800, heartRate: 148, cadence: 176,
  totalCalories: 428, totalAscentMeters: 286, stepLengthMeters: 1.24, powerWatts: 248,
  verticalOscillationCentimeters: 8.2, groundContactTimeMilliseconds: 238,
  groundContactTimePercent: 42, groundContactTimeBalancePercent: 50, verticalRatioPercent: 6.6,
  respirationRateBreathsPerMinute: 32, stepSpeedLossPercent: 3.8, formPowerWatts: 72,
  airPowerWatts: 12, legSpringStiffnessKilonewtonsPerMeter: 11.2, altitudeMeters: 120,
  weatherTemperatureCelsius: 21, weatherSummary: 'Clouds', weatherHumidityPercent: 85,
};
const series = { totalDistanceMeters: 18000, samples: [
  { elapsed: 0, distanceMeters: 0, altitudeMeters: 100, latitude: 30, longitude: 120 },
  { elapsed: 2000, distanceMeters: 10000, altitudeMeters: 160, latitude: 30.002, longitude: 120.003 },
  { elapsed: 3600, distanceMeters: 18000, altitudeMeters: 110, latitude: 30.004, longitude: 120.005 },
] };
const preview = { sample, series };
function rendered(elements, options = preview, width = 1920, height = 1080) {
  assert.equal(typeof renderer.renderLayout, 'function', 'renderLayout must expose shared render and measured bounds');
  return renderer.renderLayout(layout(...elements), width, height, options);
}
const line = (markup, value) => {
  const found = texts(markup).find(t => t.value === value);
  assert.ok(found, `missing native text ${JSON.stringify(value)}`);
  return found;
};
function colored(markup, value, rgb, alpha) {
  const fill = attribute(line(markup, value).attrs, 'fill');
  const channels = fill?.match(/^rgba\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*\)$/);
  assert.ok(channels, `${value} must retain RGBA fill, got ${fill}`);
  assert.deepEqual(channels.slice(1).map(Number), cssChannels({ red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255, alpha }));
}

// Fixed CGColor.converted(to:sRGB) samples from the 2026-10-25 native probe and dark-toe probe.
const nativeColors = [
  ['black', [0, 0, 0], [0, 0, 0]],
  ['dark toe .01', [0.01, 0.01, 0.01], [0.008075, 0.008075, 0.008075]],
  ['gray', [0.5, 0.5, 0.5], [0.572306752204895, 0.572306752204895, 0.572306752204895]],
  ['white', [1, 1, 1], [1, 0.9999999403953552, 1]],
  ['red mix .38', [1, 0.38, 0.42], [1, 0.47584325075149536, 0.4939435124397278]],
  ['red clipped blue', [1, 0, 0], [1, 0.14910030364990234, 0]],
  ['green clipped red and blue', [0, 1, 0], [0, 0.9767891764640808, 0]],
  ['blue clipped upper bound', [0, 0, 1], [0.01684189960360527, 0.1983414590358734, 1]],
  ['electric blue', [0.45, 0.82, 1], [0.5130228400230408, 0.8545490503311157, 1]],
];
for (const [name, [red, green, blue], native] of nativeColors) {
  test(`GenericRGB to sRGB matches independent CoreGraphics sample: ${name}`, () => {
    for (const alpha of [0, 0.01, 0.25, 0.95, 1]) {
      const converted = genericRGBToSRGB({ red, green, blue, alpha });
      const actual = [converted.red, converted.green, converted.blue];
      assert.ok(Math.max(...actual.map((c, i) => Math.abs(c - native[i]))) < 0.1 / 255, name);
      assert.ok(actual.every(c => c >= 0 && c <= 1), 'sRGB output must be clipped');
      assert.equal(converted.alpha, alpha, 'alpha is not gamma encoded or premultiplied');
    }
  });
}

test('in-gamut native colors round-trip through the picker sRGB space with exact alpha', () => {
  for (const [red, green, blue] of [[0.01, 0.01, 0.01], [0.5, 0.5, 0.5], [0.95, 0.95, 0.95], [0.2, 0.4, 0.6]]) {
    for (const alpha of [0, 0.35, 1]) {
      const source = { red, green, blue, alpha }, displayed = genericRGBToSRGB(source);
      assert.ok(['red', 'green', 'blue'].every(key => displayed[key] > 0 && displayed[key] < 1), 'round-trip sample must not clip');
      const restored = sRGBToGenericRGB(displayed);
      for (const key of ['red', 'green', 'blue']) close(restored[key], source[key]);
      assert.equal(restored.alpha, alpha);
    }
  }
});

test('picker inverse conversion stays finite and clipped at sRGB gamut boundaries', () => {
  for (const [red, green, blue] of [[0, 0, 0], [1, 1, 1], [1, 0, 0], [0, 1, 0], [0, 0, 1], [1, 0, 1], [0, 1, 1]]) {
    const native = sRGBToGenericRGB({ red, green, blue, alpha: 0.35 });
    assert.ok(['red', 'green', 'blue'].every(key => Number.isFinite(native[key]) && native[key] >= 0 && native[key] <= 1));
    assert.equal(native.alpha, 0.35);
  }
  assert.equal(sRGBToGenericRGB({ red: 0, green: 0, blue: 0 }).alpha, 1);
});

// Expectations come from drawTopProgress, drawTimeDate and drawMetricTile in OverlayRenderer.swift.
test('topProgress renders start, current, finish and its knob', () => {
  const markup = svg(createElement('topProgress'));
  assert.deepEqual(texts(markup).map(t => t.value), ['0.0 km', '12.8 km', '18.0 km']);
  assert.match(markup, /<(?:circle|ellipse)\b/, 'progress requires a knob');
});

test('timeDate renders elapsed, clock and calendar date aligned right', () => {
  const lines = texts(svg(createElement('timeDate')));
  assert.deepEqual(lines.map(t => t.value), ['00:42:48', '07:32:18', '2026/10/25']);
  // Browser geometry below checks right alignment without dictating SVG anchor implementation.
});

const metrics = [
  ['pace', 'PACE', '4:38', '/KM'], ['distance', 'DIST', '12.80', 'km'],
  ['heartRate', 'HR', '148', 'BPM'], ['cadence', 'CAD', '176', 'SPM'],
  ['calories', 'CAL', '428', 'KCAL'], ['ascent', 'ASC', '286', 'm'],
  ['strideLength', 'STRIDE', '1.24', 'm'], ['power', 'PWR', '248', 'W'],
  ['verticalOscillation', 'VERT', '8.2', 'CM'], ['groundContactTime', 'GCT', '238', 'MS'],
  ['groundContactTimePercent', 'GCT %', '42.0', '%'], ['groundContactTimeBalance', 'GCT BAL', '50.0', '%'],
  ['verticalRatio', 'VERT R', '6.6', '%'], ['respirationRate', 'RESP', '32.0', 'BR/MIN'],
  ['stepSpeedLoss', 'SSL', '3.8', '%'], ['formPower', 'FORM', '72', 'W'],
  ['airPower', 'AIR', '12', 'W'], ['legSpringStiffness', 'LSS', '11.2', 'kN/m'],
  ['weather', 'WEATHER', '21℃', '85%'],
];
for (const [kind, label, value, unit] of metrics) {
  test(`${kind}: native label, telemetry value, unit and baseline`, () => {
    const markup = svg(createElement(kind), preview);
    for (const expected of [label, value, unit]) line(markup, expected);
    assert.doesNotMatch(markup, /dominant-baseline="middle"/, 'CoreText uses a real alphabetic baseline');
  });
}

test('all 24 kinds return finite top-origin logical bounds without mutating layout', () => {
  assert.equal(gauges.length, 24);
  const elements = gauges.map(g => createElement(g.kind));
  const before = clone(elements), result = rendered(elements);
  assert.equal(result.length, 24);
  assert.deepEqual(elements, before);
  for (const element of elements) {
    const entry = result.find(item => item.id === element.id);
    assert.ok(entry, `${element.kind} keeps its identity`);
    for (const key of ['x', 'y', 'width', 'height']) assert.ok(Number.isFinite(entry.bounds[key]), `${element.kind}.${key}`);
    assert.ok(entry.bounds.width > 0 && entry.bounds.height > 0, `${element.kind} remains selectable`);
    assert.doesNotMatch(entry.svg, /NaN|Infinity|undefined/);
  }
});

test('hidden gauges retain logical bounds for arrangement', () => {
  for (const kind of gauges.map(g => g.kind)) {
    const e = createElement(kind); e.frame.isVisible = false;
    const [entry] = rendered([e]);
    assert.ok(entry.bounds.width > 0 && entry.bounds.height > 0, kind);
  }
});

test('metric bounds grow for long labels and large text; visible metrics align', () => {
  const pace = createElement('pace'), heart = createElement('heartRate');
  const initial = rendered([pace, heart]);
  heart.frame.style.textScale = 4;
  heart.customization.labelScale = 3;
  heart.customization.labelOverride = 'A very long custom label that must stay selectable';
  const result = rendered([pace, heart]);
  assert.ok(result[0].bounds.width > initial[0].bounds.width);
  assert.equal(result[0].bounds.width, result[1].bounds.width);
  assert.ok(result[1].bounds.height > initial[1].bounds.height);
  assert.equal(result[1].bounds.y, heart.frame.y * 1080);
  heart.frame.isVisible = false;
  const hidden = rendered([pace, heart]);
  assert.equal(hidden[0].bounds.width, initial[0].bounds.width, 'hidden text must not widen visible siblings');
  assert.ok(hidden[1].bounds.width > hidden[0].bounds.width);
});

test('resizing one metric does not resize its sibling', () => {
  const pace = createElement('pace'), heart = createElement('heartRate');
  const before = rendered([pace, heart]); heart.frame.scale = 2;
  const after = rendered([pace, heart]);
  assert.ok(Math.abs(after[0].bounds.width - before[0].bounds.width) < 1e-6);
  assert.ok(Math.abs(after[1].bounds.width - before[1].bounds.width * 2) < 1e-6);
});

test('time bounds grow left and downward while preserving their right edge', () => {
  const e = createElement('timeDate'), [before] = rendered([e]);
  e.frame.style.textScale = 4; e.customization.unitScale = 4;
  const [after] = rendered([e]);
  assert.ok(after.bounds.x < before.bounds.x);
  assert.ok(after.bounds.height > before.bounds.height);
  assert.ok(Math.abs(after.bounds.y - before.bounds.y) < 1e-6);
  assert.ok(Math.abs(after.bounds.x + after.bounds.width - before.bounds.x - before.bounds.width) < 1e-6);
});

test('metric label, unit, icon and panel switches are independent', () => {
  const e = createElement('heartRate');
  Object.assign(e.customization, { labelOverride: 'LABEL', unitOverride: 'UNIT', iconOverride: 'ICON', showsIcon: true });
  let markup = svg(e, preview);
  for (const value of ['LABEL', 'UNIT', 'ICON', '148']) line(markup, value);
  Object.assign(e.customization, { showsLabel: false, showsUnit: false, showsIcon: false, showsPanel: false });
  markup = svg(e, preview);
  assert.deepEqual(texts(markup).map(t => t.value), ['148']);
  assert.doesNotMatch(markup, /<rect\b/);
});

test('text overrides are XML escaped and multiline units remain separate lines', () => {
  const e = createElement('heartRate');
  Object.assign(e.customization, { labelOverride: '<script>&"\'', unitOverride: 'FIRST\nSECOND', iconOverride: '<icon>', showsIcon: true });
  const markup = svg(e, preview);
  line(markup, '&lt;script&gt;&amp;&quot;&apos;');
  line(markup, '&lt;icon&gt;'); line(markup, 'FIRST'); line(markup, 'SECOND');
  assert.doesNotMatch(markup, /<script>|<icon>/);
});

test('value, label, unit and icon colors preserve their own alpha', () => {
  const e = createElement('heartRate'); e.customization.showsIcon = true;
  Object.assign(e.customization, {
    labelOverride: 'LABEL', unitOverride: 'UNIT', iconOverride: 'ICON',
    labelColor: { red: 1, green: 0, blue: 0, alpha: 0.11 },
    valueColor: { red: 0, green: 1, blue: 0, alpha: 0.22 },
    unitColor: { red: 0, green: 0, blue: 1, alpha: 0.33 },
    iconColor: { red: 1, green: 1, blue: 0, alpha: 0.44 },
  });
  const markup = svg(e, preview);
  colored(markup, 'LABEL', [255, 0, 0], 0.11); colored(markup, '148', [0, 255, 0], 0.22);
  colored(markup, 'UNIT', [0, 0, 255], 0.33); colored(markup, 'ICON', [255, 255, 0], 0.44);
});

test('metric precision changes decimal metrics but not integer HR or pace', () => {
  for (const [kind, value] of [['distance', '12.800'], ['strideLength', '1.240'], ['verticalRatio', '6.600'], ['heartRate', '148'], ['pace', '4:38']]) {
    const e = createElement(kind); e.customization.valuePrecision = 3;
    line(svg(e, preview), value);
  }
});

test('missing and nonfinite telemetry do not become bogus numeric values', () => {
  const e = createElement('distance');
  for (const distanceMeters of [null, NaN, Infinity]) line(svg(e, { ...preview, sample: { ...sample, distanceMeters } }), '--');
  const pace = createElement('pace');
  for (const speedMetersPerSecond of [null, 0, 0.3]) line(svg(pace, { ...preview, sample: { ...sample, speedMetersPerSecond } }), '--:--');
});

test('per-gauge distance units convert values without changing other gauges', () => {
  const distance = createElement('distance'); distance.customization.distanceUnit = 'm';
  line(svg(distance, preview), '12800'); line(svg(distance, preview), 'm');
  distance.customization.distanceUnit = 'mi'; distance.customization.valuePrecision = 2;
  line(svg(distance, preview), '7.95'); line(svg(distance, preview), 'mi');
  line(svg(createElement('pace'), preview), '/KM');
});

test('weather manual data wins; humidity and icon flags preserve temperature', () => {
  const e = createElement('weather');
  Object.assign(e.customization, { manualWeatherTemperatureCelsius: -3, manualWeatherHumidityPercent: 17, iconOverride: 'rain' });
  let markup = svg(e, preview);
  line(markup, '-3℃'); line(markup, '17%'); line(markup, '☂');
  e.customization.showsWeatherHumidity = false;
  markup = svg(e, preview); assert.ok(!texts(markup).some(t => t.value.endsWith('%')));
  e.customization.showsIcon = false; markup = svg(e, preview); line(markup, 'Clouds');
  e.customization.showsUnit = false; markup = svg(e, preview);
  assert.deepEqual(texts(markup).map(t => t.value), ['WEATHER', '-3℃']);
});

for (const [summary, symbol] of [['Clear', '☀'], ['Clouds', '☁'], ['Drizzle', '☂'], ['Snow', '❄'], ['Thunderstorm', '⚡'], ['Haze', '≋'], ['Tornado', '≈'], ['unknown', '☁']]) {
  test(`weather auto icon for ${summary}`, () => line(svg(createElement('weather'), { ...preview, sample: { ...sample, weatherSummary: summary } }), symbol));
}

test('topProgress switches, distance conversion and per-row colors use native rules', () => {
  const e = createElement('topProgress');
  Object.assign(e.customization, {
    distanceUnit: 'm', progressStartColor: { red: 1, green: 0, blue: 0, alpha: 0.2 },
    progressCurrentColor: { red: 0, green: 1, blue: 0, alpha: 0.3 },
    progressEndColor: { red: 0, green: 0, blue: 1, alpha: 0.4 },
  });
  let markup = svg(e);
  colored(markup, '0.0 m', [255, 0, 0], 0.2); colored(markup, '12800.0 m', [0, 255, 0], 0.3);
  colored(markup, '18000.0 m', [0, 0, 255], 0.4);
  e.customization.showsLabel = false;
  assert.deepEqual(texts(svg(e)).map(t => t.value), ['18000.0 m']);
  e.customization.showsUnit = false; assert.deepEqual(texts(svg(e)), []);
});

test('topProgress ticks honor explicit count and per-element override', () => {
  const e = createElement('topProgress'); e.customization.showGaugeTicks = false;
  const without = svg(e);
  e.customization.showGaugeTicks = true; e.customization.progressTickCount = 8;
  const withTicks = svg(e);
  assert.notEqual(withTicks, without);
  e.customization.progressTickCount = 0;
  assert.equal([...svg(e).matchAll(/<line\b/g)].length, 0, 'zero ticks still retains tick spacing extent');
});

test('timeDate showsUnit hides clock and calendar while keeping elapsed', () => {
  const e = createElement('timeDate'); e.customization.showsUnit = false;
  assert.deepEqual(texts(svg(e)).map(t => t.value), ['00:42:48']);
  Object.assign(e.customization, { showsLabel: true, showsIcon: true, labelOverride: 'MY TIME', iconOverride: 'CLOCK' });
  for (const value of ['MY TIME', 'CLOCK', '00:42:48']) line(svg(e), value);
});

test('frame scale scales text uniformly; metricScale is not a hidden second text multiplier', () => {
  const e = createElement('heartRate');
  const before = Number(attribute(line(svg(e, preview), '148').attrs, 'font-size'));
  e.frame.scale = 2;
  assert.equal(Number(attribute(line(svg(e, preview), '148').attrs, 'font-size')), before * 2);
  const l = layout(e), original = renderer.gaugeSVG(e, l, 1920, 1080, preview);
  l.style.metricScale = 3;
  assert.equal(renderer.gaugeSVG(e, l, 1920, 1080, preview), original);
});

test('speed uses elapsed, km/h conversion, range labels and independent ticks', () => {
  const e = createElement('speed');
  const markup = svg(e, preview);
  for (const value of ['RUN', 'SPEED', '42:48', '13.0', 'KM/H']) line(markup, value);
  assert.ok(texts(markup).some(t => /^0\s+24$/.test(t.value)));
  e.customization.showGaugeTicks = false; assert.notEqual(svg(e, preview), markup);
});

test('route label, distance and icon flags follow native content', () => {
  const e = createElement('route'); e.customization.showsIcon = true;
  const markup = svg(e, preview);
  for (const value of ['GPS ROUTE', '12.80', 'km', 'GPS']) line(markup, value);
});

test('altitude has current value, axis labels and independently switched decorations', () => {
  const e = createElement('altitudeProfile');
  let markup = svg(e, preview);
  line(markup, 'ALTITUDE'); line(markup, '120.0'); line(markup, 'M');
  const initial = texts(markup).length;
  Object.assign(e.customization, { altitudeShowsMinMax: false, altitudeShowsDistanceLabels: false });
  markup = svg(e, preview); assert.equal(texts(markup).length, initial - 4);
  for (const key of ['altitudeShowsFill', 'altitudeShowsGrid', 'altitudeShowsCursor']) {
    const before = svg(e, preview); e.customization[key] = false;
    assert.notEqual(svg(e, preview), before, key);
  }
});

test('altitude width and height controls change bounds independently', () => {
  const e = createElement('altitudeProfile'), [before] = rendered([e]);
  e.customization.altitudeWidthScale = 2;
  let [after] = rendered([e]);
  close(after.bounds.width, before.bounds.width * 2); close(after.bounds.height, before.bounds.height);
  e.customization.altitudeHeightScale = 1.5;
  [after] = rendered([e]); close(after.bounds.height, before.bounds.height * 1.5);
});

test('preview sample and series are independent and missing telemetry stays missing', () => {
  const e = createElement('heartRate');
  line(svg(e, { sample: { elapsed: 0 }, series }), '--');
  assert.doesNotThrow(() => svg(createElement('route'), { sample }));
  assert.doesNotThrow(() => svg(createElement('altitudeProfile'), { sample }));
});

test('calories round like native Int(value.rounded())', () => {
  line(svg(createElement('calories'), { ...preview, sample: { ...sample, totalCalories: 428.8 } }), '429');
});

test('weather temperature fallback uses activity data and icon overrides require a known weather icon', () => {
  const e = createElement('weather');
  const options = { ...preview, sample: { ...sample, weatherTemperatureCelsius: null, temperatureCelsius: 7 } };
  line(svg(e, options), '7℃');
  e.customization.iconOverride = 'not-a-weather-icon'; line(svg(e, options), '☁');
  e.customization.iconOverride = 'auto'; line(svg(e, options), '☁');
  options.sample.temperatureCelsius = null; line(svg(e, options), '--℃');
});

test('topProgress knob, inset, label scale and value margin each affect their native geometry', () => {
  const e = createElement('topProgress');
  const circles = markup => [...markup.matchAll(/<circle\b([^>]*)\/?\s*>/g)].map(([,attrs]) => ({ r: Number(attribute(attrs, 'r')), x: Number(attribute(attrs, 'cx')) }));
  const original = circles(svg(e)); e.customization.progressKnobScale = 2;
  assert.ok(Math.max(...circles(svg(e)).map(c => c.r)) > Math.max(...original.map(c => c.r)));
  const start = Number(attribute(line(svg(e), '0.0 km').attrs, 'x'));
  e.customization.progressInsetScale = 0;
  assert.ok(Number(attribute(line(svg(e), '0.0 km').attrs, 'x')) < start);
  e.customization.progressCurrentScale = 3;
  assert.equal(Number(attribute(line(svg(e), '12.8 km').attrs, 'font-size')), 36);
  const y = Number(attribute(line(svg(e), '12.8 km').attrs, 'y'));
  e.customization.progressValueMarginScale = 3;
  assert.ok(Number(attribute(line(svg(e), '12.8 km').attrs, 'y')) > y);
});

test('topProgress knob defaults to white and bar/value colors override in that order', () => {
  const e = createElement('topProgress'); e.frame.style.accentColor = 'electricBlue';
  const rgba = value => value.match(/^rgba\(([^)]+)\)$/)?.[1].split(',').map(Number);
  function knob() {
    const circles = [...svg(e).matchAll(/<circle\b([^>]*)\/?\s*>/g)].map(([, attrs]) => attrs);
    const inner = circles.find(attrs => Number(attribute(attrs, 'r')) === Math.min(...circles.map(a => Number(attribute(a, 'r')))));
    return { fill: rgba(attribute(inner, 'fill')), stroke: rgba(attribute(circles.find(a => attribute(a, 'fill') === 'none'), 'stroke')) };
  }
  assert.deepEqual(knob(), { fill: cssChannels({ red: 0.96, green: 0.98, blue: 1, alpha: 0.96 }), stroke: cssChannels({ red: 0.45, green: 0.82, blue: 1, alpha: 0.98 }) });
  e.customization.valueColor = { red: 1, green: 0, blue: 0, alpha: 0.4 };
  assert.deepEqual(knob(), { fill: cssChannels(e.customization.valueColor), stroke: cssChannels(e.customization.valueColor) });
  e.customization.progressBarColor = { red: 0, green: 1, blue: 0, alpha: 0.6 };
  assert.deepEqual(knob(), { fill: cssChannels(e.customization.progressBarColor), stroke: cssChannels(e.customization.progressBarColor) });
  delete e.customization.valueColor;
  assert.deepEqual(knob(), { fill: cssChannels(e.customization.progressBarColor), stroke: cssChannels(e.customization.progressBarColor) });
});

test('topProgress clamps progress at an increased current distance and does not render negative fill', () => {
  const e = createElement('topProgress');
  const options = { sample: { ...sample, distanceMeters: 20000 }, series };
  assert.deepEqual(texts(svg(e, options)).map(t => t.value), ['0.0 km', '20.0 km', '20.0 km']);
  options.sample.distanceMeters = -10;
  assert.deepEqual(texts(svg(e, options)).map(t => t.value), ['0.0 km', '0.0 km', '18.0 km']);
  assert.doesNotMatch(svg(e, options), /width="-/);
});

test('altitude cursor size is its diameter and opacity multiplies the configured alpha', () => {
  const e = createElement('altitudeProfile'); e.frame.scale = 1;
  Object.assign(e.customization, { altitudeCursorSize: 20, altitudeCursorColor: { red: 1, green: 0, blue: 1, alpha: 0.6 }, altitudeFillColor: { red: 0, green: 1, blue: 0, alpha: 0.5 }, altitudeFillOpacity: 0.4, altitudeGridColor: { red: 1, green: 0, blue: 0, alpha: 0.8 }, altitudeGridOpacity: 0.5 });
  const markup = svg(e, preview);
  const cursor = [...markup.matchAll(/<circle\b([^>]*)\/?\s*>/g)].find(([,attrs]) => attribute(attrs, 'fill') === cssColor(e.customization.altitudeCursorColor));
  assert.ok(cursor); assert.equal(Number(attribute(cursor[1], 'r')), 10);
  assert.ok(markup.includes(cssColor({ ...e.customization.altitudeFillColor, alpha: 0.2 })), 'fill alpha .5 × opacity .4');
  assert.ok(markup.includes(cssColor({ ...e.customization.altitudeGridColor, alpha: 0.4 })), 'grid alpha .8 × opacity .5');
});

test('route and altitude without usable source data draw no synthetic map or profile', () => {
  const empty = { sample, series: { totalDistanceMeters: 0, samples: [] } };
  for (const kind of ['route', 'altitudeProfile']) {
    assert.equal(texts(svg(createElement(kind), empty)).length, 0);
    assert.doesNotMatch(svg(createElement(kind), empty), /<(?:path|line|circle|ellipse)\b/);
  }
});

test('weather includes temperature unit, automatic cloud icon and humidity', () => {
  const values = texts(svg(createElement('weather'))).map(t => t.value);
  assert.ok(values.includes('21℃'), 'temperature includes its native unit');
  assert.ok(values.includes('☁'), 'Clouds selects the cloud weather icon');
  assert.ok(values.includes('85%'), 'humidity is visible by default');
});

test('lengthScale changes panel width without stretching text', () => {
  const element = createElement('heartRate'); element.customization.lengthScale = 0.4;
  for (const [, x, y] of svg(element).matchAll(/scale\(\s*([\d.e+-]+)[ ,]+([\d.e+-]+)\s*\)/g)) {
    assert.equal(Number(x), Number(y), 'lengthScale cannot apply an anisotropic transform to text');
  }
});
