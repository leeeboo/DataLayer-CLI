import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { accents, fonts, gauges, createDocument, createElement, presets, parseDocument, validateDocument, exportDocument, bounds, History, clone } from '../web/model.mjs';
import { escapeXML, gaugeSVG } from '../web/render.mjs';
import { translations, languageFrom } from '../web/i18n.mjs';

const source = readFileSync(new URL('../Sources/OverlayCore/Rendering/OverlayLayout.swift', import.meta.url), 'utf8');
const nativeRenderer = readFileSync(new URL('../Sources/OverlayCore/Rendering/OverlayRenderer.swift', import.meta.url), 'utf8');
const section = (start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));
const cases = code => [...code.matchAll(/^    case (\w+)$/gm)].map(m => m[1]);
const requiredKeys = code => [...code.matchAll(/^    public var (\w+): [^\n?]+$/gm)].map(m => m[1]);

test('browser schema tracks all native kinds, fonts, accents and required Codable fields', () => {
  assert.deepEqual(gauges.map(g => g.kind), cases(section('public enum OverlayComponentID', '    public var id:')));
  assert.deepEqual(Object.keys(fonts), cases(section('public enum OverlayFontFamily', '    public var id:')));
  assert.deepEqual(Object.keys(accents), cases(section('public enum OverlayAccentColor', '    public var id:')));
  const e = createElement('speed'), doc = createDocument();
  for (const [start, end, value] of [
    ['public struct OverlayElementCustomization', '    public init(', e.customization],
    ['public struct OverlayComponentFrame', '    public init(', e.frame],
    ['public struct OverlayComponentStyle', '    public init(', e.frame.style],
    ['public struct OverlayStyle', '    public init(', doc.layout.style],
  ]) for (const key of requiredKeys(section(start, end))) assert.ok(Object.hasOwn(value, key), `${start}.${key}`);
  assert.deepEqual(doc.layout.elements.map(e => e.kind), ['topProgress', 'speed', 'pace', 'distance', 'heartRate', 'cadence', 'route', 'timeDate']);
  for (const g of gauges) {
    const e = createElement(g.kind); assert.equal(e.frame.x, g.x); assert.equal(e.frame.y, g.y);
    validateDocument({ ...createDocument(), layout: { ...doc.layout, elements: [e] } });
  }
});
test('browser positions, overrides and bounding boxes stay aligned with native definitions', () => {
  const frames = section('    static func defaultFrame(', '    static func defaultCustomization(');
  for (const block of frames.split(/\n        case \./).slice(1)) {
    const kind = block.match(/^(\w+):/)[1], frame = createElement(kind).frame;
    for (const key of ['x', 'y', 'scale']) assert.equal(frame[key], Number(block.match(new RegExp(`\\b${key}:\\s*([\\d.]+)`))?.[1] ?? 1), `${kind}.${key}`);
    for (const key of ['accentColor', 'panelOpacity']) {
      const match = block.match(new RegExp(`${key}:\\s*\\.?([\\w.]+)`));
      assert.equal(frame.style[key], match ? (key === 'panelOpacity' ? Number(match[1]) : match[1]) : undefined, `${kind}.${key}`);
    }
  }
  const sizes = nativeRenderer.slice(nativeRenderer.indexOf('    private func baseSize('), nativeRenderer.indexOf('    private func showsGaugeTicks('));
  for (const block of sizes.split(/\n        case /).slice(1)) {
    const kinds = [...block.slice(0, block.indexOf(':')).matchAll(/\.(\w+)/g)].map(m => m[1]);
    const size = (block.includes('Self.routeBaseSize') ? nativeRenderer.match(/routeBaseSize = CGSize\(width: (\d+), height: (\d+)\)/) : block.match(/CGSize\(width: (\d+), height: (\d+)\)/));
    assert.ok(size);
    for (const kind of kinds) { const g = gauges.find(g => g.kind === kind); assert.equal(g.width, Number(size[1])); assert.equal(g.height, Number(size[2])); }
  }
});
test('single preset export is readable again without discarding unedited or future fields', () => {
  const doc = createDocument(); doc.future = { revision: 8 }; doc.layout.elements[0].customization.progressTickCount = 84;
  doc.layout.elements[1].customization.valueColor = { red: 0.2, green: 0.4, blue: 0.6, alpha: 0.3 };
  const imported = parseDocument(JSON.stringify(doc)); imported.layout.elements[1].frame.x = 0.125;
  const expected = clone(doc); expected.layout.elements[1].frame.x = 0.125;
  assert.deepEqual(parseDocument(exportDocument(imported, imported.id)), expected);
  assert.equal(typeof imported.createdAt, 'number');
  for (const unit of ['m', 'km', 'mi']) { doc.layout.elements[0].customization.distanceUnit = unit; assert.equal(parseDocument(JSON.stringify(doc)).layout.elements[0].customization.distanceUnit, unit); }
});
test('multi-preset library keeps other presets and metadata; selected preset is CLI default', () => {
  const first = createDocument('A'), second = createDocument('B'); second.future = 'untouched';
  const library = { presets: [first, second], defaultPresetID: first.id, futureLibraryData: { keep: true } };
  const doc = parseDocument(JSON.stringify(library)); presets(doc)[1].layout.elements[0].frame.scale = 1.2;
  const output = parseDocument(exportDocument(doc, second.id));
  assert.deepEqual(output.presets[0], first); assert.equal(output.defaultPresetID, second.id);
  assert.deepEqual(output.futureLibraryData, library.futureLibraryData); assert.equal(output.presets[1].future, 'untouched');
  assert.equal(doc.defaultPresetID, first.id, 'export must not mutate the source document');
});
test('invalid files and known field types are rejected before replacing current work', () => {
  for (const change of [
    d => { d.layout.elements[0].kind = 'unknown'; },
    d => { d.layout.elements[0].frame.x = 1e400; },
    d => { d.layout.elements[0].frame.x = 3; },
    d => { d.layout.elements[0].frame.isVisible = 'yes'; },
    d => { d.layout.elements[0].customization.valueFont = null; },
    d => { delete d.layout.elements[0].customization.showsLabel; },
    d => { d.layout.elements[0].customization.valuePrecision = 1.5; },
    d => { d.layout.elements[0].customization.valueColor = { red: 1, green: 1, blue: 1 }; },
    d => { d.layout.elements[0].customization.gaugeMinimum = 20; d.layout.elements[0].customization.gaugeMaximum = 10; },
    d => { d.layout.elements[0].frame.style.accentColor = 'red'; },
    d => { d.layout.elements[1].id = d.layout.elements[0].id; },
    d => { d.createdAt = '2026-10-25'; },
    d => { d.name = ' '; },
  ]) { const doc = createDocument(); change(doc); assert.throws(() => parseDocument(JSON.stringify(doc))); }
  for (const text of ['{', 'null', '[]', '{"presets":[]}', '{"__proto__":{"polluted":true}}', ' '.repeat(5 * 1024 * 1024 + 1)]) assert.throws(() => parseDocument(text));
  assert.equal({}.polluted, undefined);
});
test('native coordinate geometry handles aspect ratios and independent width customization', () => {
  const e = createElement('speed'); assert.deepEqual(bounds(e, 1920, 1080), { x: 48, y: 736.5600000000001, width: 420, height: 238 });
  e.customization.lengthScale = 2; assert.equal(bounds(e, 1920, 1080).width, 840); assert.equal(bounds(e, 1920, 1080).height, 238);
  assert.equal(bounds(e, 3840, 2160).width, 1680);
  const altitude = createElement('altitudeProfile'); altitude.customization.altitudeWidthScale = 2; altitude.customization.altitudeHeightScale = 3;
  assert.equal(bounds(altitude, 1920, 1080).width, 840 * 0.65 * 2); assert.equal(bounds(altitude, 1920, 1080).height, 520 * 0.65 * 3);
});
test('history isolates snapshots, branches after undo and has a bounded memory footprint', () => {
  const value = { data: createDocument() }, history = new History(value); value.data.name = 'B'; history.push(value);
  value.data.name = 'C'; assert.notEqual(history.entries[history.index].data.name, 'C');
  assert.notEqual(history.undo().data.name, 'B'); assert.equal(history.redo().data.name, 'B');
  history.undo(); history.push(value); assert.equal(history.entries.length, 2); assert.equal(history.redo().data.name, 'C');
  for (let n = 0; n < 90; n++) { value.data.name = String(n); history.push(value); }
  assert.equal(history.entries.length, 80); assert.equal(history.index, 79);
});
test('all 24 gauge previews render escaped user text without script or network markup', () => {
  const doc = createDocument();
  for (const g of gauges) {
    const e = createElement(g.kind); e.customization.labelOverride = '<img src=x onerror=alert(1)>'; e.customization.unitOverride = '</text><script>alert(1)</script>';
    const markup = gaugeSVG(e, doc.layout, 1920, 1080);
    assert.ok(markup.includes('<g')); assert.ok(!markup.includes('<script>')); assert.ok(!markup.includes('<img')); assert.ok(!markup.includes('NaN')); assert.ok(!markup.includes('undefined'));
  }
  assert.equal(escapeXML('<&"\''), '&lt;&amp;&quot;&apos;');
});
test('all four UI languages have the same keys and complete gauge labels', () => {
  for (const [language, dictionary] of Object.entries(translations)) {
    assert.deepEqual(Object.keys(dictionary).sort(), Object.keys(translations.en).sort());
    for (const text of Object.values(dictionary)) assert.ok(typeof text === 'string' && text.trim());
    for (const gauge of gauges) assert.ok(gauge.titles[language]);
  }
  assert.equal(languageFrom('zh-Hant-HK'), 'zh-TW'); assert.equal(languageFrom('ja-JP'), 'ja'); assert.equal(languageFrom('de-DE'), 'en');
});
