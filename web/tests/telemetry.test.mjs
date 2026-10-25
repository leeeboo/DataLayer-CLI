import test from 'node:test';
import assert from 'node:assert/strict';
import { TelemetryError, parseFIT, parseGPX, parseTelemetryFile, previewAt } from '../telemetry.mjs';
import { createNativeSeries } from '../telemetry-series.mjs';

const epoch = Date.UTC(1989, 11, 31);
const origin = 1100000000;
const field = (number, size = 4, type = 0x86) => ({ number, size, type });
const timestamp = field(253);
const hr = field(3, 1, 2), distance = field(5), speed = field(6, 2, 0x84), cadence = field(4, 1, 2);
const close = (actual, expected, epsilon = 1e-6) => assert.ok(Math.abs(actual - expected) < epsilon, `${actual} != ${expected}`);
const rejects = (operation, code) => assert.throws(operation, error => error instanceof TelemetryError && error.code === code);

function crc(bytes) {
  const table = [0, 0xcc01, 0xd801, 0x1400, 0xf001, 0x3c00, 0x2800, 0xe401, 0xa001, 0x6c00, 0x7800, 0xb401, 0x5000, 0x9c01, 0x8801, 0x4400];
  let value = 0;
  for (const byte of bytes) {
    value = (value >>> 4) ^ table[value & 15] ^ table[byte & 15];
    value = (value >>> 4) ^ table[value & 15] ^ table[byte >>> 4];
  }
  return value;
}
function definition(local, global, fields, little = true, developer = []) {
  const bytes = [0x40 | local | (developer.length ? 0x20 : 0), 0, little ? 0 : 1, little ? global & 255 : global >>> 8, little ? global >>> 8 : global & 255, fields.length];
  for (const f of fields) bytes.push(f.number, f.size, f.type);
  if (developer.length) { bytes.push(developer.length); for (const f of developer) bytes.push(f.number, f.size, f.index); }
  return Buffer.from(bytes);
}
function data(local, fields, values, little = true, { compressed, developer = [] } = {}) {
  const parts = [Buffer.from([compressed === undefined ? local : 0x80 | local << 5 | compressed & 31])];
  for (const f of fields) {
    if (compressed !== undefined && f.number === 253) continue;
    const value = values[f.number], bytes = Buffer.alloc(f.size, 255);
    if (Buffer.isBuffer(value)) value.copy(bytes);
    else if (typeof value === 'string') { bytes.fill(0); bytes.write(value); }
    else if (value !== undefined) {
      const type = f.type & 31;
      if (type === 8) little ? bytes.writeFloatLE(value) : bytes.writeFloatBE(value);
      else if (type === 9) little ? bytes.writeDoubleLE(value) : bytes.writeDoubleBE(value);
      else {
        let integer = BigInt(value);
        if (integer < 0) integer += 1n << BigInt(f.size * 8);
        for (let i = 0; i < f.size; i++) { bytes[little ? i : f.size - 1 - i] = Number(integer & 255n); integer >>= 8n; }
      }
    }
    parts.push(bytes);
  }
  return Buffer.concat([...parts, ...developer]);
}
function fit(chunks, { headerSize = 14, zeroHeaderCRC = false } = {}) {
  const payload = Buffer.concat(chunks), header = Buffer.alloc(headerSize);
  header[0] = headerSize; header[1] = 0x20; header.writeUInt16LE(21000, 2); header.writeUInt32LE(payload.length, 4); header.write('.FIT', 8);
  if (headerSize >= 14 && !zeroHeaderCRC) header.writeUInt16LE(crc(header.subarray(0, headerSize - 2)), headerSize - 2);
  const body = Buffer.concat([header, payload]), tail = Buffer.alloc(2); tail.writeUInt16LE(crc(body));
  return Buffer.concat([body, tail]);
}
function records(values, fields = [timestamp, hr, distance, speed, cadence]) {
  return fit([definition(0, 20, fields), ...values.map((v, i) => data(0, fields, { 253: origin + i, ...v }))]);
}

