import { parseTelemetryFile, previewAt, applyingWeatherRecords } from './telemetry.mjs?v=20261025-weather';
import { weatherAnchor, loadWeatherRecords, clearWeatherCache, hasWeatherCache, WeatherError } from './weather.mjs?v=20261119-tips';

const $ = id => document.getElementById(id);
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
// Disable unusable buttons and explain why on hover; usable buttons show their name.
export function available(node, reason = '') { node.disabled = !!reason; node.title = reason || node.getAttribute('aria-label') || node.textContent.trim(); }
const activityErrors = { unsupportedFormat:'activityUnsupported', fileTooLarge:'activityTooLarge', tooManySamples:'activityTooManySamples', crcMismatch:'activityCRC', missingTime:'activityMissingTime', noSamples:'activityNoSamples', invalidFIT:'activityMalformed', truncatedFIT:'activityMalformed', invalidGPX:'activityMalformed', invalidTime:'activityMalformed' };
export function formatTime(seconds) {
  seconds = Math.max(0, Math.floor(seconds || 0));
  const parts = [Math.floor(seconds / 3600), Math.floor(seconds / 60) % 60, seconds % 60].map(n => String(n).padStart(2, '0'));
  return parts[0] === '00' ? parts.slice(1).join(':') : parts.join(':');
}

