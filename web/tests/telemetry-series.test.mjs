import test from 'node:test';
import assert from 'node:assert/strict';
import { createNativeSeries, sampleNativeSeries, dateNativeSeries, activeElapsed, wallElapsed,
  interpolateNativeSample, startupCatchUpCorrection, motionResumptionCorrections,
  correctingRunningDecelerations } from '../telemetry-series.mjs';

const close = (a, b, tolerance = 1e-9) => assert.ok(Math.abs(a - b) <= tolerance, `${a} != ${b}`);
const complete = (elapsed, distanceMeters, speedMetersPerSecond = 3, extras = {}) => ({ elapsed,
  latitude: 35 + elapsed * 0.0001, longitude: 139 + elapsed * 0.0001, heartRate: 130,
  cadence: 180, distanceMeters, speedMetersPerSecond, ...extras });
const at = (series, elapsed) => sampleNativeSeries(series, elapsed);
function catchUpSamples() {
  const distances = [0, 0, 0, 0, 9, 18, 25, 32, 39, 46, 53.5, 61];
  const speeds = [undefined, undefined, 0, 0, 2.172, 4.347, 4.733, 5.119, 5.608, 6.1, 6.119, 6.139];
  const cadences = [undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, 220, 218, 216, 212];
  return [{ elapsed: 0, distanceMeters: 0 }, ...distances.map((distance, i) => complete(i + 1, distance, speeds[i], { cadence: cadences[i], speedMetersPerSecond: speeds[i] }))];
}
function intervalSamples(rest, launch) {
  const samples = [];
  let distance = 0;
  for (let second = 0; second <= 70; second++) {
    let values;
    if (second < 25) values = [4.5, second > 0 ? 4.5 : 0, 180];
    else if (second < 45) values = rest(second);
    else if (second < 45 + launch.length) values = launch[second - 45];
    else values = [6.1, 6.1, 212];
    distance += values[1];
    samples.push(complete(second, distance, values[0], { cadence: values[2] }));
  }
  return samples;
}
const launch = [[1.5, 6, 0], [2.5, 8, 180], [3.5, 7, 212], [4.5, 7, 212], [5.5, 6.5, 212],
  [6, 6, 212], [6.05, 6, 212], ...Array.from({ length: 8 }, () => [6.1, 6, 212])];

test('startup catch-up matches native ramp, cadence and stable distance anchor', () => {
  const series = createNativeSeries(catchUpSamples());
  close(at(series, 0).speedMetersPerSecond, 0.35);
  assert.ok(at(series, 6).speedMetersPerSecond > 5);
  close(at(series, 10).speedMetersPerSecond, 6.1);
  close(at(series, 11).speedMetersPerSecond, 6.119);
  close(at(series, 10).distanceMeters, 46);
  assert.ok(at(series, 7).cadence > 200);
  assert.ok(at(series, 2).cadence > 90);
  close(at(series, 9).cadence, 220);
  for (let i = 1; i <= 10; i++) {
    assert.ok(at(series, i).speedMetersPerSecond >= at(series, i - 1).speedMetersPerSecond);
    assert.ok(at(series, i).distanceMeters - at(series, i - 1).distanceMeters < 7);
  }
  const rebuilt = createNativeSeries(series.samples);
  series.samples.forEach((sample, i) => {
    close(sample.speedMetersPerSecond, rebuilt.samples[i].speedMetersPerSecond);
    close(sample.distanceMeters, rebuilt.samples[i].distanceMeters);
  });
});

test('self-consistent startup and synthetic-distance records do not trigger catch-up', () => {
  const distances = [0, 1.69, 4.42, 6.48, 9.02, 11.75, 14.15, 16.2];
  const speeds = [3.386, 3.386, 1.983, 1.983, 2.205, 2.298, 2.465, 2.465];
  const samples = distances.map((d, i) => complete(i, d, speeds[i]));
  assert.equal(startupCatchUpCorrection(samples), undefined);
  assert.deepEqual(createNativeSeries(samples).samples.map(s => s.speedMetersPerSecond), speeds);
  const synthetic = catchUpSamples(); synthetic[5].hasSyntheticDistance = true;
  assert.equal(startupCatchUpCorrection(synthetic), undefined);
});

