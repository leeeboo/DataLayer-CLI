import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { languages, translations } from '../i18n.mjs';
import { createDocument, createElement, parseDocument } from '../model.mjs';

function library() {
  const first = createDocument('Preserved preset'), second = createDocument('Editable preset');
  second.layout.elements = [createElement('speed'), createElement('weather')];
  second.layout.elements[0].customization.valueColor = { red: 0.1, green: 0.8, blue: 0.4, alpha: 0.35 };
  first.future = { untouched: true };
  return { presets: [first, second], defaultPresetID: second.id, futureMetadata: { version: 8 } };
}
async function upload(page, value) {
  await page.locator('#file').setInputFiles({ name: 'layout.dlspreset', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(value)) });
}
async function download(page) {
  const pending = page.waitForEvent('download');
  await page.locator('#download').click();
  const file = await pending;
  expect(file.suggestedFilename()).toBe('layout.json');
  return parseDocument(await readFile(await file.path(), 'utf8'));
}
for (const language of Object.keys(languages)) {
  test(`${language}: localized controls, errors and responsive layout`, async ({ page }) => {
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    const words = translations[language];
    await page.goto(`./?lang=${language}`);
    await expect(page.locator('h1')).toHaveText(words.title);
    await expect(page.locator('html')).toHaveAttribute('lang', language);
    await expect(page.locator('html')).toHaveAttribute('dir', language === 'ar' ? 'rtl' : 'ltr');
    await expect(page.locator('#language option')).toHaveCount(12);
    await expect(page.locator('#add-kind option')).toHaveCount(24);
    await expect(page.locator('#add-kind option[value=weather]')).toHaveText(words['gauge.weather']);
    await expect(page.locator('#canvas')).toHaveAttribute('direction', 'ltr');
    await expect(page.locator('#canvas-size')).toHaveCSS('direction', 'ltr');
    await expect(page.locator('#field-inspector-opacity')).toHaveValue('0.64');
    for (const viewport of [{ width: 1440, height: 1000 }, { width: 390, height: 844 }]) {
      await page.setViewportSize(viewport);
      const overflow = await page.evaluate(() => {
        const controls = [...document.querySelectorAll('.app-header button,.app-header select')];
        return { page: document.documentElement.scrollWidth > innerWidth + 1,
          header: controls.some(node => { const r = node.getBoundingClientRect(); return r.left < -1 || r.right > innerWidth + 1; }) };
      });
      expect(overflow).toEqual({ page: false, header: false });
    }
    await upload(page, { presets: [] });
    await expect(page.locator('#status')).toHaveText(`${words.invalid}: ${words.errorPresets}`);
    expect(errors).toEqual([]);
  });
}
test('switching all languages preserves the complete imported layout and Alpha', async ({ page }) => {
  await page.goto('./?lang=en'); const source = library(); await upload(page, source);
  for (const language of Object.keys(languages)) {
    await page.locator('#language').selectOption(language);
    expect(await download(page)).toEqual(source);
  }
});
test('import, edit, drag, resize, undo and export preserve unrelated data', async ({ page }) => {
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  await page.goto('./?lang=en'); const source = library(); await upload(page, source);
  const uploads = []; page.on('request', request => { if (request.method() !== 'GET') uploads.push(request.url()); });
  await page.locator('#field-inspector-x').fill('0.15'); await page.locator('#field-inspector-x').press('Tab');
  await expect(page.locator('#field-inspector-x')).toHaveValue('0.15');
  await page.locator('#undo').click(); await expect(page.locator('#field-inspector-x')).toHaveValue('0.025');
  await page.locator('#redo').click(); await expect(page.locator('#field-inspector-x')).toHaveValue('0.15');
  const gauge = await page.locator('#canvas [data-index="0"]').boundingBox();
  await page.mouse.move(gauge.x + 25, gauge.y + 25); await page.mouse.down();
  await page.mouse.move(gauge.x + 80, gauge.y - 10, { steps: 5 }); await page.mouse.up();
  const handle = await page.locator('[data-resize]').boundingBox();
  await page.mouse.move(handle.x + handle.width / 2, handle.y + handle.height / 2); await page.mouse.down();
  await page.mouse.move(handle.x + 35, handle.y + 20, { steps: 5 }); await page.mouse.up();
  expect(await page.locator('input:invalid').count()).toBe(0);
  await page.locator('#field-inspector-label').fill('Browser QA'); await page.locator('#field-inspector-label').press('Tab');
  const output = await download(page);
  expect(output.presets[0]).toEqual(source.presets[0]); expect(output.futureMetadata).toEqual(source.futureMetadata);
  const edited = output.presets[1].layout.elements[0];
  expect(edited.frame.x).toBeGreaterThan(0.15); expect(edited.frame.y).toBeLessThan(0.682); expect(edited.frame.scale).toBeGreaterThan(1);
  expect(edited.customization.labelOverride).toBe('Browser QA');
  expect(edited.customization.valueColor).toEqual(source.presets[1].layout.elements[0].customization.valueColor);
  expect(uploads).toEqual([]); expect(errors).toEqual([]);
});
test('invalid customization and invalid files do not replace edited work', async ({ page }) => {
  await page.goto('./?lang=fr'); const source = library(); await upload(page, source);
  await page.locator('#advanced summary').click();
  const original = await page.locator('#custom-json').inputValue();
  await page.locator('#custom-json').fill('{'); await page.locator('#advanced button').first().click();
  await expect(page.locator('#status')).toHaveText(`${translations.fr.jsonError}: ${translations.fr.errorJSON}`);
  await page.locator('#custom-json').fill(original); await page.locator('#advanced button').first().click();
  await upload(page, { presets: [] });
  await expect(page.locator('#layout-name')).toHaveValue('Editable preset');
  expect(await download(page)).toEqual(source);
});
