import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { createDocument, createElement, parseDocument } from '../model.mjs';
import { translations } from '../i18n.mjs';

const requests = new WeakMap();
test.beforeEach(async ({ page, baseURL }) => {
  const failures = [];
  const allowedOrigin = new URL(baseURL).origin;
  requests.set(page, failures);
  page.on('request', request => {
    if (!['GET', 'HEAD'].includes(request.method())) failures.push(`${request.method()} ${request.url()}`);
    if (/^https?:/.test(request.url()) && new URL(request.url()).origin !== allowedOrigin)
      failures.push(`External request: ${request.url()}`);
  });
  page.on('pageerror', error => failures.push(error.message));
  await page.goto('./?lang=en');
});
test.afterEach(async ({ page }) => { expect(requests.get(page)).toEqual([]); });

function template(...kinds) {
  const source = createDocument('Local telemetry regression', true);
  source.layout.elements = kinds.map(createElement);
  for (const element of source.layout.elements) {
    if (element.kind === 'distance') Object.assign(element.customization, { distanceUnit: 'm', valuePrecision: 2 });
    if (element.kind === 'weather') element.customization.showsWeatherHumidity = true;
  }
  source.futureMetadata = { keep: 'Unrelated template content' };
  return source;
}
async function importTemplate(page, source) {
  await page.locator('#file').setInputFiles({ name: 'local.dlspreset', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(source)) });
  await expect(page.locator('#layout-name')).toHaveValue(source.name);
}
async function importActivity(page, xml, name = 'synthetic.gpx') {
  await page.locator('#activity-file').setInputFiles({ name, mimeType: 'application/gpx+xml', buffer: Buffer.from(xml) });
}
async function seek(page, seconds) {
  await page.locator('#seek').evaluate((node, value) => {
    node.value = String(value);
    node.dispatchEvent(new Event('input', { bubbles: true }));
  }, seconds);
}
function value(page, index, text) {
  return expect(page.locator(`#canvas [data-index="${index}"] text`).filter({ hasText: new RegExp(`^${text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`) })).toHaveCount(1);
}
async function downloaded(page) {
  const pending = page.waitForEvent('download');
  await page.locator('#download').click();
  const file = await pending;
  expect(file.suggestedFilename()).toBe('layout.dlspreset');
  return parseDocument(await readFile(await file.path(), 'utf8'));
}
function gpx(points, prefix = '') {
  const q = name => `${prefix}${name}`;
  const namespace = prefix ? `xmlns:${prefix.slice(0, -1)}` : 'xmlns';
  return `<?xml version="1.0"?><${q('gpx')} ${namespace}="http://www.topografix.com/GPX/1/1" xmlns:t="http://www.garmin.com/xmlschemas/TrackPointExtension/v1" xmlns:m="urn:synthetic:metrics" version="1.1" creator="Regression"><${q('trk')}><${q('type')}>running</${q('type')}><${q('trkseg')}>${points(q)}</${q('trkseg')}></${q('trk')}></${q('gpx')}>`;
}
function metricActivity(prefix = '') {
  return gpx(q => [
    ['2025-12-31T23:59:55-04:00', 140, 80, 2, 1000, -4],
    ['2026-01-01T04:00:05Z', 160, 90, 4, 1200, -6],
  ].map(([time, hr, cadence, speed, distance, temperature], i) =>
    `<${q('trkpt')} lat="0" lon="${i * .00001}"><${q('ele')}>${10 + i * 10}</${q('ele')}><${q('time')}>${time}</${q('time')}><${q('extensions')}><t:TrackPointExtension><t:hr>${hr}</t:hr><t:cad>${cadence}</t:cad><t:atemp>${temperature}</t:atemp></t:TrackPointExtension><m:speed>${speed}</m:speed><m:distance>${distance}</m:distance></${q('extensions')}></${q('trkpt')}>`).join(''), prefix);
}