test('fallback startup preserves the first complete reliable device point', () => {
  const samples = catchUpSamples().slice(0, 8);
  const series = createNativeSeries(samples);
  close(at(series, 5).speedMetersPerSecond, 2.172);
  close(at(series, 6).speedMetersPerSecond, 4.347);
  close(at(series, 7).speedMetersPerSecond, 4.733);
  assert.ok(at(series, 4).speedMetersPerSecond < at(series, 5).speedMetersPerSecond);
});

test('motion resumption accelerates only the lag window and reconstructs idempotently', () => {
  const samples = intervalSamples(() => [1, 1, 110], launch);
  assert.equal(motionResumptionCorrections(samples).length, 1);
  const series = createNativeSeries(samples);
  close(at(series, 40).speedMetersPerSecond, 1);
  assert.ok(at(series, 47).speedMetersPerSecond > 5.5);
  close(at(series, 52).speedMetersPerSecond, 6.1);
  close(at(series, 50).distanceMeters, samples[50].distanceMeters);
  const rebuilt = createNativeSeries(series.samples);
  series.samples.forEach((sample, i) => {
    close(sample.speedMetersPerSecond, rebuilt.samples[i].speedMetersPerSecond);
    close(sample.distanceMeters, rebuilt.samples[i].distanceMeters);
  });
});

test('motion resumption resets a standing launch anchor instead of borrowing launch distance speed', () => {
  const stationaryLaunch = [[0, 6, 76], [1.2, 6, 100], [2.5, 5.5, 101], [2.95, 5.5, 101],
    [3.44, 5.5, 102], [4.38, 5.5, 103], [5.325, 5.5, 104], [5.333, 5.5, 103],
    [5.342, 5.5, 103], [5.344, 5.5, 102], [5.35, 5.5, 102], [5.34, 5, 101],
    [5.336, 5, 101], [5.32, 5, 101], [5.31, 5, 101]];
  const series = createNativeSeries(intervalSamples(() => [0, 0, 0], stationaryLaunch));
  assert.ok(at(series, 44).speedMetersPerSecond <= 0.4);
  assert.ok(at(series, 47).speedMetersPerSecond > 4.5);
});

test('walk/stop, GPS drift and a consistent gradual recovery do not qualify as running resumptions', () => {
  const samples = intervalSamples(second => second >= 27 && second <= 29 ? [0.6, 2, 124]
    : second >= 30 && second <= 33 ? [0, 0, 0] : second === 34 || second === 35 ? [0, 1.5, 0] : [0.3, 0, 0], []);
  assert.deepEqual(motionResumptionCorrections(samples), []);
  for (let i = 25; i < 45; i++) assert.ok(at(createNativeSeries(samples), i).speedMetersPerSecond < 2.5);
  let speed = 1;
  const gradual = Array.from({ length: 15 }, () => { speed = Math.min(6, speed + 0.4); return [speed, speed, 180]; });
  assert.deepEqual(motionResumptionCorrections(intervalSamples(() => [1, 1, 110], gradual)), []);
});

test('native optional interpolation keeps metadata and Swift cadence rounding', () => {
  const a = { elapsed: 0, date: 1000, altitudeMeters: 10, sourceAltitudeMeters: 9,
    cadence: 0, heartRate: 120, powerWatts: 100, weatherSummary: 'a', trackSegmentIndex: 2, hasSyntheticDistance: false };
  const b = { elapsed: 2, date: 1002, altitudeMeters: 12, cadence: 181, heartRate: 140,
    temperatureCelsius: -2, weatherSummary: 'b', trackSegmentIndex: 3, hasSyntheticDistance: true };
  const sample = interpolateNativeSample(a, b, 0.5, 1);
  close(sample.date, 1001); close(sample.altitudeMeters, 11); close(sample.sourceAltitudeMeters, 10.5);
  assert.equal(sample.cadence, 91); assert.equal(sample.heartRate, 140); assert.equal(sample.powerWatts, 100);
  assert.equal(sample.temperatureCelsius, -2); assert.equal(sample.weatherSummary, 'b');
  assert.equal(sample.trackSegmentIndex, 2); assert.equal(sample.hasSyntheticDistance, true);
  assert.equal(interpolateNativeSample(a, b, 0, 0).hasSyntheticDistance, false);
  assert.equal(interpolateNativeSample(a, b, 1, 2).trackSegmentIndex, 3);
  assert.equal(interpolateNativeSample(a, { elapsed: 2 }, 0.5, 1).cadence, undefined);
  assert.equal(interpolateNativeSample({ cadence: 170 }, { cadence: 190 }, 0.49, 1).cadence, 170);
});

