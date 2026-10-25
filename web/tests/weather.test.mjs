import test from 'node:test';
import assert from 'node:assert/strict';
import { loadWeatherRecords, weatherAnchor, clearWeatherCache, WeatherError } from '../weather.mjs';
import { applyingWeatherRecords, previewAt } from '../telemetry.mjs';
import { createNativeSeries } from '../telemetry-series.mjs';

const origin = 1700000000, key = 'TEST_KEY_NOT_A_REAL_CREDENTIAL';
const point = (dt = origin, values = {}) => ({ dt, temp: 28.6, humidity: 65, weather: [{ main: 'Rain' }], ...values });
function activity(samples = Array.from({ length: 5 }, (_, elapsed) => ({ elapsed, date: origin + elapsed, latitude: 0, longitude: 0,
  hasSyntheticDistance: false, distanceMeters: elapsed * 3, speedMetersPerSecond: 3, heartRate: 140, cadence: 180, temperatureCelsius: 12 })), pauses = []) {
  const series = createNativeSeries(samples, pauses);
  return { ...series, nativeSeries: series, sport: 'running', timeZoneOffsetSeconds: 0 };
}
function intercept(t, handler = () => ({ data: [point()] })) {
  const calls = [];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    calls.push({ url: new URL(url), options });
    const value = await handler(calls.length, options);
    return value instanceof Response ? value : new Response(JSON.stringify(value), { headers: { 'content-type': 'application/json' } });
  });
  return calls;
}
function code(expected) { return error => error instanceof WeatherError && error.code === expected && !error.message.includes(key); }
test.beforeEach(() => clearWeatherCache());

test('weather anchor requires a real timestamp and finite in-range activity GPS', async t => {
  const calls = intercept(t);
  for (const samples of [[], [{ date: origin }], [{ date: origin, latitude: 91, longitude: 0 }], [{ date: origin, latitude: 0, longitude: NaN }]]) {
    const source = { samples };
    assert.equal(weatherAnchor(source), undefined);
    await assert.rejects(loadWeatherRecords(source, key, 'en'), code('weatherNeedsLocation'));
  }
  for (const invalidKey of ['', '   ', '\nkey\u0000', 'x'.repeat(257)]) await assert.rejects(loadWeatherRecords(activity(), invalidKey, 'en'), code('weatherNeedsKey'));
  assert.equal(calls.length, 0);
});

test('hourly request matches native parameters, negative rounding and private request options', async t => {
  const calls = intercept(t, () => ({ data: [point(origin, { temp: -4.5 })], next: 'https://untrusted.invalid/next' }));
  const result = await loadWeatherRecords(activity(), `  ${key}  `, 'zh-CN');
  assert.deepEqual(result, { records: [{ timestamp: origin, temperatureCelsius: -5, humidityPercent: 65, summary: 'Rain' }], cached: false });
  assert.equal(calls.length, 1);
  const { url, options } = calls[0];
  assert.equal(url.origin + url.pathname, 'https://api.openweathermap.org/data/4.0/onecall/timeline/1h');
  assert.deepEqual(Object.fromEntries(url.searchParams), { lat: '0', lon: '0', start: String(Math.floor(origin / 3600) * 3600), units: 'metric', lang: 'zh_cn', appid: key });
  for (const [field, value] of Object.entries({ credentials: 'omit', referrerPolicy: 'no-referrer', redirect: 'error', cache: 'no-store' })) assert.equal(options[field], value);
});

test('late first response uses the native bounded twenty-hour fallback, with no pagination', async t => {
  const first = origin + 2 * 3600;
  const calls = intercept(t, count => ({ data: [point(count === 1 ? first : origin - 600)] }));
  const result = await loadWeatherRecords(activity(), key, 'en');
  assert.equal(calls.length, 2);
  assert.equal(calls[1].url.searchParams.get('start'), String(first - 20 * 3600));
  assert.deepEqual(result.records.map(record => record.timestamp), [first, origin - 600]);
});

test('ninety-minute fallback threshold is strict and cache excludes the API Key', async t => {
  const calls = intercept(t, () => ({ data: [point(origin + 90 * 60)] }));
  assert.equal((await loadWeatherRecords(activity(), key, 'zh-TW')).cached, false);
  assert.equal(calls[0].url.searchParams.get('lang'), 'zh_tw');
  assert.equal((await loadWeatherRecords(activity(), 'ANOTHER_TEST_KEY', 'zh-TW')).cached, true);
  assert.equal(calls.length, 1);
  clearWeatherCache();
  assert.equal((await loadWeatherRecords(activity(), key, 'pt-BR')).cached, false);
  assert.equal(calls[1].url.searchParams.get('lang'), 'pt_br');
});