for (const prefix of ['', 'g:']) {
  test(`GPX ${prefix ? 'prefixed' : 'default'} namespace shows real metrics, offset dates and seek interpolation`, async ({ page }) => {
    const source = template('heartRate', 'cadence', 'speed', 'weather', 'distance', 'timeDate');
    await importTemplate(page, source);
    await importActivity(page, metricActivity(prefix));
    await expect(page.locator('#activity-name')).toContainText('2 samples');
    await expect(page.locator('#seek')).toHaveAttribute('max', '10');
    await value(page, 0, '140'); await value(page, 1, '160'); await value(page, 2, '07.2');
    await value(page, 3, '-4℃'); await value(page, 4, '0.00');
    await value(page, 5, '23:59:55'); await value(page, 5, '2025/12/31');
    await seek(page, 2);
    await value(page, 0, '140'); await value(page, 1, '160'); await value(page, 2, '08.6');
    await value(page, 3, '-4℃'); await value(page, 4, '40.00');
    await seek(page, 5);
    await value(page, 5, '00:00:00'); await value(page, 5, '2026/01/01');
    await value(page, 4, '100.00');
    await seek(page, 10);
    await value(page, 0, '160'); await value(page, 1, '180'); await value(page, 2, '14.4');
    await value(page, 3, '-6℃'); await value(page, 4, '200.00');
    expect(await page.locator('#canvas [data-index="3"] text').allTextContents()).not.toContain('85%');
    expect((await page.locator('#canvas [data-index="3"] text').allTextContents()).some(text => text.endsWith('%'))).toBe(false);
    expect(await downloaded(page)).toEqual(source);
  });
}

test('separate GPX track segments hold metrics through gaps without adding connecting distance', async ({ page }) => {
  await importTemplate(page, template('heartRate', 'distance', 'route'));
  const xml = `<gpx xmlns="http://www.topografix.com/GPX/1/1"><trk>${[
    [[0, 0, 120], [2, .00001, 140]],
    [[10, .01, 180], [12, .01001, 200]],
  ].map(segment => `<trkseg>${segment.map(([seconds, lon, hr]) => `<trkpt lat="0" lon="${lon}"><time>2026-01-01T00:00:${String(seconds).padStart(2, '0')}Z</time><extensions><hr>${hr}</hr></extensions></trkpt>`).join('')}</trkseg>`).join('')}</trk></gpx>`;
  await importActivity(page, xml);
  await expect(page.locator('#activity-name')).toContainText('4 samples');
  await seek(page, 2); await value(page, 0, '140'); await value(page, 1, '1.11');
  await seek(page, 6); await value(page, 0, '140'); await value(page, 1, '1.11');
  await seek(page, 10); await value(page, 0, '180'); await value(page, 1, '1.11');
  await seek(page, 12); await value(page, 1, '2.22');
  const paths = await page.locator('#canvas [data-index="2"] path').evaluateAll(nodes => nodes.map(node => node.getAttribute('d')));
  expect(paths.some(path => (path.match(/M/g) ?? []).length >= 2)).toBe(true);
});

test('same-second GPX points retain geometry with millisecond ordering, not extra full seconds', async ({ page }) => {
  await importTemplate(page, template('heartRate', 'route'));
  const xml = gpx(q => [0, 0, 1].map((second, i) => `<${q('trkpt')} lat="0" lon="${i * .00001}"><${q('time')}>2026-01-01T00:00:0${second}Z</${q('time')}><${q('extensions')}><t:hr>${140 + i * 2}</t:hr></${q('extensions')}></${q('trkpt')}>`).join(''));
  await importActivity(page, xml);
  await expect(page.locator('#activity-name')).toContainText('3 samples');
  await expect(page.locator('#seek')).toHaveAttribute('max', '1');
  const times = await page.evaluate(async xml => {
    const { parseGPX } = await import('./telemetry.mjs?v=20261025-realpreview');
    return parseGPX(xml).samples.map(sample => sample.wallElapsed);
  }, xml);
  expect(times).toEqual([0, .001, 1]);
  await seek(page, 1); await value(page, 0, '144');
});

