import { createNativeSeries, sampleNativeSeries, dateNativeSeries, wallElapsed, correctingRunningDecelerations } from './telemetry-series.mjs?v=20261025-native-data';
import { applyingQuantizedAltitudeDisplaySmoothing } from './telemetry-altitude.mjs?v=20261025-native-data';

// Local-only parsing. FIT wire format: https://developer.garmin.com/fit/articles/fit-protocol/fit_protocol.html
const MAX_BYTES = 50 * 1024 * 1024;
const MAX_SAMPLES = 200000;
const FIT_EPOCH = Date.UTC(1989, 11, 31);
const finite = Number.isFinite;
export class TelemetryError extends Error {
  constructor(code) { super(code); this.name = 'TelemetryError'; this.code = code; }
}
const fail = code => { throw new TelemetryError(code); };
const checkCount = count => { if (count > MAX_SAMPLES) fail('tooManySamples'); };

export async function parseTelemetryFile(file) {
  const extension = String(file?.name ?? '').split('.').at(-1).toLowerCase();
  if (!['fit', 'gpx'].includes(extension)) fail('unsupportedFormat');
  if (!finite(file?.size) || file.size < 0) fail('readFailed');
  if (file.size > MAX_BYTES) fail('fileTooLarge');
  let bytes;
  try { bytes = await file.arrayBuffer(); } catch { fail('readFailed'); }
  if (bytes.byteLength > MAX_BYTES) fail('fileTooLarge');
  if (extension === 'fit') return parseFIT(bytes);
  let xml;
  try { xml = new TextDecoder('utf-8', { fatal: true }).decode(bytes); } catch { fail('invalidGPX'); }
  return parseGPX(xml);
}

function upperBound(values, time, key) {
  let lo = 0, hi = values.length;
  while (lo < hi) {
    const mid = (lo + hi) >>> 1;
    if (values[mid][key] <= time) lo = mid + 1; else hi = mid;
  }
  return lo;
}

const validOffset = value => finite(value) && Number.isInteger(value) && value >= -12 * 3600 && value <= 14 * 3600;
const rounded = value => value < 0 ? -Math.round(-value) : Math.round(value);
const exactInteger = (value, min = -9223372036854775808, max = 9223372036854774784) => Number.isInteger(value) && value >= min && value <= max ? value : undefined;
function calendarFields(date, offset) {
  if (!finite(date)) return {};
  const display = new Date((date + (offset ?? 0)) * 1000);
  if (!finite(display.getTime())) return {};
  const parts = offset === undefined ? [display.getFullYear(), display.getMonth() + 1, display.getDate(), display.getHours(), display.getMinutes(), display.getSeconds()]
    : [display.getUTCFullYear(), display.getUTCMonth() + 1, display.getUTCDate(), display.getUTCHours(), display.getUTCMinutes(), display.getUTCSeconds()];
  const [year, month, day, hour, minute, second] = parts.map(value => String(value).padStart(2, '0'));
  return { clock: `${hour}:${minute}:${second}`, calendar: `${year}/${month}/${day}` };
}

function finish(series, timeZoneOffsetSeconds, sport) {
  if (!series.samples.length) fail('noSamples');
  checkCount(series.samples.length);
  const samples = series.samples.map(sample => ({ ...sample, wallElapsed: wallElapsed(series, sample.elapsed), ...calendarFields(sample.date, timeZoneOffsetSeconds) }));
  return { ...series, samples, nativeSeries: series, startDate: finite(series.activityStartDate) ? new Date(series.activityStartDate * 1000).toISOString() : undefined,
    timeZoneOffsetSeconds, sport };
}

export function previewAt(activity, wall) {
  if (!finite(wall)) fail('invalidTime');
  if (!activity.samples?.length) fail('noSamples');
  const series = activity.nativeSeries ?? activity;
  const sample = { ...sampleNativeSeries(series, wall) };
  const date = dateNativeSeries(series, wall);
  sample.wallElapsed = Math.min(activity.duration, Math.max(0, wall));
  delete sample.clock;
  delete sample.calendar;
  Object.assign(sample, calendarFields(date, activity.timeZoneOffsetSeconds));
  return { sample, absoluteDate: date, series: activity, inRange: wall >= 0 && wall <= activity.duration };
}