test('small cache is bounded and a failed or empty response is never cached', async t => {
  const calls = intercept(t, count => ({ data: count === 1 ? [] : [point()] }));
  await assert.rejects(loadWeatherRecords(activity(), key, 'en'), code('weatherNoData'));
  await loadWeatherRecords(activity(), key, 'en');
  assert.equal(calls.length, 2);
  for (let i = 1; i <= 8; i++) {
    const source = activity(); source.nativeSeries.samples[0].latitude = i;
    await loadWeatherRecords(source, key, 'en');
  }
  assert.equal((await loadWeatherRecords(activity(), key, 'en')).cached, false);
  assert.equal(calls.length, 11);
});

for (const [status, expected] of [[401, 'weatherUnauthorized'], [429, 'weatherQuota'], [500, 'weatherRequestError'], [404, 'weatherRequestError']]) {
  test(`HTTP ${status} is a sanitized error, not weather data`, async t => {
    intercept(t, () => new Response(key, { status }));
    await assert.rejects(loadWeatherRecords(activity(), key, 'en'), code(expected));
  });
}
for (const [name, response] of [
  ['invalid syntax', '{'], ['wrong schema', '{}'], ['non-array data', '{"data":{}}'],
  ['missing timestamp', JSON.stringify({ data: [{}] })],
  ['invalid temperature', JSON.stringify({ data: [point(origin, { temp: '28' })] })],
  ['invalid humidity', JSON.stringify({ data: [point(origin, { humidity: 101 })] })],
  ['invalid weather conditions', JSON.stringify({ data: [point(origin, { weather: 'Rain' })] })],
  ['out-of-range timestamp', JSON.stringify({ data: [point(1e100)] })],
  ['too many records', JSON.stringify({ data: Array.from({ length: 1001 }, () => point()) })],
]) {
  test(`response validation rejects ${name}`, async t => {
    intercept(t, () => new Response(response));
    await assert.rejects(loadWeatherRecords(activity(), key, 'en'), code('weatherInvalid'));
  });
}

test('oversized responses are rejected using both declared and actual length', async t => {
  intercept(t, count => count === 1 ? new Response('', { headers: { 'content-length': '3000000' } }) : new Response(' '.repeat(2 * 1024 * 1024 + 1)));
  for (let i = 0; i < 2; i++) await assert.rejects(loadWeatherRecords(activity(), key, 'en'), code('weatherInvalid'));
});

test('network failures cannot expose a request URL or Key', async t => {
  intercept(t, () => { throw new Error(`https://example.invalid/?appid=${key}`); });
  await assert.rejects(loadWeatherRecords(activity(), key, 'en'), code('weatherNetworkError'));
});

test('aborting an in-flight request does not populate the cache', async t => {
  const calls = intercept(t, (count, options) => count > 1 ? { data: [point()] } : new Promise((resolve, reject) => {
    options.signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')), { once: true });
  }));
  const controller = new AbortController(), pending = loadWeatherRecords(activity(), key, 'en', controller.signal);
  controller.abort();
  await assert.rejects(pending, code('weatherCancelled'));
  assert.equal((await loadWeatherRecords(activity(), key, 'en')).cached, false);
  assert.equal(calls.length, 2);
});

test('native nearest-record semantics retain the first on ties and accept exactly six hours', () => {
  const source = activity(), saved = structuredClone(source);
  const before = { timestamp: origin - 3600, temperatureCelsius: 20, humidityPercent: 60, summary: 'Clouds' };
  const after = { timestamp: origin + 3600, temperatureCelsius: 30, humidityPercent: 80, summary: 'Rain' };
  const enriched = applyingWeatherRecords(source, [before, after]);
  assert.equal(previewAt(enriched, 0).sample.weatherTemperatureCelsius, 20);
  assert.equal(previewAt(enriched, 2).sample.weatherTemperatureCelsius, 30);
  assert.equal(applyingWeatherRecords(source, [{ ...before, timestamp: origin - 6 * 3600 }]).samples[0].weatherTemperatureCelsius, 20);
  assert.equal(applyingWeatherRecords(source, [{ ...before, timestamp: origin - 6 * 3600 - 1 }]).samples[0].weatherTemperatureCelsius, undefined);
  assert.deepEqual(source, saved);
  for (let i = 0; i < source.samples.length; i++) {
    const { weatherTemperatureCelsius, weatherHumidityPercent, weatherSummary, ...rest } = enriched.nativeSeries.samples[i];
    assert.deepEqual(rest, source.nativeSeries.samples[i]);
  }
  assert.equal(applyingWeatherRecords(source, []), source);
});

test('missing weather fields clear previous API values while retaining file temperature', () => {
  const source = activity(); Object.assign(source.nativeSeries.samples[0], { weatherTemperatureCelsius: 99, weatherHumidityPercent: 90, weatherSummary: 'Clear' });
  const result = applyingWeatherRecords(source, [{ timestamp: origin }]);
  assert.equal(result.samples[0].weatherTemperatureCelsius, undefined);
  assert.equal(result.samples[0].temperatureCelsius, 12);
  assert.equal(result.samples[0].weatherHumidityPercent, undefined);
  assert.equal(result.samples[0].weatherSummary, undefined);
});