test('FIT maps standard and enhanced metrics, normalizes distance and never invents weather', () => {
  const fields = [timestamp, hr, cadence, distance, speed, field(0, 4, 0x85), field(1, 4, 0x85), field(2, 2, 0x84), field(73), field(78),
    field(13, 1, 1), field(39, 2, 0x84), field(40, 2, 0x84), field(41, 2, 0x84), field(83, 2, 0x84), field(84, 2, 0x84), field(85, 2, 0x84), field(108, 2, 0x84), field(147, 2, 0x84)];
  const activity = parseFIT(records([{ 3: 140, 4: 88, 5: 10000, 6: 2000, 0: 0, 1: 0, 2: 3000, 73: 4000, 78: 3500,
    13: -5, 39: 820, 40: 4200, 41: 2380, 83: 660, 84: 5000, 85: 12000, 108: 3200, 147: 380 },
  { 3: 142, 4: 90, 5: 10400, 6: 4100, 78: 3510 }], fields));
  assert.equal(activity.duration, 1);
  assert.equal(activity.startDate, new Date(epoch + origin * 1000).toISOString());
  assert.equal(activity.totalDistanceMeters, 4);
  const s = activity.samples[0];
  for (const [key, value] of Object.entries({ heartRate: 140, cadence: 176, distanceMeters: 0, speedMetersPerSecond: 4,
    altitudeMeters: 200, latitude: 0, longitude: 0, temperatureCelsius: -5, verticalOscillationCentimeters: 8.2,
    groundContactTimePercent: 42, groundContactTimeMilliseconds: 238, verticalRatioPercent: 6.6,
    groundContactTimeBalancePercent: 50, stepLengthMeters: 1.2, respirationRateBreathsPerMinute: 32, stepSpeedLossPercent: 3.8 })) close(s[key], value);
  assert.equal(s.weatherHumidityPercent, undefined);
  assert.equal(s.weatherSummary, undefined);
  assert.equal(s.weatherTemperatureCelsius, undefined);
  assert.equal(activity.samples[1].totalAscentMeters, 2);
});

test('FIT big endian signed values, fractional cycling cadence and invalid sentinels', () => {
  const fields = [timestamp, hr, cadence, field(53, 1, 2), field(0, 4, 0x85), field(13, 1, 1), field(73), field(39, 4, 0x88), field(7, 2, 0x84)];
  const session = [field(5, 1, 0)];
  const bytes = fit([definition(2, 18, session, false), data(2, session, { 5: 2 }, false), definition(0, 20, fields, false),
    data(0, fields, { 253: origin, 4: 80, 53: 64, 0: -1073741824, 13: -12, 73: 18000, 39: Infinity, 7: 65535 }, false)]);
  const s = parseFIT(bytes).samples[0];
  assert.equal(s.cadence, 81);
  assert.equal(s.latitude, -90);
  assert.equal(s.temperatureCelsius, -12);
  assert.equal(s.speedMetersPerSecond, 18);
  assert.equal(s.heartRate, undefined);
  assert.equal(s.powerWatts, undefined);
  assert.equal(s.verticalOscillationCentimeters, undefined);
  assert.equal(s.distanceMeters, 0);
});

test('FIT compressed timestamps omit timestamp bytes and handle rollover and redefinition', () => {
  const fields = [timestamp, hr];
  const bytes = fit([definition(0, 20, fields), data(0, fields, { 253: origin + 30, 3: 130 }),
    data(0, fields, { 3: 131 }, true, { compressed: 31 }), data(0, fields, { 3: 132 }, true, { compressed: 1 }),
    definition(1, 20, [hr]), data(1, [hr], { 3: 133 }, true, { compressed: 2 })]);
  const activity = parseFIT(bytes);
  assert.deepEqual(activity.samples.map(p => p.wallElapsed), [0, 1, 2, 3, 4]);
  assert.deepEqual(activity.samples.map(p => p.heartRate), [130, 131, 132, 132, 133]);
  rejects(() => parseFIT(fit([definition(0, 20, fields), data(0, fields, { 3: 140 }, true, { compressed: 1 })])), 'invalidFIT');
});

