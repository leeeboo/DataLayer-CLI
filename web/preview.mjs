import { parseTelemetryFile, previewAt, applyingWeatherRecords } from './telemetry.mjs?v=20261025-weather';
import { weatherAnchor, loadWeatherRecords, clearWeatherCache, WeatherError } from './weather.mjs?v=20261025-weather';

const $ = id => document.getElementById(id);
const clamp = (value, max) => Math.max(0, Math.min(max, value));
const activityErrors = { unsupportedFormat:'activityUnsupported', fileTooLarge:'activityTooLarge', tooManySamples:'activityTooManySamples', crcMismatch:'activityCRC', missingTime:'activityMissingTime', noSamples:'activityNoSamples', invalidFIT:'activityMalformed', truncatedFIT:'activityMalformed', invalidGPX:'activityMalformed', invalidTime:'activityMalformed' };
export function formatTime(seconds) {
  seconds = Math.max(0, Math.floor(seconds || 0));
  const parts = [Math.floor(seconds / 3600), Math.floor(seconds / 60) % 60, seconds % 60].map(n => String(n).padStart(2, '0'));
  return parts[0] === '00' ? parts.slice(1).join(':') : parts.join(':');
}

export function createPreview({ t, redraw }) {
  let activity, activityName = '', time = 0;
  let playing = false, raf = 0, lastDraw = 0, playStart = 0, playTime = 0, activityGeneration = 0;
  let activityLoading = false, message;
  let baseActivity, weatherRequest, weatherMessage;
  $('weather-key').value = '';
  const duration = () => activity?.duration ?? 0;
  const currentTime = () => time;
  const frame = () => activity ? previewAt(activity, currentTime()) : undefined;
  function setMessage(key, error = false) { message = {key,error}; refresh(); }
  function refresh() {
    const end = duration(), current = currentTime();
    $('activity-name').textContent = activityLoading ? t('activityLoading') : activity ? t('activityLoaded', {name:activityName,count:activity.samples.length,duration:formatTime(activity.duration)}) : t('activityEmpty');
    $('remove-activity').hidden = !activity;
    $('play').textContent = t(playing ? 'pause' : 'play'); $('play').disabled = !(end > 0);
    $('seek').disabled = !(end > 0); $('seek').max = String(end); $('seek').value = String(current);
    $('preview-time').textContent = `${formatTime(current)} / ${formatTime(end)}`;
    $('preview-note').textContent = t(activity ? 'previewReal' : 'preview');
    $('media-status').textContent = message ? t(message.key) : '';
    $('media-status').classList.toggle('error', !!message?.error);
    $('load-weather').disabled = !!weatherRequest || activityLoading || !weatherAnchor(baseActivity) || !$('weather-key').value.trim();
    $('load-weather').textContent = t(weatherRequest ? 'weatherLoading' : 'weatherLoad');
    $('weather-status').textContent = t(weatherMessage?.key ?? (activity && activity !== baseActivity ? 'weatherLoaded' : 'weatherIdle'));
    $('weather-status').classList.toggle('error', !!weatherMessage?.error);
  }
  function update() { refresh(); redraw(); }
  function stop() {
    playing = false; cancelAnimationFrame(raf); raf = 0;
  }
  function pause() { stop(); update(); }
  function tick(now) {
    if (!playing) return;
    time = clamp(playTime + (now - playStart) / 1000, duration());
    // Refresh telemetry at 15 Hz to keep editing responsive.
    if (now - lastDraw >= 1000 / 15) { lastDraw = now; update(); }
    if (time >= duration()) { stop(); update(); return; }
    raf = requestAnimationFrame(tick);
  }
  function startTicks() { if (raf) return; playing = true; lastDraw = 0; raf = requestAnimationFrame(tick); refresh(); }
  function seek(value) {
    value = clamp(value, duration());
    time = value; playStart = performance.now(); playTime = value;
    update();
  }
  function resetTime() { seek(0); }
  function cancelWeather() { weatherRequest?.abort(); weatherRequest = undefined; }
  async function loadActivity(file) {
    if (!file) return;
    const generation = ++activityGeneration; activityLoading = true; message = undefined; refresh();
    try {
      const next = await parseTelemetryFile(file);
      if (generation !== activityGeneration) return;
      cancelWeather(); weatherMessage = undefined;
      pause(); activity = baseActivity = next; activityName = file.name; resetTime();
    } catch (error) {
      if (generation === activityGeneration) setMessage(activityErrors[error.code] ?? 'activityInvalid', true);
    } finally { if (generation === activityGeneration) { activityLoading = false; update(); } }
  }
  $('import-activity').onclick = () => $('activity-file').click();
  $('activity-file').onchange = () => { loadActivity($('activity-file').files[0]); $('activity-file').value = ''; };
  $('remove-activity').onclick = () => { ++activityGeneration; cancelWeather(); weatherMessage = undefined; activityLoading = false; pause(); activity = baseActivity = undefined; activityName = ''; message = undefined; resetTime(); update(); };
  $('weather-key').oninput = () => { cancelWeather(); weatherMessage = undefined; refresh(); };
  $('load-weather').onclick = async () => {
    if (!baseActivity || !weatherAnchor(baseActivity)) { weatherMessage = { key: 'weatherNeedsLocation', error: true }; refresh(); return; }
    cancelWeather();
    const controller = new AbortController(), source = baseActivity;
    weatherRequest = controller; weatherMessage = undefined; refresh();
    try {
      const result = await loadWeatherRecords(source, $('weather-key').value, document.documentElement.lang, controller.signal);
      if (weatherRequest !== controller || baseActivity !== source) return;
      activity = applyingWeatherRecords(source, result.records);
      weatherMessage = { key: result.cached ? 'weatherCached' : 'weatherLoaded' };
    } catch (error) {
      if (weatherRequest === controller && !controller.signal.aborted) weatherMessage = { key: error instanceof WeatherError ? error.code : 'weatherRequestError', error: true };
    } finally { if (weatherRequest === controller) { weatherRequest = undefined; update(); } }
  };
  $('clear-weather').onclick = () => {
    cancelWeather(); clearWeatherCache(); $('weather-key').value = ''; activity = baseActivity;
    weatherMessage = { key: 'weatherCleared' }; update();
  };
  $('play').onclick = () => {
    if (playing) { pause(); return; }
    if (currentTime() >= duration()) seek(0);
    playStart = performance.now(); playTime = time; startTicks();
  };
  $('seek').oninput = () => seek(Number($('seek').value));
  window.addEventListener('pagehide', event => { if (!event.persisted) { cancelWeather(); $('weather-key').value = ''; clearWeatherCache(); stop(); } });
  refresh();
  return { frame, renderLabels:refresh, pause, loadActivity, exportSource:()=>({activity,activityLabel:$('activity-name').textContent}) };
}