export function parseGPX(xml) {
  if (typeof xml !== 'string') fail('invalidGPX');
  if (xml.length > MAX_BYTES || new TextEncoder().encode(xml).byteLength > MAX_BYTES) fail('fileTooLarge');
  if (/<!\s*(?:DOCTYPE|ENTITY)\b/i.test(xml)) fail('invalidGPX');
  if (typeof DOMParser === 'undefined') fail('invalidGPX');
  const document = new DOMParser().parseFromString(xml, 'application/xml');
  const all = Array.from(document.getElementsByTagName('*'));
  if (document.documentElement?.localName !== 'gpx' || all.some(e => e.localName === 'parsererror')) fail('invalidGPX');
  const points = all.filter(e => e.localName === 'trkpt');
  checkCount(points.length);
  if (!points.length) fail('noSamples');
  const typeText = all.find(e => e.localName === 'type' && !e.closest('trkpt'))?.textContent.toLowerCase() ?? '';
  const cycling = !/run|jog/.test(typeText) && /cycl|bik|ride/.test(typeText);
  const segments = new Map(all.filter(e => e.localName === 'trkseg').map((e, i) => [e, i]));
  const fields = { ele: 'altitudeMeters', hr: 'heartRate', heartrate: 'heartRate', heart_rate: 'heartRate', cad: 'cadence',
    cadence: 'cadence', distance: 'distanceMeters', dist: 'distanceMeters', speed: 'speedMetersPerSecond', power: 'powerWatts',
    watts: 'powerWatts', calories: 'totalCalories', calorie: 'totalCalories', steplength: 'stepLengthMeters', step_length: 'stepLengthMeters', atemp: 'temperatureCelsius', temp: 'temperatureCelsius', temperature: 'temperatureCelsius' };
  let previousElapsed, firstDate, timeZoneOffsetSeconds;
  const records = points.map(point => {
    const record = { hasSyntheticDistance: false };
    for (const [attribute, key] of [['lat', 'latitude'], ['lon', 'longitude']]) {
      const text = point.getAttribute(attribute);
      if (text !== null && text.trim() !== '' && finite(Number(text))) record[key] = Number(text);
    }
    let date;
    for (const node of point.getElementsByTagName('*')) {
      const name = node.localName.toLowerCase().replaceAll('-', '_'), text = node.textContent.trim();
      if (name === 'time' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)$/i.test(text)) {
        date = Date.parse(text) / 1000;
        const zone = text.match(/([+-])(\d\d):(\d\d)$/);
        const offset = zone ? (Number(zone[2]) * 3600 + Number(zone[3]) * 60) * (zone[1] === '-' ? -1 : 1) : 0;
        if ((!zone || Number(zone[3]) < 60) && validOffset(offset)) timeZoneOffsetSeconds ??= offset;
      }
      const key = fields[name];
      if (key && text !== '' && finite(Number(text))) record[key] = ['heartRate', 'cadence', 'powerWatts', 'temperatureCelsius'].includes(key) ? exactInteger(rounded(Number(text))) : Number(text);
    }
    if (!finite(date)) fail('missingTime');
    firstDate ??= date;
    const candidate = date - firstDate;
    record.elapsed = previousElapsed !== undefined && candidate <= previousElapsed ? previousElapsed + .001 : Math.max(0, candidate);
    previousElapsed = record.elapsed;
    record.date = date;
    let segment = point.parentElement;
    while (segment && segment.localName !== 'trkseg') segment = segment.parentElement;
    if (segments.has(segment)) record.trackSegmentIndex = segments.get(segment);
    if (finite(record.cadence)) record.cadence = record.cadence < 0 ? undefined : !cycling && record.cadence < 130 ? record.cadence * 2 : record.cadence;
    return record;
  });
  return finish(createNativeSeries(records), timeZoneOffsetSeconds, gpxSport(typeText));
}

function crc16(bytes) {
  let crc = 0;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = crc & 1 ? (crc >>> 1) ^ 0xa001 : crc >>> 1;
  }
  return crc;
}