test('FIT compressed speed/distance and distance accumulator rollover', () => {
  const packed = (speed, dist) => Buffer.from([speed & 255, (speed >>> 8) | (dist & 15) << 4, dist >>> 4]);
  const fields = [timestamp, field(8, 3, 13)];
  const activity = parseFIT(records([{ 8: packed(400, 4080) }, { 8: packed(420, 16) }], fields));
  close(activity.totalDistanceMeters, 2);
  close(activity.samples[1].speedMetersPerSecond, 4.2);
});

test('FIT activity timezone controls clock/calendar while date stays UTC, including midnight and pause', () => {
  const fields = [timestamp, hr], timezone = [timestamp, field(5)];
  const utc = Math.floor((Date.UTC(2026, 0, 1, 23, 59, 58) - epoch) / 1000);
  const bytes = fit([definition(0, 20, fields), data(0, fields, { 253: utc, 3: 100 }), data(0, fields, { 253: utc + 10, 3: 120 }),
    definition(1, 34, timezone), data(1, timezone, { 253: utc + 10, 5: utc + 10 + 9 * 3600 })]);
  const activity = parseFIT(bytes), s = previewAt(activity, 3).sample;
  assert.equal(activity.timeZoneOffsetSeconds, 9 * 3600);
  assert.equal(s.date, Date.UTC(2026, 0, 2, 0, 0, 1) / 1000);
  assert.equal(s.clock, '09:00:01');
  assert.equal(s.calendar, '2026/01/02');
  const settings = [field(0, 1, 2), field(5, 2, 1)];
  const device = parseFIT(fit([definition(2, 2, settings), data(2, settings, { 0: 1, 5: Buffer.from([0, 0xec]) }),
    definition(0, 20, fields), data(0, fields, { 253: utc, 3: 100 })]));
  assert.equal(device.timeZoneOffsetSeconds, -5 * 3600);
  assert.equal(device.samples[0].clock, '18:59:58');
  const invalid = parseFIT(fit([definition(0, 20, fields), data(0, fields, { 253: utc, 3: 100 }), definition(1, 34, timezone),
    data(1, timezone, { 253: utc, 5: utc + 100000 })]));
  assert.equal(invalid.timeZoneOffsetSeconds, undefined);
});

test('FIT skips unknown developer bytes and reads native-supported named running fields', () => {
  const description = [field(0, 1, 2), field(1, 1, 2), field(2, 1, 2), field(3, 20, 7), field(6, 1, 2), field(7, 1, 1)];
  const fields = [timestamp, hr], developer = [{ number: 1, size: 2, index: 0 }, { number: 99, size: 7, index: 1 }];
  const bytes = fit([definition(1, 206, description), data(1, description, { 0: 0, 1: 1, 2: 0x84, 3: 'Form Power', 6: 2, 7: 1 }),
    definition(0, 20, fields, true, developer), data(0, fields, { 253: origin, 3: 120 }, true, { developer: [Buffer.from([146, 0]), Buffer.alloc(7)] }),
    data(0, fields, { 253: origin + 1, 3: 121 }, true, { developer: [Buffer.from([150, 0]), Buffer.alloc(7)] })]);
  const activity = parseFIT(bytes);
  assert.equal(activity.samples[0].formPowerWatts, 72);
  assert.equal(activity.samples[1].formPowerWatts, 74);
  assert.equal(activity.samples[1].heartRate, 121);
});

function pausedActivity() {
  const fields = [timestamp, hr, distance, speed, cadence, field(2, 2, 0x84)];
  const event = [timestamp, field(0, 1, 0), field(1, 1, 0)];
  const chunks = [definition(0, 20, fields), ...[
    { 253: origin, 3: 100, 4: 80, 5: 0, 6: 3000, 2: 3000 },
    { 253: origin + 4, 3: 110, 4: 82, 5: 1200, 6: 3100, 2: 3010 },
    { 253: origin + 10, 3: 200, 4: 120, 5: 5000, 6: 10000, 2: 3500 },
    { 253: origin + 16, 3: 120, 4: 84, 5: 1800, 6: 3200, 2: 3020 },
    { 253: origin + 20, 3: 130, 4: 86, 5: 3000, 6: 3300, 2: 3030 },
  ].map(v => data(0, fields, v)), definition(1, 21, event),
  ...[[0, 0], [5, 1], [5, 4], [15, 0], [20, 4]].map(([t, type]) => data(1, event, { 253: origin + t, 0: 0, 1: type }))];
  return parseFIT(fit(chunks));
}

