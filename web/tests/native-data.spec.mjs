import { test, expect } from '@playwright/test';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { nativeParityInputs } from './native-parity-inputs.mjs';
import { nativeSourceHashes } from './generate-native-goldens.mjs';

const goldens = JSON.parse(readFileSync(new URL('./native-goldens.json', import.meta.url), 'utf8'));

test('all synthetic telemetry scenarios match native Swift inside the browser', async ({ page }) => {
  expect(nativeSourceHashes()).toEqual(goldens.sourceHashes);
  expect(goldens.cases.map(row => row.name)).toEqual(nativeParityInputs.map(row => row.name));
  const cases = nativeParityInputs.map(({ name, input }, index) => {
    const golden = goldens.cases[index];
    expect(createHash('sha256').update(JSON.stringify(input)).digest('hex'), name).toBe(golden.inputHash);
    return { name, input, expected: golden.expected };
  });
  const pageErrors = [];
  page.on('pageerror', error => pageErrors.push(error.message));
  await page.goto('./?lang=en');
  const result = await page.evaluate(async cases => {
    const native = await import('./telemetry-series.mjs?v=20261025-native-data');
    const { applyingQuantizedAltitudeDisplaySmoothing } = await import('./telemetry-altitude.mjs?v=20261025-native-data');
    const { parseFIT, previewAt } = await import('./telemetry.mjs?v=20261025-native-data');
    const sampleFields = ['elapsed', 'date', 'hasSyntheticDistance', 'latitude', 'longitude', 'altitudeMeters', 'sourceAltitudeMeters',
      'totalAscentMeters', 'heartRate', 'cadence', 'distanceMeters', 'speedMetersPerSecond', 'powerWatts',
      'verticalOscillationCentimeters', 'groundContactTimeMilliseconds', 'groundContactTimePercent', 'groundContactTimeBalancePercent',
      'verticalRatioPercent', 'respirationRateBreathsPerMinute', 'stepSpeedLossPercent', 'formPowerWatts', 'airPowerWatts',
      'legSpringStiffnessKilonewtonsPerMeter', 'totalCalories', 'stepLengthMeters', 'temperatureCelsius', 'weatherTemperatureCelsius',
      'weatherHumidityPercent', 'weatherSummary', 'trackSegmentIndex'];
    const compact = value => JSON.parse(JSON.stringify(value));
    const coreSample = value => Object.fromEntries(sampleFields.filter(key => value[key] != null).map(key => [key, value[key]]));
    function compare(actual, expected, path) {
      if (typeof expected === 'number') {
        const epsilon = /(?:^|\.)(?:date|absoluteDate)$|activityStartDate$/.test(path) ? 1e-6 : 1e-8 + Math.abs(expected) * 1e-12;
        if (!Number.isFinite(actual) || Math.abs(actual - expected) > epsilon)
          throw new Error(`${path}: ${actual} != native ${expected} (±${epsilon})`);
      } else if (Array.isArray(expected)) {
        if (!Array.isArray(actual) || actual.length !== expected.length)
          throw new Error(`${path}: count ${actual?.length} != native ${expected.length}`);
        expected.forEach((value, index) => compare(actual[index], value, `${path}[${index}]`));
      } else if (expected && typeof expected === 'object') {
        if (JSON.stringify(Object.keys(actual ?? {}).sort()) !== JSON.stringify(Object.keys(expected).sort()))
          throw new Error(`${path}: field presence mismatch`);
        for (const key of Object.keys(expected)) compare(actual[key], expected[key], `${path}.${key}`);
      } else if (actual !== expected) {
        throw new Error(`${path}: ${actual} != native ${expected}`);
      }
    }
    let fitCases = 0, previewQueries = 0;
    for (const { name, input, expected } of cases) {
      let actual;
      if (input.operation === 'correction') {
        actual = { samples: native.correctingRunningDecelerations(structuredClone(input.samples)).map(coreSample) };
      } else {
        let series, activity;
        if (input.operation === 'fit') {
          activity = parseFIT(Uint8Array.from(atob(input.fitBase64), character => character.charCodeAt(0)));
          series = activity.nativeSeries ?? activity;
          fitCases++;
          for (const query of expected.queries) {
            const preview = previewAt(activity, query.wall);
            compare(coreSample(preview.sample), coreSample(query.sample), `${name}.previewAt(${query.wall}).sample`);
            compare(preview.absoluteDate, query.date, `${name}.previewAt(${query.wall}).absoluteDate`);
            compare(preview.inRange, query.wall >= 0 && query.wall <= expected.duration, `${name}.previewAt(${query.wall}).inRange`);
            previewQueries++;
          }
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
      compare(actual, expected, name);
    }
    return { cases: cases.length, fitCases, previewQueries };
  }, JSON.parse(JSON.stringify(cases)));
  expect(result.cases).toBe(nativeParityInputs.length);
  expect(result.fitCases).toBe(nativeParityInputs.filter(row => row.input.operation === 'fit').length);
  expect(result.previewQueries).toBe(nativeParityInputs.filter(row => row.input.operation === 'fit').reduce((count, row) => count + row.input.queries.length, 0));
  expect(pageErrors).toEqual([]);
});
