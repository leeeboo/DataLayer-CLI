// Direct port of OverlayCore/Telemetry/TelemetrySeries.swift. Dates are UNIX seconds.
const MAX_SAMPLES = 100_000;
const MOVING = 0.3, BASE = 0.35, STARTUP_WINDOW = 15, EXPONENT = 1.7;
const RATIO = 1.6, TOLERANCE = 0.05, EPSILON = 0.001;
const present = value => value != null;
const finite = Number.isFinite;
// Swift min/max retain the first operand when the comparison is unordered (NaN).
const min = (a, b) => b < a ? b : a;
const max = (a, b) => a < b ? b : a;
const copy = samples => samples.map(sample => ({ ...sample }));
const clamp = value => min(1, max(0, value));
const round = value => value < 0 ? -Math.round(-value) : Math.round(value);
const sortSamples = samples => samples.sort((a, b) => a.elapsed === b.elapsed
  ? (a.date ?? -62135769600) - (b.date ?? -62135769600) : a.elapsed - b.elapsed);
const segmentBreak = (a, b) => (a.trackSegmentIndex ?? null) !== (b.trackSegmentIndex ?? null);
const plausible = speed => finite(speed) && speed >= MOVING && speed <= 12 ? speed : undefined;
const shouldReplaceSpeed = speed => !finite(speed) || speed < MOVING;
const interpolateValue = (a, b, fraction) => present(a) && present(b) ? a + (b - a) * fraction : a ?? b;
const DATE_REFERENCE_EPOCH = 978307200;
const addingDate = (date, interval) => (date - DATE_REFERENCE_EPOCH) + interval + DATE_REFERENCE_EPOCH;
const interpolatedDate = (a, b, fraction) => present(a) && present(b)
  ? addingDate(a, ((b - DATE_REFERENCE_EPOCH) - (a - DATE_REFERENCE_EPOCH)) * fraction) : a ?? b;
const nearest = (a, b, fraction) => fraction < 0.5 ? a ?? b : b ?? a;

const doubleFields = ['latitude', 'longitude', 'altitudeMeters', 'totalAscentMeters',
  'distanceMeters', 'speedMetersPerSecond', 'verticalOscillationCentimeters',
  'groundContactTimeMilliseconds', 'groundContactTimePercent', 'groundContactTimeBalancePercent',
  'verticalRatioPercent', 'respirationRateBreathsPerMinute', 'stepSpeedLossPercent',
  'legSpringStiffnessKilonewtonsPerMeter', 'totalCalories', 'stepLengthMeters'];
const nearestFields = ['heartRate', 'powerWatts', 'formPowerWatts', 'airPowerWatts',
  'temperatureCelsius', 'weatherTemperatureCelsius', 'weatherHumidityPercent', 'weatherSummary'];

export function interpolateNativeSample(a, b, fraction, elapsed) {
  const sample = { elapsed, date: interpolatedDate(a.date, b.date, fraction) };
  for (const field of doubleFields) sample[field] = interpolateValue(a[field], b[field], fraction);
  for (const field of nearestFields) sample[field] = nearest(a[field], b[field], fraction);
  sample.cadence = !present(a.cadence) || !present(b.cadence) ? undefined
    : a.cadence === 0 || b.cadence === 0
      ? max(0, round(a.cadence + (b.cadence - a.cadence) * fraction))
      : nearest(a.cadence, b.cadence, fraction);
  sample.trackSegmentIndex = fraction < 1 ? a.trackSegmentIndex : b.trackSegmentIndex;
  if (present(a.sourceAltitudeMeters) || present(b.sourceAltitudeMeters)) {
    sample.sourceAltitudeMeters = interpolateValue(a.sourceAltitudeMeters ?? a.altitudeMeters,
      b.sourceAltitudeMeters ?? b.altitudeMeters, fraction);
  }
  sample.hasSyntheticDistance = fraction <= 0 ? !!a.hasSyntheticDistance
    : fraction >= 1 ? !!b.hasSyntheticDistance : !!(a.hasSyntheticDistance || b.hasSyntheticDistance);
  return sample;
}

function heldSample(sample, elapsed) {
  const held = { ...sample, elapsed };
  if (present(sample.date)) held.date = addingDate(sample.date, elapsed - sample.elapsed);
  return held;
}

function sampleAtActiveElapsed(samples, elapsed) {
  if (!samples.length) return { elapsed, hasSyntheticDistance: false };
  if (samples.length === 1 || elapsed <= samples[0].elapsed) return { ...samples[0] };
  if (elapsed >= samples.at(-1).elapsed) return { ...samples.at(-1) };
  let low = 0, high = samples.length - 1;
  while (low + 1 < high) {
    const mid = Math.floor((low + high) / 2);
    if (samples[mid].elapsed <= elapsed) low = mid;
    else high = mid;
  }
  const a = samples[low], b = samples[high];
  if (segmentBreak(a, b)) return heldSample(a, elapsed);
  const span = max(b.elapsed - a.elapsed, 0.000001);
  return interpolateNativeSample(a, b, clamp((elapsed - a.elapsed) / span), elapsed);
}

export function activeElapsed(series, wall) {
  if (!finite(wall)) return wall;
  let active = wall;
  for (const range of series.pausedRanges) {
    if (wall >= range.start + range.duration) active -= range.duration;
    else if (wall > range.start) active -= wall - range.start;
  }
  return active;
}

export function wallElapsed(series, active) {
  if (!finite(active)) return active;
  let pauseShift = 0;
  for (const range of series.pausedRanges) {
    if (!(active > range.start - pauseShift)) break;
    pauseShift += range.duration;
  }
  return active + pauseShift;
}