test('pause sanitation, wall/active mapping and dates keep wall clock running', () => {
  const series = createNativeSeries([complete(0, 0, 3, { date: 1000 }), complete(10, 30, 3, { date: 1016 })],
    [{ start: 6, duration: 2 }, { start: 4, duration: 3 }, { start: -1, duration: 2 }, { start: 3, duration: 0 }, { start: Infinity, duration: 1 }]);
  assert.deepEqual(series.pausedRanges, [{ start: 4, duration: 4 }]);
  close(series.activeDuration, 10); close(series.duration, 14); close(series.activityStartDate, 1000);
  close(activeElapsed(series, 7), 4); close(activeElapsed(series, 10), 6);
  close(wallElapsed(series, 4), 4); close(wallElapsed(series, 4.5), 8.5);
  assert.deepEqual(at(series, 5), at(series, 7));
  close(dateNativeSeries(series, 7), 1007);
  assert.equal(dateNativeSeries(series, Infinity), undefined);
  assert.equal(activeElapsed(series, Infinity), Infinity);
});

test('series leaves a nonzero first elapsed untouched and sorts equal times by date', () => {
  const series = createNativeSeries([complete(12, 6, 3, { date: 1012 }), complete(10, 0, 3, { date: 1010 }),
    complete(10, 0, 3, { date: 1009 })]);
  close(series.samples[0].elapsed, 10); close(series.samples[0].date, 1009);
  close(series.activeDuration, 2); close(series.duration, 2); close(series.activityStartDate, 999);
  close(dateNativeSeries(series, 9), 1008); close(dateNativeSeries(series, 13), 1013);
  assert.equal(series.samples.filter(s => s.elapsed === 10).length, 1);
});

test('resampling is relative to each source point and segment breaks hold values', () => {
  const series = createNativeSeries([complete(0.25, 0), complete(2.75, 7.5), complete(5, 14.25, 3, { trackSegmentIndex: 1 })]);
  assert.deepEqual(series.samples.map(s => s.elapsed), [0.25, 1.25, 2.25, 2.75, 5]);
  const held = at(series, 4);
  close(held.elapsed, 4); close(held.distanceMeters, 7.5);
  assert.equal(held.trackSegmentIndex, undefined);
  const dated = createNativeSeries([complete(0, 0, 3, { date: 1000 }), complete(3, 9, 3, { date: 1003, trackSegmentIndex: 2 })]);
  close(at(dated, 2).date, 1002);
});

test('100k insertion budget skips an entire huge gap while keeping all source points', () => {
  const series = createNativeSeries([complete(0, 0), complete(1_000_000, 3_000_000)]);
  assert.equal(series.samples.length, 2);
  const source = Array.from({ length: 100_001 }, (_, i) => ({ elapsed: i * 2, distanceMeters: i * 6, speedMetersPerSecond: 3 }));
  const dense = createNativeSeries(source);
  assert.equal(dense.samples.length, source.length);
  close(dense.samples.at(-1).elapsed, 200_000);
});

test('distance baseline, missing startup distance and segment ascent use native source data', () => {
  const series = createNativeSeries([{ elapsed: 0 }, complete(3, 9)]);
  close(at(series, 1).distanceMeters, 3);
  const offset = createNativeSeries([{ elapsed: 0 }, { elapsed: 2, distanceMeters: 1000 }]);
  close(at(offset, 1).distanceMeters, 0);
  const ascent = createNativeSeries([complete(0, 30, 3, { altitudeMeters: 10.3, sourceAltitudeMeters: 10 }),
    complete(1, 33, 3, { altitudeMeters: 10.8, sourceAltitudeMeters: 11 }),
    complete(2, 36, 3, { altitudeMeters: 12.3, sourceAltitudeMeters: 12 }),
    complete(3, 39, 3, { altitudeMeters: 20, trackSegmentIndex: 1 })]);
  assert.deepEqual(ascent.samples.map(s => s.totalAscentMeters), [0, 1, 2, 2]);
  close(ascent.totalDistanceMeters, 9);
  assert.deepEqual(createNativeSeries(ascent.samples).samples.map(s => s.totalAscentMeters), [0, 1, 2, 2]);
});