export function createPreview({ t, redraw, changed }) {
  let activity, activityName = '', time = 0;
  let trimStart = 0, trimEnd = 0;
  let playing = false, raf = 0, lastDraw = 0, playStart = 0, playTime = 0, activityGeneration = 0;
  let activityLoading = false, message;
  let baseActivity, weatherRequest, weatherMessage;
  $('weather-key').value = '';
  const currentTime = () => time;
  const rangeLabel = () => t('trimSummary', { start:trimStart, end:trimEnd, duration:Number((trimEnd-trimStart).toFixed(3)) });
  const frame = () => activity ? previewAt(activity, currentTime()) : undefined;
  function setMessage(key, error = false) { message = {key,error}; refresh(); }
  function refresh() {
    const end = trimEnd, current = currentTime();
    $('activity-name').textContent = activityLoading ? t('activityLoading') : activity ? t('activityLoaded', {name:activityName,count:activity.samples.length,duration:formatTime(activity.duration)}) : t('activityEmpty');
    $('remove-activity').hidden = !activity;
    const busy = activityLoading ? t('whyActivityLoading') : !activity ? t('whyNeedsActivity') : '';
    $('play').textContent = t(playing ? 'pause' : 'play'); available($('play'), end > 0 ? '' : busy || t('whyNeedsActivity'));
    $('seek').disabled = !(end > 0); $('seek').min = String(trimStart); $('seek').max = String(end); $('seek').value = String(current);
    $('preview-time').textContent = `${formatTime(current)} / ${formatTime(end)}`;
    $('preview-note').textContent = t(activity ? 'previewReal' : 'preview');
    $('activity-trim').hidden = !activity;
    $('trim-summary').textContent = rangeLabel();
    renderTimeline(current);
    for (const id of ['trim-start','trim-end']) $(id).disabled = !!busy;
    // Match the rounding used by "Start here" / "End here" so the reason reflects what a click would do.
    const at = clamp(Number(current.toFixed(2)), trimStart, trimEnd);
    available($('trim-set-start'), busy || (at === trimStart ? t('whyAtStart') : trimEnd - at < .1 - 1e-8 ? t('whyTrimShort') : ''));
    available($('trim-set-end'), busy || (at === trimEnd ? t('whyAtEnd') : at - trimStart < .1 - 1e-8 ? t('whyTrimShort') : ''));
    available($('trim-reset'), busy || (trimStart === 0 && trimEnd === activity.duration ? t('whyFullActivity') : ''));
    available($('import-activity')); available($('remove-activity'));
    $('media-status').textContent = message ? t(message.key) : '';
    $('media-status').classList.toggle('error', !!message?.error);
    $('load-weather').textContent = t(weatherRequest ? 'weatherLoading' : 'weatherLoad');
    available($('load-weather'), weatherRequest ? t('weatherLoading') : busy || (!weatherAnchor(baseActivity) ? t('weatherNeedsLocation') : !$('weather-key').value.trim() ? t('whyWeatherKey') : ''));
    available($('clear-weather'), weatherRequest || $('weather-key').value || activity !== baseActivity || hasWeatherCache() ? '' : t('whyNothingToClear'));
    $('weather-status').textContent = t(weatherMessage?.key ?? (activity && activity !== baseActivity ? 'weatherLoaded' : 'weatherIdle'));
    $('weather-status').classList.toggle('error', !!weatherMessage?.error);
    changed?.();
  }
  function update() { refresh(); redraw(); }
  // Timeline: proportional bar over the whole activity, with draggable trim handles and a playhead.
  const percent = value => activity?.duration > 0 ? `${clamp(value / activity.duration, 0, 1) * 100}%` : '0%';
  function renderTimeline(current) {
    const duration = activity?.duration ?? 0;
    $('timeline-range').style.left = percent(trimStart); $('timeline-range').style.right = `calc(100% - ${percent(trimEnd)})`;
    $('timeline-playhead').style.left = percent(current);
    for (const [id, value, min, max] of [['timeline-start', trimStart, 0, trimEnd], ['timeline-end', trimEnd, trimStart, duration]]) {
      const handle = $(id); handle.style.left = percent(value);
      handle.setAttribute('aria-valuemin', String(min)); handle.setAttribute('aria-valuemax', String(max));
      handle.setAttribute('aria-valuenow', String(value)); handle.setAttribute('aria-valuetext', formatTime(value));
      handle.tabIndex = activity && !activityLoading ? 0 : -1; handle.setAttribute('aria-disabled', String(!activity || activityLoading));
    }
    $('timeline-selection').textContent = `${formatTime(trimStart)} – ${formatTime(trimEnd)}`;
    $('timeline-total').textContent = formatTime(duration);
  }
  const tidy = value => Number(value.toFixed(3));
  function moveHandle(which, value) {
    if (!activity || activityLoading) return;
    const duration = activity.duration;
    // Preview the frame under the dragged handle; trim() re-seeks once with the new bounds.
    const start = which === 'start' ? tidy(clamp(value, 0, Math.max(0, trimEnd - .1))) : trimStart;
    const end = which === 'end' ? (value >= duration ? duration : tidy(clamp(value, Math.min(duration, trimStart + .1), duration))) : trimEnd;
    time = which === 'start' ? start : end;
    if (start !== trimStart || end !== trimEnd) trim(start, end); else seek(time);
  }
  function timelineValue(event) {
    const box = $('timeline-track').getBoundingClientRect(), duration = activity.duration;
    const value = clamp((event.clientX - box.left) / box.width, 0, 1) * duration;
    return value >= duration ? duration : Math.round(value * 10) / 10;
  }
  let timelineDrag;
  $('timeline-track').onpointerdown = event => {
    if (!activity || activityLoading || event.button > 0) return;
    event.preventDefault();
    timelineDrag = event.target.id === 'timeline-start' ? 'start' : event.target.id === 'timeline-end' ? 'end' : 'seek';
    $('timeline-track').setPointerCapture(event.pointerId);
    if (timelineDrag === 'seek') { stop(); seek(timelineValue(event)); } else event.target.focus({ preventScroll: true });
  };
  $('timeline-track').onpointermove = event => {
    if (!timelineDrag || !activity) return;
    if (timelineDrag === 'seek') seek(timelineValue(event)); else moveHandle(timelineDrag, timelineValue(event));
  };
  $('timeline-track').onpointerup = $('timeline-track').onpointercancel = () => { timelineDrag = undefined; };
  for (const [id, which] of [['timeline-start', 'start'], ['timeline-end', 'end']]) $(id).onkeydown = event => {
    if (!activity || activityLoading) return;
    const step = event.shiftKey ? 10 : 1, value = which === 'start' ? trimStart : trimEnd;
    const next = { ArrowLeft: value - step, ArrowDown: value - step, ArrowRight: value + step, ArrowUp: value + step, PageDown: value - 10, PageUp: value + 10, Home: 0, End: activity.duration }[event.key];
    if (next === undefined) return;
    event.preventDefault(); stop(); moveHandle(which, next);
  };
  function stop() {
    playing = false; cancelAnimationFrame(raf); raf = 0;
  }
  function pause() { stop(); update(); }
  function tick(now) {
    if (!playing) return;
    time = clamp(playTime + (now - playStart) / 1000, trimStart, trimEnd);
    // Refresh telemetry at 15 Hz to keep editing responsive.
    if (now - lastDraw >= 1000 / 15) { lastDraw = now; update(); }
    if (time >= trimEnd) { stop(); update(); return; }
    raf = requestAnimationFrame(tick);
  }
  function startTicks() { if (raf) return; playing = true; lastDraw = 0; raf = requestAnimationFrame(tick); refresh(); }
  function seek(value) {
    value = clamp(value, trimStart, trimEnd);
    time = value; playStart = performance.now(); playTime = value;
    update();
  }
  function syncTrimFields() {
    $('trim-start').value = String(trimStart); $('trim-end').value = String(trimEnd);
    $('trim-start').max = $('trim-end').max = String(activity?.duration ?? 0);
  }
  function resetTime() { trimStart = 0; trimEnd = activity?.duration ?? 0; syncTrimFields(); seek(0); }
  function trim(start, end) {
    if (!activity || activityLoading) return;
    if (![start,end].every(Number.isFinite) || start < 0 || end > activity.duration || end-start < .1-1e-8) {
      syncTrimFields(); setMessage('trimInvalid', true); return;
    }
    stop(); trimStart = start; trimEnd = end; message = undefined; syncTrimFields(); seek(time);
  }
  for (const id of ['trim-start','trim-end']) $(id).onchange = () => trim($('trim-start').valueAsNumber, $('trim-end').valueAsNumber);
  $('trim-set-start').onclick = () => trim(clamp(Number(time.toFixed(2)), trimStart, trimEnd), trimEnd);
  $('trim-set-end').onclick = () => trim(trimStart, clamp(Number(time.toFixed(2)), trimStart, trimEnd));
  $('trim-reset').onclick = () => { if (activity && !activityLoading) { stop(); message = undefined; resetTime(); } };
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
    if (currentTime() >= trimEnd) seek(trimStart);
    playStart = performance.now(); playTime = time; startTicks();
  };
  $('seek').oninput = () => seek(Number($('seek').value));
  window.addEventListener('pagehide', event => { if (!event.persisted) { cancelWeather(); $('weather-key').value = ''; clearWeatherCache(); stop(); } });
  refresh();
  return { frame, renderLabels:refresh, pause, loadActivity, exportSource:()=>({activity,loading:activityLoading,activityLabel:$('activity-name').textContent,range:{start:trimStart,end:trimEnd},rangeLabel:rangeLabel()}) };
}