const widths = [1, 1, 1, 2, 2, 4, 4, 1, 4, 8, 1, 2, 4, 1, 8, 8, 8];
function fitValue(view, position, field, little) {
  const type = field.type & 31, width = widths[type];
  if (!width || field.size < width) return undefined;
  if (type === 7) {
    const bytes = new Uint8Array(view.buffer, view.byteOffset + position, field.size);
    const end = bytes.indexOf(0);
    return new TextDecoder().decode(end < 0 ? bytes : bytes.subarray(0, end));
  }
  let raw = 0n;
  for (let i = 0; i < width; i++) raw = raw << 8n | BigInt(view.getUint8(position + (little ? width - 1 - i : i)));
  const signed = [1, 3, 5, 14].includes(type), zeroInvalid = [10, 11, 12, 16].includes(type);
  const invalid = zeroInvalid ? 0n : (1n << BigInt(width * 8 - (signed ? 1 : 0))) - 1n;
  if (raw === invalid) return undefined;
  let value;
  if (type === 8) value = view.getFloat32(position, little);
  else if (type === 9) value = view.getFloat64(position, little);
  else {
    if (signed && raw & 1n << BigInt(width * 8 - 1)) raw -= 1n << BigInt(width * 8);
    value = Number(raw);
  }
  return finite(value) ? value : undefined;
}

const recordFields = { 0: ['latitude', 2147483648 / 180], 1: ['longitude', 2147483648 / 180], 2: ['altitudeMeters', 5, 500],
  3: ['heartRate', 1], 4: ['cadence', 1], 5: ['distanceMeters', 100], 6: ['speedMetersPerSecond', 1000], 7: ['powerWatts', 1],
  13: ['temperatureCelsius', 1], 39: ['verticalOscillationCentimeters', 100], 40: ['groundContactTimePercent', 100],
  41: ['groundContactTimeMilliseconds', 10], 83: ['verticalRatioPercent', 100], 84: ['groundContactTimeBalancePercent', 100],
  85: ['stepLengthMeters', 10000], 108: ['respirationRateBreathsPerMinute', 100], 147: ['stepSpeedLossPercent', 100] };

function fitSport(code) {
  if (code === undefined) return undefined;
  return ({ 1: 'running', 2: 'cycling', 4: 'training', 10: 'training', 5: 'swimming', 11: 'walking', 12: 'skiing', 13: 'skiing', 14: 'snowboarding', 15: 'rowing', 16: 'hiking', 17: 'hiking', 19: 'paddling' })[code] ?? 'generic';
}
function gpxSport(text) {
  if (!text) return undefined;
  for (const [pattern, sport] of [[/run|jog/, 'running'], [/cycl|bik|ride/, 'cycling'], [/swim/, 'swimming'], [/hik|mountain/, 'hiking'], [/walk/, 'walking'], [/row/, 'rowing'], [/snowboard/, 'snowboarding'], [/ski/, 'skiing'], [/paddle|kayak|canoe/, 'paddling']]) if (pattern.test(text)) return sport;
  return 'generic';
}