test('malformed, DOCTYPE, untimed and unsupported files preserve the valid activity and template', async ({ page }) => {
  const source = template('heartRate', 'distance');
  await importTemplate(page, source);
  await importActivity(page, metricActivity(), 'retained.gpx');
  await expect(page.locator('#activity-name')).toContainText('retained.gpx');
  await seek(page, 10);
  const invalid = [
    ['broken.gpx', '<gpx><trk><trkseg><trkpt></gpx>', 'activityMalformed'],
    ['doctype.gpx', '<!DOCTYPE gpx [<!ENTITY sample "unsafe">]><gpx><trk><trkseg><trkpt><time>2026-01-01T00:00:00Z</time></trkpt></trkseg></trk></gpx>', 'activityMalformed'],
    ['untimed.gpx', '<gpx><trk><trkseg><trkpt lat="0" lon="0"/></trkseg></trk></gpx>', 'activityMissingTime'],
    ['zoneless.gpx', '<gpx><trk><trkseg><trkpt><time>2026-01-01T00:00:00</time></trkpt></trkseg></trk></gpx>', 'activityMissingTime'],
    ['wrong-extension.txt', metricActivity(), 'activityUnsupported'],
  ];
  for (const [name, xml, message] of invalid) {
    await importActivity(page, xml, name);
    await expect(page.locator('#media-status')).toHaveClass(/error/);
    await expect(page.locator('#media-status')).toHaveText(translations.en[message]);
    await expect(page.locator('#activity-name')).toContainText('retained.gpx');
    await expect(page.locator('#seek')).toHaveValue('10');
    await value(page, 0, '160'); await value(page, 1, '200.00');
    expect(await downloaded(page), name).toEqual(source);
  }
});

test('local activity import, seek, replacement and removal leave the template clean and portable', async ({ page }) => {
  const source = template('heartRate', 'weather', 'timeDate');
  await importTemplate(page, source);
  const dialogs = [];
  page.on('dialog', async dialog => { dialogs.push(dialog.message()); await dialog.dismiss(); });
  for (const name of ['private-first.gpx', 'private-replacement.gpx']) {
    await importActivity(page, metricActivity(), name);
    await expect(page.locator('#activity-name')).toContainText(name);
    await seek(page, 5);
    await page.locator('#language').selectOption('fr'); await page.locator('#language').selectOption('en');
    await expect(page.locator('#status')).toHaveText(translations.en.ready);
    expect(await downloaded(page)).toEqual(source);
  }
  await page.locator('#remove-activity').click();
  await expect(page.locator('#seek')).toBeDisabled();
  await page.locator('#language').selectOption('fr'); await page.locator('#language').selectOption('en');
  await expect(page.locator('#status')).toHaveText(translations.en.ready);
  expect(await downloaded(page)).toEqual(source);
  await importTemplate(page, source);
  expect(dialogs).toEqual([]);
});

test('200,000-point route and altitude series render finite, bounded SVG without stack overflow', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { createDocument, createElement } = await import('./model.mjs?v=20261025-realpreview');
    const { renderLayout } = await import('./render.mjs?v=20261025-realpreview');
    const source = createDocument('Long synthetic activity', true);
    source.layout.elements = ['route', 'altitudeProfile'].map(createElement);
    const samples = Array.from({ length: 200000 }, (_, i) => ({ elapsed: i, wallElapsed: i, distanceMeters: i,
      latitude: i * .00000001, longitude: Math.sin(i / 1000) * .001, altitudeMeters: 10 + Math.sin(i / 1000), trackSegmentIndex: 0 }));
    return renderLayout(source.layout, 1920, 1080, { sample: samples[100000], series: { samples, totalDistanceMeters: 199999 } })
      .map(({ svg, bounds }) => ({ bytes: svg.length, paths: (svg.match(/<path\b/g) ?? []).length, invalid: /NaN|Infinity/.test(svg), bounds }));
  });
  expect(result).toHaveLength(2);
  for (const output of result) {
    expect(output.paths).toBeGreaterThan(0); expect(output.invalid).toBe(false);
    expect(output.bytes).toBeLessThan(2000000);
    expect(Object.values(output.bounds).every(Number.isFinite)).toBe(true);
    expect(output.bounds.width).toBeGreaterThan(0); expect(output.bounds.height).toBeGreaterThan(0);
  }
});
