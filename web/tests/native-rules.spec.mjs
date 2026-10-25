import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { isAbsolute } from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { createDocument, createElement, gauges, presets, parseDocument } from '../model.mjs';
import { genericRGBToSRGB } from '../render-color.mjs';

async function upload(page, source) {
  await page.locator('#file').setInputFiles({ name: 'native-regression.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(source)) });
}
async function download(page) {
  const pending = page.waitForEvent('download'); await page.locator('#download').click();
  return parseDocument(await readFile(await (await pending).path(), 'utf8'));
}
function documentWith(...elements) {
  const source = createDocument('Native rendering regression', true); source.layout.elements = elements; return source;
}
function positioned(kind) {
  const element = createElement(kind);
  Object.assign(element.frame, { x: 0.15, y: 0.2, scale: 0.55 });
  return element;
}
async function logicalBox(locator) {
  return locator.evaluate(node => Object.fromEntries(['x', 'y', 'width', 'height'].map(k => [k, node[k].baseVal.value])));
}
async function edit(page, id, value) {
  await page.locator(id).fill(String(value)); await page.locator(id).press('Tab');
}
async function applyCustomization(page, customization) {
  await page.locator('#advanced').evaluate(node => { node.open = true; });
  await page.locator('#custom-json').fill(JSON.stringify(customization));
  await page.locator('#advanced button').first().click();
}
async function textOverflow(page, selector = '#canvas [data-index="0"]') {
  return page.locator(selector).evaluate(async group => {
    const hit = group.querySelector('.hit').getBBox(), tolerance = 2, overflow = [];
    // SVG getBBox includes font cell whitespace; native bounds enclose painted glyphs.
    for (const node of group.querySelectorAll('text')) {
      const b = node.getBBox(), x = Math.floor(b.x) - 2, y = Math.floor(b.y) - 2;
      const canvas = document.createElement('canvas');
      canvas.width = Math.ceil(b.x + b.width) - x + 2; canvas.height = Math.ceil(b.y + b.height) - y + 2;
      const image = new Image(), xml = `<svg xmlns="http://www.w3.org/2000/svg" width="${canvas.width}" height="${canvas.height}" viewBox="${x} ${y} ${canvas.width} ${canvas.height}">${node.outerHTML}</svg>`;
      await new Promise((resolve, reject) => { image.onload = resolve; image.onerror = reject; image.src = `data:image/svg+xml,${encodeURIComponent(xml)}`; });
      const context = canvas.getContext('2d'); context.drawImage(image, 0, 0);
      const rgba = context.getImageData(0, 0, canvas.width, canvas.height).data;
      let outside = false, painted = false;
      for (let row = 0; row < canvas.height && !outside; row++) for (let column = 0; column < canvas.width; column++) {
        if (rgba[(row * canvas.width + column) * 4 + 3] <= 8) continue;
        painted = true;
        const px = x + column + 0.5, py = y + row + 0.5;
        if (px < hit.x - tolerance || py < hit.y - tolerance || px > hit.x + hit.width + tolerance || py > hit.y + hit.height + tolerance) { outside = true; break; }
      }
      if (node.textContent.trim() && !painted) throw new Error('Text rasterization produced no visible pixels');
      if (outside) overflow.push(node.textContent);
    }
    return overflow;
  });
}

for (const { kind } of gauges) {
  test(`${kind}: native artwork, dynamic hit bounds, drag, resize, undo and visibility`, async ({ page }) => {
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    const source = documentWith(positioned(kind));
    await page.goto('./?lang=en'); await upload(page, source);
    const group = page.locator('#canvas [data-index="0"]'), hit = group.locator('.hit');
    await expect(group).toBeVisible(); await expect(group.locator('text,path,rect,circle,ellipse,line').nth(1)).toBeAttached();
    expect(await textOverflow(page)).toEqual([]);
    const initial = await logicalBox(hit);
    expect(initial.width).toBeGreaterThan(0); expect(initial.height).toBeGreaterThan(0);
    await hit.scrollIntoViewIfNeeded();
    let box = await hit.boundingBox();
    await page.mouse.move(box.x + 8, box.y + 8); await page.mouse.down();
    await page.mouse.move(box.x + 28, box.y + 23, { steps: 3 }); await page.mouse.up();
    const afterDrag = await logicalBox(hit);
    expect(afterDrag.x).toBeGreaterThan(initial.x); expect(afterDrag.y).toBeGreaterThan(initial.y);
    const handle = page.locator('[data-resize]'); await handle.scrollIntoViewIfNeeded(); box = await handle.boundingBox();
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2); await page.mouse.down();
    await page.mouse.move(box.x + box.width / 2 + 24, box.y + box.height / 2 + 16, { steps: 3 }); await page.mouse.up();
    const resized = await logicalBox(hit);
    expect(resized.width).toBeGreaterThan(afterDrag.width);
    const output = await download(page), edited = output.layout.elements[0];
    expect(edited.customization).toEqual(source.layout.elements[0].customization);
    expect(edited.frame.scale).toBeGreaterThan(source.layout.elements[0].frame.scale);
    await page.locator('#undo').click(); expect((await logicalBox(hit)).width).toBeCloseTo(afterDrag.width, 4);
    await page.locator('#undo').click(); expect((await logicalBox(hit)).x).toBeCloseTo(initial.x, 4);
    await page.locator('#field-inspector-visible').uncheck(); await expect(group).toHaveCount(0);
    await expect(page.locator('[data-resize]')).toBeVisible();
    await page.locator('#undo').click(); await expect(group).toBeVisible();
    expect(errors).toEqual([]);
  });
}

test('timeDate renders three native rows with a common right edge and real baselines', async ({ page }) => {
  const e = positioned('timeDate'); e.frame.scale = 1;
  await page.goto('./?lang=en'); await upload(page, documentWith(e));
  const rows = await page.locator('#canvas [data-index="0"] text').evaluateAll(nodes => nodes.map(node => {
    const x = node.x.baseVal[0].value, y = node.y.baseVal[0].value, length = node.getComputedTextLength();
    const anchor = getComputedStyle(node).textAnchor;
    return { text: node.textContent, right: x + (anchor === 'end' ? 0 : anchor === 'middle' ? length / 2 : length), y, baseline: getComputedStyle(node).dominantBaseline };
  }));
  expect(rows.map(r => r.text)).toEqual(['00:42:48', '07:32:18', '2026/10/25']);
  expect(rows[0].right).toBeCloseTo(e.frame.x * 1920 + 300, 1);
  for (const row of rows) { expect(row.right).toBeCloseTo(rows[0].right, 1); expect(row.baseline).not.toBe('middle'); }
  expect(rows[1].y).toBeGreaterThan(rows[0].y); expect(rows[2].y).toBeGreaterThan(rows[1].y);
});

test('metric baselines follow CoreText coordinates and lengthScale preserves glyph width', async ({ page }) => {
  const e = positioned('heartRate'); e.frame.scale = 1;
  await page.goto('./?lang=en'); await upload(page, documentWith(e));
  const value = page.locator('#canvas [data-index="0"] text').filter({ hasText: /^148$/ });
  const label = page.locator('#canvas [data-index="0"] text').filter({ hasText: /^HR$/ });
  expect(await label.evaluate(n => n.y.baseVal[0].value)).toBeCloseTo(216 + 9 + 10 * 0.78, 4);
  expect(await value.evaluate(n => n.y.baseVal[0].value)).toBeCloseTo(216 + 74 - 14 - 23.92 * 0.24, 4);
  const before = await value.boundingBox();
  await edit(page, '#field-inspector-length', 0.4);
  const after = await value.boundingBox(); expect(after.width).toBeCloseTo(before.width, 3); expect(after.height).toBeCloseTo(before.height, 3);
  expect(await textOverflow(page)).toEqual([]);
});

test('macOS: all five font faces keep their native measured tile dimensions', async ({ page }) => {
  test.skip(process.platform !== 'darwin', 'Native reference dimensions require the macOS system fonts');
  const e = positioned('heartRate'); Object.assign(e.frame, { x: 0.2, y: 0.2, scale: 1 });
  Object.assign(e.customization, { labelOverride: 'WIDE METRIC 123', labelScale: 2.4, valueScale: 1.4, unitScale: 2.4 });
  await page.goto('./?lang=en'); await upload(page, documentWith(e));
  // Fixed OverlayRenderer/CoreText bounds measured on 2026-10-25 at 1920 × 1080.
  const native = [
    ['helveticaNeue', 230.704, 85.2], ['helveticaNeueBold', 238.624, 85.2],
    ['menloBold', 244.73828125, 85.2], ['avenirNextCondensedHeavy', 208.24, 85.2],
    ['futuraCondensedExtraBold', 214.1171875, 85.2],
  ];
  for (const [font, width, height] of native) {
    for (const field of ['labelFont', 'valueFont', 'unitFont']) await page.locator(`#field-inspector-${field}`).selectOption(font);
    await page.evaluate(async () => { await document.fonts.ready; });
    await expect.poll(async () => {
      const b = await logicalBox(page.locator('#canvas [data-index="0"] .hit'));
      return Math.max(Math.abs(b.width - width), Math.abs(b.height - height));
    }, { message: `${font} must use the native face and keep width/height within .25px` }).toBeLessThan(0.25);
  }
});

test('font and accent selectors persist string enums, preserve other fields and support undo/redo', async ({ page }) => {
  const e = positioned('heartRate'); e.customization.labelOverride = 'Keep this label';
  const source = documentWith(e); source.futureMetadata = { keep: 'selector regression' };
  await page.goto('./?lang=en'); await upload(page, source);
  const choices = { labelFont: 'helveticaNeue', valueFont: 'futuraCondensedExtraBold', unitFont: 'menloBold', accent: 'amber' };
  for (const [field, value] of Object.entries(choices)) {
    await page.locator(`#field-inspector-${field}`).selectOption(value);
    await expect(page.locator('#status'), `${field} must accept its string enum`).not.toHaveClass(/error/);
  }
  await page.locator('#global-details').evaluate(node => { node.open = true; });
  const globalAccent = page.locator('#field-global-fields-accent');
  await globalAccent.selectOption('cleanWhite');
  await expect(page.locator('#status'), 'global accent must accept its string enum').not.toHaveClass(/error/);
  const output = await download(page), edited = output.layout.elements[0];
  for (const field of ['labelFont', 'valueFont', 'unitFont']) expect(edited.customization[field]).toBe(choices[field]);
  expect(edited.frame.style.accentColor).toBe('amber'); expect(output.layout.style.accentColor).toBe('cleanWhite');
  const preserved = structuredClone(output);
  preserved.updatedAt = source.updatedAt; preserved.layout.style.accentColor = source.layout.style.accentColor;
  preserved.layout.elements[0].frame.style.accentColor = e.frame.style.accentColor;
  for (const field of ['labelFont', 'valueFont', 'unitFont']) preserved.layout.elements[0].customization[field] = e.customization[field];
  expect(preserved).toEqual(source);
  await page.locator('#undo').click();
  await expect(globalAccent).toHaveValue(source.layout.style.accentColor);
  expect((await download(page)).layout.elements[0]).toEqual(edited);
  await page.locator('#redo').click();
  await expect(globalAccent).toHaveValue('cleanWhite');
  expect((await download(page)).layout.style.accentColor).toBe('cleanWhite');
  await expect(page.locator('#status')).not.toHaveClass(/error/);
});

test('macOS: weather cloud keeps the native glyph ink size rather than a smaller fallback', async ({ page }) => {
  test.skip(process.platform !== 'darwin', 'Native weather glyph reference requires macOS system fonts');
  const e = positioned('weather'); e.frame.scale = 1; e.frame.style.textScale = 1;
  e.customization.iconFont = 'helveticaNeueBold'; e.customization.iconScale = 2; e.customization.iconOverride = 'clouds';
  await page.goto('./?lang=en'); await upload(page, documentWith(e));
  const icon = page.locator('#canvas text').filter({ hasText: /^☁︎$/ });
  await expect(icon).toHaveAttribute('font-family', /^DLS Weather W6,/);
  const ink = await icon.evaluate(async node => {
    await document.fonts.ready;
    const canvas = document.createElement('canvas'); canvas.width = 128; canvas.height = 100;
    const context = canvas.getContext('2d');
    context.font = `${node.getAttribute('font-weight')} ${node.getAttribute('font-size')}px ${node.getAttribute('font-family')}`;
    context.fillText(node.textContent, 40, 70);
    const pixels = context.getImageData(0, 0, 128, 100).data, xs = [], ys = [];
    for (let y = 0; y < 100; y++) for (let x = 0; x < 128; x++) if (pixels[(y * 128 + x) * 4 + 3] > 16) { xs.push(x); ys.push(y); }
    return { width: Math.max(...xs) - Math.min(...xs) + 1, height: Math.max(...ys) - Math.min(...ys) + 1 };
  });
  // CoreText's 32pt cloud ink measures 29.6 × 20.192px before antialiasing.
  expect(ink.width).toBeGreaterThanOrEqual(29); expect(ink.width).toBeLessThanOrEqual(33);
  expect(ink.height).toBeGreaterThanOrEqual(20); expect(ink.height).toBeLessThanOrEqual(23);
  expect((await download(page)).layout.elements[0]).toEqual(e);
});

test('long visible text expands aligned hit bounds and resizing one tile preserves its sibling', async ({ page }) => {
  const heart = positioned('heartRate'), pace = positioned('pace'); pace.frame.y = 0.5;
  await page.goto('./?lang=en'); await upload(page, documentWith(heart, pace));
  const hits = page.locator('#canvas .hit'), initial = await logicalBox(hits.nth(0));
  await edit(page, '#field-inspector-label', 'Long translated label 超长标签 長いラベル');
  await edit(page, '#field-inspector-labelScale', 3);
  const wider = await logicalBox(hits.nth(0)), sibling = await logicalBox(hits.nth(1));
  expect(wider.width).toBeGreaterThan(initial.width); expect(wider.width).toBeCloseTo(sibling.width, 4);
  expect(await textOverflow(page)).toEqual([]);
  await edit(page, '#field-inspector-scale', 1.1);
  // Native fonts round to .01pt; browser hinting can change normalized width by a fraction of a pixel.
  expect(Math.abs((await logicalBox(hits.nth(1))).width - sibling.width)).toBeLessThan(0.25);
  await page.locator('#layers .layer-name').nth(1).click();
  await expect(page.locator('#canvas [data-index="1"]')).toHaveAttribute('aria-pressed', 'true');
  await hits.nth(0).scrollIntoViewIfNeeded();
  const box = await hits.nth(0).boundingBox();
  await page.mouse.click(box.x + box.width - 5, box.y + box.height / 2);
  await expect(page.locator('#canvas [data-index="0"]')).toHaveAttribute('aria-pressed', 'true');
});

test('large special-gauge text stays within the bounds used by selection and resizing', async ({ page }) => {
  await page.goto('./?lang=en');
  for (const kind of ['speed', 'route', 'altitudeProfile', 'topProgress', 'timeDate']) {
    const e = positioned(kind);
    Object.assign(e.customization, { labelOverride: 'Custom long title 长标题', unitOverride: 'LONG UNIT / KM', labelScale: 3, valueScale: 3, unitScale: 3, showsPanel: false });
    await upload(page, documentWith(e));
    expect(await textOverflow(page), kind).toEqual([]);
    const hit = await logicalBox(page.locator('#canvas .hit'));
    const selection = await page.locator('#canvas > g[pointer-events="none"] > rect').evaluate(n => Object.fromEntries(['x', 'y', 'width', 'height'].map(k => [k, n[k].baseVal.value])));
    expect(selection).toEqual(hit);
  }
});

test('weather icon, humidity, manual data and Alpha survive rendering and export', async ({ page }) => {
  const e = positioned('weather');
  Object.assign(e.customization, { manualWeatherTemperatureCelsius: -8, manualWeatherHumidityPercent: 19, iconOverride: 'snow', iconColor: { red: 1, green: 0, blue: 0, alpha: 0.25 }, showsWeatherHumidity: true });
  const source = documentWith(e);
  await page.goto('./?lang=en'); await upload(page, source);
  const group = page.locator('#canvas [data-index="0"]');
  await expect(group.locator('text').filter({ hasText: /^-8℃$/ })).toHaveCount(1);
  await expect(group.locator('text').filter({ hasText: /^19%$/ })).toHaveCount(1);
  const icon = group.locator('text').filter({ hasText: /^❄/ });
  // CoreGraphics GenericRGB pure red converts to sRGB (1, .1491003, 0).
  await expect(icon).toHaveCSS('fill', 'rgba(255, 38, 0, 0.25)');
  const tempY = await group.locator('text').filter({ hasText: /^-8℃$/ }).evaluate(n => n.y.baseVal[0].value);
  const iconY = await icon.evaluate(n => n.y.baseVal[0].value);
  expect(Math.abs(iconY - tempY)).toBeLessThan(10);
  expect(await download(page)).toEqual(source);
  await applyCustomization(page, { ...e.customization, showsWeatherHumidity: false });
  await expect(group.locator('text').filter({ hasText: /^19%$/ })).toHaveCount(0);
});

test('color picker displays sRGB, writes native RGB and preserves alpha and unknown fields', async ({ page }) => {
  const e = positioned('heartRate'); e.customization.valueColor = { red: 0.2, green: 0.4, blue: 0.6, alpha: 0.35 };
  e.customization.futureColorSetting = { keep: 'customization metadata' };
  const source = documentWith(e); source.futureMetadata = { keep: ['document metadata'] };
  await page.goto('./?lang=en'); await upload(page, source);
  const input = page.locator('#field-inspector-valueColor'), displayed = genericRGBToSRGB(e.customization.valueColor);
  const hex = '#' + ['red', 'green', 'blue'].map(key => Math.round(displayed[key] * 255).toString(16).padStart(2, '0')).join('');
  await expect(input).toHaveValue(hex);
  expect(await download(page), 'viewing the picker must not rewrite native colors').toEqual(source);
  // Set the HTML color value and its standard change event without opening a native picker dialog.
  await input.evaluate(node => { node.value = '#77aacc'; node.dispatchEvent(new Event('change', { bubbles: true })); });
  await input.press('Tab');
  await expect(input).toHaveValue('#77aacc');
  const fill = await page.locator('#canvas [data-index="0"] text').filter({ hasText: /^148$/ }).evaluate(node => getComputedStyle(node).fill);
  const channels = fill.match(/^rgba\(([^)]+)\)$/)?.[1].split(',').map(Number);
  expect(channels).toBeDefined();
  for (const [index, expected] of [119, 170, 204].entries()) expect(Math.abs(channels[index] - expected)).toBeLessThanOrEqual(1);
  expect(channels[3]).toBe(0.35);
  const output = await download(page), native = output.layout.elements[0].customization.valueColor;
  const roundTrip = genericRGBToSRGB(native);
  for (const [index, key] of ['red', 'green', 'blue'].entries()) expect(Math.abs(roundTrip[key] * 255 - [119, 170, 204][index])).toBeLessThan(0.1);
  expect(native.alpha).toBe(0.35);
  output.updatedAt = source.updatedAt; output.layout.elements[0].customization.valueColor = e.customization.valueColor;
  expect(output).toEqual(source);
});