test('incomplete stationary tail is trimmed but moving tail fills only heart rate/cadence', () => {
  const head = [complete(0, 0), complete(1, 3), complete(2, 6)];
  const trimmed = createNativeSeries([...head, { elapsed: 3, heartRate: 133, cadence: 180 }, { elapsed: 4, heartRate: 134 }]);
  close(trimmed.duration, 2); close(trimmed.totalDistanceMeters, 6);
  const moving = createNativeSeries([...head, { elapsed: 3, distanceMeters: 9, speedMetersPerSecond: 3 },
    { elapsed: 4, distanceMeters: 12, speedMetersPerSecond: 3 }]);
  close(moving.duration, 4); close(at(moving, 4).distanceMeters, 12);
  assert.equal(at(moving, 4).heartRate, 130); assert.equal(at(moving, 4).cadence, 180);
  assert.equal(at(moving, 4).latitude, undefined);
});

test('synthetic distance cannot backfill speed and valid mid-activity high speed is retained', () => {
  const stationary = Array.from({ length: 26 }, (_, i) => complete(i, 0, 0));
  const synthetic = createNativeSeries([...stationary, complete(26, 16, 0, { hasSyntheticDistance: true }), complete(27, 32, 0)]);
  close(at(synthetic, 26).speedMetersPerSecond, 0);
  const high = createNativeSeries(Array.from({ length: 41 }, (_, i) => complete(i, Math.max(0, i - 4) * 16, i >= 5 && i < 20 ? 16 : 0)));
  assert.ok(at(high, 30).speedMetersPerSecond > 12);
  const subsecond = createNativeSeries([...stationary, complete(25.05, 0.61, 0), complete(26, 0.61, 0), complete(27, 0.61, 0)]);
  assert.ok(at(subsecond, 25).speedMetersPerSecond < 2.5);
});

function laggedDecelerationSamples() {
  let distance = 0;
  const speed = second => Math.max(1, Math.min(5, 5 - (second - 29) * 0.5));
  return Array.from({ length: 61 }, (_, second) => {
    if (second > 0) distance += speed(second);
    return { elapsed: second, date: 1000 + second, heartRate: 150, cadence: 180, distanceMeters: distance, speedMetersPerSecond: speed(second - 3) };
  });
}
test('running deceleration uses a bounded device-curve lead and rejects gaps or synthetic evidence', () => {
  const samples = laggedDecelerationSamples(), corrected = correctingRunningDecelerations(samples);
  assert.ok(corrected[34].speedMetersPerSecond < samples[34].speedMetersPerSecond);
  for (let i = 0; i < samples.length; i++) {
    assert.deepEqual(corrected[i], { ...samples[i], speedMetersPerSecond: corrected[i].speedMetersPerSecond });
    assert.ok(samples.slice(i, i + 3).some(s => s.speedMetersPerSecond === corrected[i].speedMetersPerSecond));
  }
  for (const mutate of [s => { s[34].date += 10; }, s => { s[34].hasSyntheticDistance = true; },
    s => { s[34].trackSegmentIndex = 1; }, s => { s[34].distanceMeters = undefined; },
    s => { s[34].speedMetersPerSecond = NaN; }, s => { s[34].elapsed += 0.5; },
    s => { for (let i = 37; i < s.length; i++) s[i].speedMetersPerSecond = 0; }]) {
    const invalid = samples.map(s => ({ ...s })); mutate(invalid);
    assert.deepEqual(correctingRunningDecelerations(invalid), invalid);
  }
});

test('native unordered min/max semantics do not contaminate normalized distance with NaN', () => {
  const source = [complete(0, 0), complete(1, NaN), complete(2, 6)];
  const original = structuredClone(source);
  const series = createNativeSeries(source);
  assert.deepEqual(series.samples.map(s => s.distanceMeters), [0, 3, 6]);
  const queried = at(series, NaN);
  assert.ok(Number.isNaN(queried.elapsed));
  close(queried.latitude, source[0].latitude);
  assert.deepEqual(source, original);
});
