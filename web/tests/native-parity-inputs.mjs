// Public synthetic inputs only. Expected values come exclusively from native-reference.swift.
const dateOrigin = 1_700_000_000;
const sample = (elapsed, values = {}) => ({ elapsed, hasSyntheticDistance: false, date: dateOrigin + elapsed, ...values });
const positioned = (elapsed, values = {}) => sample(elapsed, { latitude: elapsed * .00001, longitude: 0, heartRate: 150, cadence: 180, ...values });
const seconds = (end, make) => Array.from({ length: end + 1 }, (_, second) => make(second));
const entry = (name, samples, queries = [0, .25, .5, 1, 2, 5, 10, 15, 20, 30, 45, 60], extra = {}) =>
  ({ name, input: { operation: 'series', samples, queries, ...extra } });

function startup() {
  const distances = [0, 0, 0, 0, 9, 18, 25, 32, 39, 46, 53.5, 61];
  const speeds = [undefined, undefined, 0, 0, 2.172, 4.347, 4.733, 5.119, 5.608, 6.1, 6.119, 6.139];
  const cadences = [undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, 220, 218, 216, 212];
  return [sample(0, { distanceMeters: 0 }), ...distances.map((distanceMeters, i) => positioned(i + 1,
    { distanceMeters, speedMetersPerSecond: speeds[i], cadence: cadences[i], heartRate: 125 + i }))];
}

function interval(rest, launch) {
  let distance = 0;
  const rows = [];
  const append = (second, [speedMetersPerSecond, delta, cadence]) => {
    distance += delta;
    rows.push(positioned(second, { speedMetersPerSecond, distanceMeters: distance, cadence }));
  };
  for (let i = 0; i < 20; i++) append(i, [5, i ? 5 : 0, 180]);
  [4, 3, 2, 1.5, 1.2].forEach((speed, i) => append(20 + i, [speed, speed, 150]));
  for (let i = 25; i <= 44; i++) append(i, rest(i));
  launch.forEach((row, i) => append(45 + i, row));
  return rows;
}

const launch = [[1.5, 6, 0], [2.5, 8, 180], [3.5, 7, 212], [4.5, 7, 212], [5.5, 6.5, 212],
  [6, 6, 212], [6.05, 6, 212], ...Array.from({ length: 8 }, () => [6.1, 6, 212])];
function deceleration() {
  let distance = 0;
  const speed = t => Math.max(1, Math.min(5, 5 - (t - 29) * .5));
  return seconds(60, second => {
    if (second) distance += speed(second);
    return sample(second, { distanceMeters: distance, speedMetersPerSecond: speed(second - 3), heartRate: 150, cadence: 180 });
  });
}

// Minimal deterministic FIT writer; no dependency on the Web parser under test.
const field = (number, size = 4, type = 0x86) => ({ number, size, type });
const timestamp = field(253);
const recordFields = [timestamp, field(0, 4, 0x85), field(1, 4, 0x85), field(5), field(6, 2, 0x84), field(3, 1, 2), field(4, 1, 2)];
const summaryFields = [timestamp, field(2), field(7), field(8), field(9), field(11, 2, 0x84)];
const eventFields = [timestamp, field(0, 1, 0), field(1, 1, 0)];
const fitOrigin = 1_000_000;
const definition = (local, global, fields) => Buffer.from([0x40 | local, 0, 0, global & 255, global >>> 8, fields.length,
  ...fields.flatMap(f => [f.number, f.size, f.type])]);
