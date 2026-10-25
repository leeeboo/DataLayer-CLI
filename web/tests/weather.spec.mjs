import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { createDocument, createElement } from '../model.mjs';
import { languages, translations } from '../i18n.mjs';

const key = 'TEST_KEY_NOT_A_REAL_CREDENTIAL', origin = Date.parse('2026-01-01T00:00:00Z') / 1000;
const api = 'https://api.openweathermap.org/data/4.0/onecall/timeline/1h**';
const response = { data: [{ dt: origin, temp: 28.6, humidity: 65, weather: [{ main: 'Rain' }] }] };
const headers = { 'access-control-allow-origin': '*', 'content-type': 'application/json' };
function gpx(temperature = 12, location = true) {
  return `<gpx><trk><trkseg>${[0,2,4].map((elapsed, i) => `<trkpt${location ? ` lat="0" lon="${i * .0001}"` : ''}><time>2026-01-01T00:00:0${elapsed}Z</time><extensions><atemp>${temperature}</atemp><hr>${140 + i}</hr><speed>4</speed></extensions></trkpt>`).join('')}</trkseg></trk></gpx>`;
}
async function loadActivity(page, name = 'local.gpx', temperature = 12, location = true) {
  await page.locator('#activity-file').setInputFiles({ name, mimeType: 'application/gpx+xml', buffer: Buffer.from(gpx(temperature, location)) });
  await expect(page.locator('#activity-name')).toContainText(name);
}
async function setup(page, customization = {}) {
  await page.goto('./?lang=en');
  const source = createDocument('Weather regression', true);
  const weather = createElement('weather'); Object.assign(weather.customization, customization);
  source.layout.elements = [weather, createElement('heartRate')]; source.future = { preserved: true };
  await page.locator('#file').setInputFiles({ name: 'layout.dlspreset', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(source)) });
  await loadActivity(page);
  await page.locator('.weather-settings summary').click();
  await page.locator('#weather-key').fill(key);
  return source;
}
async function download(page) {
  const pending = page.waitForEvent('download'); await page.locator('#download').click();
  return JSON.parse(await readFile(await (await pending).path(), 'utf8'));
}
async function hasValue(page, value) {
  await expect(page.locator('#canvas [data-index="0"] text').filter({ hasText: new RegExp(`^${value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`) })).toHaveCount(1);
}

test('weather controls, help and disabled state work in all twelve languages on desktop and mobile', async ({ page }) => {
  const requests = []; page.on('request', request => { if (request.url().startsWith('https://api.openweathermap.org/')) requests.push(request.url()); });
  for (const language of Object.keys(languages)) {
    await page.goto(`./?lang=${language}`);
    const words = translations[language];
    await page.locator('.weather-settings summary').click();
    await expect(page.locator('.weather-settings summary')).toHaveText(words.weatherSettings);
    await expect(page.locator('#weather-help')).toHaveText(words.weatherHelp);
    await expect(page.locator('#weather-key')).toHaveAccessibleName(words.weatherKey);
    await expect(page.locator('#weather-key')).toHaveAttribute('type', 'password');
    await expect(page.locator('#weather-key')).toHaveValue('');
    await expect(page.locator('#load-weather')).toHaveText(words.weatherLoad);
    await expect(page.locator('#clear-weather')).toHaveText(words.weatherClear);
    await page.locator('#weather-key').fill(key);
    await expect(page.locator('#load-weather')).toBeDisabled();
    for (const viewport of [{ width: 1440, height: 1000 }, { width: 390, height: 844 }]) {
      await page.setViewportSize(viewport);
      expect(await page.evaluate(() => {
        const bounds = [...document.querySelectorAll('.weather-controls input,.weather-controls button')].map(node => node.getBoundingClientRect());
        return document.documentElement.scrollWidth > innerWidth + 1 || bounds.some(r => r.left < 0 || r.right > innerWidth + 1 || r.width < 30);
      })).toBe(false);
    }
  }
  await loadActivity(page, 'no-gps.gpx', 12, false);
  await expect(page.locator('#load-weather')).toBeDisabled();
  expect(requests).toEqual([]);
});

test('explicit load applies weather, reuses only page cache, preserves the template and clears the Key', async ({ page }) => {
  const requests = [], errors = []; page.on('pageerror', error => errors.push(error.message));
  await page.route(api, route => {
    const request = route.request(); requests.push(request);
    return route.fulfill({ headers, body: JSON.stringify(response) });
  });
  const source = await setup(page);
  await hasValue(page, '12℃'); expect(requests).toHaveLength(0);
  await page.locator('#load-weather').click(); await expect(page.locator('#weather-status')).toHaveText(translations.en.weatherLoaded);
  await hasValue(page, '29℃'); await hasValue(page, '65%');
  expect(requests).toHaveLength(1);
  const url = new URL(requests[0].url());
  expect(url.pathname).toBe('/data/4.0/onecall/timeline/1h');
  expect(Object.fromEntries(url.searchParams)).toEqual({ lat: '0', lon: '0', start: String(Math.floor(origin / 3600) * 3600), units: 'metric', lang: 'en', appid: key });
  expect(requests[0].headers()['referer']).toBeUndefined(); expect(requests[0].headers()['cookie']).toBeUndefined();
  await page.locator('#seek').evaluate(node => { node.value = '2'; node.dispatchEvent(new Event('input', { bubbles: true })); });
  await page.locator('#language').selectOption('fr'); await page.locator('#language').selectOption('en');
  expect(requests).toHaveLength(1);
  await page.locator('#weather-key').fill('CHANGED_TEST_KEY');
  await expect(page.locator('#weather-status')).toHaveText(translations.en.weatherLoaded);
  await page.locator('#load-weather').click(); await expect(page.locator('#weather-status')).toHaveText(translations.en.weatherCached);
  expect(requests).toHaveLength(1);
  await expect(page.locator('#undo')).toBeDisabled(); expect(await download(page)).toEqual(source);
  expect(await page.evaluate(() => JSON.stringify({ local: { ...localStorage }, session: { ...sessionStorage } }))).not.toContain(key);
  await page.locator('#clear-weather').click();
  await expect(page.locator('#weather-key')).toHaveValue(''); await expect(page.locator('#load-weather')).toBeDisabled();
  await expect(page.locator('#weather-status')).toHaveText(translations.en.weatherCleared); await hasValue(page, '12℃');
  expect(await download(page)).toEqual(source); expect(errors).toEqual([]);
  await page.reload(); await page.locator('.weather-settings summary').click();
  await expect(page.locator('#weather-key')).toHaveValue(''); expect(requests).toHaveLength(1);
});

