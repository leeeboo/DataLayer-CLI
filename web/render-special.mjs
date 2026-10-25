// CoreGraphics coordinates are retained; the host SVG helpers perform the canvas flip.
const clamp = (value, lower, upper) => Math.min(upper, Math.max(lower, value));
const finite = Number.isFinite;
const rounded = value => value < 0 ? -Math.round(-value) : Math.round(value);
const polyline = points => points.map((p, i) => `${i ? 'L' : 'M'} ${p.x} ${p.y}`).join(' ');

function includePoints(env, points, stroke = 0) {
  if (!points.length) return;
  const xs = points.map(p => p.x), ys = points.map(p => p.y), inset = stroke / 2;
  const x = Math.min(...xs), y = Math.min(...ys);
  env.addBounds({ x: x - inset, y: y - inset, width: Math.max(...xs) - x + stroke, height: Math.max(...ys) - y + stroke });
}

function drawSpeed(e, env) {
  const { r, s, t, c, C, sample, text, panel, circle, line, path, override, withAlpha } = env;
  const right = r.x + r.width, top = r.y + r.height;
  const size = (base, field, scale = s) => base * scale * (c[field] ?? 1);
  const lw = Math.max(0.25, (c.lineWidth ?? 1) * s);
  let out = panel(r, 20 * s);
  if (c.showsLabel) out += text(override(c.labelOverride, 'RUN'), r.x + 30 * s, top - 32 * s, size(15, 'labelScale'), C.label, c.labelFont);
  const seconds = Math.max(0, Math.floor(sample.elapsed));
  const elapsed = `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
  out += text(elapsed, r.x + 30 * s, top - 62 * s, size(24, 'unitScale', s * t), C.unit, c.unitFont);
  if (c.showsIcon) out += text(override(c.iconOverride, 'SPD'), right - 68 * s, top - 32 * s, size(13, 'iconScale'), C.icon, c.iconFont);

  const center = { x: r.x + 154 * s, y: r.y + 100 * s }, radius = 76 * s;
  const divisor = env.usesImperialMeasurements ? 1.609344 : 1;
  const minimumKmh = c.gaugeMinimum ?? 0, maximumKmh = Math.max(minimumKmh + 1, c.gaugeMaximum ?? 24);
  const minimum = minimumKmh / divisor, maximum = maximumKmh / divisor;
  const speed = Math.max(0, sample.speedMetersPerSecond ?? 0) * 3.6 / divisor;
  const progress = clamp((speed - minimum) / (maximum - minimum), 0, 1);
  const polar = (degrees, rad = radius) => ({ x: center.x + Math.cos(degrees * Math.PI / 180) * rad, y: center.y + Math.sin(degrees * Math.PI / 180) * rad });
  const arc = end => {
    const a = polar(224), b = polar(end);
    return `M ${a.x} ${a.y} A ${radius} ${radius} 0 ${224 - end > 180 ? 1 : 0} 0 ${b.x} ${b.y}`;
  };
  out += path(arc(-44), C.track, lw);
  if (progress > 0) out += path(arc(224 - 268 * progress), env.accent ?? C.value, lw);
  env.addBounds({ x: center.x - radius - lw / 2, y: center.y - radius - lw / 2, width: 2 * radius + lw, height: 2 * radius + lw });
  if (c.showsPanel && c.showsPanelBorder !== false) out += circle(center.x, center.y, radius - 22 * s, 'none', C.panelStroke, Math.max(0.5, lw * 0.12));
  if (c.showsLabel) {
    const edge = value => Math.abs(Math.round(value) - value) < 0.01 ? value.toFixed(0) : value.toFixed(1);
    out += text(override(c.labelOverride, 'SPEED'), center.x - 32 * s, center.y + 8 * s, size(12, 'labelScale'), C.label, c.labelFont);
    out += text(`${edge(minimum)}        ${edge(maximum)}`, center.x - 58 * s, center.y - 30 * s, size(12, 'unitScale'), C.unit, c.unitFont);
  }
  out += text(env.speedValue(sample.speedMetersPerSecond, e), r.x + 196 * s, r.y + 122 * s, size(76, 'valueScale', s * t), C.value, c.valueFont);
  if (c.showsUnit) out += text(override(c.unitOverride, env.usesImperialMeasurements ? 'MPH' : 'KM/H'), r.x + 252 * s, r.y + 67 * s, size(17, 'unitScale', s * t), C.unit, c.unitFont);
  if (env.showGaugeTicks ?? c.showGaugeTicks ?? env.layout?.style.showGaugeTicks) {
    const tickWidth = Math.max(0.8, lw * 0.12);
    for (let i = 0; i <= 12; i++) {
      const angle = 224 - 268 * i / 12, a = polar(angle, 79 * s), b = polar(angle, 91 * s);
      out += line(a.x, a.y, b.x, b.y, withAlpha(C.unit, 0.42), tickWidth);
      includePoints(env, [a, b], tickWidth);
    }
  }
  return out;
}

function drawRoute(e, env) {
  const { r, s, c, C, sample, series, text, panel, measure, path, circle, override, withAlpha } = env;
  let points = series.samples.filter(p => finite(p.latitude ?? p.lat) && finite(p.longitude ?? p.lon));
  if (points.length < 2) return '';
  const lat = p => p.latitude ?? p.lat, lon = p => p.longitude ?? p.lon;
  let minLat = Infinity, maxLat = -Infinity, minLon = Infinity, maxLon = -Infinity;
  for (const p of points) { minLat = Math.min(minLat, lat(p)); maxLat = Math.max(maxLat, lat(p)); minLon = Math.min(minLon, lon(p)); maxLon = Math.max(maxLon, lon(p)); }
  const latSpan = Math.max(maxLat - minLat, 0.000001), lonSpan = Math.max(maxLon - minLon, 0.000001);
  const limit = env.routePointLimit ?? 900;
  if (limit <= 0) return '';
  if (points.length > limit) {
    const source = points;
    points = limit === 1 ? [source[0]] : Array.from({ length: limit }, (_, i) => source[Math.round(i * (source.length - 1) / (limit - 1))]);
  }
  if (points.length < 2) return '';
  const map = { x: r.x + 26 * s, y: r.y + 34 * s, width: r.width - 52 * s, height: r.height - 68 * s };
  const aspect = lonSpan / latSpan;
  if (aspect > map.width / map.height) {
    const height = map.width / aspect;
    map.y += (map.height - height) / 2;
    map.height = height;
  } else {
    const width = map.height * aspect;
    map.x += (map.width - width) / 2;
    map.width = width;
  }
  const position = p => ({ x: map.x + (lon(p) - minLon) / lonSpan * map.width, y: map.y + (lat(p) - minLat) / latSpan * map.height });
  const routePath = values => values.map((p, i) => {
    const point = position(p), move = i === 0 || (p.trackSegmentIndex ?? null) !== (values[i - 1].trackSegmentIndex ?? null);
    return `${move ? 'M' : 'L'} ${point.x} ${point.y}`;
  }).join(' ');
  const countThrough = elapsed => {
    let lo = 0, hi = points.length;
    while (lo < hi) {
      const mid = Math.floor((lo + hi) / 2);
      if (points[mid].elapsed <= elapsed) lo = mid + 1;
      else hi = mid;
    }
    return lo;
  };
  const lw = Math.max(0.25, (c.lineWidth ?? 1) * s), top = r.y + r.height, right = r.x + r.width;
  let out = panel(r, 20 * s);
  if (c.showsLabel) out += text(override(c.labelOverride, 'GPS ROUTE'), r.x + 24 * s, top - 26 * s, 13 * s * (c.labelScale ?? 1), C.label, c.labelFont);
  if (c.showsIcon) out += text(override(c.iconOverride, 'GPS'), right - 70 * s, top - 26 * s, 12 * s * (c.iconScale ?? 1), C.icon, c.iconFont);
  if (c.showsUnit) {
    const value = env.distance(sample.distanceMeters, e), unit = override(c.unitOverride, env.distanceUnit(e));
    const unitSize = 10 * s * (c.unitScale ?? 1), valueSize = 18 * s * (c.valueScale ?? 1);
    const unitX = right - 24 * s - measure(unit, unitSize, c.unitFont), valueX = unitX - 7 * s - measure(value, valueSize, c.valueFont);
    out += text(value, valueX, top - 27 * s, valueSize, C.value, c.valueFont);
    out += text(unit, unitX, top - 27 * s, unitSize, C.unit, c.unitFont);
  }
  const full = routePath(points), glowWidth = Math.max(1, lw * 1.8);
  out += path(full, withAlpha(C.value, 0.16), glowWidth);
  out += path(full, withAlpha(C.track, 0.62), Math.max(0.5, lw * 0.82));
  includePoints(env, points.map(position), glowWidth);
  const elapsedCount = countThrough(sample.elapsed);
  if (elapsedCount > 1) out += path(routePath(points.slice(0, elapsedCount)), C.value, lw);
  if (finite(lat(sample)) && finite(lon(sample))) {
    const current = position(sample), ringWidth = Math.max(1, lw * 0.55);
    out += circle(current.x, current.y, 6 * s, withAlpha(C.value, 0.92));
    out += circle(current.x, current.y, 12 * s, 'none', C.value, ringWidth);
    env.addBounds({ x: current.x - 12 * s - ringWidth / 2, y: current.y - 12 * s - ringWidth / 2, width: 24 * s + ringWidth, height: 24 * s + ringWidth });
    let before = Math.max(0, countThrough(sample.elapsed - 2) - 1), after = Math.min(points.length - 1, countThrough(sample.elapsed + 2));
    if (before === after) { before = Math.max(0, before - 1); after = Math.min(points.length - 1, after + 1); }
    const a = position(points[before]), b = position(points[after]), dx = b.x - a.x, dy = b.y - a.y;
    if (before !== after && (points[before].trackSegmentIndex ?? null) === (points[after].trackSegmentIndex ?? null) && Math.hypot(dx, dy) > 1) {
      const angle = Math.atan2(dy, dx), ux = Math.cos(angle), uy = Math.sin(angle), length = Math.max(14 * s, lw * 1.7), width = length * 0.72;
      const base = { x: current.x + ux * 2 * s, y: current.y + uy * 2 * s };
      const triangle = [{ x: current.x + ux * length, y: current.y + uy * length }, { x: base.x - uy * width / 2, y: base.y + ux * width / 2 }, { x: base.x + uy * width / 2, y: base.y - ux * width / 2 }];
      out += path(`${polyline(triangle)} Z`, 'none', 0, C.value);
      includePoints(env, triangle);
    }
  }
  return out;
}

function altitudeGeometry(series) {
  if (series.samples.length < 2 || !finite(series.totalDistanceMeters) || series.totalDistanceMeters < 0) return null;
  let vertices = [];
  for (const sample of series.samples) {
    const distance = sample.distanceMeters, altitude = sample.altitudeMeters, last = vertices.at(-1);
    if (!finite(distance) || !finite(altitude) || distance < 0 || (last && distance < last.distanceMeters)) continue;
    const vertex = { distanceMeters: distance, altitudeMeters: altitude };
    if (last && Math.abs(distance - last.distanceMeters) <= 0.000001) vertices[vertices.length - 1] = vertex;
    else vertices.push(vertex);
  }
  if (vertices.length < 2) return null;
  const total = Math.max(series.totalDistanceMeters, vertices.at(-1).distanceMeters);
  if (total <= 0) return null;
  if (total > vertices.at(-1).distanceMeters + 0.000001) vertices.push({ distanceMeters: total, altitudeMeters: vertices.at(-1).altitudeMeters });
  let minimum = Infinity, maximum = -Infinity;
  for (const vertex of vertices) { minimum = Math.min(minimum, vertex.altitudeMeters); maximum = Math.max(maximum, vertex.altitudeMeters); }
  if (vertices.length > 4096) {
    const source = vertices;
    vertices = Array.from({ length: 4096 }, (_, i) => source[Math.round(i * (source.length - 1) / 4095)]);
  }
  const altitudeAt = distance => {
    if (!finite(distance)) return null;
    if (distance <= vertices[0].distanceMeters) return vertices[0].altitudeMeters;
    if (distance >= vertices.at(-1).distanceMeters) return vertices.at(-1).altitudeMeters;
    let lo = 0, hi = vertices.length - 1;
    while (lo + 1 < hi) {
      const mid = Math.floor((lo + hi) / 2);
      if (vertices[mid].distanceMeters <= distance) lo = mid;
      else hi = mid;
    }
    const a = vertices[lo], b = vertices[hi], span = b.distanceMeters - a.distanceMeters;
    const fraction = span > 0 ? clamp((distance - a.distanceMeters) / span, 0, 1) : 1;
    return a.altitudeMeters + (b.altitudeMeters - a.altitudeMeters) * fraction;
  };
  return { vertices, total, minimum, maximum, altitudeAt };
}

function drawAltitude(e, env) {
  const { r, s, t, c, C, sample, series, text, panel, measure, path, line, circle, rect, rgba, withAlpha, override } = env;
  const g = altitudeGeometry(series);
  if (!g || !finite(sample.distanceMeters)) return '';
  const sizeScale = Math.min(c.altitudeWidthScale ?? 1, c.altitudeHeightScale ?? 1), contentScale = s * sizeScale, textScale = contentScale * t;
  const padding = Math.max(8 * sizeScale, 24 * contentScale), headerHeight = Math.max(28 * sizeScale, 58 * contentScale);
  const leftAxis = c.altitudeShowsMinMax !== false ? Math.max(30 * sizeScale, 58 * contentScale) : 0;
  const bottomAxis = c.altitudeShowsDistanceLabels !== false ? Math.max(18 * sizeScale, 32 * contentScale) : 0;
  const chart = { x: r.x + padding + leftAxis, y: r.y + padding + bottomAxis, width: r.width - 2 * padding - leftAxis, height: r.height - 2 * padding - headerHeight - bottomAxis };
  if (chart.width < 2 || chart.height < 2) return '';
  let out = panel(r, 20 * contentScale);
  const span = Math.max(0.000001, Math.max(Math.max(0, g.maximum - g.minimum), c.altitudeMinimumRangeMeters ?? 50) * (1 + (c.altitudeVerticalPadding ?? 0.12) * 2));
  const visualMinimum = (g.minimum + g.maximum) / 2 - span / 2, currentDistance = clamp(sample.distanceMeters, 0, g.total);
  const position = (distance, altitude) => ({ x: chart.x + chart.width * clamp(distance / g.total, 0, 1), y: chart.y + chart.height * clamp((altitude - visualMinimum) / span, 0, 1) });
  const lw = Math.max(0.25, (c.lineWidth ?? 1) * contentScale);
  const color = (field, fallback) => rgba(c[field] ?? fallback);
  if (c.altitudeShowsGrid !== false) {
    const base = c.altitudeGridColor ?? { red: 1, green: 1, blue: 1, alpha: 0.22 };
    const gridColor = withAlpha(rgba(base), (base.alpha ?? 1) * (c.altitudeGridOpacity ?? 0.35));
    const rows = c.altitudeGridRows ?? 3, columns = c.altitudeGridColumns ?? 4;
    if (rows > 0) for (let i = 0; i <= rows; i++) { const y = chart.y + chart.height * i / rows; out += line(chart.x, y, chart.x + chart.width, y, gridColor, Math.max(1, contentScale), 'stroke-linecap="butt"'); }
    if (columns > 0) for (let i = 0; i <= columns; i++) { const x = chart.x + chart.width * i / columns; out += line(x, chart.y, x, chart.y + chart.height, gridColor, Math.max(1, contentScale), 'stroke-linecap="butt"'); }
  }
  const remaining = g.vertices.map(v => position(v.distanceMeters, v.altitudeMeters));
  out += path(polyline(remaining), color('altitudeRemainingColor', { red: 1, green: 1, blue: 1, alpha: 0.34 }), lw);
  includePoints(env, remaining, lw);
  const completed = [];
  for (let i = 0; i < g.vertices.length - 1; i++) {
    const a = g.vertices[i], b = g.vertices[i + 1];
    if (a.distanceMeters > currentDistance) break;
    if (!completed.length) completed.push(position(a.distanceMeters, a.altitudeMeters));
    const distanceSpan = b.distanceMeters - a.distanceMeters, fraction = distanceSpan > 0 ? clamp((currentDistance - a.distanceMeters) / distanceSpan, 0, 1) : 1;
    completed.push(position(a.distanceMeters + distanceSpan * fraction, a.altitudeMeters + (b.altitudeMeters - a.altitudeMeters) * fraction));
    if (fraction < 1) break;
  }
  if (completed.length >= 2) {
    if (c.altitudeShowsFill !== false) {
      const startX = Math.ceil(chart.x), endX = Math.floor(chart.x + chart.width), bottomY = Math.ceil(chart.y), topY = Math.floor(chart.y + chart.height);
      const width = endX - startX, height = topY - bottomY, fraction = clamp(currentDistance / g.total, 0, 1), completedX = Math.min(endX, startX + Math.ceil(fraction * width));
      const base = c.altitudeFillColor ?? { red: 0.16, green: 0.82, blue: 0.98, alpha: 1 };
      const fill = withAlpha(rgba(base), (base.alpha ?? 1) * (c.altitudeFillOpacity ?? 0.18));
      if (width > 0 && height > 0 && completedX > startX) {
        out += '<g shape-rendering="crispEdges">';
        for (let x = startX; x < completedX; x++) {
          const columnFraction = Math.min(fraction, (x - startX + 0.5) / width), altitude = g.altitudeAt(columnFraction * g.total);
          if (altitude == null) continue;
          const top = Math.min(topY, Math.max(bottomY, rounded(bottomY + height * clamp((altitude - visualMinimum) / span, 0, 1))));
          if (top > bottomY) out += rect({ x, y: bottomY, width: 1, height: top - bottomY }, 0, fill);
        }
        out += '</g>';
      }
    }
    out += path(polyline(completed), C.value, lw);
  }
  const currentAltitude = finite(sample.altitudeMeters) ? sample.altitudeMeters : g.altitudeAt(currentDistance);
  if (c.altitudeShowsCursor !== false && currentAltitude != null) {
    const diameter = Math.max(2, (c.altitudeCursorSize ?? 14) * contentScale), current = position(currentDistance, currentAltitude);
    out += circle(current.x, current.y, diameter / 2, color('altitudeCursorColor', { red: 1, green: 1, blue: 1, alpha: 1 }));
    env.addBounds({ x: current.x - diameter / 2, y: current.y - diameter / 2, width: diameter, height: diameter });
  }
  const headerBaseline = r.y + r.height - padding - 18 * textScale;
  if (c.showsLabel) out += text(override(c.labelOverride, 'ALTITUDE'), r.x + padding, headerBaseline, 16 * textScale * (c.labelScale ?? 1), C.label, c.labelFont);
  const elevation = meters => env.usesImperialMeasurements ? meters / 0.3048 : meters;
  const value = currentAltitude == null ? '--' : elevation(currentAltitude).toFixed(1), unit = c.showsUnit ? override(c.unitOverride, env.usesImperialMeasurements ? 'ft' : 'M') : '';
  const valueSize = 24 * textScale * (c.valueScale ?? 1), unitSize = 12 * textScale * (c.unitScale ?? 1);
  const valueWidth = measure(value, valueSize, c.valueFont), unitWidth = unit ? measure(unit, unitSize, c.unitFont) : 0, gap = unit ? Math.max(4 * sizeScale, 8 * contentScale) : 0;
  const valueX = r.x + r.width - padding - valueWidth - gap - unitWidth;
  out += text(value, valueX, headerBaseline, valueSize, C.value, c.valueFont);
  if (unit) out += text(unit, valueX + valueWidth + gap, headerBaseline, unitSize, C.unit, c.unitFont);
  const axisSize = Math.max(1, 11 * contentScale * (c.altitudeAxisLabelScale ?? 1));
  const rightText = (value, right, y) => text(value, right - measure(value, axisSize, c.unitFont), y, axisSize, C.unit, c.unitFont);
  if (c.altitudeShowsMinMax !== false) {
    const right = chart.x - Math.max(5 * sizeScale, padding / 4);
    out += rightText(elevation(g.maximum).toFixed(0), right, chart.y + chart.height - axisSize);
    out += rightText(elevation(g.minimum).toFixed(0), right, chart.y);
  }
  if (c.altitudeShowsDistanceLabels !== false) {
    const endDistance = g.total / (env.usesImperialMeasurements ? 1609.344 : 1000), symbol = env.usesImperialMeasurements ? 'MI' : 'KM';
    const baseline = chart.y - Math.max(4 * sizeScale, padding / 4) - axisSize;
    out += text(`0 ${symbol}`, chart.x, baseline, axisSize, C.unit, c.unitFont);
    out += rightText(`${endDistance.toFixed(endDistance >= 100 ? 0 : 1)} ${symbol}`, chart.x + chart.width, baseline);
  }
  return out;
}

export function drawSpecial(e, env) {
  if (e.kind === 'speed') return drawSpeed(e, env);
  if (e.kind === 'route') return drawRoute(e, env);
  if (e.kind === 'altitudeProfile') return drawAltitude(e, env);
  return null;
}