export function sampleNativeSeries(series, wall) {
  return sampleAtActiveElapsed(series.samples, activeElapsed(series, wall));
}

export function dateNativeSeries(series, elapsed) {
  if (!finite(elapsed)) return undefined;
  if (series.pausedRanges.length && present(series.activityStartDate)) return addingDate(series.activityStartDate, elapsed);
  const first = series.samples[0], last = series.samples.at(-1);
  if (first && elapsed < first.elapsed && present(first.date)) return addingDate(first.date, elapsed - first.elapsed);
  if (last && elapsed > last.elapsed && present(last.date)) return addingDate(last.date, elapsed - last.elapsed);
  const date = sampleNativeSeries(series, elapsed).date;
  if (present(date)) return date;
  return present(series.activityStartDate) ? addingDate(series.activityStartDate, elapsed) : undefined;
}

function sanitizedPausedRanges(ranges) {
  const positive = ranges.filter(range => finite(range.start) && finite(range.duration)
    && range.duration > 0 && range.start >= 0).map(range => ({ start: range.start, duration: range.duration }))
    .sort((a, b) => a.start - b.start);
  const merged = [];
  for (const range of positive) {
    const last = merged.at(-1);
    if (last && range.start <= last.start + last.duration) {
      last.duration = max(last.start + last.duration, range.start + range.duration) - last.start;
    } else merged.push(range);
  }
  return merged;
}

function haversineMeters(lat1, lon1, lat2, lon2) {
  const phi1 = lat1 * Math.PI / 180, phi2 = lat2 * Math.PI / 180;
  const dPhi = (lat2 - lat1) * Math.PI / 180, dLambda = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dPhi / 2) * Math.sin(dPhi / 2)
    + Math.cos(phi1) * Math.cos(phi2) * Math.sin(dLambda / 2) * Math.sin(dLambda / 2);
  return 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function startupDistanceBaseline(samples) {
  const first = samples[0], firstDistanceSample = samples.find(s => present(s.distanceMeters));
  if (!first || !firstDistanceSample) return 0;
  const distance = firstDistanceSample.distanceMeters;
  if (present(first.distanceMeters) || !(firstDistanceSample.elapsed > first.elapsed)) return distance;
  return distance / (firstDistanceSample.elapsed - first.elapsed) <= 12 ? 0 : distance;
}

function normalized(samples) {
  if (!samples.length) return [];
  const baseline = startupDistanceBaseline(samples), firstElapsed = samples[0].elapsed;
  let previousInput, previousOutput, hasSeenReportedMovingSpeed = false, accumulatedDistance = 0;
  const output = [];
  for (const input of samples) {
    const sample = { ...input };
    if (finite(input.speedMetersPerSecond) && input.speedMetersPerSecond >= MOVING) hasSeenReportedMovingSpeed = true;
    if (present(input.distanceMeters)) {
      accumulatedDistance = max(accumulatedDistance, max(0, input.distanceMeters - baseline));
    } else if (previousInput && !segmentBreak(previousInput, input)
      && present(previousInput.latitude) && present(previousInput.longitude)
      && present(input.latitude) && present(input.longitude)) {
      accumulatedDistance += haversineMeters(previousInput.latitude, previousInput.longitude, input.latitude, input.longitude);
    }
    sample.distanceMeters = accumulatedDistance;
    if (!present(sample.speedMetersPerSecond) && !sample.hasSyntheticDistance && !previousOutput?.hasSyntheticDistance) {
      if (!hasSeenReportedMovingSpeed && input.elapsed - firstElapsed <= STARTUP_WINDOW) sample.speedMetersPerSecond = 0;
      else if (previousOutput && input.elapsed > previousOutput.elapsed) {
        const deltaDistance = accumulatedDistance - (previousOutput.distanceMeters ?? accumulatedDistance);
        const deltaTime = input.elapsed - previousOutput.elapsed;
        if (deltaDistance >= 0 && deltaTime > 0) sample.speedMetersPerSecond = deltaDistance / deltaTime;
      }
    }
    output.push(sample);
    previousInput = input;
    previousOutput = sample;
  }
  if (!(baseline <= EPSILON) || samples.length <= 1) return output;
  const targetIndex = output.findIndex(s => (s.distanceMeters ?? 0) > EPSILON);
  if (targetIndex <= 0) return output;
  const target = output[targetIndex], elapsed = target.elapsed - output[0].elapsed;
  if (!finite(target.distanceMeters) || !(elapsed > 0)
    || !finite(target.distanceMeters / elapsed) || target.distanceMeters / elapsed > 12) return output;
  if (!output.slice(0, targetIndex).every(s => (s.distanceMeters ?? 0) <= EPSILON)) return output;
  for (let i = 1; i <= targetIndex; i++) if (segmentBreak(output[i - 1], output[i])) return output;
  for (let i = 0; i < targetIndex; i++) {
    const sampleElapsed = output[i].elapsed - output[0].elapsed;
    output[i].distanceMeters = sampleElapsed > 0 ? target.distanceMeters * clamp(sampleElapsed / elapsed) : 0;
  }
  return output;
}

