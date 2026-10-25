// Local-only parsing. FIT wire format: https://developer.garmin.com/fit/articles/fit-protocol/fit_protocol.html
const MAX_BYTES = 50 * 1024 * 1024;
const MAX_SAMPLES = 200000;
const FIT_EPOCH = Date.UTC(1989, 11, 31);
const finite = Number.isFinite;
const numericFields = ['latitude', 'longitude', 'altitudeMeters', 'heartRate', 'cadence', 'distanceMeters',
  'speedMetersPerSecond', 'powerWatts', 'verticalOscillationCentimeters', 'groundContactTimeMilliseconds',
  'groundContactTimePercent', 'groundContactTimeBalancePercent', 'verticalRatioPercent',
  'respirationRateBreathsPerMinute', 'stepSpeedLossPercent', 'formPowerWatts', 'airPowerWatts',
  'legSpringStiffnessKilonewtonsPerMeter', 'totalCalories', 'stepLengthMeters', 'temperatureCelsius',
  'totalAscentMeters', 'weatherTemperatureCelsius', 'weatherHumidityPercent'];
const nearestFields = new Set(['heartRate', 'powerWatts', 'temperatureCelsius', 'weatherTemperatureCelsius',
  'weatherHumidityPercent', 'formPowerWatts', 'airPowerWatts']);

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

function cleanMetrics(input) {
  const out = {};
  for (const key of numericFields) {
    const value = input[key];
    if (!finite(value)) continue;
    if (key === 'latitude' ? Math.abs(value) > 90 : key === 'longitude' ? Math.abs(value) > 180
      : !['altitudeMeters', 'temperatureCelsius', 'weatherTemperatureCelsius'].includes(key) && value < 0) continue;
    out[key] = value;
  }
  return out;
}

