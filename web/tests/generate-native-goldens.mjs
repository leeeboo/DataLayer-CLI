// Rebuild oracle only: node web/tests/generate-native-goldens.mjs --build-only
// Regenerate synthetic goldens from current Swift: node web/tests/generate-native-goldens.mjs
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));
export const repository = resolve(here, '../..');
export const nativeSources = [
  'Sources/OverlayCore/Telemetry/TelemetrySample.swift',
  'Sources/OverlayCore/Telemetry/TelemetrySeries.swift',
  'Sources/OverlayCore/Telemetry/ActivityTrim.swift',
  'Sources/OverlayCore/Telemetry/TelemetrySport.swift',
  'Sources/OverlayCore/Rendering/OverlayTimeZone.swift',
  'Sources/OverlayCore/FIT/ByteReader.swift',
  'Sources/OverlayCore/FIT/FITCRC.swift',
  'Sources/OverlayCore/FIT/FITError.swift',
  'Sources/OverlayCore/FIT/FITFieldDecoder.swift',
  'Sources/OverlayCore/FIT/FITParser.swift',
];
export function nativeSourceHashes() {
  return Object.fromEntries([...nativeSources,
    'Sources/OverlayCore/Rendering/OverlayRenderer.swift',
    'Sources/OverlayCore/Rendering/OverlayRenderConfig.swift',
    'Sources/OverlayCore/Rendering/OverlayLayout.swift',
  ].map(path => [path, createHash('sha256').update(readFileSync(join(repository, path))).digest('hex')]));
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const sourceHashes = nativeSourceHashes();
  const directory = mkdtempSync(join(tmpdir(), 'dls-native-reference-'));
  const binary = join(directory, 'native-reference');
  let keepDirectory = false;
  try {
    execFileSync('swiftc', ['-O', '-parse-as-library', ...nativeSources.map(path => join(repository, path)), join(here, 'native-reference.swift'), '-o', binary], { stdio: 'inherit' });
    console.log(`Compiled current Swift sources: ${binary}`);
    if (process.argv.includes('--build-only')) {
      keepDirectory = true;
    } else {
      const { nativeParityInputs, nativeDisplayInputs } = await import('./native-parity-inputs.mjs');
      const cases = nativeParityInputs.map(({ name, input }) => {
        const inputPath = join(directory, 'synthetic-input.json');
        const outputPath = join(directory, 'synthetic-output.json');
        writeFileSync(inputPath, JSON.stringify(input));
        execFileSync(binary, [inputPath, outputPath]);
        return { name, inputHash: createHash('sha256').update(JSON.stringify(input)).digest('hex'), expected: JSON.parse(readFileSync(outputPath, 'utf8')) };
      });
      const displayCases = nativeDisplayInputs.map(({ name, input }) => {
        const inputPath = join(directory, 'synthetic-display-input.json');
        const outputPath = join(directory, 'synthetic-display-output.json');
        writeFileSync(inputPath, JSON.stringify(input));
        execFileSync(binary, [inputPath, outputPath, '--display'], { env: { ...process.env, TZ: 'UTC' } });
        return { name, inputHash: createHash('sha256').update(JSON.stringify(input)).digest('hex'), expected: JSON.parse(readFileSync(outputPath, 'utf8')) };
      });
      if (JSON.stringify(sourceHashes) !== JSON.stringify(nativeSourceHashes())) throw new Error('Native sources changed during generation; rerun.');
      writeFileSync(join(here, 'native-goldens.json'), `${JSON.stringify({ schemaVersion: 1, sourceHashes, cases, displayCases }, null, 2)}\n`);
      console.log(`Generated ${cases.length} synthetic native goldens and ${displayCases.length} display cases.`);
    }
  } finally {
    if (!keepDirectory) rmSync(directory, { recursive: true, force: true });
  }
}