function enrichedWithDistanceDerivedSpeed(samples) {
  if (samples.length <= 1) return samples;
  const output = copy(samples), firstElapsed = samples[0].elapsed;
  for (let i = 0; i < samples.length - 1; i++) {
    const current = { ...output[i] }, next = { ...output[i + 1] };
    if (segmentBreak(current, next) || current.hasSyntheticDistance || next.hasSyntheticDistance
      || !present(current.distanceMeters) || !present(next.distanceMeters)) continue;
    const dt = next.elapsed - current.elapsed, dd = next.distanceMeters - current.distanceMeters;
    if (!(dt > 0 && dd > 0 && dt >= 0.5)) continue;
    const speed = dd / dt;
    if (!(speed >= MOVING) || !(current.elapsed - firstElapsed > STARTUP_WINDOW || speed <= 12)) continue;
    const hasPriorMotion = i > 0 && !samples[i - 1].hasSyntheticDistance
      && present(samples[i - 1].distanceMeters) && current.distanceMeters > samples[i - 1].distanceMeters + EPSILON;
    if (shouldReplaceSpeed(output[i].speedMetersPerSecond)
      && (current.speedMetersPerSecond !== 0 || current.elapsed - firstElapsed <= STARTUP_WINDOW || hasPriorMotion)) {
      output[i].speedMetersPerSecond = i === 0 && current.elapsed <= 0.000001
        ? min(speed, max(BASE, speed * 0.25)) : speed;
    }
    if (shouldReplaceSpeed(output[i + 1].speedMetersPerSecond)) output[i + 1].speedMetersPerSecond = speed;
  }
  return output;
}

function firstStartupCompleteSampleIndex(samples) {
  return samples.findIndex(s => finite(s.latitude) && finite(s.longitude)
    && present(plausible(s.speedMetersPerSecond)) && (s.heartRate ?? 0) > 0);
}
function protectedStartIndex(samples, elapsed) {
  const index = present(elapsed) ? samples.findIndex(s => s.elapsed >= elapsed) : firstStartupCompleteSampleIndex(samples);
  return index < 0 ? samples.length : index;
}

function stabilizedStartupSpeedJumps(samples, protectedElapsed) {
  if (samples.length <= 2) return samples;
  const output = copy(samples);
  for (let i = 1; i < samples.length - 1; i++) {
    const previous = samples[i - 1], current = samples[i], next = samples[i + 1];
    if (segmentBreak(previous, current) || segmentBreak(current, next)) continue;
    if (present(protectedElapsed) && current.elapsed >= protectedElapsed) break;
    if (!(current.elapsed <= STARTUP_WINDOW) || previous.hasSyntheticDistance || current.hasSyntheticDistance
      || next.hasSyntheticDistance || !finite(current.speedMetersPerSecond)
      || !present(previous.distanceMeters) || !present(current.distanceMeters) || !present(next.distanceMeters)) continue;
    const previousSpan = current.elapsed - previous.elapsed, nextSpan = next.elapsed - current.elapsed;
    if (!(previousSpan > 0 && nextSpan > 0)) continue;
    const previousSpeed = (current.distanceMeters - previous.distanceMeters) / previousSpan;
    const nextSpeed = (next.distanceMeters - current.distanceMeters) / nextSpan;
    if (!(previousSpeed >= MOVING && nextSpeed >= MOVING)) continue;
    if (!(max(previousSpeed, nextSpeed) / min(previousSpeed, nextSpeed) <= RATIO)) continue;
    const distanceSpeed = (previousSpeed + nextSpeed) / 2;
    if (!(distanceSpeed <= 12)) continue;
    const ratio = max(current.speedMetersPerSecond, distanceSpeed)
      / max(min(current.speedMetersPerSecond, distanceSpeed), 0.000001);
    if (ratio >= RATIO) output[i].speedMetersPerSecond = distanceSpeed;
  }
  return output;
}

function resampled(samples) {
  if (samples.length <= 1) return samples;
  const output = [];
  let available = max(0, MAX_SAMPLES - samples.length);
  for (let i = 0; i < samples.length - 1; i++) {
    const current = samples[i], next = samples[i + 1];
    if (output.at(-1)?.elapsed !== current.elapsed) output.push(current);
    const gap = next.elapsed - current.elapsed;
    if (!finite(gap) || !(gap > 1) || segmentBreak(current, next)) continue;
    const required = Math.ceil(gap) - 1;
    if (!finite(required) || !(required <= available)) continue;
    available -= required;
    for (let elapsed = current.elapsed + 1; elapsed < next.elapsed; elapsed += 1) {
      output.push(interpolateNativeSample(current, next, clamp((elapsed - current.elapsed) / gap), elapsed));
    }
  }
  const last = samples.at(-1);
  if (output.at(-1)?.elapsed !== last.elapsed) output.push(last);
  return output;
}