function haversine(a, b) {
  if (![a.latitude, a.longitude, b.latitude, b.longitude].every(finite)) return undefined;
  const rad = Math.PI / 180, lat = (b.latitude - a.latitude) * rad, lon = (b.longitude - a.longitude) * rad;
  const h = Math.sin(lat / 2) ** 2 + Math.cos(a.latitude * rad) * Math.cos(b.latitude * rad) * Math.sin(lon / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
}

// The ranges carry a prefix sum so video-frame lookups stay logarithmic even with many pauses.
function pauseTimeline(events, startMs) {
  const ranges = []; let stopped, removed = 0;
  for (const event of events.sort((a, b) => a.timestampMs - b.timestampMs)) {
    const wall = Math.max(0, (event.timestampMs - startMs) / 1000);
    if ([1, 4, 8, 9].includes(event.type)) stopped ??= wall;
    else if (event.type === 0 && stopped !== undefined) {
      if (wall > stopped) {
        ranges.push({ start: stopped, end: wall, removedBefore: removed });
        removed += wall - stopped;
      }
      stopped = undefined;
    }
  }
  // A trailing stop marks the activity end; it is not a pause without a subsequent resume.
  return ranges;
}

function upperBound(values, time, key) {
  let lo = 0, hi = values.length;
  while (lo < hi) {
    const mid = (lo + hi) >>> 1;
    if (values[mid][key] <= time) lo = mid + 1; else hi = mid;
  }
  return lo;
}

function activeAt(ranges, wall) {
  const range = ranges[upperBound(ranges, wall, 'start') - 1];
  return range ? wall - range.removedBefore - Math.min(wall - range.start, range.end - range.start) : wall;
}

function caloriesAt(points, elapsed) {
  const index = Math.max(0, upperBound(points, elapsed, 'elapsed') - 1), a = points[index], b = points[index + 1];
  return b ? a.calories + (b.calories - a.calories) * Math.max(0, (elapsed - a.elapsed) / (b.elapsed - a.elapsed)) : a.calories;
}

const validOffset = value => finite(value) && Number.isInteger(value) && value >= -12 * 3600 && value <= 14 * 3600;
function calendarFields(startDate, wall, offset) {
  const date = new Date(Date.parse(startDate) + wall * 1000).toISOString();
  const display = new Date(Date.parse(date) + (offset ?? 0) * 1000);
  const parts = offset === undefined ? [display.getFullYear(), display.getMonth() + 1, display.getDate(), display.getHours(), display.getMinutes(), display.getSeconds()]
    : [display.getUTCFullYear(), display.getUTCMonth() + 1, display.getUTCDate(), display.getUTCHours(), display.getUTCMinutes(), display.getUTCSeconds()];
  const [year, month, day, hour, minute, second] = parts.map(value => String(value).padStart(2, '0'));
  return { date, clock: `${hour}:${minute}:${second}`, calendar: `${year}/${month}/${day}` };
}

function finish(records, { startMs, pauses = [], caloriePoints = [], timeZoneOffsetSeconds } = {}) {
  if (!records.length) fail('noSamples');
  checkCount(records.length);
  records.sort((a, b) => a.timestampMs - b.timestampMs);
  const unique = [];
  for (const record of records) {
    const sample = { ...cleanMetrics(record), timestampMs: record.timestampMs, trackSegmentIndex: record.trackSegmentIndex ?? 0 };
    if (unique.at(-1)?.timestampMs === sample.timestampMs) Object.assign(unique.at(-1), sample);
    else unique.push(sample);
  }
  startMs ??= unique[0].timestampMs;
  const startDate = new Date(startMs).toISOString();
  const duration = (unique.at(-1).timestampMs - startMs) / 1000;
  const baseline = unique.find(p => finite(p.distanceMeters))?.distanceMeters ?? 0;
  const hasAltitude = unique.some(p => finite(p.altitudeMeters));
  let distance = 0, hasDistance = false, ascent = 0, altitudeReference, previous;
  const normalized = [];
  for (const raw of unique) {
    const wallElapsed = (raw.timestampMs - startMs) / 1000;
    const range = pauses[upperBound(pauses, wallElapsed, 'start') - 1];
    if (range && wallElapsed >= range.start && wallElapsed < range.end) continue;
    const sample = { ...raw, wallElapsed, elapsed: activeAt(pauses, wallElapsed), ...calendarFields(startDate, wallElapsed, timeZoneOffsetSeconds) };
    delete sample.timestampMs;
    const dt = previous ? sample.elapsed - previous.elapsed : 0;
    const sameSegment = previous && previous.trackSegmentIndex === sample.trackSegmentIndex;
    const continuous = sameSegment && Math.abs(wallElapsed - previous.wallElapsed - dt) < 1e-6;
    if (finite(raw.distanceMeters)) { distance = Math.max(distance, raw.distanceMeters - baseline); hasDistance = true; }
    else if (continuous && dt >= .5) {
      const delta = haversine(previous, sample);
      if (finite(delta)) { distance += delta; hasDistance = true; }
    }
    if (hasDistance) sample.distanceMeters = distance;
    else delete sample.distanceMeters;
    if (!finite(sample.speedMetersPerSecond) && continuous && dt >= .5 && finite(previous.distanceMeters) && hasDistance) {
      sample.speedMetersPerSecond = Math.max(0, distance - previous.distanceMeters) / dt;
    }
    if (hasAltitude) {
      if (!continuous) altitudeReference = undefined;
      if (finite(sample.altitudeMeters)) {
        const delta = sample.altitudeMeters - altitudeReference;
        if (finite(delta) && delta >= 1) ascent += delta;
        if (!finite(altitudeReference) || delta >= 1 || delta < 0) altitudeReference = sample.altitudeMeters;
      }
      sample.totalAscentMeters = ascent;
    }
    if (caloriePoints.length > 1) {
      sample.totalCalories = caloriesAt(caloriePoints, sample.elapsed);
    }
    normalized.push(sample); previous = sample;
  }
  if (!normalized.length) fail('noSamples');
  const samples = [];
  let index = 0;
  for (const range of pauses) {
    if (range.start > duration) break;
    while (index < normalized.length && normalized[index].wallElapsed <= range.start) samples.push(normalized[index++]);
    const held = samples.at(-1) ?? normalized[0];
    if (samples.at(-1)?.wallElapsed !== range.start) samples.push({ ...held, wallElapsed: range.start, elapsed: activeAt(pauses, range.start), ...calendarFields(startDate, range.start, timeZoneOffsetSeconds) });
    if (range.end <= duration && normalized[index]?.wallElapsed !== range.end) samples.push({ ...held, wallElapsed: range.end, elapsed: activeAt(pauses, range.end), ...calendarFields(startDate, range.end, timeZoneOffsetSeconds) });
  }
  for (; index < normalized.length; index++) samples.push(normalized[index]);
  checkCount(samples.length);
  if (caloriePoints.length > 1) for (const sample of samples) sample.totalCalories = caloriesAt(caloriePoints, sample.elapsed);
  // shortcut: Web preserves device metrics; native startup/resumption, lap-distance and COROS altitude smoothing are not ported.
  return { samples, startDate, duration, totalDistanceMeters: hasDistance ? distance : 0, pausedRanges: pauses, timeZoneOffsetSeconds, caloriePoints };
}

export function previewAt(activity, wallElapsed) {
  if (!finite(wallElapsed)) fail('invalidTime');
  const samples = activity.samples;
  if (!samples?.length) fail('noSamples');
  const inRange = wallElapsed >= 0 && wallElapsed <= activity.duration;
  const wall = Math.min(activity.duration, Math.max(0, wallElapsed));
  const index = upperBound(samples, wall, 'wallElapsed');
  const a = samples[Math.max(0, index - 1)], b = samples[index];
  const ranges = activity.pausedRanges ?? [];
  const range = ranges[upperBound(ranges, wall, 'start') - 1];
  const paused = range && wall >= range.start && wall < range.end;
  let sample = { ...a };
  if (b && wall > a.wallElapsed && a.trackSegmentIndex === b.trackSegmentIndex && !paused) {
    const fraction = (wall - a.wallElapsed) / (b.wallElapsed - a.wallElapsed);
    sample = {};
    for (const key of numericFields) {
      if (!finite(a[key]) || !finite(b[key])) continue;
      sample[key] = nearestFields.has(key) ? (fraction < .5 ? a[key] : b[key]) : a[key] + (b[key] - a[key]) * fraction;
    }
    if (finite(a.cadence) && finite(b.cadence)) sample.cadence = a.cadence === 0 || b.cadence === 0
      ? Math.round(a.cadence + (b.cadence - a.cadence) * fraction) : fraction < .5 ? a.cadence : b.cadence;
    sample.trackSegmentIndex = a.trackSegmentIndex;
  }
  // Endpoint metrics clamp; absolute time advances only within the activity's wall-clock range.
  sample.wallElapsed = wall;
  sample.elapsed = activeAt(ranges, wall);
  if (activity.caloriePoints?.length > 1) sample.totalCalories = caloriesAt(activity.caloriePoints, sample.elapsed);
  Object.assign(sample, calendarFields(activity.startDate, wall, activity.timeZoneOffsetSeconds));
  return { sample, series: activity, inRange };
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
    watts: 'powerWatts', calories: 'totalCalories', steplength: 'stepLengthMeters', atemp: 'temperatureCelsius', temp: 'temperatureCelsius', temperature: 'temperatureCelsius' };
  let previousTime, timeZoneOffsetSeconds;
  const records = points.map(point => {
    const record = {};
    for (const [attribute, key] of [['lat', 'latitude'], ['lon', 'longitude']]) {
      const text = point.getAttribute(attribute);
      if (text !== null && text.trim() !== '') record[key] = Number(text);
    }
    let timestampMs;
    for (const node of point.getElementsByTagName('*')) {
      const name = node.localName.toLowerCase(), text = node.textContent.trim();
      if (name === 'time' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)$/i.test(text)) {
        timestampMs = Date.parse(text);
        const zone = text.match(/([+-])(\d\d):(\d\d)$/);
        const offset = zone ? (Number(zone[2]) * 3600 + Number(zone[3]) * 60) * (zone[1] === '-' ? -1 : 1) : 0;
        if (validOffset(offset)) timeZoneOffsetSeconds ??= offset;
      }
      const key = fields[name];
      if (key && text !== '') record[key] = Number(text);
    }
    if (!finite(timestampMs)) fail('missingTime');
    // Keep route order and geometry without turning same-second points into full extra seconds.
    if (finite(previousTime) && timestampMs <= previousTime) timestampMs = previousTime + 1;
    previousTime = timestampMs;
    let segment = point.parentElement;
    while (segment && segment.localName !== 'trkseg') segment = segment.parentElement;
    record.trackSegmentIndex = segments.get(segment) ?? 0;
    if (finite(record.cadence) && record.cadence >= 0 && !cycling && record.cadence < 130) record.cadence *= 2;
    return { ...record, timestampMs };
  });
  return finish(records, { timeZoneOffsetSeconds });
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
    if (!Number.isSafeInteger(value)) return undefined;
  }
  return finite(value) ? value : undefined;
}