test('FIT pause holds every motion metric while UTC date advances and active time freezes', () => {
  const activity = pausedActivity();
  assert.equal(activity.duration, 20);
  assert.equal(activity.samples.at(-1).elapsed, 10);
  assert.equal(activity.pausedRanges.length, 1);
  const early = previewAt(activity, 6), late = previewAt(activity, 14);
  assert.equal(early.sample.elapsed, 5);
  assert.equal(late.sample.elapsed, 5);
  for (const key of ['heartRate', 'cadence', 'distanceMeters', 'speedMetersPerSecond', 'altitudeMeters', 'totalAscentMeters']) assert.equal(early.sample[key], late.sample[key]);
  assert.equal(late.sample.heartRate, 200);
  assert.equal(late.sample.date, early.sample.date);
  assert.equal(late.absoluteDate - early.absoluteDate, 8);
  assert.equal(late.absoluteDate, epoch / 1000 + origin + 14);
  assert.equal(previewAt(activity, 16).sample.elapsed, 6);
  assert.equal(early.series, activity);
});

test('FIT calories are assigned before native resampling and freeze across a pause', () => {
  const base = pausedActivity(), fields = [timestamp, hr], event = [timestamp, field(0, 1, 0), field(1, 1, 0)];
  const lap = [timestamp, field(2), field(8), field(11, 2, 0x84)];
  const bytes = fit([definition(0, 20, fields), data(0, fields, { 253: origin, 3: 100 }), data(0, fields, { 253: origin + 20, 3: 120 }),
    definition(1, 21, event), data(1, event, { 253: origin, 0: 0, 1: 0 }), data(1, event, { 253: origin + 5, 0: 0, 1: 1 }), data(1, event, { 253: origin + 15, 0: 0, 1: 0 }),
    definition(2, 19, lap), data(2, lap, { 253: origin + 5, 2: origin, 8: 5000, 11: 10 }), data(2, lap, { 253: origin + 20, 2: origin + 15, 8: 5000, 11: 20 })]);
  const activity = parseFIT(bytes);
  assert.equal(base.duration, activity.duration);
  assert.equal(activity.samples.at(-1).totalCalories, 30);
  // Sparse source records interpolate their assigned calories during native resampling.
  assert.equal(previewAt(activity, 10).sample.totalCalories, 15);
  assert.equal(previewAt(activity, 17.5).sample.totalCalories, 22.5);
});

test('FIT retains native source-order origin and duplicate resampling rules', () => {
  const fields = [timestamp, hr, distance, speed];
  const activity = parseFIT(records([{ 253: origin + 2, 3: 140, 5: 10200 }, { 253: origin, 3: 130, 5: 10000 },
    { 253: origin + 2, 6: 4000 }, { 253: origin + 3, 3: 142, 5: 10100 }], fields));
  assert.deepEqual(activity.samples.map(p => p.wallElapsed), [0, 1]);
  assert.equal(activity.samples[0].heartRate, 130);
  assert.equal(activity.samples[1].heartRate, 142);
  assert.equal(activity.samples[1].speedMetersPerSecond, 2);
  assert.equal(activity.totalDistanceMeters, 2);
});