function timerTimeline(events, start) {
  const sorted = events.filter(e => finite(e.timestamp) && (e.type === 0 || [1, 4, 8, 9].includes(e.type))).sort((a, b) => a.timestamp - b.timestamp);
  const hasStart = sorted.some(e => e.type === 0), checkpoints = [], pauses = [];
  let elapsed = 0, runningSince, pauseStart;
  for (const event of sorted) {
    const timestamp = Math.max(event.timestamp, start);
    if (event.type === 0) {
      runningSince ??= timestamp;
      if (pauseStart !== undefined && event.timestamp > pauseStart) pauses.push({ start: pauseStart - start, duration: event.timestamp - pauseStart });
      pauseStart = undefined;
    } else {
      if (runningSince !== undefined) { elapsed += Math.max(0, timestamp - runningSince); runningSince = undefined; }
      pauseStart ??= timestamp;
    }
    checkpoints.push({ timestamp, elapsed, runningSince });
  }
  return { pauses, at(timestamp) {
    if (!hasStart) return Math.max(0, timestamp - start);
    const checkpoint = checkpoints[upperBound(checkpoints, timestamp, 'timestamp') - 1];
    return checkpoint ? Math.max(0, checkpoint.elapsed + (checkpoint.runningSince === undefined ? 0 : Math.max(0, timestamp - checkpoint.runningSince))) : 0;
  } };
}
function summaryEnd(summary, start, timeline, isSession = false) {
  const duration = summary.timer ?? summary.elapsed;
  if (summary.start !== undefined && duration !== undefined) return timeline.at(summary.start) + duration;
  if (summary.timestamp === undefined || (isSession ? summary.timestamp <= start : summary.timestamp < start)) return undefined;
  return timeline.at(summary.timestamp);
}
function caloriePoints(laps, sessions, records, start, timeline) {
  const points = [{ elapsed: 0, calories: 0 }];
  let cumulative = 0;
  for (const lap of [...laps].sort((a, b) => (a.timestamp ?? 0) - (b.timestamp ?? 0))) {
    const elapsed = summaryEnd(lap, start, timeline);
    if (elapsed === undefined || lap.calories === undefined || lap.calories < 0) continue;
    cumulative += lap.calories;
    if (elapsed < 0) continue;
    const point = { elapsed, calories: cumulative };
    if (Math.abs(points.at(-1).elapsed - elapsed) < .000001) points[points.length - 1] = point;
    else points.push(point);
  }
  if (points.length > 1) return points;
  const total = sessions.filter(s => s.calories !== undefined).at(-1)?.calories;
  if (!(total > 0)) return [];
  const ends = sessions.map(s => summaryEnd(s, start, timeline, true)).filter(v => v !== undefined);
  const end = ends.length ? ends.reduce((max, value) => Math.max(max, value), -Infinity) : timeline.at(records.reduce((max, r) => Math.max(max, r.timestamp ?? -Infinity), -Infinity));
  return end > 0 ? [{ elapsed: 0, calories: 0 }, { elapsed: end, calories: total }] : [];
}
function caloriesAt(points, elapsed) {
  if (points.length < 2) return undefined;
  if (elapsed <= points[0].elapsed) return points[0].calories;
  if (elapsed >= points.at(-1).elapsed) return points.at(-1).calories;
  let low = 0, high = points.length - 1;
  while (low + 1 < high) { const mid = (low + high) >>> 1; if (points[mid].elapsed <= elapsed) low = mid; else high = mid; }
  const a = points[low], b = points[high], fraction = Math.min(1, Math.max(0, (elapsed - a.elapsed) / Math.max(b.elapsed - a.elapsed, .000001)));
  return a.calories + (b.calories - a.calories) * fraction;
}
function authoritativeLaps(laps, sessions, series, start, timeline) {
  const ends = sessions.map(s => summaryEnd(s, start, timeline, true)).filter(v => v !== undefined);
  const sessionEnd = ends.length ? ends.reduce((max, value) => Math.max(max, value), -Infinity) : undefined;
  const distances = sessions.map(s => s.distance).filter(finite), sessionDistance = distances.length ? distances.reduce((max, value) => Math.max(max, value), -Infinity) : undefined;
  const anchors = [];
  let cumulative = 0, previous = 0;
  for (const lap of [...laps].sort((a, b) => (a.start ?? a.timestamp ?? 0) - (b.start ?? b.timestamp ?? 0))) {
    const duration = lap.timer ?? lap.elapsed;
    if (!finite(lap.distance) || lap.distance <= 0 || !finite(duration) || duration <= 0) continue;
    cumulative += lap.distance;
    if (sessionDistance !== undefined && cumulative > sessionDistance + .01) continue;
    let anchorElapsed;
    if (lap.start !== undefined) anchorElapsed = timeline.at(lap.start) + duration;
    else if (lap.timestamp !== undefined) anchorElapsed = timeline.at(lap.timestamp);
    else continue;
    if (lap.timestamp !== undefined) {
      const timestampElapsed = timeline.at(lap.timestamp), distance = sampleNativeSeries(series, timestampElapsed).distanceMeters;
      if (finite(timestampElapsed) && timestampElapsed > 0 && Math.abs(timestampElapsed - anchorElapsed) > .0005 && distance !== undefined && Math.abs(distance - cumulative) <= .01) anchorElapsed = timestampElapsed;
    }
    if (!finite(anchorElapsed) || anchorElapsed <= 0 || cumulative <= previous + .001 || sessionEnd !== undefined && anchorElapsed > sessionEnd + .001) continue;
    const anchor = { ...sampleNativeSeries(series, anchorElapsed) };
    if (anchor.distanceMeters === undefined || Math.abs(anchor.distanceMeters - cumulative) > 25) continue;
    Object.assign(anchor, { elapsed: anchorElapsed, distanceMeters: cumulative, hasSyntheticDistance: true });
    const date = dateNativeSeries(series, anchorElapsed);
    if (date !== undefined) anchor.date = date;
    anchors.push(anchor); previous = cumulative;
  }
  return anchors;
}
function authoritativeFinal(sessions, series, start, timeline) {
  if (start === undefined) return undefined;
  let authoritative;
  for (const session of sessions) {
    const elapsed = summaryEnd(session, start, timeline, true), distance = session.distance;
    if (!finite(elapsed) || !finite(distance) || distance < 0) continue;
    if (!authoritative || elapsed > authoritative.elapsed) authoritative = { elapsed, distance, timestamp: session.timestamp };
  }
  if (!authoritative) return undefined;
  const duration = series.duration, current = sampleNativeSeries(series, duration), distance = current.distanceMeters;
  if (!(authoritative.elapsed > duration + .0005 || authoritative.distance > (distance ?? 0) + .01)) return undefined;
  const final = { ...current, elapsed: Math.max(authoritative.elapsed, duration), hasSyntheticDistance: true, distanceMeters: Math.max(authoritative.distance, distance ?? 0) };
  final.date = dateNativeSeries(series, final.elapsed) ?? (authoritative.timestamp === undefined ? final.date : FIT_EPOCH / 1000 + authoritative.timestamp);
  if (distance !== undefined && final.elapsed > duration && final.distanceMeters >= distance) {
    const delta = final.elapsed - duration, speed = (final.distanceMeters - distance) / delta;
    if (delta >= 1 && finite(speed) && speed >= 0 && speed <= 12) final.speedMetersPerSecond = speed;
  }
  return final;
}

