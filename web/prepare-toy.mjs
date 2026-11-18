import { copyFile, mkdir, readdir, readFile, writeFile } from 'node:fs/promises';

const destination = new URL('../.build/datalayer-toy/', import.meta.url);
const modules = [
  'toy/preview.mjs',
  'default-preset.mjs',
  'model.mjs',
  'render.mjs',
  'render-color.mjs',
  'render-special.mjs',
  'telemetry.mjs',
  'telemetry-altitude.mjs',
  'telemetry-series.mjs',
];
const assets = [
  ['toy/index.html', 'index.html'],
  ['toy/style.css', 'toy/style.css'],
];
const outputModule = file => file.replace(/\.mjs$/, '.js');

await mkdir(new URL('toy/', destination), { recursive: true });
const allowed = new Set(['toy', ...assets.map(([, target]) => target), ...modules.map(outputModule)]);
const unexpected = (await readdir(destination, { recursive: true })).filter(path => !allowed.has(path));
if (unexpected.length) throw Error('Unexpected files in Toy package: ' + unexpected.join(', '));

for (const [source, target] of assets) {
  await copyFile(new URL(source, import.meta.url), new URL(target, destination));
}

// Keep the MIT notice in the served entry module as the host filters plain text assets.
const license = await readFile(new URL('../LICENSE', import.meta.url), 'utf8');
// Toy preview serves .js resources and drops .mjs files from its content package.
for (const file of modules) {
  const source = await readFile(new URL(file, import.meta.url), 'utf8');
  const script = source.replace(/(['"]\.\.?\/[\w/-]+)\.mjs(?=[?'"])/g, '$1.js');
  const notice = file === 'toy/preview.mjs' ? '/*\n' + license.trimEnd() + '\n*/\n' : '';
  await writeFile(new URL(outputModule(file), destination), notice + script);
}

console.log(destination.pathname);
