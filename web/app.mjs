import { accents, fonts, gauges, clone, createElement, createDocument, presets, parseJSON, parseDocument, validateDocument, validateCustomization, exportDocument, swiftDate, uid, History } from './model.mjs?v=20261025-weather';
import { languages, translate, errorMessage, languageFrom } from './i18n.mjs?v=20261025-weather';
import { genericRGBToSRGB, sRGBToGenericRGB } from './render-color.mjs?v=20261025-weather';
import { escapeXML, renderLayout, svgDefinitions, fontsReady } from './render.mjs?v=20261025-weather';
import { createPreview } from './preview.mjs?v=20261025-weather';

const $ = id => document.getElementById(id);
let language = languageFrom(new URLSearchParams(location.search).get('lang') || navigator.language);
const t = (key, details) => translate(language, key, details);
let data = createDocument(t('demoName'));
data.layout.elements = data.layout.elements.filter(e => !['cadence', 'timeDate'].includes(e.kind));
let activeID = data.id, selectedID = data.layout.elements[1].id;
let history = new History(snapshot()), saved = exportDocument(data, activeID), drag = null;
const drafts = new Map();
let width = 1920, height = 1080, canvasScene = [];
const localPreview = createPreview({ t, redraw:renderCanvas, videoSize:(w,h) => {
  const value = `${w}x${h}`, choices = $('canvas-size');
  if (![...choices.options].some(option => option.value === value)) { const option = element('option', '', `${w} × ${h}`); option.value = value; choices.append(option); }
  choices.value = value; width = w; height = h; render();
} });
function snapshot() { return { data, activeID, selectedID }; }
function restore(value) { ({ data, activeID, selectedID } = clone(value)); }
const preset = () => presets(data).find(p => p.id === activeID) ?? presets(data)[0];
const selected = () => preset().layout.elements.find(e => e.id === selectedID);
const draftKey = () => `${activeID}/${selectedID}`;
const dirty = () => drafts.size > 0 || exportDocument(data, activeID) !== saved;
function status(message, error = false) { $('status').textContent = message; $('status').classList.toggle('error', error); }
function title(element) { return t(`gauge.${element.kind}`); }
function mutate(action) {
  const previous = clone(snapshot());
  try {
    const before = JSON.stringify(data); action(); validateDocument(data);
    if (before !== JSON.stringify(data)) { preset().updatedAt = swiftDate(); history.push(snapshot()); }
    render(); status(dirty() ? t('changed') : t('ready'));
    return true;
  } catch (error) { restore(previous); render(); status(errorMessage(error, language), true); return false; }
}
function element(tag, className, text) {
  const node = document.createElement(tag); if (className) node.className = className;
  if (text !== undefined) node.textContent = text; return node;
}
function button(parent, key, action, className = '') {
  const b = element('button', className, t(key)); b.type = 'button'; b.onclick = action; parent.append(b); return b;
}
function control(parent, key, options) {
  const { value, type = 'number', min, max, step = 'any', choices, change, label = t(key) } = options;
  const wrapper = element('label', `field${type === 'checkbox' ? ' checkbox' : ''}`);
  const caption = element('span', '', label);
  const input = element(choices ? 'select' : 'input'); input.id = `field-${parent.id || 'inspector'}-${key}`;
  if (choices) for (const [v, name] of choices) { const option = element('option', '', name); option.value = v; input.append(option); }
  else input.type = type;
  if (min !== undefined) input.min = min;
  if (max !== undefined) input.max = max;
  if (['number', 'range'].includes(type)) input.step = type === 'number' && step !== 1 ? 'any' : step;
  if (type === 'checkbox') input.checked = value;
  else input.value = type === 'number' && typeof value === 'number' ? Number(value.toFixed(6)) : value ?? '';
  input.setAttribute('aria-label', label);
  if (type === 'text') input.maxLength = 500;
  input.dir = type === 'text' ? 'auto' : 'ltr';
  if (type === 'range') {
    const output = element('span', 'range-value', Number(value).toFixed(2)); caption.append(output);
    input.oninput = () => { output.textContent = Number(input.value).toFixed(2); };
  }
  input.onchange = () => {
    if (!input.checkValidity()) { input.reportValidity(); return; }
    const next = choices ? input.value : type === 'checkbox' ? input.checked : ['number', 'range'].includes(type) ? (input.value === '' ? undefined : Number(input.value)) : input.value;
    change(next);
  };
  if (type === 'checkbox') wrapper.append(input, caption); else wrapper.append(caption, input);
  parent.append(wrapper); return input;
}
function section(parent, key) {
  const group = element('section', 'field-section'); group.append(element('h3', '', t(key)));
  const fields = element('div', 'fields'); group.append(fields); parent.append(group); return fields;
}
const accentOptions = inherit => [...(inherit ? [['', t('inherit')]] : []), ...Object.entries(accents).map(([key, value]) => [key, value])];
const fontOptions = () => Object.entries(fonts);
function renderGlobal() {
  const fields = $('global-fields'); fields.replaceChildren(); const style = preset().layout.style;
  const change = (key, value) => mutate(() => { style[key] = value; });
  control(fields, 'accent', { value: style.accentColor, choices: accentOptions(false), change: v => change('accentColor', v) });
  control(fields, 'opacity', { type: 'range', value: style.panelOpacity, min: 0, max: 1, step: 0.01, change: v => change('panelOpacity', v) });
  control(fields, 'textScale', { value: style.metricScale, min: 0.1, max: 4, step: 0.05, change: v => mutate(() => { const ratio = v / style.metricScale; style.metricScale = v; for (const e of preset().layout.elements) e.frame.style.textScale = Math.max(0.1, Math.min(4, e.frame.style.textScale * ratio)); }) });
  control(fields, 'ticks', { type: 'checkbox', value: style.showGaugeTicks, change: v => change('showGaugeTicks', v) });
}
function renderInspector() {
  const container = $('inspector'), e = selected(); container.replaceChildren();
  if (!e) { container.append(element('p', 'hint', t('select'))); return; }
  container.append(element('h2', '', title(e)));
  const position = section(container, 'position'), grid = element('div', 'field-grid'); position.append(grid);
  const frameChange = (key, value) => mutate(() => { e.frame[key] = value; });
  for (const key of ['x', 'y']) control(grid, key, { value: e.frame[key], min: -1, max: 2, step: 0.001, change: v => frameChange(key, v) });
  control(grid, 'scale', { value: e.frame.scale, min: 0.1, max: 4, step: 0.05, change: v => frameChange('scale', v) });
  control(grid, 'visible', { type: 'checkbox', value: e.frame.isVisible, change: v => frameChange('isVisible', v) });
  position.parentElement.append(element('p', 'hint', t('limits')));
  const appearance = section(container, 'appearance'), c = e.customization;
  const change = (key, value) => mutate(() => { if (value === undefined || value === '') delete c[key]; else c[key] = value; });
  const styleChange = (key, value) => mutate(() => { if (value === '') delete e.frame.style[key]; else e.frame.style[key] = value; });
  control(appearance, 'accent', { value: e.frame.style.accentColor ?? '', choices: accentOptions(true), change: v => styleChange('accentColor', v) });
  control(appearance, 'opacity', { type: 'range', value: e.frame.style.panelOpacity ?? preset().layout.style.panelOpacity, min: 0, max: 1, step: 0.01, change: v => styleChange('panelOpacity', v) });
  control(appearance, 'textScale', { value: e.frame.style.textScale, min: 0.1, max: 4, step: 0.05, change: v => styleChange('textScale', v) });
  for (const [key, property] of [['label', 'labelOverride'], ['unit', 'unitOverride'], ['icon', 'iconOverride']]) control(appearance, key, { type: 'text', value: c[property] ?? '', change: v => change(property, v) });
  const checks = element('div', 'checkbox-grid'); appearance.append(checks);
  for (const [key, property] of [['showLabel', 'showsLabel'], ['showUnit', 'showsUnit'], ['showPanel', 'showsPanel'], ['showIcon', 'showsIcon'], ['border', 'showsPanelBorder'], ['ticks', 'showGaugeTicks']]) control(checks, key, { type: 'checkbox', value: c[property] ?? (property === 'showGaugeTicks' ? preset().layout.style.showGaugeTicks : true), change: v => change(property, v) });
  for (const key of ['valueFont', 'labelFont', 'unitFont']) control(appearance, key, { value: c[key], choices: fontOptions(), change: v => change(key, v) });
  const sizes = element('div', 'field-grid'); appearance.append(sizes);
  for (const key of ['labelScale', 'valueScale', 'unitScale']) control(sizes, key, { value: c[key], min: 0.05, max: 20, step: 0.05, change: v => change(key, v) });
  control(sizes, 'length', { value: c.lengthScale, min: 0.1, max: 4, step: 0.05, change: v => change('lengthScale', v) });
  control(sizes, 'lineWidth', { value: c.lineWidth, min: 0.25, max: 64, step: 0.25, change: v => change('lineWidth', v) });
  control(sizes, 'precision', { value: c.valuePrecision ?? '', min: 0, max: 3, step: 1, change: v => change('valuePrecision', v) });
  if (e.kind === 'speed') {
    control(sizes, 'minimum', { value: c.gaugeMinimum ?? '', min: 0, max: 120, change: v => change('gaugeMinimum', v) });
    control(sizes, 'maximum', { value: c.gaugeMaximum ?? '', min: 1, max: 180, change: v => change('gaugeMaximum', v) });
  }
  const colorFields = element('div', 'field-grid'); appearance.append(colorFields);
  for (const key of ['valueColor', 'labelColor', 'unitColor']) {
    const accent = accents[e.frame.style.accentColor ?? preset().layout.style.accentColor];
    const fallback = key === 'valueColor' ? { red: parseInt(accent.slice(1,3),16)/255, green: parseInt(accent.slice(3,5),16)/255, blue: parseInt(accent.slice(5,7),16)/255, alpha:.98 }
      : key === 'labelColor' ? {red:.74,green:.80,blue:.86,alpha:.92} : {red:.66,green:.72,blue:.78,alpha:.82};
    const source = c[key] ?? fallback, displayed = genericRGBToSRGB(source);
    const value = '#' + ['red','green','blue'].map(channel => Math.round(displayed[channel]*255).toString(16).padStart(2,'0')).join('');
    control(colorFields, key, { type:'color', value, change:v => change(key, sRGBToGenericRGB({red:parseInt(v.slice(1,3),16)/255,green:parseInt(v.slice(3,5),16)/255,blue:parseInt(v.slice(5,7),16)/255,alpha:source.alpha})) });
  }
  button(appearance, 'resetColor', () => mutate(() => { for (const key of ['valueColor', 'labelColor', 'unitColor']) delete c[key]; }), 'text-button');
  const advanced = element('details'); advanced.id = 'advanced'; advanced.append(element('summary', '', t('advanced')), element('p', 'hint', t('advancedHelp')));
  const json = element('textarea'); json.id = 'custom-json'; json.setAttribute('aria-label', t('advanced')); json.spellcheck = false; json.value = drafts.get(draftKey()) ?? JSON.stringify(c, null, 2);
  json.oninput = () => { drafts.set(draftKey(), json.value); };
  advanced.append(json);
  button(advanced, 'apply', () => {
    try {
      const next = parseJSON(json.value);
      validateCustomization(next); const key = draftKey();
      if (mutate(() => { e.customization = next; })) { drafts.delete(key); render(); }
    } catch (error) { status(`${t('jsonError')}: ${errorMessage(error, language)}`, true); }
  });
  if (drafts.has(draftKey())) button(advanced, 'undo', () => { drafts.delete(draftKey()); render(); });
  container.append(advanced);
  const actions = element('div', 'inspector-actions');
  button(actions, 'duplicate', () => mutate(() => { const copy = clone(e); copy.id = uid(); copy.frame.x = Math.min(2, copy.frame.x + 0.02); copy.frame.y = Math.min(2, copy.frame.y + 0.02); preset().layout.elements.push(copy); selectedID = copy.id; }));
  button(actions, 'delete', () => mutate(() => { drafts.delete(draftKey()); preset().layout.elements = preset().layout.elements.filter(item => item.id !== e.id); selectedID = preset().layout.elements.at(-1)?.id ?? null; }), 'danger');
  const index = preset().layout.elements.indexOf(e);
  for (const [key, delta] of [['backward', -1], ['forward', 1]]) {
    const b = button(actions, key, () => mutate(() => { const items = preset().layout.elements; items.splice(index, 1); items.splice(index + delta, 0, e); }));
    b.disabled = index + delta < 0 || index + delta >= preset().layout.elements.length;
  }
  container.append(actions);
}
function renderCanvas() {
  const layout = preset().layout, svg = $('canvas');
  svg.setAttribute('viewBox', `0 0 ${width} ${height}`); svg.style.aspectRatio = `${width}/${height}`;
  $('canvas-wrap').style.setProperty('--canvas-ratio', width / height);
  let content = svgDefinitions;
  canvasScene = renderLayout(layout, width, height, localPreview.frame());
  if ($('grid').checked) {
    content += '<g fill="none" stroke="#bdccd5" stroke-opacity=".09" stroke-width="1">';
    for (let n = 1; n < 10; n++) content += `<path d="M ${width * n / 10} 0 V ${height} M 0 ${height * n / 10} H ${width}"/>`;
    content += '</g>';
  }
  layout.elements.forEach((e, index) => {
    if (!e.frame.isVisible) return;
    const { bounds: b, svg: artwork } = canvasScene[index];
    content += `<g data-index="${index}" role="button" tabindex="0" aria-label="${escapeXML(title(e))}" aria-pressed="${e.id === selectedID}"><rect class="hit" x="${b.x}" y="${b.y}" width="${b.width}" height="${b.height}" fill="transparent"/>${artwork}</g>`;
  });
  const e = selected();
  if (e) {
    const b = canvasScene.find(item => item.id === e.id).bounds, handle = Math.max(9, width / (svg.clientWidth || 960) * 9);
    content += `<g pointer-events="none"><rect x="${b.x}" y="${b.y}" width="${b.width}" height="${b.height}" fill="none" stroke="#75f794" stroke-width="1.5" vector-effect="non-scaling-stroke"${e.frame.isVisible ? '' : ' stroke-dasharray="5 5"'}/></g><rect data-resize="true" x="${b.x + b.width - handle / 2}" y="${b.y + b.height - handle / 2}" width="${handle}" height="${handle}" fill="#75f794" stroke="#143522" vector-effect="non-scaling-stroke"/>`;
  }
  svg.innerHTML = content;
  $('empty-canvas').hidden = layout.elements.length !== 0;
  $('canvas-wrap').classList.toggle('solid', $('background').checked);
}
function render() {
  const focus = document.activeElement?.id, selection = document.activeElement?.selectionStart;
  const open = new Set([...document.querySelectorAll('details[open]')].map(node => node.id));
  document.documentElement.lang = language; document.title = `${t('title')} · DataLayer Studio`;
  document.documentElement.dir = language === 'ar' ? 'rtl' : 'ltr';
  document.querySelectorAll('[data-t]').forEach(node => { node.textContent = t(node.dataset.t); });
  document.querySelectorAll('[data-t-aria]').forEach(node => { node.setAttribute('aria-label', t(node.dataset.tAria)); });
  $('language').replaceChildren(...Object.entries(languages).map(([code, name]) => { const option = element('option', '', name); option.value = code; return option; }));
  $('language').value = language; $('layout-name').value = preset().name;
  $('preset-picker').hidden = presets(data).length < 2;
  $('preset').replaceChildren(...presets(data).map(p => { const option = element('option', '', p.name); option.value = p.id; return option; })); $('preset').value = activeID;
  const kind = $('add-kind').value || 'speed';
  $('add-kind').replaceChildren(...gauges.map(g => { const option = element('option', '', t(`gauge.${g.kind}`)); option.value = g.kind; return option; })); $('add-kind').value = kind;
  const layers = $('layers'); layers.replaceChildren();
  preset().layout.elements.forEach(e => {
    const row = element('div', `layer${e.id === selectedID ? ' selected' : ''}${e.frame.isVisible ? '' : ' is-hidden'}`);
    const select = element('button', 'layer-name', title(e)); select.type = 'button'; select.setAttribute('aria-pressed', String(e.id === selectedID));
    select.onclick = () => { selectedID = e.id; render(); $('canvas').focus({ preventScroll:true }); }; row.append(select);
    const eye = element('button', 'layer-eye'); eye.type = 'button'; eye.setAttribute('aria-label', `${t(e.frame.isVisible ? 'hide' : 'show')} ${title(e)}`);
    eye.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/></svg>';
    eye.onclick = () => mutate(() => { e.frame.isVisible = !e.frame.isVisible; }); row.append(eye); layers.append(row);
  });
  renderGlobal(); renderInspector(); renderCanvas();
  localPreview.renderLabels();
  $('undo').disabled = history.index === 0; $('redo').disabled = history.index >= history.entries.length - 1;
  $('command').textContent = `overlay --fit "activity.fit" --layout-preset "layout.dlspreset" --width ${width} --height ${height} --codec prores-4444 --output "overlay.mov"`;
  for (const id of open) if ($(id)) $(id).open = true;
  if (focus && $(focus)) { $(focus).focus({ preventScroll: true }); if (typeof selection === 'number' && ['text', 'textarea'].includes($(focus).type)) $(focus).setSelectionRange(selection, selection); }
}
function confirmDiscard() { return !dirty() || window.confirm(t('dirty')); }
async function importFile(file) {
  if (!file) return;
  try {
    if (file.size > 5 * 1024 * 1024) { status(`${t('invalid')}: ${t('fileHelp')}`, true); return; }
    const next = parseDocument(await file.text()); if (!confirmDiscard()) return;
    data = next; activeID = data.defaultPresetID ?? presets(data)[0].id; selectedID = preset().layout.elements[0]?.id ?? null;
    drafts.clear(); history = new History(snapshot()); saved = exportDocument(data, activeID); render(); status(t('imported'));
  } catch (error) { status(`${t('invalid')}: ${errorMessage(error, language)}`, true); }
}
$('import').onclick = () => $('file').click();
$('file').onchange = async () => { await importFile($('file').files[0]); $('file').value = ''; };
$('download').onclick = () => {
  const invalid = document.querySelector('.sidebar input:invalid, .inspector input:invalid');
  if (invalid) { invalid.reportValidity(); status(`${t('errorInput')}: ${invalid.getAttribute('aria-label')}`, true); return; }
  if (drafts.size) { status(t('advancedHelp') + ' — ' + t('apply') + ' / ' + t('undo'), true); return; }
  try {
    const json = exportDocument(data, activeID), url = URL.createObjectURL(new Blob([json], { type: 'application/json' }));
    const link = element('a'); link.href = url; link.download = 'layout.dlspreset'; document.body.append(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
    saved = json; status(t('downloaded'));
  } catch (error) { status(errorMessage(error, language), true); }
};
$('new').onclick = () => {
  if (!confirmDiscard()) return; data = createDocument(t('newName'), true); activeID = data.id; selectedID = null; drafts.clear(); history = new History(snapshot()); saved = ''; render(); status(t('changed'));
};
$('add').onclick = () => mutate(() => { const e = createElement($('add-kind').value); preset().layout.elements.push(e); selectedID = e.id; });
$('layout-name').onchange = () => { const name = $('layout-name').value.trim(); if (!name) { status(t('emptyName'), true); $('layout-name').value = preset().name; return; } mutate(() => { preset().name = name; }); };
$('canvas-size').onchange = () => { [width, height] = $('canvas-size').value.split('x').map(Number); render(); };
$('language').onchange = () => { language = $('language').value; const url = new URL(location.href); url.searchParams.set('lang', language); window.history.replaceState(null, '', url); render(); status(dirty() ? t('changed') : t('ready')); };
$('preset').onchange = () => { activeID = $('preset').value; selectedID = preset().layout.elements[0]?.id ?? null; render(); status(dirty() ? t('changed') : t('ready')); };
$('grid').onchange = renderCanvas; $('background').onchange = renderCanvas;
$('fit').onclick = () => { $('canvas-wrap').scrollIntoView({ block: 'nearest', behavior: 'instant' }); renderCanvas(); };
$('undo').onclick = () => { restore(history.undo()); render(); status(dirty() ? t('changed') : t('ready')); };
$('redo').onclick = () => { restore(history.redo()); render(); status(dirty() ? t('changed') : t('ready')); };
$('copy').onclick = async () => { try { await navigator.clipboard.writeText($('command').textContent); status(t('copied')); } catch { status($('command').textContent); } };
function point(event) { return new DOMPoint(event.clientX, event.clientY).matrixTransform($('canvas').getScreenCTM().inverse()); }
$('canvas').onpointerdown = event => {
  if (event.button !== 0) return;
  const target = event.target.closest('[data-index]'), resize = event.target.hasAttribute('data-resize');
  if (!target && !resize) return;
  localPreview.pause();
  if (target) selectedID = preset().layout.elements[Number(target.dataset.index)].id;
  const e = selected(); if (!e) return;
  const p = point(event); drag = { start: p, frame: clone(e.frame), box: canvasScene.find(item => item.id === e.id).bounds, resize, previous: clone(snapshot()) };
  $('canvas').setPointerCapture(event.pointerId); event.preventDefault(); render(); $('canvas').focus({ preventScroll: true });
};
$('canvas').onpointermove = event => {
  if (!drag) return; const e = selected(), p = point(event);
  if (drag.resize) {
    e.frame.scale = Math.max(0.1, Math.min(4, drag.frame.scale * Math.max(1 + (p.x - drag.start.x) / drag.box.width, 1 + (p.y - drag.start.y) / drag.box.height)));
    e.frame.x = drag.frame.x; e.frame.y = drag.frame.y;
    const next = renderLayout(preset().layout, width, height, localPreview.frame()).find(item => item.id === e.id).bounds;
    e.frame.x = Math.max(-1, Math.min(2, e.frame.x + (drag.box.x - next.x) / width));
    e.frame.y = Math.max(-1, Math.min(2, e.frame.y + (drag.box.y - next.y) / height));
  }
  else { e.frame.x = Math.max(-1, Math.min(2, drag.frame.x + (p.x - drag.start.x) / width)); e.frame.y = Math.max(-1, Math.min(2, drag.frame.y + (p.y - drag.start.y) / height)); }
  renderCanvas();
};
function endDrag(event, cancel = false) {
  if (!drag) return; const previous = drag.previous; drag = null;
  if ($('canvas').hasPointerCapture(event.pointerId)) $('canvas').releasePointerCapture(event.pointerId);
  if (cancel) restore(previous);
  else { const next = clone(snapshot()); restore(previous); mutate(() => { restore(next); }); }
  render();
}
$('canvas').onpointerup = event => endDrag(event);
$('canvas').onpointercancel = event => endDrag(event, true);
$('canvas').onkeydown = event => {
  const target = event.target.closest('[data-index]');
  if (target && ['Enter', ' '].includes(event.key)) { event.preventDefault(); selectedID = preset().layout.elements[Number(target.dataset.index)].id; render(); $('canvas').focus(); }
};
document.addEventListener('keydown', event => {
  if (event.target.matches('input,textarea,select') || event.target.isContentEditable) return;
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'z') { event.preventDefault(); (event.shiftKey ? $('redo') : $('undo')).click(); return; }
  // Safari can deliver media-control arrow keys to the page body instead of the slider.
  if (!event.target.closest('#canvas, #layers')) return;
  const e = selected(); if (!e || !['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Delete', 'Backspace'].includes(event.key)) return;
  event.preventDefault();
  if (['Delete', 'Backspace'].includes(event.key)) { const b = document.querySelector('.inspector-actions .danger'); b?.click(); return; }
  const amount = event.shiftKey ? 10 : 1;
  mutate(() => { if (event.key === 'ArrowLeft') e.frame.x = Math.max(-1, e.frame.x - amount / width); if (event.key === 'ArrowRight') e.frame.x = Math.min(2, e.frame.x + amount / width); if (event.key === 'ArrowUp') e.frame.y = Math.max(-1, e.frame.y - amount / height); if (event.key === 'ArrowDown') e.frame.y = Math.min(2, e.frame.y + amount / height); });
});
document.addEventListener('dragover', event => { if ([...event.dataTransfer.types].includes('Files')) { event.preventDefault(); $('canvas-wrap').classList.add('drop-active'); } });
document.addEventListener('dragleave', event => { if (!event.relatedTarget) $('canvas-wrap').classList.remove('drop-active'); });
document.addEventListener('drop', async event => {
  event.preventDefault(); $('canvas-wrap').classList.remove('drop-active');
  for (const file of event.dataTransfer.files) {
    if (/\.(fit|gpx)$/i.test(file.name)) await localPreview.loadActivity(file);
    else if (file.type.startsWith('video/') || /\.(mp4|mov|m4v|webm|mkv|avi)$/i.test(file.name)) await localPreview.loadVideo(file);
    else await importFile(file);
  }
});
window.addEventListener('beforeunload', event => { if (dirty()) { event.preventDefault(); event.returnValue = ''; } });
new ResizeObserver(renderCanvas).observe($('canvas'));
render(); status(t('ready'));
fontsReady.then(renderCanvas);