export function parseFIT(input) {
  const bytes = input instanceof Uint8Array ? input : input instanceof ArrayBuffer ? new Uint8Array(input) : fail('invalidFIT');
  if (bytes.byteLength > MAX_BYTES) fail('fileTooLarge');
  if (bytes.length < 14) fail('truncatedFIT');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength), headerSize = bytes[0];
  if (headerSize < 12 || headerSize === 13 || (bytes[1] >>> 4) > 2 || String.fromCharCode(...bytes.subarray(8, 12)) !== '.FIT') fail('invalidFIT');
  const end = headerSize + view.getUint32(4, true);
  if (end + 2 > bytes.length) fail('truncatedFIT');
  if (end + 2 !== bytes.length) fail('invalidFIT');
  if (headerSize >= 14) {
    const expected = view.getUint16(headerSize - 2, true);
    if (expected !== 0 && expected !== crc16(bytes.subarray(0, headerSize - 2))) fail('crcMismatch');
  }
  if (view.getUint16(end, true) !== crc16(bytes.subarray(0, end))) fail('crcMismatch');
  let position = headerSize, lastTimestamp, recordCount = 0, retainedCount = 0, compressedDistance, compressedPrevious, timeZoneOffsetSeconds, deviceTimeZoneOffsetSeconds;
  const definitions = new Map(), descriptions = new Map(), manufacturers = new Set(), records = [], events = [], sessions = [], laps = [];
  const take = size => { if (position + size > end) fail('truncatedFIT'); const at = position; position += size; return at; };
  while (position < end) {
    const header = view.getUint8(take(1)), compressed = Boolean(header & 0x80), local = compressed ? (header >>> 5) & 3 : header & 15;
    if (!compressed && header & 0x10) fail('invalidFIT');
    if (!compressed && header & 0x40) {
      const at = take(5), architecture = view.getUint8(at + 1);
      if (view.getUint8(at) !== 0 || architecture > 1) fail('invalidFIT');
      const definition = { little: architecture === 0, global: view.getUint16(at + 2, architecture === 0), fields: [], developer: [] };
      const count = view.getUint8(at + 4);
      for (let i = 0; i < count; i++) {
        const offset = take(3), field = { number: view.getUint8(offset), size: view.getUint8(offset + 1), type: view.getUint8(offset + 2) };
        if (!field.size) fail('invalidFIT');
        definition.fields.push(field);
      }
      if (header & 0x20) {
        const count = view.getUint8(take(1));
        for (let i = 0; i < count; i++) {
          const offset = take(3);
          definition.developer.push({ number: view.getUint8(offset), size: view.getUint8(offset + 1), index: view.getUint8(offset + 2) });
        }
      }
      definitions.set(local, definition); continue;
    }
    if (!compressed && header & 0x20) fail('invalidFIT');
    const definition = definitions.get(local);
    if (!definition) fail('invalidFIT');
    let timestamp;
    if (compressed) {
      if (!finite(lastTimestamp)) fail('invalidFIT');
      timestamp = Math.floor(lastTimestamp / 32) * 32 + (header & 31);
      if (timestamp < lastTimestamp) timestamp += 32;
      if (timestamp >= 0xffffffff) fail('invalidFIT');
    }
    const values = new Map(), record = {};
    for (const field of definition.fields) {
      if (compressed && field.number === 253) {
        if (field.size !== 4 || (field.type & 31) !== 6) fail('invalidFIT');
        continue;
      }
      const offset = take(field.size);
      if (definition.global === 2 && field.number === 5) {
        if ((field.type & 31) === 1) values.set('timeZoneOffsets', Array.from({ length: field.size }, (_, i) => view.getInt8(offset + i) * 900));
        continue;
      }
      if (definition.global === 20 && field.number === 8 && field.size >= 3) {
        const packed = view.getUint8(offset) | view.getUint8(offset + 1) << 8 | view.getUint8(offset + 2) << 16;
        const speed = packed & 4095, distance = packed >>> 12 & 4095;
        if (speed !== 4095 && distance !== 4095) {
          compressedDistance = compressedPrevious === undefined ? distance : compressedDistance + (distance >= compressedPrevious ? distance - compressedPrevious : distance + 4096 - compressedPrevious);
          compressedPrevious = distance;
          record.speedMetersPerSecond ??= speed / 100;
          record.distanceMeters ??= compressedDistance / 16;
          continue;
        }
      }
      if (definition.global === 206 && [3, 8].includes(field.number)) {
        const raw = bytes.subarray(offset, offset + field.size), zero = raw.indexOf(0);
        try { values.set(field.number, new TextDecoder('utf-8', { fatal: true }).decode(zero < 0 ? raw : raw.subarray(0, zero))); } catch { /* Invalid UTF-8 is an absent native field description. */ }
        continue;
      }
      const value = fitValue(view, offset, field, definition.little);
      if (!finite(value)) continue;
      values.set(field.number, value);
      if (field.number === 253) timestamp = exactInteger(value, 0, 0xffffffff);
      if (definition.global === 20) {
        const mapped = recordFields[field.number];
        if (mapped) {
          const [key, scale, bias = 0] = mapped;
          if (![2, 6].includes(field.number) || record[key] === undefined) record[key] = [3, 4, 7, 13].includes(field.number) ? exactInteger(value) : [0, 1].includes(field.number) ? value * 180 / 2147483648 : value / scale - bias;
        } else if (field.number === 53) record.fractionalCadence = value / 128;
        else if (field.number === 73) record.speedMetersPerSecond = value / 1000;
        else if (field.number === 78) record.altitudeMeters = value / 5 - 500;
      }
    }
    for (const field of definition.developer) {
      const offset = take(field.size), description = descriptions.get(`${field.index}:${field.number}`);
      if (definition.global !== 20 || !description) continue;
      const value = fitValue(view, offset, { ...field, type: description.type }, definition.little);
      if (!finite(value) || !finite(description.scale) || description.scale === 0 || !finite(description.offset)) continue;
      const scaled = value / description.scale - description.offset;
      const key = { airpower: 'airPowerWatts', formpower: 'formPowerWatts', legspringstiffness: 'legSpringStiffnessKilonewtonsPerMeter' }[description.name];
      if (key && finite(scaled)) record[key] = key === 'legSpringStiffnessKilonewtonsPerMeter' ? scaled : exactInteger(rounded(scaled));
    }
    if (timestamp !== undefined) lastTimestamp = timestamp;
    if ([20, 21, 18, 19, 206].includes(definition.global)) checkCount(++retainedCount);
    if (definition.global === 0 && finite(values.get(1))) manufacturers.add(values.get(1));
    else if (definition.global === 34 && timestamp !== undefined && finite(values.get(5))) {
      const offset = values.get(5) - timestamp;
      if (validOffset(offset)) timeZoneOffsetSeconds = offset;
    } else if (definition.global === 2) {
      const offsets = values.get('timeZoneOffsets') ?? [], index = values.get(0) ?? (offsets.length === 1 ? 0 : undefined);
      if (validOffset(offsets[index])) deviceTimeZoneOffsetSeconds = offsets[index];
    } else if (definition.global === 20) {
      checkCount(++recordCount);
      if (timestamp !== undefined || Object.keys(record).some(key => key !== 'fractionalCadence')) records.push({ ...record, timestamp });
    } else if (definition.global === 21 && values.get(0) === 0 && (values.get(1) === 0 || [1, 4, 8, 9].includes(values.get(1)))) {
      events.push({ timestamp, type: values.get(1) });
    } else if ([18, 19].includes(definition.global)) {
      const summary = { timestamp, start: exactInteger(values.get(2), 0, 0xffffffff), sport: exactInteger(values.get(5)),
        timer: finite(values.get(8)) ? values.get(8) / 1000 : undefined, elapsed: finite(values.get(7)) ? values.get(7) / 1000 : undefined,
        distance: finite(values.get(9)) ? values.get(9) / 100 : undefined, calories: exactInteger(values.get(11)) };
      if (definition.global === 18) sessions.push(summary);
      else if (summary.timestamp !== undefined || summary.calories !== undefined) laps.push(summary);
    } else if (definition.global === 206 && [0, 1, 2].every(field => exactInteger(values.get(field), 0, 255) !== undefined)) {
      const name = String(values.get(3) ?? '').toLowerCase().replace(/[^\p{L}\p{N}]/gu, '');
      descriptions.set(`${values.get(0)}:${values.get(1)}`, { type: values.get(2), name, scale: values.get(6) ?? 1, offset: values.get(7) ?? 0 });
    }
  }
  if (!records.length) fail(recordCount ? 'missingTime' : 'noSamples');
  const timestamped = records.filter(record => record.timestamp !== undefined);
  if (!timestamped.length) fail('missingTime');
  const firstRecord = timestamped.reduce((min, record) => Math.min(min, record.timestamp), Infinity);
  const starts = [...events.filter(event => event.type === 0).map(event => event.timestamp), ...sessions.map(session => session.start)].filter(time => time !== undefined && time <= firstRecord);
  const start = starts.length ? starts.reduce((min, value) => Math.min(min, value), Infinity) : undefined, origin = start ?? timestamped[0].timestamp;
  const timeline = timerTimeline(events, origin), points = caloriePoints(laps, sessions, records, start ?? firstRecord, timerTimeline(events, start ?? firstRecord));
  const sport = fitSport(sessions.find(session => session.sport !== undefined)?.sport);
  let samples = timestamped.map(record => {
    const { timestamp, fractionalCadence, ...sample } = record;
    if (sample.cadence !== undefined) sample.cadence = exactInteger(rounded((sample.cadence + (fractionalCadence ?? 0)) * (sport === 'cycling' ? 1 : 2)));
    const elapsed = timeline.at(timestamp);
    return { ...sample, elapsed, date: FIT_EPOCH / 1000 + timestamp, totalCalories: caloriesAt(points, elapsed), hasSyntheticDistance: false };
  });
  if (start !== undefined && timestamped[0].timestamp > start && samples[0].elapsed > 0) {
    const first = samples[0], distance = first.distanceMeters;
    samples.unshift({ ...first, elapsed: 0, date: FIT_EPOCH / 1000 + start, cadence: first.cadence === undefined ? undefined : 0,
      distanceMeters: distance !== undefined && distance / first.elapsed <= 12 ? 0 : distance, totalCalories: caloriesAt(points, 0) });
  }
  if (sessions.length && sessions.every(session => session.sport === 1)) samples = correctingRunningDecelerations(samples);
  const pauses = timerTimeline(events, start ?? firstRecord).pauses;
  let series = createNativeSeries(samples, pauses);
  const anchors = authoritativeLaps(laps, sessions, series, start ?? firstRecord, timerTimeline(events, start ?? firstRecord));
  if (anchors.length) {
    const merged = series.samples.map(sample => ({ ...sample })), inserted = [];
    for (const anchor of anchors) {
      let nearest = -1;
      for (let i = 0; i < merged.length; i++) if (nearest < 0 || Math.abs(merged[i].elapsed - anchor.elapsed) < Math.abs(merged[nearest].elapsed - anchor.elapsed)) nearest = i;
      if (nearest >= 0 && Math.abs(merged[nearest].elapsed - anchor.elapsed) < .25) Object.assign(merged[nearest], { distanceMeters: anchor.distanceMeters, hasSyntheticDistance: true });
      else inserted.push(anchor);
    }
    series = createNativeSeries([...merged, ...inserted], pauses);
  }
  const final = authoritativeFinal(sessions, series, start, timeline);
  if (final) series = createNativeSeries([...series.samples, final], pauses);
  if (manufacturers.has(294)) series = applyingQuantizedAltitudeDisplaySmoothing(series);
  return finish(series, timeZoneOffsetSeconds ?? deviceTimeZoneOffsetSeconds, sport);
}