export function startupCatchUpCorrection(samples) {
  if (samples.length <= 3) return undefined;
  const first = samples[0], firstElapsed = first.elapsed;
  const movingSpeed = index => finite(samples[index].speedMetersPerSecond)
    && samples[index].speedMetersPerSecond >= MOVING ? samples[index].speedMetersPerSecond : undefined;
  const movingIndex = samples.findIndex((sample, i) => sample.elapsed - firstElapsed <= STARTUP_WINDOW && present(movingSpeed(i)));
  if (movingIndex < 0) return undefined;
  let stabilization;
  for (let i = movingIndex + 1; i + 2 < samples.length && samples[i].elapsed - firstElapsed <= STARTUP_WINDOW; i++) {
    const current = movingSpeed(i), next = movingSpeed(i + 1), after = movingSpeed(i + 2);
    if (present(current) && present(next) && present(after)
      && Math.abs(next - current) <= TOLERANCE && Math.abs(after - next) <= TOLERANCE) { stabilization = i; break; }
  }
  if (!present(stabilization) || samples.slice(0, stabilization + 1).some(s => s.hasSyntheticDistance)) return undefined;
  const targetSpeed = plausible(samples[stabilization].speedMetersPerSecond), firstMoving = movingSpeed(movingIndex);
  if (!present(targetSpeed) || !present(firstMoving)) return undefined;
  const stabilizationElapsed = samples[stabilization].elapsed - firstElapsed;
  if (!(stabilizationElapsed > 0 && targetSpeed / firstMoving >= RATIO)) return undefined;
  let previousSpeed = firstMoving;
  for (let i = movingIndex + 1; i <= stabilization; i++) {
    const speed = movingSpeed(i);
    if (!present(speed)) continue;
    if (!(speed >= previousSpeed - TOLERANCE)) return undefined;
    previousSpeed = speed;
  }
  let distanceRunsAhead = false;
  for (let i = max(movingIndex, 1); i <= stabilization; i++) {
    const speed = movingSpeed(i), previousDistance = samples[i - 1].distanceMeters, distance = samples[i].distanceMeters;
    if (!present(speed) || !present(previousDistance) || !present(distance)) continue;
    const dt = samples[i].elapsed - samples[i - 1].elapsed;
    if (dt > 0 && (distance - previousDistance) / dt >= RATIO * speed) { distanceRunsAhead = true; break; }
  }
  if (!distanceRunsAhead || !present(samples[stabilization].distanceMeters)) return undefined;
  const coveredDistance = samples[stabilization].distanceMeters - (first.distanceMeters ?? 0);
  if (!(coveredDistance > EPSILON)) return undefined;
  let integral = 0;
  for (let i = 1; i <= stabilization; i++) {
    const dt = samples[i].elapsed - samples[i - 1].elapsed;
    if (!(dt > 0)) continue;
    const previous = samples[i - 1].speedMetersPerSecond ?? 0, current = samples[i].speedMetersPerSecond ?? 0;
    integral += (max(finite(previous) ? previous : 0, 0) + max(finite(current) ? current : 0, 0)) / 2 * dt;
  }
  if (!(coveredDistance > 1.2 * integral)) return undefined;
  const exponent = 1 / EXPONENT, coefficient = (targetSpeed - BASE) * (1 - 1 / (exponent + 1));
  if (!(coefficient > 0)) return undefined;
  const rawDuration = (targetSpeed * stabilizationElapsed - coveredDistance) / coefficient;
  return { stabilizationElapsed, targetSpeed, rampDuration: min(max(rawDuration, 2), stabilizationElapsed) };
}

function appliedStartupCatchUp(samples, correction) {
  if (!samples.length) return samples;
  const first = samples[0], output = copy(samples);
  let lastCorrectedIndex;
  for (let i = 0; i < samples.length; i++) {
    const elapsed = samples[i].elapsed - first.elapsed;
    if (!(elapsed < correction.stabilizationElapsed - 0.000001)) break;
    output[i].speedMetersPerSecond = elapsed > 0
      ? elapsed < correction.rampDuration
        ? BASE + (correction.targetSpeed - BASE) * Math.pow(elapsed / correction.rampDuration, 1 / EXPONENT)
        : correction.targetSpeed : BASE;
    lastCorrectedIndex = i;
  }
  if (!present(lastCorrectedIndex) || lastCorrectedIndex + 1 >= output.length) return output;
  const anchor = lastCorrectedIndex + 1, startDistance = first.distanceMeters ?? 0;
  if (!present(output[anchor].distanceMeters)) return output;
  const covered = output[anchor].distanceMeters - startDistance;
  if (!(covered > EPSILON)) return output;
  const integrals = new Array(anchor + 1).fill(0);
  for (let i = 1; i <= anchor; i++) {
    const dt = output[i].elapsed - output[i - 1].elapsed;
    integrals[i] = integrals[i - 1];
    if (dt > 0) integrals[i] += ((output[i - 1].speedMetersPerSecond ?? BASE)
      + (output[i].speedMetersPerSecond ?? correction.targetSpeed)) / 2 * dt;
  }
  const total = integrals[anchor];
  if (!(total > EPSILON)) return output;
  const scale = covered / total;
  for (let i = 0; i <= lastCorrectedIndex; i++) output[i].distanceMeters = startDistance + integrals[i] * scale;
  return output;
}

