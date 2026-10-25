import { activeElapsed } from './telemetry-series.mjs?v=20261025-native-data';

// Mirrors TelemetrySeries.applyingQuantizedAltitudeDisplaySmoothing; FIT alone gates manufacturer 294.
export function applyingQuantizedAltitudeDisplaySmoothing(series) {
  const { samples, pausedRanges } = series;
  if (samples.length < 3) return series;
  const source = samples.map(sample => sample.sourceAltitudeMeters ?? sample.altitudeMeters);
  let count = 0, whole = 0;
  for (const altitude of source) if (Number.isFinite(altitude)) {
    count++;
    if (Math.abs(altitude - Math.round(altitude)) < 0.000001) whole++;
  }
  if (count < 3 || whole / count < 0.9) return series;

  const pauseBoundaries = pausedRanges.map(range => activeElapsed(series, range.start));
  const segments = []; let start, pauseIndex = 0;
  for (let index = 0; index < samples.length; index++) {
    if (!Number.isFinite(source[index])) {
      if (start !== undefined && start < index) segments.push([start,index]);
      start = undefined; continue;
    }
    if (start === undefined || index === 0) { start = index; continue; }
    const previous = samples[index - 1], current = samples[index];
    while (pauseIndex < pauseBoundaries.length && pauseBoundaries[pauseIndex] < previous.elapsed) pauseIndex++;
    const crossesPause = pauseIndex < pauseBoundaries.length && pauseBoundaries[pauseIndex] >= previous.elapsed && pauseBoundaries[pauseIndex] < current.elapsed;
    if (crossesPause) pauseIndex++;
    if ((previous.trackSegmentIndex ?? null) !== (current.trackSegmentIndex ?? null) || current.elapsed - previous.elapsed > 2 || crossesPause) {
      segments.push([start,index]); start = index;
    }
  }
  if (start !== undefined && start < samples.length) segments.push([start,samples.length]);
  const output = { ...series, samples:samples.map((sample,index) => Number.isFinite(source[index]) ? { ...sample, sourceAltitudeMeters:source[index] } : { ...sample }) };
  for (const [lower,upper] of segments) {
    if (upper - lower < 3) continue;
    for (let index = lower + 1; index < upper - 1; index++) {
      const raw = source[index], center = samples[index].elapsed;
      let weighted = raw * 5, total = 5;
      for (const direction of [-1,1]) {
        let cursor = index + direction, neighbors = 0;
        while (cursor >= lower && cursor < upper && neighbors < 64) {
          const distance = direction === -1 ? center - samples[cursor].elapsed : samples[cursor].elapsed - center;
          if (distance > 4) break;
          if (source[cursor] != null) { const weight = 5 - distance; weighted += source[cursor] * weight; total += weight; }
          neighbors++; cursor += direction;
        }
      }
      output.samples[index].altitudeMeters = Math.min(raw + 0.5, Math.max(raw - 0.5, weighted / total));
    }
  }
  return output;
}