test('preview uses native optional-field interpolation, nearest and cadence rules', () => {
  const fields = [timestamp, hr, distance, speed, cadence, field(7, 2, 0x84)];
  const activity = parseFIT(records([{ 3: 100, 4: 80, 5: 0, 6: 2000, 7: 200 }, { 3: 120, 4: 90, 5: 400, 6: 4000 }, { 3: 130, 4: 0, 5: 800, 6: 0 }], fields));
  const s = previewAt(activity, .6).sample;
  close(s.speedMetersPerSecond, 3.2);
  close(s.distanceMeters, 2.4);
  assert.equal(s.heartRate, 120);
  assert.equal(s.cadence, 180);
  assert.equal(s.powerWatts, 200);
  assert.equal(previewAt(activity, 1.5).sample.cadence, 90);
  assert.equal(previewAt(activity, -5).inRange, false);
  assert.equal(previewAt(activity, 100).inRange, false);
  assert.equal(previewAt(activity, 100).sample.wallElapsed, 2);
  assert.equal(previewAt(activity, 2).inRange, true);
  rejects(() => previewAt(activity, NaN), 'invalidTime');
});

test('segment break holds metrics and GPS position instead of interpolating a route jump', () => {
  const activity = createNativeSeries([{ elapsed: 0, trackSegmentIndex: 0, latitude: 0, longitude: 0, heartRate: 100 },
      { elapsed: 10, trackSegmentIndex: 1, latitude: 1, longitude: 1, heartRate: 150 }]);
  const middle = previewAt(activity, 5).sample;
  assert.equal(middle.latitude, 0);
  assert.equal(middle.longitude, 0);
  assert.equal(middle.heartRate, 100);
  assert.equal(middle.elapsed, 5);
  assert.equal(previewAt(activity, 10).sample.latitude, 1);
});

test('12-byte FIT headers, optional zero header CRC, Uint8Array offsets and ArrayBuffer inputs work', () => {
  const chunks = [definition(0, 20, [timestamp, hr]), data(0, [timestamp, hr], { 253: origin, 3: 100 })];
  for (const options of [{ headerSize: 12 }, { zeroHeaderCRC: true }, { headerSize: 16 }]) {
    const bytes = fit(chunks, options), padded = Buffer.concat([Buffer.alloc(7), bytes, Buffer.alloc(7)]);
    assert.equal(parseFIT(new Uint8Array(padded.buffer, padded.byteOffset + 7, bytes.length)).samples.length, 1);
    assert.equal(parseFIT(Uint8Array.from(bytes).buffer).samples.length, 1);
  }
});

test('FIT rejects invalid headers, CRC, truncation, undefined messages and missing timestamps', () => {
  const valid = records([{ 3: 100 }]);
  for (const [offset, code] of [[0, 'truncatedFIT'], [8, 'invalidFIT'], [12, 'crcMismatch'], [valid.length - 1, 'crcMismatch']]) {
    const bytes = Buffer.from(valid); bytes[offset] ^= 1; rejects(() => parseFIT(bytes), code);
  }
  rejects(() => parseFIT(valid.subarray(0, 10)), 'truncatedFIT');
  rejects(() => parseFIT(valid.subarray(0, -1)), 'truncatedFIT');
  rejects(() => parseFIT(Buffer.concat([valid, valid])), 'invalidFIT');
  rejects(() => parseFIT(fit([Buffer.from([0])])), 'invalidFIT');
  rejects(() => parseFIT(fit([definition(0, 20, [timestamp]), Buffer.from([0, 1])])), 'truncatedFIT');
  rejects(() => parseFIT(fit([definition(0, 20, [hr]), data(0, [hr], { 3: 100 })])), 'missingTime');
  rejects(() => parseFIT(fit([definition(0, 20, [timestamp]), data(0, [timestamp], {})])), 'missingTime');
  rejects(() => parseFIT(fit([])), 'noSamples');
});

test('binary and XML limits are enforced before reading content or invoking DOMParser', async () => {
  rejects(() => parseFIT(new Uint8Array(50 * 1024 * 1024 + 1)), 'fileTooLarge');
  rejects(() => parseGPX(' '.repeat(50 * 1024 * 1024 + 1)), 'fileTooLarge');
  for (const xml of ['<!DOCTYPE gpx><gpx/>', '<!ENTITY secret SYSTEM "file:///private"><gpx/>']) rejects(() => parseGPX(xml), 'invalidGPX');
  await assert.rejects(parseTelemetryFile({ name: 'activity.fit', size: 50 * 1024 * 1024 + 1, arrayBuffer() { assert.fail('must not read oversized file'); } }), { code: 'fileTooLarge' });
  const fields = [timestamp];
  const chunk = data(0, fields, { 253: origin });
  const many = fit([definition(0, 20, fields), Buffer.concat(Array(200001).fill(chunk))]);
  rejects(() => parseFIT(many), 'tooManySamples');
});