test('global text scale updates native per-layer textScale with ratio and clamps', async ({ page }) => {
  const elements = ['heartRate', 'pace', 'cadence'].map(positioned);
  elements[0].frame.style.textScale = 0.8; elements[1].frame.style.textScale = 3.8; elements[2].frame.style.textScale = 0.15;
  elements[1].frame.y = 0.5; elements[2].frame.isVisible = false;
  await page.goto('./?lang=en'); await upload(page, documentWith(...elements));
  const value = page.locator('#canvas [data-index="0"] text').filter({ hasText: /^148$/ });
  const before = await value.evaluate(node => Number(node.getAttribute('font-size')));
  await page.locator('#global-details').evaluate(node => { node.open = true; });
  await edit(page, '#field-global-fields-textScale', 2);
  let output = await download(page);
  expect(output.layout.elements.map(e => e.frame.style.textScale)).toEqual([1.6, 4, 0.3]);
  expect(await value.evaluate(node => Number(node.getAttribute('font-size')))).toBeCloseTo(before * 2, 1);
  await edit(page, '#field-global-fields-textScale', 0.1);
  output = await download(page);
  expect(output.layout.elements.map(e => e.frame.style.textScale)).toEqual([0.1, 0.2, 0.1]);
});

test('altitude switches remove each decoration and cursor size is a diameter', async ({ page }) => {
  const e = positioned('altitudeProfile'); e.frame.scale = 1;
  Object.assign(e.customization, { altitudeCursorSize: 20, altitudeCursorColor: { red: 1, green: 0, blue: 1, alpha: 1 } });
  await page.goto('./?lang=en'); await upload(page, documentWith(e));
  const group = page.locator('#canvas [data-index="0"]');
  expect(await group.locator('circle').evaluateAll(nodes => Math.max(...nodes.map(n => n.r.baseVal.value * 2)))).toBeCloseTo(20, 4);
  const before = await group.locator('text').count();
  const customization = { ...e.customization, altitudeShowsMinMax: false, altitudeShowsDistanceLabels: false, altitudeShowsCursor: false, altitudeShowsFill: false, altitudeShowsGrid: false };
  await applyCustomization(page, customization);
  await expect(group.locator('circle')).toHaveCount(0); await expect(group.locator('line')).toHaveCount(0);
  await expect(group.locator('text')).toHaveCount(before - 4);
  const hit = await logicalBox(group.locator('.hit'));
  await applyCustomization(page, { ...customization, altitudeWidthScale: 1.5, altitudeHeightScale: 1.2 });
  const resized = await logicalBox(group.locator('.hit'));
  expect(resized.width).toBeCloseTo(hit.width * 1.5, 4); expect(resized.height).toBeCloseTo(hit.height * 1.2, 4);
});

