import { copyFile, mkdir, readdir } from 'node:fs/promises';

// Publish runtime files only; browser-test dependencies and fixtures stay outside Pages.
const files = ['index.html', 'mark.svg', 'style.css', 'app.mjs', 'model.mjs', 'render.mjs', 'render-special.mjs', 'render-color.mjs', 'i18n.mjs', 'preview.mjs', 'telemetry.mjs'];
const destination = new URL('../.build/gauge-pages/', import.meta.url);
await mkdir(destination, { recursive: true });
for (const file of files) await copyFile(new URL(file, import.meta.url), new URL(file, destination));
if ((await readdir(destination)).some(file => !files.includes(file))) throw Error('Unexpected file in generated Pages directory');
