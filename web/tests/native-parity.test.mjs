import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { nativeSourceHashes } from './generate-native-goldens.mjs';
import { nativeParityInputs, nativeDisplayInputs } from './native-parity-inputs.mjs';

const goldens = JSON.parse(readFileSync(new URL('./native-goldens.json', import.meta.url), 'utf8'));
const regeneration = 'Regenerate with node web/tests/generate-native-goldens.mjs after reviewing native changes.';
const sampleFields = ['elapsed', 'date', 'hasSyntheticDistance', 'latitude', 'longitude', 'altitudeMeters', 'sourceAltitudeMeters',
  'totalAscentMeters', 'heartRate', 'cadence', 'distanceMeters', 'speedMetersPerSecond', 'powerWatts',
  'verticalOscillationCentimeters', 'groundContactTimeMilliseconds', 'groundContactTimePercent', 'groundContactTimeBalancePercent',
  'verticalRatioPercent', 'respirationRateBreathsPerMinute', 'stepSpeedLossPercent', 'formPowerWatts', 'airPowerWatts',
  'legSpringStiffnessKilonewtonsPerMeter', 'totalCalories', 'stepLengthMeters', 'temperatureCelsius', 'weatherTemperatureCelsius',
  'weatherHumidityPercent', 'weatherSummary', 'trackSegmentIndex'];
const compact = value => JSON.parse(JSON.stringify(value));
const coreSample = value => Object.fromEntries(sampleFields.filter(key => value[key] != null).map(key => [key, value[key]]));

function compare(actual, expected, path = 'output') {
  if (typeof expected === 'number') {
    assert.equal(typeof actual, 'number', `${path}: missing numeric value`);
    const epsilon = /(?:^|\.)date$|activityStartDate$/.test(path) ? 1e-6 : 1e-8 + Math.abs(expected) * 1e-12;
    assert.ok(Number.isFinite(actual) && Math.abs(actual - expected) <= epsilon, `${path}: ${actual} != native ${expected} (±${epsilon})`);
    return;
  }
  if (Array.isArray(expected)) {
    assert.ok(Array.isArray(actual), `${path}: expected array`);
    assert.equal(actual.length, expected.length, `${path}: sample/count mismatch`);
    expected.forEach((item, index) => compare(actual[index], item, `${path}[${index}]`));
    return;
  }
  if (expected && typeof expected === 'object') {
    assert.deepEqual(Object.keys(actual ?? {}).sort(), Object.keys(expected).sort(), `${path}: field presence mismatch`);
    for (const key of Object.keys(expected)) compare(actual[key], expected[key], `${path}.${key}`);
    return;
  }
  assert.equal(actual, expected, path);
}

test('native golden source hashes match current Core implementation', () => {
  assert.equal(goldens.schemaVersion, 1);
  assert.deepEqual(nativeSourceHashes(), goldens.sourceHashes, regeneration);
});

test('native goldens match the complete synthetic input manifest', () => {
  assert.deepEqual(goldens.cases.map(row => row.name), nativeParityInputs.map(row => row.name), regeneration);
  goldens.cases.forEach((row, i) => {
    assert.equal(row.inputHash, createHash('sha256').update(JSON.stringify(nativeParityInputs[i].input)).digest('hex'), `${row.name}: ${regeneration}`);
  });
  assert.deepEqual(goldens.displayCases.map(row => row.name), nativeDisplayInputs.map(row => row.name), regeneration);
  goldens.displayCases.forEach((row, i) => {
    assert.equal(row.inputHash, createHash('sha256').update(JSON.stringify(nativeDisplayInputs[i].input)).digest('hex'), `${row.name}: ${regeneration}`);
  });
});

