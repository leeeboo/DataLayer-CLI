import { defaultPreset } from '../default-preset.mjs';
import { renderLayout, svgDefinitions, fontsReady } from '../render.mjs';
import { parseTelemetryFile, previewAt } from '../telemetry.mjs';

const get = id => document.getElementById(id);
const fitInput = get('fit-file');
const videoInput = get('video-file');
const video = get('video');
const overlay = get('overlay');
const stage = get('stage');
const placeholder = get('placeholder');
const play = get('play');
const seek = get('seek');
const offset = get('offset');
const clock = get('video-time');
const syncStatus = get('sync-status');

const gaugeLabels = { pace: '配速', heartRate: '心率', cadence: '步频' };
const layout = {
  ...defaultPreset.layout,
  elements: Object.entries(gaugeLabels).map(([kind, label], index) => {
    const gauge = defaultPreset.layout.elements.find(element => element.kind === kind);
    return {
      ...gauge,
      frame: { ...gauge.frame, x: 0.04 + index * 0.32, y: 0.05, scale: 2.1 },
      customization: { ...gauge.customization, labelOverride: label },
    };
  }),
};

const fitErrors = {
  unsupportedFormat: '请选择 .fit 文件。',
  fileTooLarge: 'FIT 文件过大，上限为 50 MiB。',
  tooManySamples: '记录点过多，请选择较短的 FIT。',
  crcMismatch: 'FIT 校验失败，请重新从设备导出。',
  noSamples: '这个 FIT 没有可预览的记录。',
};

let activity;
let fitSelection = 0;
let videoURL;
let videoName;
let frameRequest;
let lastDraw = -Infinity;
const hasFrameCallback = typeof video.requestVideoFrameCallback === 'function';

function setStatus(id, message, error = false) {
  const status = get(id);
  status.textContent = message;
  status.classList.toggle('error', error);
}

function videoReady() {
  return !!videoURL && video.currentSrc === videoURL && video.videoWidth > 0 &&
    Number.isFinite(video.duration) && video.duration > 0 && !video.error;
}

function timeLabel(seconds) {
  const total = Math.floor(seconds);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor(total / 60) % 60;
  const tail = String(total % 60).padStart(2, '0');
  return hours ? hours + ':' + String(minutes).padStart(2, '0') + ':' + tail : minutes + ':' + tail;
}

function syncOverlay(mediaTime = video.currentTime) {
  const ready = videoReady();
  const seconds = ready ? video.currentTime : 0;
  seek.value = seconds;
  clock.textContent = timeLabel(seconds) + ' / ' + timeLabel(ready ? video.duration : 0);

  const shift = Number.isFinite(offset.valueAsNumber) ? offset.valueAsNumber : 0;
  const frame = ready && activity ? previewAt(activity, mediaTime + shift) : null;
  const outOfRange = frame !== null && !frame.inRange;
  syncStatus.hidden = !outOfRange;
  if (!frame?.inRange) {
    overlay.replaceChildren();
    return;
  }

  const gauges = renderLayout(layout, video.videoWidth, video.videoHeight, frame);
  // The SVG fragments come from the fixed gauge preset and numeric samples.
  overlay.innerHTML = svgDefinitions + gauges.map(gauge => gauge.svg).join('');
}

function refreshControls() {
  const ready = videoReady();
  video.hidden = !ready;
  placeholder.hidden = ready;
  play.disabled = seek.disabled = !ready;
  offset.disabled = !ready || !activity;
  seek.max = ready ? video.duration : 0;
  play.textContent = video.paused || video.ended ? '播放' : '暂停';
  syncOverlay();
}

function drawVideoFrame(now, metadata) {
  frameRequest = undefined;
  if (video.paused || video.ended || !videoReady()) return;
  if (now - lastDraw >= 50) {
    lastDraw = now;
    syncOverlay(metadata?.mediaTime);
  }
  scheduleFrame();
}

function scheduleFrame() {
  if (frameRequest !== undefined) return;
  frameRequest = hasFrameCallback
    ? video.requestVideoFrameCallback(drawVideoFrame)
    : requestAnimationFrame(drawVideoFrame);
}

function stopFrames() {
  if (frameRequest === undefined) return;
  if (hasFrameCallback) video.cancelVideoFrameCallback(frameRequest);
  else cancelAnimationFrame(frameRequest);
  frameRequest = undefined;
}

fitInput.addEventListener('change', async () => {
  const file = fitInput.files[0];
  if (!file) return;
  fitInput.value = '';
  const selection = ++fitSelection;
  activity = undefined;
  offset.value = '0';
  refreshControls();
  setStatus('fit-status', '正在读取 FIT…');

  try {
    if (!/\.fit$/i.test(file.name)) {
      setStatus('fit-status', fitErrors.unsupportedFormat, true);
      return;
    }
    const parsed = await parseTelemetryFile(file);
    if (selection !== fitSelection) return;
    activity = parsed;
    setStatus('fit-status', file.name + ' · ' + timeLabel(parsed.duration));
  } catch (error) {
    if (selection !== fitSelection) return;
    setStatus('fit-status', fitErrors[error.code] ?? '无法读取 FIT，请选择设备原始导出的文件。', true);
  }
  refreshControls();
});

videoInput.addEventListener('change', () => {
  const file = videoInput.files[0];
  if (!file) return;
  videoInput.value = '';
  stopFrames();
  video.pause();
  const previousURL = videoURL;
  videoURL = URL.createObjectURL(file);
  videoName = file.name;
  video.src = videoURL;
  if (previousURL) URL.revokeObjectURL(previousURL);
  offset.value = '0';
  stage.style.removeProperty('aspect-ratio');
  placeholder.textContent = '正在打开视频…';
  setStatus('video-status', file.name);
  refreshControls();
});

video.addEventListener('loadedmetadata', () => {
  if (!videoReady()) return;
  stage.style.aspectRatio = video.videoWidth + ' / ' + video.videoHeight;
  overlay.setAttribute('viewBox', '0 0 ' + video.videoWidth + ' ' + video.videoHeight);
  refreshControls();
});

video.addEventListener('error', () => {
  if (!videoURL || !video.error) return;
  stopFrames();
  stage.style.removeProperty('aspect-ratio');
  placeholder.textContent = '选择另一个视频重试';
  setStatus('video-status', '无法播放此文件，请试试 H.264 编码的 MP4。', true);
  refreshControls();
});

play.addEventListener('click', async () => {
  if (!video.paused) {
    video.pause();
    return;
  }
  const source = videoURL;
  try {
    await video.play();
    if (source === videoURL) setStatus('video-status', videoName);
  } catch (error) {
    if (source === videoURL && error.name !== 'AbortError') {
      setStatus('video-status', '未能开始播放，请重新选择视频后重试。', true);
    }
  }
});

video.addEventListener('playing', () => {
  lastDraw = -Infinity;
  refreshControls();
  scheduleFrame();
});
for (const event of ['pause', 'ended']) {
  video.addEventListener(event, () => {
    stopFrames();
    refreshControls();
  });
}
video.addEventListener('seeked', () => syncOverlay());
seek.addEventListener('input', () => { video.currentTime = seek.valueAsNumber; });
offset.addEventListener('input', () => syncOverlay());
window.addEventListener('pagehide', event => {
  if (!event.persisted && videoURL) URL.revokeObjectURL(videoURL);
});

syncStatus.textContent = '当前画面超出 FIT 记录范围。';
fontsReady.then(() => syncOverlay());
