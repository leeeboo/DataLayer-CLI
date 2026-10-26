import { copyFile, mkdir, readdir } from 'node:fs/promises';

// Publish runtime files only; browser-test dependencies and fixtures stay outside Pages.
const files = ['index.html', 'mark.svg', 'style.css', 'app.mjs', 'model.mjs', 'render.mjs', 'render-special.mjs', 'render-color.mjs', 'i18n.mjs', 'preview.mjs', 'telemetry.mjs', 'telemetry-series.mjs', 'telemetry-altitude.mjs', 'weather.mjs', 'default-preset.mjs', 'export/index.html', 'export/app.mjs', 'export/style.css', 'export/i18n.mjs', 'export/config.mjs', 'export/mp4.mjs', 'export/storage.mjs', 'export/encode-worker.mjs', 'export/isolation-worker.mjs', 'export/encoder/x265.mjs', 'export/encoder/x265.wasm', 'export/encoder/COPYING', 'export/encoder/EMSCRIPTEN-LICENSE', 'export/encoder/SYSTEM-LICENSES', 'export/encoder/README.md', 'export/encoder/bridge.cpp', 'export/encoder/build.sh', 'export/encoder/x265_4.1.tar.gz'];
const destination = new URL('../.build/gauge-pages/', import.meta.url);
await mkdir(destination, { recursive: true });
for (const file of files) {
  await mkdir(new URL('.', new URL(file, destination)), { recursive: true });
  await copyFile(new URL(file, import.meta.url), new URL(file, destination));
}
const allowed = new Set(files.flatMap(file => [file, ...file.split('/').slice(0,-1).map((_,index)=>file.split('/').slice(0,index+1).join('/'))]));
if ((await readdir(destination, { recursive: true })).some(file => !allowed.has(file))) throw Error('Unexpected file in generated Pages directory');