function data(local, fields, values) {
  return Buffer.concat([Buffer.from([local]), ...fields.map(f => {
    const bytes = Buffer.alloc(f.size, 255);
    if (values[f.number] !== undefined) {
      let integer = BigInt(values[f.number]);
      if (integer < 0) integer += 1n << BigInt(f.size * 8);
      for (let i = 0; i < f.size; i++) { bytes[i] = Number(integer & 255n); integer >>= 8n; }
    }
    return bytes;
  })]);
}
function crc16(bytes) {
  let crc = 0;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = crc & 1 ? crc >>> 1 ^ 0xa001 : crc >>> 1;
  }
  return crc;
}
function fit(chunks) {
  const payload = Buffer.concat(chunks), header = Buffer.alloc(14);
  header[0] = 14; header[1] = 0x20; header.writeUInt16LE(21000, 2);
  header.writeUInt32LE(payload.length, 4); header.write('.FIT', 8); header.writeUInt16LE(crc16(header.subarray(0, 12)), 12);
  const body = Buffer.concat([header, payload]), tail = Buffer.alloc(2); tail.writeUInt16LE(crc16(body));
  return Buffer.concat([body, tail]).toString('base64');
}
const fitRecord = (second, distance, speed, cadence = 90) => data(0, recordFields,
  { 253: fitOrigin + second, 0: 0, 1: 0, 5: Math.round(distance * 100), 6: Math.round(speed * 1000), 3: 150, 4: cadence });
const summary = (local, seconds, distance, start = 0, timer = seconds) => data(local, summaryFields,
  { 253: fitOrigin + Math.floor(start + seconds), 2: fitOrigin + start, 7: Math.round(seconds * 1000), 8: Math.round(timer * 1000), 9: Math.round(distance * 100), 11: 20 });
const fitEntry = (name, chunks, queries) => ({ name, input: { operation: 'fit', fitBase64: fit(chunks), queries } });

function altitudeFIT(manufacturer, altitudes) {
  const fields = [timestamp, field(2, 2, 0x84)];
  const chunks = [definition(1, 0, [field(1, 2, 0x84)]), data(1, [field(1, 2, 0x84)], { 1: manufacturer }), definition(0, 20, fields)];
  altitudes.forEach((altitude, i) => chunks.push(data(0, fields, { 253: fitOrigin + i, 2: Math.round((altitude + 500) * 5) })));
  return chunks;
}
const stairs = [804, 804, 804, 804, 805, 805, 805, 805, 805];