test('long timeDate resize pins its measured top-left, follows the pointer and undoes the frame', async ({ page }) => {
  const e = positioned('timeDate'); e.frame.x = 0.45; e.frame.y = 0.15; e.customization.unitScale = 10;
  const source = documentWith(e);
  await page.goto('./?lang=en'); await upload(page, source);
  const hit = page.locator('#canvas [data-index="0"] .hit'), handle = page.locator('[data-resize]');
  await handle.scrollIntoViewIfNeeded();
  const before = await logicalBox(hit);
  expect(before.x, 'large clock text must expand left of the configured frame').toBeLessThan(e.frame.x * 1920);
  const box = await handle.boundingBox(), screenScale = await page.locator('#canvas').evaluate(node => {
    const matrix = node.getScreenCTM(); return { x: matrix.a, y: matrix.d };
  });
  const delta = { x: before.width * 0.15, y: before.height * 0.15 };
  const start = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
  // WebKit can quantize injected mouse coordinates; assert against delivered input.
  await page.locator('#canvas').evaluate(canvas => {
    for (const name of ['pointerdown', 'pointerup']) canvas.addEventListener(name, event => {
      const point = new DOMPoint(event.clientX, event.clientY).matrixTransform(canvas.getScreenCTM().inverse());
      canvas.dataset[name] = JSON.stringify({ x: point.x, y: point.y });
    }, { once: true });
  });
  await page.mouse.move(start.x, start.y); await page.mouse.down();
  await page.mouse.move(start.x + delta.x * screenScale.x, start.y + delta.y * screenScale.y, { steps: 5 });
  await page.mouse.up();
  const delivered = await page.locator('#canvas').evaluate(canvas => ({
    start: JSON.parse(canvas.dataset.pointerdown), end: JSON.parse(canvas.dataset.pointerup),
  }));
  const ratio = 1 + Math.max((delivered.end.x - delivered.start.x) / before.width, (delivered.end.y - delivered.start.y) / before.height);
  const after = await logicalBox(hit);
  expect(Math.abs(after.x - before.x)).toBeLessThan(1);
  expect(Math.abs(after.y - before.y)).toBeLessThan(1);
  // Remeasured fallback glyph widths are not strictly linear; allow less than one screen pixel.
  expect(Math.abs(after.width - before.width * ratio) * screenScale.x).toBeLessThan(1);
  expect(Math.abs(after.height - before.height * ratio) * screenScale.y).toBeLessThan(1);
  expect((await download(page)).layout.elements[0].frame.scale).toBeCloseTo(e.frame.scale * ratio, 6);
  await page.locator('#undo').click();
  expect((await download(page)).layout.elements[0].frame).toEqual(e.frame);
  const restored = await logicalBox(hit);
  for (const key of ['x', 'y', 'width', 'height']) expect(restored[key]).toBeCloseTo(before[key], 4);
});