test('file entry point reads only recognized local files and reports read/encoding errors', async () => {
  const bytes = Uint8Array.from(records([{ 3: 100 }]));
  const activity = await parseTelemetryFile({ name: 'activity.FIT', size: bytes.length, async arrayBuffer() { return bytes.buffer; } });
  assert.equal(activity.samples[0].heartRate, 100);
  await assert.rejects(parseTelemetryFile({ name: 'activity.csv', size: 1 }), { code: 'unsupportedFormat' });
  await assert.rejects(parseTelemetryFile({ name: 'activity.fit', size: 1, async arrayBuffer() { throw Error('private local path'); } }), { code: 'readFailed', message: 'readFailed' });
  await assert.rejects(parseTelemetryFile({ name: 'activity.gpx', size: 1, async arrayBuffer() { return new Uint8Array([255]).buffer; } }), { code: 'invalidGPX' });
});

const summaryFields = [timestamp, field(2), field(7), field(8), field(9), field(11, 2, 0x84)];
function summary(local, global, values) {
  return [definition(local, global, summaryFields), data(local, summaryFields, values)];
}

test('FIT timer start synthesizes the native startup sample and cadence ramp', () => {
  const fields = [timestamp, hr, distance, speed, cadence], event = [timestamp, field(0, 1, 0), field(1, 1, 0)];
  const activity = parseFIT(fit([definition(1, 21, event), data(1, event, { 253: origin, 0: 0, 1: 0 }), definition(0, 20, fields),
    data(0, fields, { 253: origin + 8, 3: 151, 4: 84, 5: 120000, 6: 3000 }),
    data(0, fields, { 253: origin + 10, 3: 154, 4: 86, 5: 120600, 6: 3400 })]));
  assert.equal(activity.duration, 10);
  assert.equal(activity.samples[0].cadence, 0);
  assert.equal(activity.samples[0].distanceMeters, 0);
  assert.equal(previewAt(activity, 4).sample.cadence, 84);
  assert.equal(previewAt(activity, 8).sample.cadence, 168);
  assert.equal(activity.samples[0].hasSyntheticDistance, false);
});

test('FIT fractional lap near a standstill sample merges distance without creating speed', () => {
  const fields = [timestamp, hr, distance, speed, cadence];
  const activity = parseFIT(fit([definition(0, 20, fields), ...Array.from({ length: 31 }, (_, t) => data(0, fields,
    { 253: origin + t, 3: 150, 4: t <= 20 ? 90 : 0, 5: Math.min(t, 20) * 500, 6: t <= 20 ? 5000 : 0 })),
    ...summary(1, 19, { 253: origin + 25, 2: origin, 7: 25050, 8: 25050, 9: 10061, 11: 20 }),
    ...summary(2, 18, { 253: origin + 30, 2: origin, 7: 30000, 8: 30000, 9: 10061, 11: 20 })]));
  assert.equal(activity.samples.length, 31);
  close(previewAt(activity, 26).sample.distanceMeters, 100.61);
  assert.equal(activity.samples.find(sample => sample.elapsed === 25).hasSyntheticDistance, true);
  for (const sample of activity.samples.filter(sample => sample.elapsed > 21)) assert.equal(sample.speedMetersPerSecond, 0);
});

test('FIT fractional lap remains authoritative when records still lag its distance', () => {
  const fields = [timestamp, hr, distance, speed, cadence];
  const activity = parseFIT(fit([definition(0, 20, fields), ...[[0, 0], [182, 99300], [183, 99750], [184, 100200]].map(([t, d]) =>
    data(0, fields, { 253: origin + t, 3: 150, 4: 80, 5: d, 6: 4500 })),
    ...summary(2, 19, { 253: origin + 183, 2: origin, 7: 182680, 8: 182680, 9: 100000, 11: 42 })]));
  const anchor = activity.samples.find(sample => Math.abs(sample.elapsed - 182.68) < 1e-6);
  assert.equal(anchor.hasSyntheticDistance, true);
  close(anchor.distanceMeters, 1000);
  close(previewAt(activity, 182.68).sample.distanceMeters, 1000);
});