export function motionResumptionCorrections(samples) {
  if (samples.length <= 4) return [];
  const first = samples[0], last = samples.at(-1);
  const deviceSpeed = i => finite(samples[i].speedMetersPerSecond) ? max(0, samples[i].speedMetersPerSecond) : 0;
  const segmentSpeed = i => i > 0 && present(samples[i].distanceMeters) && present(samples[i - 1].distanceMeters)
    && samples[i].elapsed - samples[i - 1].elapsed > 0
    ? (samples[i].distanceMeters - samples[i - 1].distanceMeters) / (samples[i].elapsed - samples[i - 1].elapsed) : undefined;
  const corrections = [];
  let index = samples.findIndex(s => s.elapsed - first.elapsed > STARTUP_WINDOW);
  if (index < 0) index = samples.length;
  while (index < samples.length) {
    while (index < samples.length && deviceSpeed(index) >= 2) index++;
    if (index >= samples.length) break;
    const quietStart = index;
    while (index < samples.length && deviceSpeed(index) < 2) index++;
    if (index >= samples.length) break;
    const quietEnd = index - 1;
    if (!(samples[quietEnd].elapsed - samples[quietStart].elapsed >= 5)) continue;
    let stabilization;
    for (let probe = index; probe + 2 < samples.length && samples[probe].elapsed - samples[quietEnd].elapsed <= STARTUP_WINDOW; probe++) {
      const v0 = deviceSpeed(probe), v1 = deviceSpeed(probe + 1), v2 = deviceSpeed(probe + 2);
      if (v0 >= 2.5 && Math.abs(v1 - v0) <= TOLERANCE && Math.abs(v2 - v1) <= TOLERANCE) { stabilization = probe; break; }
    }
    if (!present(stabilization)) continue;
    const targetSpeed = plausible(samples[stabilization].speedMetersPerSecond);
    if (!present(targetSpeed)) continue;
    const persistenceEnd = samples[stabilization].elapsed + 5;
    if (!(last.elapsed >= persistenceEnd)) continue;
    let persistent = true, check = stabilization;
    while (check < samples.length && samples[check].elapsed <= persistenceEnd) {
      if (deviceSpeed(check) < targetSpeed * 0.8) { persistent = false; break; }
      check++;
    }
    if (!persistent) continue;
    let anchor = quietEnd;
    while (anchor > quietStart && present(segmentSpeed(anchor)) && segmentSpeed(anchor) >= 2.5) anchor--;
    const anchorElapsed = samples[anchor].elapsed, stabilizationElapsed = samples[stabilization].elapsed;
    const duration = stabilizationElapsed - anchorElapsed;
    if (!(duration > 1) || samples.slice(anchor, stabilization + 1).some(s => s.hasSyntheticDistance) || !(duration <= STARTUP_WINDOW * 2)) continue;
    const baseSpeed = max(deviceSpeed(anchor), BASE);
    if (!(targetSpeed / max(baseSpeed, MOVING) >= RATIO)) continue;
    let previousSpeed = 0, monotone = true;
    for (let candidate = anchor + 1; candidate <= stabilization; candidate++) {
      const speed = deviceSpeed(candidate);
      if (!(speed >= MOVING)) continue;
      if (speed < previousSpeed - TOLERANCE) { monotone = false; break; }
      previousSpeed = speed;
    }
    if (!monotone) continue;
    let evidence = false;
    for (let candidate = anchor + 1; candidate <= stabilization; candidate++) {
      const segment = segmentSpeed(candidate), device = max(deviceSpeed(candidate), MOVING);
      if (!present(segment) || !(segment >= RATIO * device)) continue;
      if ((samples[candidate].cadence ?? 0) >= 140) { evidence = true; break; }
      const horizon = samples[candidate].elapsed + 3;
      let follower = candidate;
      while (follower + 1 < samples.length && samples[follower + 1].elapsed <= horizon) follower++;
      if (follower > candidate && present(samples[follower].distanceMeters) && present(samples[candidate].distanceMeters)
        && samples[follower].elapsed > samples[candidate].elapsed
        && (samples[follower].distanceMeters - samples[candidate].distanceMeters)
          / (samples[follower].elapsed - samples[candidate].elapsed) >= 2.5) { evidence = true; break; }
    }
    if (!evidence || !present(samples[anchor].distanceMeters) || !present(samples[stabilization].distanceMeters)) continue;
    const covered = samples[stabilization].distanceMeters - samples[anchor].distanceMeters;
    if (!(covered > EPSILON)) continue;
    let integral = 0;
    for (let candidate = anchor + 1; candidate <= stabilization; candidate++) {
      const dt = samples[candidate].elapsed - samples[candidate - 1].elapsed;
      if (dt > 0) integral += (deviceSpeed(candidate - 1) + deviceSpeed(candidate)) / 2 * dt;
    }
    if (!(covered > 1.2 * integral)) continue;
    const exponent = 1 / EXPONENT, coefficient = (targetSpeed - baseSpeed) * (1 - 1 / (exponent + 1));
    if (!(coefficient > 0)) continue;
    const rawDuration = (targetSpeed * duration - covered) / coefficient;
    corrections.push({ anchorElapsed, stabilizationElapsed, baseSpeed, targetSpeed,
      rampDuration: min(max(rawDuration, 2), duration) });
    index = max(check, stabilization + 1);
  }
  return corrections;
}

function appliedMotionResumptions(samples, corrections) {
  if (!corrections.length) return samples;
  const output = copy(samples);
  for (const correction of corrections) {
    let anchor = -1;
    for (let i = output.length - 1; i >= 0; i--) if (output[i].elapsed <= correction.anchorElapsed + 0.0005) { anchor = i; break; }
    const stabilization = output.findIndex(s => s.elapsed >= correction.stabilizationElapsed - 0.0005);
    if (anchor < 0 || stabilization < 0 || !(anchor < stabilization)) continue;
    output[anchor].speedMetersPerSecond = correction.baseSpeed;
    for (let i = anchor + 1; i < stabilization; i++) {
      const time = output[i].elapsed - correction.anchorElapsed;
      output[i].speedMetersPerSecond = time > 0
        ? time < correction.rampDuration
          ? correction.baseSpeed + (correction.targetSpeed - correction.baseSpeed) * Math.pow(time / correction.rampDuration, 1 / EXPONENT)
          : correction.targetSpeed : correction.baseSpeed;
    }
    if (!present(output[anchor].distanceMeters) || !present(output[stabilization].distanceMeters)) continue;
    const covered = output[stabilization].distanceMeters - output[anchor].distanceMeters;
    if (!(covered > EPSILON)) continue;
    const span = stabilization - anchor, integrals = new Array(span + 1).fill(0);
    for (let offset = 1; offset <= span; offset++) {
      const i = anchor + offset, dt = output[i].elapsed - output[i - 1].elapsed;
      integrals[offset] = integrals[offset - 1];
      if (dt > 0) integrals[offset] += ((output[i - 1].speedMetersPerSecond ?? correction.baseSpeed)
        + (output[i].speedMetersPerSecond ?? correction.targetSpeed)) / 2 * dt;
    }
    const total = integrals[span];
    if (!(total > EPSILON)) continue;
    const scale = covered / total;
    for (let offset = 1; offset < span; offset++) output[anchor + offset].distanceMeters = output[anchor].distanceMeters + integrals[offset] * scale;
  }
  return output;
}