test('optional private preset: readonly import, all presets render, export is unchanged', async ({ page }) => {
  const path = process.env.DLS_PRIVATE_PRESET;
  test.skip(!path, 'Set DLS_PRIVATE_PRESET to an absolute local preset path');
  expect(isAbsolute(path)).toBe(true);
  const source = parseDocument(await readFile(path, 'utf8'));
  const failures = []; page.on('pageerror', error => failures.push(error.message));
  const externalWrites = []; page.on('request', request => { if (!['GET', 'HEAD'].includes(request.method())) externalWrites.push(request.method()); });
  await page.goto('./?lang=en'); await upload(page, source);
  for (const preset of presets(source)) {
    if (presets(source).length > 1) await page.locator('#preset').selectOption(preset.id);
    await expect(page.locator('#canvas [data-index]')).toHaveCount(preset.layout.elements.filter(e => e.frame.isVisible).length);
    const geometryOK = await page.locator('#canvas .hit').evaluateAll(nodes => nodes.every(node => ['x', 'y', 'width', 'height'].every(k => Number.isFinite(node[k].baseVal.value)) && node.width.baseVal.value > 0 && node.height.baseVal.value > 0));
    expect(geometryOK).toBe(true);
  }
  if (presets(source).length > 1) await page.locator('#preset').selectOption(source.defaultPresetID ?? presets(source)[0].id);
  expect(isDeepStrictEqual(await download(page), source), 'Private preset export must preserve all imported content').toBe(true);
  expect(failures).toEqual([]); expect(externalWrites).toEqual([]);
});