const recordFields = { 0: ['latitude', 2147483648 / 180], 1: ['longitude', 2147483648 / 180], 2: ['altitudeMeters', 5, 500],
  3: ['heartRate', 1], 4: ['cadence', 1], 5: ['distanceMeters', 100], 6: ['speedMetersPerSecond', 1000], 7: ['powerWatts', 1],
  13: ['temperatureCelsius', 1], 39: ['verticalOscillationCentimeters', 100], 40: ['groundContactTimePercent', 100],
  41: ['groundContactTimeMilliseconds', 10], 83: ['verticalRatioPercent', 100], 84: ['groundContactTimeBalancePercent', 100],
  85: ['stepLengthMeters', 10000], 108: ['respirationRateBreathsPerMinute', 100], 147: ['stepSpeedLossPercent', 100] };

export function parseFIT(input) {
  const bytes = input instanceof Uint8Array ? input : input instanceof ArrayBuffer ? new Uint8Array(input) : fail('invalidFIT');
  if (bytes.byteLength > MAX_BYTES) fail('fileTooLarge');
  if (bytes.length < 14) fail('truncatedFIT');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength), headerSize = bytes[0];
  if (headerSize < 12 || headerSize === 13 || (bytes[1] >>> 4) > 2 || String.fromCharCode(...bytes.subarray(8, 12)) !== '.FIT') fail('invalidFIT');
  const end = headerSize + view.getUint32(4, true);
  if (end + 2 > bytes.length) fail('truncatedFIT');
  // Chained activity files need an explicit session policy; never silently ignore trailing content.
  if (end + 2 !== bytes.length) fail('invalidFIT');
  if (headerSize >= 14) {
    const expected = view.getUint16(headerSize - 2, true);
    if (expected !== 0 && expected !== crc16(bytes.subarray(0, headerSize - 2))) fail('crcMismatch');
  }
  if (view.getUint16(end, true) !== crc16(bytes.subarray(0, end))) fail('crcMismatch');
  let position = headerSize, lastTimestamp, recordCount = 0, retainedCount = 0, compressedDistance, timeZoneOffsetSeconds, deviceTimeZoneOffsetSeconds;
  const definitions = new Map(), descriptions = new Map(), records = [], events = [], sessions = [], laps = [];
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
    const values = new Map(), developer = {};
    for (const field of definition.fields) {
      if (compressed && field.number === 253) {
        if (field.size !== 4 || (field.type & 31) !== 6) fail('invalidFIT');
        continue;
      }
      const offset = take(field.size);
      if (definition.global === 2 && field.number === 5 && (field.type & 31) === 1) {
        values.set('timeZoneOffsets', Array.from({ length: field.size }, (_, i) => view.getInt8(offset + i) * 900));
        continue;
      }
      if (definition.global === 20 && field.number === 8 && field.size >= 3) {
        const packed = view.getUint8(offset) | view.getUint8(offset + 1) << 8 | view.getUint8(offset + 2) << 16;
        const speed = packed & 4095, distance = packed >>> 12 & 4095;
        if (speed !== 4095) values.set('compressedSpeed', speed / 100);
        if (distance !== 4095) {
          const previous = compressedDistance ?? 0;
          compressedDistance = previous + ((distance - previous % 4096 + 4096) % 4096);
          values.set('compressedDistance', compressedDistance / 16);
        }
      } else {
        const value = fitValue(view, offset, field, definition.little);
        if (value !== undefined) values.set(field.number, value);
      }
    }
    for (const field of definition.developer) {
      const offset = take(field.size), description = descriptions.get(`${field.index}:${field.number}`);
      if (definition.global !== 20 || !description) continue;
      const value = fitValue(view, offset, { ...field, type: description.type }, definition.little);
      if (finite(value) && finite(description.scale) && description.scale !== 0) developer[description.name] = value / description.scale - description.offset;
    }
    if (finite(values.get(253))) timestamp = values.get(253);
    if (timestamp !== undefined) {
      if (!Number.isInteger(timestamp) || timestamp < 0 || timestamp >= 0xffffffff) fail('invalidFIT');
      lastTimestamp = timestamp;
    }
    const timestampMs = timestamp === undefined ? undefined : FIT_EPOCH + timestamp * 1000;
    if ([20, 21, 18, 19, 206].includes(definition.global)) checkCount(++retainedCount);
    if (definition.global === 34 && finite(timestamp) && finite(values.get(5))) {
      const offset = values.get(5) - timestamp;
      if (validOffset(offset)) timeZoneOffsetSeconds = offset;
    } else if (definition.global === 2) {
      const offsets = values.get('timeZoneOffsets') ?? [], index = values.get(0) ?? (offsets.length === 1 ? 0 : undefined);
      if (validOffset(offsets[index])) deviceTimeZoneOffsetSeconds = offsets[index];
    } else if (definition.global === 20) {
      checkCount(++recordCount);
      if (timestampMs === undefined) continue;
      const record = { timestampMs };
      for (const [field, [key, scale, offset = 0]] of Object.entries(recordFields)) {
        if (finite(values.get(Number(field)))) record[key] = values.get(Number(field)) / scale - offset;
      }
      if (finite(values.get(73))) record.speedMetersPerSecond = values.get(73) / 1000;
      else record.speedMetersPerSecond ??= values.get('compressedSpeed');
      if (finite(values.get(78))) record.altitudeMeters = values.get(78) / 5 - 500;
      record.distanceMeters ??= values.get('compressedDistance');
      record.fractionalCadence = values.get(53) / 128 || 0;
      for (const [name, key] of Object.entries({ airpower: 'airPowerWatts', formpower: 'formPowerWatts', legspringstiffness: 'legSpringStiffnessKilonewtonsPerMeter' })) {
        if (finite(developer[name])) record[key] = developer[name];
      }
      records.push(record);
    } else if (definition.global === 21 && timestampMs !== undefined && values.get(0) === 0) {
      events.push({ timestampMs, type: values.get(1) });
    } else if ([18, 19].includes(definition.global)) {
      (definition.global === 18 ? sessions : laps).push({ timestampMs, startMs: finite(values.get(2)) ? FIT_EPOCH + values.get(2) * 1000 : undefined,
        sport: values.get(5), timer: values.get(8) / 1000, calories: values.get(11) });
    } else if (definition.global === 206 && finite(values.get(0)) && finite(values.get(1)) && finite(values.get(2))) {
      const name = String(values.get(3) ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');
      descriptions.set(`${values.get(0)}:${values.get(1)}`, { type: values.get(2), name, scale: values.get(6) ?? 1, offset: values.get(7) ?? 0 });
    }
  }
  if (!records.length) fail(recordCount ? 'missingTime' : 'noSamples');
  const firstRecordMs = records.reduce((min, r) => Math.min(min, r.timestampMs), Infinity);
  const starts = [...events.filter(e => e.type === 0).map(e => e.timestampMs), ...sessions.map(s => s.startMs)].filter(t => finite(t) && t <= firstRecordMs);
  const startMs = starts.reduce((min, t) => Math.min(min, t), firstRecordMs), pauses = pauseTimeline(events, startMs);
  const cycling = sessions.find(s => finite(s.sport))?.sport === 2;
  for (const record of records) {
    if (finite(record.cadence)) record.cadence = Math.round((record.cadence + record.fractionalCadence) * (cycling ? 1 : 2));
    delete record.fractionalCadence;
  }
  const caloriePoints = [{ elapsed: 0, calories: 0 }];
  let cumulative = 0;
  const validLaps = laps.filter(p => finite(p.calories) && (finite(p.timestampMs) || finite(p.timer) && finite(p.startMs)));
  for (const point of (validLaps.length ? validLaps : sessions).sort((a, b) => (a.timestampMs ?? Infinity) - (b.timestampMs ?? Infinity))) {
    if (!finite(point.calories) || point.calories < 0) continue;
    const elapsed = finite(point.timer) && finite(point.startMs) ? activeAt(pauses, (point.startMs - startMs) / 1000) + point.timer
      : finite(point.timestampMs) ? activeAt(pauses, (point.timestampMs - startMs) / 1000) : undefined;
    if (!finite(elapsed) || elapsed < caloriePoints.at(-1).elapsed) continue;
    cumulative += point.calories;
    if (elapsed === caloriePoints.at(-1).elapsed) caloriePoints.at(-1).calories = cumulative;
    else caloriePoints.push({ elapsed, calories: cumulative });
  }
  return finish(records, { startMs, pauses, caloriePoints, timeZoneOffsetSeconds: timeZoneOffsetSeconds ?? deviceTimeZoneOffsetSeconds });
}
