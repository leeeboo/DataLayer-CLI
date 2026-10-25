// Matches the native hourly request and fallback; only explicit UI actions call this module.
const cache = new Map();
const endpoint = 'https://api.openweathermap.org/data/4.0/onecall/timeline/1h';
const rounded = value => value < 0 ? -Math.round(-value) : Math.round(value);
export class WeatherError extends Error {
  constructor(code) { super(code); this.name = 'WeatherError'; this.code = code; }
}
const fail = code => { throw new WeatherError(code); };

export function weatherAnchor(activity) {
  return (activity?.nativeSeries ?? activity)?.samples?.find(sample => Number.isFinite(sample.date)
    && Number.isFinite(sample.latitude) && Math.abs(sample.latitude) <= 90
    && Number.isFinite(sample.longitude) && Math.abs(sample.longitude) <= 180);
}
export function clearWeatherCache() { cache.clear(); }

export async function loadWeatherRecords(activity, apiKey, language, signal) {
  const anchor = weatherAnchor(activity);
  if (!anchor) fail('weatherNeedsLocation');
  const key = String(apiKey ?? '').trim();
  if (!key || key.length > 256 || /[\x00-\x1f\x7f]/.test(key)) fail('weatherNeedsKey');
  const lang = ({ 'zh-CN':'zh_cn', 'zh-TW':'zh_tw', 'pt-BR':'pt_br' })[language] ?? language;
  const start = Math.floor(anchor.date / 3600) * 3600;
  const cacheKey = [rounded(anchor.latitude * 1000), rounded(anchor.longitude * 1000), start, lang].join('_');
  if (signal?.aborted) fail('weatherCancelled');
  if (cache.has(cacheKey)) return { records: cache.get(cacheKey), cached: true };
  const controller = new AbortController(), abort = () => controller.abort();
  signal?.addEventListener('abort', abort, { once: true });
  const timer = setTimeout(abort, 15000);
  async function request(hour) {
    const url = new URL(endpoint);
    url.search = new URLSearchParams({ lat: String(anchor.latitude), lon: String(anchor.longitude), start: String(hour), units: 'metric', lang, appid: key });
    const response = await fetch(url, { signal: controller.signal, credentials: 'omit', referrerPolicy: 'no-referrer', redirect: 'error', cache: 'no-store' });
    if (!response.ok) fail(response.status === 401 ? 'weatherUnauthorized' : response.status === 429 ? 'weatherQuota' : 'weatherRequestError');
    if (Number(response.headers.get('content-length')) > 2 * 1024 * 1024) fail('weatherInvalid');
    const text = await response.text();
    if (text.length > 2 * 1024 * 1024) fail('weatherInvalid');
    let data;
    try { data = JSON.parse(text).data; } catch { fail('weatherInvalid'); }
    if (!Array.isArray(data) || data.length > 1000) fail('weatherInvalid');
    return data.map(point => {
      if (!point || !Number.isFinite(point.dt) || Math.abs(point.dt) > 8.64e12
        || (point.temp != null && (!Number.isFinite(point.temp) || Math.abs(point.temp) > 1000))
        || (point.humidity != null && (!Number.isInteger(point.humidity) || point.humidity < 0 || point.humidity > 100))) fail('weatherInvalid');
      if (point.weather != null && (!Array.isArray(point.weather) || point.weather.length > 100
        || point.weather.some(value => !value || typeof value !== 'object' || Array.isArray(value)
          || (value.main != null && typeof value.main !== 'string')))) fail('weatherInvalid');
      const summary = point.weather?.[0]?.main;
      if (summary != null && (typeof summary !== 'string' || summary.length > 200)) fail('weatherInvalid');
      return { timestamp: point.dt, temperatureCelsius: point.temp == null ? undefined : rounded(point.temp), humidityPercent: point.humidity ?? undefined, summary: summary ?? undefined };
    });
  }
  try {
    let records = await request(start);
    if (records[0]?.timestamp - anchor.date > 90 * 60) records = records.concat(await request(records[0].timestamp - 20 * 3600));
    if (controller.signal.aborted) fail('weatherCancelled');
    if (!records.some(record => Math.abs(record.timestamp - anchor.date) <= 6 * 3600)) fail('weatherNoData');
    cache.set(cacheKey, records);
    if (cache.size > 8) cache.delete(cache.keys().next().value);
    return { records, cached: false };
  } catch (error) {
    if (signal?.aborted) fail('weatherCancelled');
    if (controller.signal.aborted) fail('weatherNetworkError');
    if (error instanceof WeatherError) throw error;
    fail('weatherNetworkError');
  } finally {
    clearTimeout(timer); signal?.removeEventListener('abort', abort);
  }
}