function shouldApplyStartupCumulativeSmoothing(samples, firstElapsed, protectedIndex) {
  if (shouldReplaceSpeed(samples[0]?.speedMetersPerSecond)) return true;
  const targetSpeed = plausible(samples[protectedIndex]?.speedMetersPerSecond);
  if (protectedIndex < samples.length && present(targetSpeed)) {
    for (let i = 0; i < min(3, protectedIndex); i++) {
      const speed = plausible(samples[i].speedMetersPerSecond);
      if (present(speed) && max(speed, targetSpeed) / max(min(speed, targetSpeed), 0.000001) >= RATIO) return true;
    }
  }
  if (present(samples[0]?.speedMetersPerSecond) && samples[0].speedMetersPerSecond <= BASE * 2) {
    for (const sample of samples.slice(0, protectedIndex)) {
      const elapsed = sample.elapsed - firstElapsed, distance = sample.distanceMeters, speed = sample.speedMetersPerSecond;
      if (!(elapsed > 0 && elapsed <= STARTUP_WINDOW && present(distance) && distance > EPSILON && finite(speed))) continue;
      const cumulative = distance / elapsed;
      if (finite(cumulative) && cumulative >= MOVING && speed / cumulative >= 2) return true;
    }
  }
  let previousSpeed, previousCumulative;
  for (const sample of samples.slice(0, protectedIndex)) {
    const elapsed = sample.elapsed - firstElapsed, distance = sample.distanceMeters, speed = sample.speedMetersPerSecond;
    if (!(elapsed > 0 && elapsed <= STARTUP_WINDOW && present(distance) && distance > EPSILON && finite(speed))) continue;
    const cumulative = distance / elapsed;
    if (!finite(cumulative) || !(cumulative >= MOVING)) continue;
    if (present(previousSpeed) && present(previousCumulative) && Math.abs(speed - previousSpeed) <= TOLERANCE
      && cumulative > previousCumulative + TOLERANCE) return true;
    previousSpeed = speed;
    previousCumulative = cumulative;
  }
  return false;
}

function smoothedStartupPace(samples, protectedElapsed) {
  if (samples.length <= 1 || !((samples[0].distanceMeters ?? 0) <= EPSILON)) return samples;
  const firstElapsed = samples[0].elapsed, protectedIndex = protectedStartIndex(samples, protectedElapsed);
  if (!(protectedIndex > 0) || samples.slice(0, protectedIndex).some(s => s.hasSyntheticDistance)
    || !shouldApplyStartupCumulativeSmoothing(samples, firstElapsed, protectedIndex)) return samples;
  const output = copy(samples);
  let lastSpeed, firstSpeed, firstIndex;
  for (let i = 0; i < protectedIndex; i++) {
    const elapsed = samples[i].elapsed - firstElapsed, distance = samples[i].distanceMeters;
    if (!(elapsed > 0 && elapsed <= STARTUP_WINDOW && present(distance) && distance > EPSILON)) continue;
    const cumulative = distance / elapsed;
    if (!finite(cumulative) || !(cumulative >= MOVING && cumulative <= 12)) continue;
    const speed = max(lastSpeed ?? BASE, cumulative);
    output[i].speedMetersPerSecond = speed;
    lastSpeed = speed;
    if (!present(firstSpeed)) { firstSpeed = speed; firstIndex = i; }
  }
  if (present(firstSpeed)) {
    const startSpeed = min(firstSpeed, max(BASE, firstSpeed * 0.25));
    output[0].speedMetersPerSecond = startSpeed;
    if (present(firstIndex) && firstIndex > 0) {
      const targetElapsed = max(samples[firstIndex].elapsed - firstElapsed, 0.000001);
      for (let i = 1; i < firstIndex; i++) output[i].speedMetersPerSecond = startSpeed
        + (firstSpeed - startSpeed) * Math.pow(clamp((samples[i].elapsed - firstElapsed) / targetElapsed), EXPONENT);
    }
  }
  return output;
}