export const nativeParityInputs = [
  entry('empty series and out-of-range queries', [], [-2, 0, 2]),
  entry('single sample without dates', [sample(3, { date: undefined, heartRate: 120 })], [-1, 0, 3, 10]),
  entry('startup catch-up positive with cadence ramp', startup()),
  entry('startup catch-up rebuild', startup(), [0, 2, 6, 10, 12], { rebuild: true }),
  entry('startup distance-speed agreement negative', [0, 1.69, 4.42, 6.48, 9.02, 11.75, 14.15, 16.2].map((d, i) => positioned(i,
    { distanceMeters: d, speedMetersPerSecond: [3.386, 3.386, 1.983, 1.983, 2.205, 2.298, 2.465, 2.465][i], cadence: 166 }))),
  entry('startup incomplete points and baseline distance', [sample(0, { distanceMeters: 800 }),
    sample(2, { distanceMeters: 800, speedMetersPerSecond: 0 }), positioned(5, { distanceMeters: 810, speedMetersPerSecond: 3 }),
    positioned(10, { distanceMeters: 830, speedMetersPerSecond: 4 })]),
  entry('quiet resumption catch-up', interval(() => [1, 1, 110], launch)),
  entry('quiet resumption rebuild', interval(() => [1, 1, 110], launch), [40, 44, 45, 47, 50, 52], { rebuild: true }),
  entry('stationary resumption zero-speed anchor', interval(() => [0, 0, 0],
    [[0, 6, 76], [1.2, 6, 100], [2.5, 5.5, 101], [2.95, 5.5, 101], [3.44, 5.5, 102], [4.38, 5.5, 103], ...Array.from({ length: 9 }, () => [5.34, 5.5, 103])])),
  entry('walk stop and drift pulses negative', interval(t => t >= 27 && t <= 29 ? [.6, 2, 124]
    : t === 34 || t === 35 ? [0, 1.5, 0] : t >= 30 && t <= 33 ? [0, 0, 0] : [.3, 0, 0], [])),
  entry('gradual resumption agreement negative', interval(() => [1, 1, 110], Array.from({ length: 15 }, (_, i) => {
    const speed = Math.min(6, 1 + .4 * (i + 1)); return [speed, speed, 180];
  }))),
  entry('raw running deceleration', deceleration(), [], { operation: 'correction' }),
  ...['date', 'distanceMeters', 'speedMetersPerSecond', 'trackSegmentIndex', 'hasSyntheticDistance'].map(key => {
    const samples = deceleration();
    samples[34][key] = key === 'trackSegmentIndex' ? 1 : key === 'hasSyntheticDistance' ? true : undefined;
    return entry(`raw deceleration uncertain ${key}`, samples, [], { operation: 'correction' });
  }),
  entry('sparse resampling with subsecond endpoint', [positioned(0, { distanceMeters: 0, speedMetersPerSecond: 3 }),
    positioned(4.25, { distanceMeters: 12.75, speedMetersPerSecond: 3 })], [-1, 0, .49, .5, 1.25, 4, 4.25, 8]),
  entry('resampling budget preserves huge gaps', [sample(0, { speedMetersPerSecond: 3 }), sample(100001, { speedMetersPerSecond: 3 })], [0, .5, 50000.5, 100001]),
  entry('missing fields integer nearest and cadence zero interpolation', [sample(0, { heartRate: 101, cadence: 0,
    temperatureCelsius: -2, weatherTemperatureCelsius: -4, weatherHumidityPercent: 45, weatherSummary: 'Clear',
    powerWatts: 201, formPowerWatts: 35, airPowerWatts: 2, altitudeMeters: 10, sourceAltitudeMeters: 11,
    latitude: 0, longitude: 0, distanceMeters: 0, speedMetersPerSecond: 2, verticalOscillationCentimeters: 7,
    groundContactTimeMilliseconds: 220, groundContactTimePercent: 40, groundContactTimeBalancePercent: 49,
    verticalRatioPercent: 8, respirationRateBreathsPerMinute: 20, stepSpeedLossPercent: 3,
    legSpringStiffnessKilonewtonsPerMeter: 9, totalCalories: 1, stepLengthMeters: .8 }),
  sample(2, { heartRate: 102, cadence: 3, temperatureCelsius: -1, weatherTemperatureCelsius: -3,
    weatherHumidityPercent: 46, weatherSummary: 'Cloudy', powerWatts: 202, airPowerWatts: 3,
    distanceMeters: 4, speedMetersPerSecond: 2, altitudeMeters: 12, latitude: .0001, longitude: .0002,
    verticalOscillationCentimeters: 9, groundContactTimeMilliseconds: 240, groundContactTimePercent: 42,
    groundContactTimeBalancePercent: 51, verticalRatioPercent: 10, respirationRateBreathsPerMinute: 24,
    stepSpeedLossPercent: 5, legSpringStiffnessKilonewtonsPerMeter: 11, totalCalories: 3, stepLengthMeters: 1 })],
  [0, .49, .5, .51, .999, 1, 1.5, 2]),
  entry('track boundaries hold sample without bridging', [sample(0, { altitudeMeters: 10, trackSegmentIndex: 0 }),
    sample(10, { altitudeMeters: 20, trackSegmentIndex: 1 })], [0, 1, 5, 9.99, 10]),
  entry('duplicate elapsed sorts by optional date and preserves native deduplication', [sample(3, { heartRate: 140, distanceMeters: 9 }),
    sample(0, { date: undefined, heartRate: 110, distanceMeters: 0 }), sample(0, { heartRate: 120, distanceMeters: 0 }),
    sample(1.5, { heartRate: 130, distanceMeters: 4.5 })], [-1, 0, .25, .75, 1, 1.5, 2, 3]),
  entry('coordinates derive distance and speed without reported distance', seconds(5, i => positioned(i,
    { latitude: i * .00002, longitude: i * .00003, speedMetersPerSecond: undefined }))),
  entry('decreasing distance normalizes without negative speed', seconds(5, i => sample(i,
    { distanceMeters: [20, 23, 21, 30, 29, 34][i], speedMetersPerSecond: 0 }))),
  entry('pause beyond duration does not extend activity', [sample(0), sample(3)], [0, 3, 10, 12], { pauses: [{ start: 10, duration: 5 }] }),
  entry('pause sanitation overlapping and boundary dates', seconds(8, i => positioned(i, { date: dateOrigin + i + (i > 2 ? 5 : 0), distanceMeters: i * 3, speedMetersPerSecond: 3 })),
    [-2, 0, 2, 2.001, 4, 6.999, 7, 7.001, 9, 10, 12, 20],
    { pauses: [{ start: 4, duration: 3 }, { start: 2, duration: 3 }, { start: -1, duration: 2 }, { start: 12, duration: 0 }] }),
  entry('moving tail keeps and fills missing channels', seconds(8, i => positioned(i, { distanceMeters: i * 3,
    speedMetersPerSecond: 3, ...(i > 5 ? { latitude: undefined, longitude: undefined, heartRate: undefined, cadence: undefined } : {}) }))),
  entry('metadata-only frozen tail trimmed', seconds(8, i => positioned(i, { distanceMeters: Math.min(i, 5) * 3,
    speedMetersPerSecond: i > 5 ? 0 : 3, ...(i > 5 ? { latitude: undefined, longitude: undefined, cadence: undefined } : {}) }))),
  entry('slowly drifting tail agreement preserved', seconds(25, i => positioned(i, { speedMetersPerSecond: 3 + i * .005, distanceMeters: 3 * i + .0025 * i * (i + 1) }))),
  entry('synthetic distance anchor cannot refill stopped speed', [...seconds(40, i => sample(i,
    { distanceMeters: Math.min(i, 20) * 5, speedMetersPerSecond: i <= 20 ? 5 : 0 })),
  sample(25.5, { hasSyntheticDistance: true, distanceMeters: 100.67, speedMetersPerSecond: 0 })], [20, 22, 25, 25.5, 26, 30, 40], { rebuild: true }),
  entry('valid high speed mid-activity backfill', seconds(40, i => positioned(i,
    { distanceMeters: Math.max(0, i - 4) * 16, speedMetersPerSecond: i >= 5 && i < 20 ? 16 : 0 }))),
  entry('altitude display raw ascent preserved', stairs.map((altitudeMeters, i) => sample(i, { altitudeMeters })), [0, 1, 3, 3.5, 4, 7, 8], { operation: 'altitude' }),
  entry('altitude smoothing rebuild', stairs.map((altitudeMeters, i) => sample(i, { altitudeMeters })), [0, 3, 4, 8], { operation: 'altitude', rebuild: true }),
  entry('altitude smoothing pause boundary', stairs.map((altitudeMeters, i) => sample(i, { altitudeMeters })), [2, 3, 4, 5, 6, 7, 8, 9, 10],
    { operation: 'altitude', pauses: [{ start: 3, duration: 2 }] }),
  entry('altitude smoothing track boundary', stairs.map((altitudeMeters, i) => sample(i, { altitudeMeters, trackSegmentIndex: i < 4 ? 0 : 1 })),
    [2, 3, 4, 5, 8], { operation: 'altitude' }),
  entry('altitude smoothing missing field boundary', [804, 804, 804, undefined, 805, 805, 805, 805, 805].map((altitudeMeters, i) => sample(i, { altitudeMeters })),
    [0, 2, 2.5, 3, 3.5, 4, 5, 8], { operation: 'altitude' }),
  entry('altitude smoothing huge gap boundary', [sample(0, { altitudeMeters: 804 }), sample(1, { altitudeMeters: 804 }),
    sample(100003, { altitudeMeters: 805 }), sample(100004, { altitudeMeters: 805 })], [0, .5, 1, 50000, 100003, 100004], { operation: 'altitude' }),
  entry('GPX-style quantized altitude skips manufacturer smoothing', stairs.map((altitudeMeters, i) => sample(i, { altitudeMeters, trackSegmentIndex: 0 })), [0, 3, 3.5, 4, 8]),
  fitEntry('COROS FIT altitude enables display smoothing', altitudeFIT(294, stairs), [0, 1, 3, 3.5, 4, 8]),
  fitEntry('other FIT manufacturer keeps raw altitude', altitudeFIT(1, stairs), [0, 3, 3.5, 4, 8]),
  fitEntry('high precision COROS FIT keeps raw altitude', altitudeFIT(294, [804, 804.2, 804.4, 804.6, 804.8, 805]), [0, 1, 2, 4, 5]),
  fitEntry('FIT timer start before first record', [definition(1, 21, eventFields), data(1, eventFields, { 253: fitOrigin, 0: 0, 1: 0 }),
    definition(0, 20, recordFields), fitRecord(8, 40, 0), fitRecord(10, 50, 0)], [0, 1, 4, 8, 9, 10]),
  fitEntry('FIT pause event wall-clock boundary', [definition(1, 21, eventFields), definition(0, 20, recordFields),
    data(1, eventFields, { 253: fitOrigin, 0: 0, 1: 0 }), fitRecord(0, 0, 3), fitRecord(2, 6, 3),
    data(1, eventFields, { 253: fitOrigin + 2, 0: 0, 1: 4 }), data(1, eventFields, { 253: fitOrigin + 7, 0: 0, 1: 0 }),
    fitRecord(7, 6, 3), fitRecord(10, 15, 3)], [0, 2, 2.01, 5, 6.99, 7, 8, 10]),
  fitEntry('FIT lap anchor standstill merges fractional time', [definition(0, 20, recordFields), definition(1, 19, summaryFields), definition(2, 18, summaryFields),
    ...seconds(30, i => fitRecord(i, Math.min(i, 20) * 5, i <= 20 ? 5 : 0, i <= 20 ? 90 : 0)),
    summary(1, 25.05, 100.61), summary(2, 30, 100.61)], [20, 21, 24.9, 25, 25.05, 26, 30]),
  fitEntry('FIT final sample tiny duration guards spike', [definition(0, 20, recordFields), definition(2, 18, summaryFields),
    fitRecord(0, 0, 4.5), fitRecord(25, 112, 4.5), fitRecord(26, 116, 4.5), summary(2, 26.01, 118)], [24, 25, 26, 26.005, 26.01]),
  fitEntry('FIT lap beyond session distance rejected', [definition(0, 20, recordFields), definition(1, 19, summaryFields), definition(2, 18, summaryFields),
    fitRecord(0, 0, 4), fitRecord(25, 100, 4), fitRecord(26, 104, 4), summary(1, 26, 110), summary(2, 26.5, 105)], [25, 26, 26.25, 26.5]),
  ...[1, 2, undefined].map(sport => {
    const fields = [field(5, 1, 0)];
    const chunks = sport === undefined ? [] : [definition(2, 18, fields), data(2, fields, { 5: sport })];
    return fitEntry(`FIT deceleration sport gate ${sport ?? 'missing'}`, [...chunks, definition(0, 20, recordFields),
      ...deceleration().map(s => fitRecord(s.elapsed, s.distanceMeters, s.speedMetersPerSecond))], [29, 30, 32, 34, 36, 45, 60]);
  }),
  ...[1, 2].map(sport => {
    const sportField = [field(5, 1, 0)], cadenceFields = [timestamp, field(4, 1, 2), field(53, 1, 2), field(13, 1, 1)];
    return fitEntry(`FIT fractional cadence rounds for sport ${sport}`, [definition(1, 18, sportField), data(1, sportField, { 5: sport }),
      definition(0, 20, cadenceFields), data(0, cadenceFields, { 253: fitOrigin, 4: 80, 53: 64, 13: -12 }),
      data(0, cadenceFields, { 253: fitOrigin + 1, 4: 81, 53: 127, 13: -11 })], [0, .49, .5, 1]);
  }),
];

export const nativeDisplayInputs = [
  entry('display metric rounding and long elapsed', [sample(3661.99, { speedMetersPerSecond: 1000 / 359.5,
    distanceMeters: 12345.55, heartRate: 150, cadence: 180, totalCalories: 12.5,
    weatherTemperatureCelsius: -12, temperatureCelsius: 8, altitudeMeters: -5.125, totalAscentMeters: 123.5 })], [3661.99]),
  entry('display missing fields and pace threshold placeholders', [sample(0, { date: undefined, speedMetersPerSecond: .3 })], [0]),
  entry('display activity temperature fallback', [sample(0, { temperatureCelsius: -11 })], [0]),
];