test('authorization, quota, malformed and network errors retain the working weather without exposing raw errors', async ({ page }) => {
  let count = 0;
  await page.route(api, route => {
    count++;
    if (count === 1) return route.fulfill({ headers, body: JSON.stringify(response) });
    if (count === 5) return route.abort('failed');
    return route.fulfill({ status: count === 2 ? 401 : count === 3 ? 429 : 200, headers,
      body: count === 4 ? '{' : JSON.stringify({ message: `private-error ${key}` }) });
  });
  const source = await setup(page); await page.locator('#load-weather').click(); await hasValue(page, '29℃');
  for (const [language, error] of [['fr', 'weatherUnauthorized'], ['de', 'weatherQuota'], ['es', 'weatherInvalid'], ['ko', 'weatherNetworkError']]) {
    await page.locator('#language').selectOption(language); await page.locator('#load-weather').click();
    await expect(page.locator('#weather-status')).toHaveText(translations[language][error]);
    await hasValue(page, '29℃');
    await expect(page.locator('body')).not.toContainText('private-error'); await expect(page.locator('body')).not.toContainText(key);
    expect(await download(page)).toEqual(source);
  }
  expect(count).toBe(5);
});

test('clearing or replacing an activity discards in-flight responses and never paints old weather onto new data', async ({ page }) => {
  let started, release;
  const startedPromise = new Promise(resolve => { started = resolve; });
  const releasePromise = new Promise(resolve => { release = resolve; });
  await page.route(api, async route => {
    started(); await releasePromise;
    await route.fulfill({ headers, body: JSON.stringify(response) }).catch(() => {});
  });
  await setup(page); await page.locator('#load-weather').click(); await startedPromise;
  await expect(page.locator('#load-weather')).toHaveText(translations.en.weatherLoading);
  await loadActivity(page, 'replacement.gpx', 14);
  await expect(page.locator('#load-weather')).toHaveText(translations.en.weatherLoad);
  release(); await hasValue(page, '14℃');
  await page.locator('#clear-weather').click();
  await expect(page.locator('#weather-key')).toHaveValue(''); await hasValue(page, '14℃');
  await expect(page.locator('#undo')).toBeDisabled();
});

test('clearing the Key during a pending request cancels it and prevents a later overwrite', async ({ page }) => {
  let started, release;
  const startedPromise = new Promise(resolve => { started = resolve; });
  const releasePromise = new Promise(resolve => { release = resolve; });
  await page.route(api, async route => { started(); await releasePromise; await route.fulfill({ headers, body: JSON.stringify(response) }).catch(() => {}); });
  await setup(page); await page.locator('#load-weather').click(); await startedPromise;
  await page.locator('#clear-weather').click(); release();
  await expect(page.locator('#weather-key')).toHaveValue(''); await expect(page.locator('#load-weather')).toBeDisabled();
  await hasValue(page, '12℃'); await expect(page.locator('#weather-status')).toHaveText(translations.en.weatherCleared);
});

test('manual weather overrides retain native priority over the API and survive export', async ({ page }) => {
  await page.route(api, route => route.fulfill({ headers, body: JSON.stringify(response) }));
  const source = await setup(page, { manualWeatherTemperatureCelsius: 23, manualWeatherHumidityPercent: 72 });
  await page.locator('#load-weather').click(); await expect(page.locator('#weather-status')).toHaveText(translations.en.weatherLoaded);
  await hasValue(page, '23℃'); await hasValue(page, '72%');
  expect(await download(page)).toEqual(source);
});

test('weather connections are restricted to the official API host', async ({ page }) => {
  let disallowedRequest = false;
  await page.route('https://untrusted.invalid/**', route => { disallowedRequest = true; return route.fulfill({ headers, body: '{}' }); });
  await setup(page);
  await expect(page.locator('meta[http-equiv="Content-Security-Policy"]')).toHaveAttribute('content', /connect-src https:\/\/api\.openweathermap\.org;/);
  const blocked = await page.evaluate(async () => {
    try { await fetch('https://untrusted.invalid/not-a-real-key'); return false; } catch { return true; }
  });
  expect(blocked).toBe(true); expect(disallowedRequest).toBe(false);
});