function distanceSpeed(samples, start, end) {
  if (start < 0 || end >= samples.length || !(start < end)
    || samples.slice(start, end + 1).some(s => s.hasSyntheticDistance)
    || !present(samples[start].distanceMeters) || !present(samples[end].distanceMeters)) return undefined;
  const elapsed = samples[end].elapsed - samples[start].elapsed, distance = samples[end].distanceMeters - samples[start].distanceMeters;
  return elapsed > 0 && distance > EPSILON ? distance / elapsed : undefined;
}
function interpolateSpeeds(samples, start, target, speed, replaceStart, replaceEnd) {
  if (start < 0 || target >= samples.length || !(start < target) || !finite(samples[start].speedMetersPerSecond)) return samples;
  const output = copy(samples), startElapsed = samples[start].elapsed;
  const span = max(samples[target].elapsed - startElapsed, 0.000001), startSpeed = samples[start].speedMetersPerSecond;
  for (let i = replaceStart; i <= replaceEnd; i++) if (i > start && i < output.length) {
    output[i].speedMetersPerSecond = startSpeed + (speed - startSpeed)
      * Math.pow(clamp((samples[i].elapsed - startElapsed) / span), EXPONENT);
  }
  return output;
}
function smoothedEdgeSpeedPlateaus(samples, protectedElapsed) {
  if (samples.length <= 2) return samples;
  const protectedIndex = protectedStartIndex(samples, protectedElapsed), firstElapsed = samples[0].elapsed;
  let output = samples, index = 0;
  while (index < min(protectedIndex, output.length - 1)) {
    if (output[index].elapsed - firstElapsed > STARTUP_WINDOW) break;
    const runSpeed = output[index].speedMetersPerSecond;
    if (!finite(runSpeed)) { index++; continue; }
    let end = index;
    while (end + 1 < protectedIndex && output[end + 1].elapsed - firstElapsed <= STARTUP_WINDOW
      && finite(output[end + 1].speedMetersPerSecond) && Math.abs(output[end + 1].speedMetersPerSecond - runSpeed) <= TOLERANCE) end++;
    if (end > index && end + 1 < output.length && finite(output[end + 1].speedMetersPerSecond)
      && output[end + 1].speedMetersPerSecond > runSpeed + TOLERANCE) {
      const nextSpeed = output[end + 1].speedMetersPerSecond;
      const candidate = end + 1 >= protectedIndex ? nextSpeed : max(nextSpeed, distanceSpeed(output, index, end + 1) ?? nextSpeed);
      const speed = plausible(candidate), replaceEnd = min(end, protectedIndex - 1);
      if (present(speed) && replaceEnd >= index + 1) output = interpolateSpeeds(output, index, end + 1, speed, index + 1, replaceEnd);
    }
    index = max(end + 1, index + 1);
  }
  const first = output[0], last = output.at(-1), lastSpeed = last.speedMetersPerSecond;
  if (!(last.elapsed - first.elapsed > STARTUP_WINDOW) || !finite(lastSpeed)) return output;
  let start = output.length - 1;
  while (start > 0 && last.elapsed - output[start - 1].elapsed <= STARTUP_WINDOW
    && finite(output[start - 1].speedMetersPerSecond) && Math.abs(output[start - 1].speedMetersPerSecond - lastSpeed) <= TOLERANCE) start--;
  if (!(start < output.length - 1 && start > 0)) return output;
  const targetSpeed = plausible(distanceSpeed(output, start - 1, output.length - 1));
  if (!present(targetSpeed) || !(Math.abs(targetSpeed - lastSpeed) > TOLERANCE)) return output;
  let evidence = false;
  if (lastSpeed > 0 && start - 1 >= 0) for (let i = start; i < output.length; i++) {
    if (!present(output[i - 1].distanceMeters) || !present(output[i].distanceMeters)) continue;
    const dt = output[i].elapsed - output[i - 1].elapsed;
    if (!(dt >= 1 - 0.001)) continue;
    const speed = (output[i].distanceMeters - output[i - 1].distanceMeters) / dt;
    if (max(speed, lastSpeed) / max(min(speed, lastSpeed), 0.000001) >= RATIO) { evidence = true; break; }
  }
  return evidence ? interpolateSpeeds(output, start - 1, output.length - 1, targetSpeed, start, output.length - 1) : output;
}

function enrichedWithStartupCadence(samples, catchUp) {
  if (samples.length <= 1) return samples;
  const first = samples[0], targetIndex = samples.findIndex(s => (s.cadence ?? 0) > 0);
  if (targetIndex <= 0) return samples;
  const target = samples[targetIndex];
  if (!present(target.cadence) || !(target.cadence > 0 && target.elapsed > first.elapsed)) return samples;
  for (let i = 1; i <= targetIndex; i++) if (segmentBreak(samples[i - 1], samples[i])) return samples;
  if (!samples.slice(0, targetIndex).every(s => (s.cadence ?? 0) <= 0)) return samples;
  const output = copy(samples);
  const cadenceAt = elapsed => {
    const progress = catchUp ? clamp((elapsed - first.elapsed) / catchUp.rampDuration)
      : clamp((elapsed - first.elapsed) / max(target.elapsed - first.elapsed, 0.000001));
    return max(0, round(target.cadence * (catchUp ? Math.pow(progress, 1 / EXPONENT) : progress)));
  };
  for (let i = 0; i < targetIndex; i++) output[i].cadence = cadenceAt(output[i].elapsed);
  const required = Math.ceil(target.elapsed - first.elapsed) - 1, available = max(0, MAX_SAMPLES - output.length);
  if (!finite(required) || !(required <= available)) return output;
  for (let elapsed = first.elapsed + 1; elapsed < target.elapsed; elapsed += 1) {
    if (!output.some(s => Math.abs(s.elapsed - elapsed) < 0.000001)) {
      const sample = sampleAtActiveElapsed(samples, elapsed);
      sample.cadence = cadenceAt(elapsed);
      output.push(sample);
    }
  }
  return sortSamples(output);
}

function enrichedWithTotalAscent(samples) {
  if (!samples.some(s => finite(s.altitudeMeters))) return samples;
  let reference, previous, total = 0;
  return samples.map(input => {
    const sample = { ...input };
    if (previous && segmentBreak(previous, input)) reference = undefined;
    previous = input;
    const altitude = input.sourceAltitudeMeters ?? input.altitudeMeters;
    if (finite(altitude)) {
      if (present(reference)) {
        const delta = altitude - reference;
        if (delta >= 1) { total += delta; reference = altitude; }
        else if (delta < 0) reference = altitude;
      } else reference = altitude;
    }
    sample.totalAscentMeters = total;
    return sample;
  });
}

function trimmedIncompleteTail(samples) {
  if (samples.length <= 1) return samples;
  const threshold = max(1, Math.ceil(samples.length * 0.5));
  const predicates = [s => present(s.latitude) && present(s.longitude), s => present(s.heartRate), s => present(s.cadence),
    s => finite(s.distanceMeters), s => finite(s.speedMetersPerSecond)];
  const required = predicates.filter(test => samples.filter(test).length >= threshold);
  if (!required.length) return samples;
  const complete = sample => required.every(test => test(sample));
  const motion = i => finite(samples[i].speedMetersPerSecond) && samples[i].speedMetersPerSecond >= MOVING
    || i > 0 && present(samples[i].distanceMeters) && present(samples[i - 1].distanceMeters)
      && samples[i].distanceMeters - samples[i - 1].distanceMeters > EPSILON;
  let last = samples.length - 1;
  while (last > 0 && !complete(samples[last]) && !motion(last)) last--;
  const output = copy(samples.slice(0, last + 1));
  let lastComplete = output.length - 1;
  while (lastComplete > 0 && !complete(output[lastComplete])) lastComplete--;
  for (let i = lastComplete + 1; i < output.length; i++) {
    if (!present(output[i].heartRate)) output[i].heartRate = output[i - 1].heartRate;
    if (!present(output[i].cadence)) output[i].cadence = output[i - 1].cadence;
  }
  return output;
}

