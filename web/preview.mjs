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

export function createPreview({ t, redraw, videoSize }) {
  let video = $('preview-video'), videoURL, videoName = '', activity, activityName = '', offset = 0, time = 0;
  let playing = false, raf = 0, lastDraw = 0, playStart = 0, playTime = 0, videoGeneration = 0, activityGeneration = 0;
  let pendingVideo, videoLoading = false, activityLoading = false, message;
  let baseActivity, weatherRequest, weatherMessage;
  $('weather-key').value = '';
  const duration = () => videoURL ? video.duration : activity?.duration ?? 0;
  const currentTime = () => videoURL ? video.currentTime : time;
  const frame = () => activity ? previewAt(activity, currentTime() + (videoURL ? offset : 0))
    : videoURL ? { sample:{elapsed:currentTime()}, series:{samples:[],totalDistanceMeters:0} } : undefined;
  function setMessage(key, error = false) { message = {key,error}; refresh(); }
  function refresh() {
    const end = duration(), current = currentTime();
    $('video-name').textContent = videoLoading ? t('videoLoading') : videoName || t('videoEmpty');
    $('activity-name').textContent = activityLoading ? t('activityLoading') : activity ? t('activityLoaded', {name:activityName,count:activity.samples.length,duration:formatTime(activity.duration)}) : t('activityEmpty');
    $('remove-video').hidden = !videoURL; $('remove-activity').hidden = !activity;
    $('play').textContent = t(playing ? 'pause' : 'play'); $('play').disabled = !(end > 0);
    $('seek').disabled = !(end > 0); $('seek').max = String(end); $('seek').value = String(current);
    $('preview-time').textContent = `${formatTime(current)} / ${formatTime(end)}`;
    $('sync-offset').disabled = !videoURL || !activity;
    const preview = frame();
    $('preview-note').textContent = t(activity ? 'previewReal' : videoURL ? 'previewVideoOnly' : 'preview');
    $('range-warning').textContent = activity && !preview.inRange ? t('outsideActivity') : '';
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
  function pause() { video.pause(); stop(); update(); }
  function tick(now) {
    if (!playing) return;
    if (!videoURL) time = clamp(playTime + (now - playStart) / 1000, duration());
    // Video keeps its native frame rate; telemetry redraws at 15 Hz to keep editing responsive.
    if (now - lastDraw >= 1000 / 15) { lastDraw = now; update(); }
    if (!videoURL && time >= duration()) { stop(); update(); return; }
    raf = requestAnimationFrame(tick);
  }
  function startTicks() { if (raf) return; playing = true; lastDraw = 0; raf = requestAnimationFrame(tick); refresh(); }
  function attachVideo(node) {
    for (const event of ['seeked', 'timeupdate', 'loadeddata']) node.addEventListener(event, () => { if (node === video && !playing) update(); });
    node.addEventListener('play', () => { if (node === video) startTicks(); });
    for (const event of ['pause', 'ended']) node.addEventListener(event, () => { if (node === video) { stop(); update(); } });
    node.addEventListener('error', () => { if (node === video && videoURL) { stop(); setMessage('videoUnsupported', true); } });
  }
  attachVideo(video);
  function seek(value) {
    value = clamp(value, duration());
    if (videoURL) video.currentTime = value;
    else { time = value; playStart = performance.now(); playTime = value; }
    update();
  }
  function resetTime() { offset = 0; $('sync-offset').value = '0'; seek(0); }
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
  async function loadVideo(file) {
    if (!file) return;
    const generation = ++videoGeneration; pendingVideo?.(); videoLoading = true; message = undefined; refresh();
    const candidate = document.createElement('video'), url = URL.createObjectURL(file);
    candidate.id = 'preview-video'; candidate.preload = 'auto'; candidate.playsInline = true;
    candidate.setAttribute('aria-label', t('videoLabel')); candidate.setAttribute('data-t-aria', 'videoLabel'); candidate.hidden = true;
    let installed = false;
    try {
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => finish(false), 15000);
        const finish = ok => { clearTimeout(timer); candidate.onloadeddata = candidate.onerror = null; pendingVideo = undefined; ok ? resolve() : reject(new Error('videoUnsupported')); };
        pendingVideo = () => finish(false); candidate.onloadeddata = () => finish(true); candidate.onerror = () => finish(false); candidate.src = url;
      });
      if (generation !== videoGeneration) return;
      if (!Number.isFinite(candidate.duration) || candidate.duration <= 0 || !candidate.videoWidth || !candidate.videoHeight) throw new Error('videoUnsupported');
      pause(); const previousURL = videoURL;
      video.replaceWith(candidate); video = candidate; videoURL = url; videoName = file.name; installed = true; video.hidden = false;
      attachVideo(video); $('canvas-wrap').classList.add('has-video'); videoSize(video.videoWidth, video.videoHeight); resetTime();
      if (previousURL) URL.revokeObjectURL(previousURL);
    } catch {
      if (generation === videoGeneration) setMessage('videoUnsupported', true);
    } finally {
      if (!installed) { candidate.removeAttribute('src'); candidate.load(); URL.revokeObjectURL(url); }
      if (generation === videoGeneration) { videoLoading = false; update(); }
    }
  }
  $('import-video').onclick = () => $('video-file').click();
  $('import-activity').onclick = () => $('activity-file').click();
  $('video-file').onchange = () => { loadVideo($('video-file').files[0]); $('video-file').value = ''; };
  $('activity-file').onchange = () => { loadActivity($('activity-file').files[0]); $('activity-file').value = ''; };
  $('remove-video').onclick = () => {
    ++videoGeneration; pendingVideo?.(); videoLoading = false; pause();
    const url = videoURL; videoURL = undefined; videoName = ''; video.removeAttribute('src'); video.load(); video.hidden = true;
    if (url) URL.revokeObjectURL(url); $('canvas-wrap').classList.remove('has-video'); message = undefined; resetTime(); update();
  };
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
  $('play').onclick = async () => {
    if (playing) { pause(); return; }
    if (currentTime() >= duration()) seek(0);
    if (videoURL) { try { await video.play(); } catch { stop(); setMessage('previewPlaybackError', true); } }
    else { playStart = performance.now(); playTime = time; startTicks(); }
  };
  $('seek').oninput = () => seek(Number($('seek').value));
  $('sync-offset').oninput = () => {
    const input = $('sync-offset'), value = Number(input.value);
    if (input.value === '' || !input.checkValidity() || !Number.isFinite(value)) return;
    offset = value; update();
  };
  window.addEventListener('pagehide', event => { if (!event.persisted) { cancelWeather(); $('weather-key').value = ''; clearWeatherCache(); ++videoGeneration; pendingVideo?.(); video.pause(); stop(); if (videoURL) URL.revokeObjectURL(videoURL); } });
  refresh();
  return { frame, renderLabels:refresh, pause, loadActivity, loadVideo };
}