test('FIT final session sample preserves fractional duration and rejects a subsecond speed spike', () => {
  const fields = [timestamp, hr, distance, speed, cadence];
  const activity = parseFIT(fit([definition(0, 20, fields), ...[[0, 0], [185, 100800], [186, 101200]].map(([t, d]) =>
    data(0, fields, { 253: origin + t, 3: 150, 4: 80, 5: d, 6: 4500 })),
    ...summary(2, 18, { 253: origin + 186, 2: origin, 7: 186010, 8: 186010, 9: 101400, 11: 44 })]));
  close(activity.duration, 186.01);
  const last = activity.samples.at(-1);
  assert.equal(last.hasSyntheticDistance, true);
  close(last.distanceMeters, 1014);
  close(last.speedMetersPerSecond, 4.5);
  close(last.date, epoch / 1000 + origin + 186.01);
  const after = previewAt(activity, 200);
  assert.equal(after.inRange, false);
  close(after.sample.distanceMeters, 1014);
  close(after.sample.date, last.date);
  assert.equal(after.absoluteDate, epoch / 1000 + origin + 200);
});

test('FIT ignores a lap cumulative distance beyond the session total', () => {
  const fields = [timestamp, hr, distance, speed];
  const activity = parseFIT(fit([definition(0, 20, fields), ...[[0, 0], [100, 40000], [101, 40400]].map(([t, d]) =>
    data(0, fields, { 253: origin + t, 3: 150, 5: d, 6: 4000 })),
    ...summary(1, 19, { 253: origin + 101, 2: origin, 7: 101000, 8: 101000, 9: 41000, 11: 20 }),
    ...summary(2, 18, { 253: origin + 101, 2: origin, 7: 101500, 8: 101500, 9: 40500, 11: 20 })]));
  close(previewAt(activity, 101).sample.distanceMeters, 404);
  close(previewAt(activity, 101.5).sample.distanceMeters, 405);
});

test('FIT requires both packed speed and distance to be valid before accumulating', () => {
  const packed = (speed, distance) => Buffer.from([speed & 255, speed >>> 8 | (distance & 15) << 4, distance >>> 4]);
  const fields = [timestamp, field(8, 3, 13)];
  const activity = parseFIT(records([{ 8: packed(400, 16) }, { 8: packed(4095, 32) }, { 8: packed(420, 48) }], fields));
  close(activity.totalDistanceMeters, 2);
  assert.equal(activity.samples[1].speedMetersPerSecond, 2);
});


test('preview preserves fractional clock precision while endpoint metrics clamp', () => {
  const activity = parseFIT(records([{ 3: 100 }, { 3: 120 }], [timestamp, hr]));
  const frame = previewAt(activity, 182.68);
  assert.equal(frame.sample.heartRate, 120);
  close(frame.absoluteDate, epoch / 1000 + origin + 182.68);
  assert.equal(frame.sample.date, epoch / 1000 + origin + 1);
  assert.equal(frame.sample.elapsed, 1);
});


test('preview outside the JavaScript calendar range omits display time without losing native time', () => {
  const activity = parseFIT(records([{ 3: 100 }, { 3: 120 }], [timestamp, hr]));
  Object.assign(activity.nativeSeries.samples.at(-1), { clock: '00:00:01', calendar: '2026/01/01' });
  const frame = previewAt(activity, 1e100);
  assert.equal(frame.inRange, false);
  assert.equal(frame.sample.heartRate, 120);
  assert.equal(frame.sample.clock, undefined);
  assert.equal(frame.sample.calendar, undefined);
  assert.equal(frame.absoluteDate, 1e100);
  assert.ok(!JSON.stringify(frame.sample).includes('NaN'));
});