function computeBounds(samples) {
  let minLatitude = Number.MAX_VALUE, maxLatitude = -Number.MAX_VALUE;
  let minLongitude = Number.MAX_VALUE, maxLongitude = -Number.MAX_VALUE, found = false;
  for (const sample of samples) {
    if (!present(sample.latitude) || !present(sample.longitude)) continue;
    minLatitude = min(minLatitude, sample.latitude); maxLatitude = max(maxLatitude, sample.latitude);
    minLongitude = min(minLongitude, sample.longitude); maxLongitude = max(maxLongitude, sample.longitude);
    found = true;
  }
  return found ? { minLatitude, maxLatitude, minLongitude, maxLongitude } : undefined;
}

export function createNativeSeries(samples, pausedRanges = []) {
  const pauses = sanitizedPausedRanges(pausedRanges);
  const sorted = sortSamples(samples.map(s => ({ ...s, hasSyntheticDistance: s.hasSyntheticDistance ?? false })));
  const normal = normalized(sorted), completeIndex = firstStartupCompleteSampleIndex(normal);
  const completeElapsed = completeIndex < 0 ? undefined : normal[completeIndex].elapsed;
  const catchUp = startupCatchUpCorrection(normal);
  const enriched = enrichedWithDistanceDerivedSpeed(normal);
  const stabilized = stabilizedStartupSpeedJumps(enriched, completeElapsed);
  const resamples = resampled(stabilized);
  const startup = catchUp ? appliedStartupCatchUp(resamples, catchUp) : smoothedStartupPace(resamples, completeElapsed);
  const resumed = appliedMotionResumptions(startup, motionResumptionCorrections(normal));
  const edges = smoothedEdgeSpeedPlateaus(resumed, completeElapsed);
  const cadence = enrichedWithStartupCadence(edges, catchUp);
  const result = trimmedIncompleteTail(enrichedWithTotalAscent(cadence));
  const series = { samples: result, pausedRanges: pauses, bounds: computeBounds(result),
    activeDuration: result.length ? max(0, result.at(-1).elapsed - result[0].elapsed) : 0,
    totalDistanceMeters: result.at(-1)?.distanceMeters ?? 0 };
  series.duration = wallElapsed(series, series.activeDuration);
  const dated = result.find(s => present(s.date));
  series.activityStartDate = dated ? addingDate(dated.date, -wallElapsed(series, dated.elapsed)) : undefined;
  return series;
}

export function correctingRunningDecelerations(samples) {
  const output = copy(samples);
  let index = 5;
  while (index + 12 < samples.length) {
    const start = index++;
    const speed = samples[start].speedMetersPerSecond, futureSpeed = samples[start + 2].speedMetersPerSecond;
    if (!(samples[start].elapsed - samples[0].elapsed > STARTUP_WINDOW)
      || !present(speed) || !(speed >= 3) || !present(futureSpeed) || !(futureSpeed <= speed - 0.3)) continue;
    let valid = true;
    for (let i = start - 5; i <= start + 12; i++) {
      const sample = samples[i];
      if (sample.hasSyntheticDistance || !finite(sample.elapsed) || !finite(sample.speedMetersPerSecond)
        || !(sample.speedMetersPerSecond >= 0) || !finite(sample.distanceMeters) || !(sample.distanceMeters >= 0) || !finite(sample.date)) { valid = false; break; }
      if (i === start - 5) continue;
      const previous = samples[i - 1];
      if (!(sample.speedMetersPerSecond >= MOVING || sample.distanceMeters <= previous.distanceMeters + EPSILON)
        || segmentBreak(previous, sample) || !(Math.abs(sample.elapsed - previous.elapsed - 1) < 0.001)
        || !(Math.abs(sample.date - previous.date - 1) < 0.001) || !(sample.distanceMeters >= previous.distanceMeters)) { valid = false; break; }
    }
    if (!valid) continue;
    for (let i = start + 1; i <= start + 12; i++) if (!(samples[i].speedMetersPerSecond <= samples[i - 1].speedMetersPerSecond + 0.05)) { valid = false; break; }
    if (!valid) continue;
    const distanceSpeedAt = i => (samples[i].distanceMeters - samples[i - 2].distanceMeters) / 2;
    const previousReference = distanceSpeedAt(start - 3), reference = distanceSpeedAt(start), nextReference = distanceSpeedAt(start + 1);
    const nextSpeed = samples[start + 1].speedMetersPerSecond;
    if (!(previousReference >= 3 && max(reference, nextReference) <= previousReference - 1
      && reference <= speed * 0.8 && nextReference <= nextSpeed * 0.8
      && speed - reference >= 0.5 && nextSpeed - nextReference >= 0.5)) continue;
    let release = start + 10;
    for (let i = start + 4; i <= start + 10; i++) {
      if (samples[i].speedMetersPerSecond <= 2 || Math.abs(samples[i].speedMetersPerSecond - distanceSpeedAt(i)) <= 0.3
        && Math.abs(samples[i - 1].speedMetersPerSecond - distanceSpeedAt(i - 1)) <= 0.3) { release = i; break; }
    }
    const end = release + 2;
    for (let i = start; i <= end; i++) output[i].speedMetersPerSecond = samples[i + min(min(2, i - start), end - i)].speedMetersPerSecond;
    index = end + 1;
  }
  return output;
}