for (const { name } of nativeDisplayInputs) {
  test(`native visible strings: ${name}`, async () => {
    const { gaugeSVG } = await import('../render.mjs');
    const { createDocument, createElement } = await import('../model.mjs');
    const { expected } = goldens.displayCases.find(row => row.name === name);
    const query = expected.queries[0], display = query.display;
    assert.ok(display, 'CLI --display must add the formatter output');
    const totalDistanceMeters = expected.samples.findLast(sample => Number.isFinite(sample.distanceMeters))?.distanceMeters ?? 0;
    const preview = { sample: { ...query.sample, clock: display.clock, calendar: display.calendar }, series: { samples: expected.samples, totalDistanceMeters } };
    function texts(kind, precision) {
      const element = createElement(kind);
      if (precision !== undefined) element.customization.valuePrecision = precision;
      const layout = { ...createDocument('Native display regression', true).layout, elements: [element] };
      return [...gaugeSVG(element, layout, 1920, 1080, preview).matchAll(/<text\b[^>]*>(.*?)<\/text>/gs)].map(match => match[1]);
    }
    for (const [kind, key] of Object.entries({ pace: 'pace', heartRate: 'heartRate', cadence: 'cadence', calories: 'calories', weather: 'weatherTemperature' })) {
      assert.ok(texts(kind).includes(display[key]), `${key}: Web visible text differs from Swift ${display[key]}`);
    }
    for (let precision = 0; precision <= 3; precision++) {
      assert.ok(texts('distance', precision).includes(display[`distanceKmPrecision${precision}`]), `distance precision ${precision}`);
      assert.ok(texts('ascent', precision).includes(display[`ascentPrecision${precision}`]), `ascent precision ${precision}`);
      assert.ok(texts('topProgress', precision).includes(`${display[`totalDistanceKm${precision}`]} km`), `total distance precision ${precision}`);
    }
    const timeTexts = texts('timeDate');
    for (const key of ['elapsed', 'clock', 'calendar']) assert.ok(timeTexts.includes(display[key]), `${key}: ${display[key]}`);
    if (name.includes('long elapsed')) assert.equal(display.elapsed, '01:01:01');
    if (name.includes('placeholders')) {
      assert.equal(display.pace, '--:--');
      assert.equal(display.clock, '--:--:--');
      assert.equal(display.calendar, '----/--/--');
      assert.equal(display.altitudePrecision3, '--');
    }
  });
}

for (const { name, input } of nativeParityInputs) {
  test(`native parity: ${name}`, async () => {
    const native = await import('../telemetry-series.mjs');
    const { applyingQuantizedAltitudeDisplaySmoothing } = await import('../telemetry-altitude.mjs');
    const golden = goldens.cases.find(row => row.name === name);
    assert.ok(golden, `${name}: missing native golden. ${regeneration}`);
    let actual;
    if (input.operation === 'correction') {
      actual = { samples: native.correctingRunningDecelerations(structuredClone(input.samples)).map(coreSample) };
    } else {
      let series, activity;
      if (input.operation === 'fit') {
        const { parseFIT } = await import('../telemetry.mjs');
        activity = parseFIT(Buffer.from(input.fitBase64, 'base64'));
        series = activity.nativeSeries ?? activity;
      } else {
        series = native.createNativeSeries(structuredClone(input.samples), structuredClone(input.pauses ?? []));
        if (input.operation === 'altitude') series = applyingQuantizedAltitudeDisplaySmoothing(series);
        if (input.rebuild) series = native.createNativeSeries(series.samples, series.pausedRanges);
      }
      actual = compact({ samples: series.samples.map(coreSample), pausedRanges: series.pausedRanges, bounds: series.bounds,
        duration: series.duration, activeDuration: series.activeDuration, activityStartDate: series.activityStartDate,
        sport: activity?.sport, timeZoneOffsetSeconds: activity?.timeZoneOffsetSeconds,
        queries: (input.queries ?? []).map(wall => ({ wall, sample: coreSample(native.sampleNativeSeries(series, wall)),
          date: native.dateNativeSeries(series, wall), active: native.activeElapsed(series, wall) })) });
    }
    compare(actual, golden.expected);
  });
}
