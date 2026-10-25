import test from 'node:test';
import assert from 'node:assert/strict';
import { createNativeSeries } from '../telemetry-series.mjs';
import { applyingQuantizedAltitudeDisplaySmoothing as smooth } from '../telemetry-altitude.mjs';

function series(altitudes, changes = {}, pauses = []) {
  return createNativeSeries(altitudes.map((altitudeMeters,elapsed) => ({elapsed,date:1700000000+elapsed,distanceMeters:elapsed*3,speedMetersPerSecond:3,altitudeMeters,...changes[elapsed]})),pauses);
}
test('quantized altitude follows the native bounded triangular window without changing raw ascent', () => {
  const input = series([100,100,100,101,101,101,102,102,102]), before = structuredClone(input), output = smooth(input);
  assert.notEqual(output.samples[2].altitudeMeters, input.samples[2].altitudeMeters);
  assert.equal(output.samples[0].altitudeMeters,100); assert.equal(output.samples.at(-1).altitudeMeters,102);
  for (let i=0;i<input.samples.length;i++) {
    assert.ok(Math.abs(output.samples[i].altitudeMeters-input.samples[i].altitudeMeters)<=.5);
    assert.equal(output.samples[i].sourceAltitudeMeters,input.samples[i].altitudeMeters);
    assert.equal(output.samples[i].totalAscentMeters,input.samples[i].totalAscentMeters);
  }
  assert.deepEqual(input,before);
  assert.deepEqual(smooth(output),output);
  const rebuilt = createNativeSeries(output.samples,output.pausedRanges);
  assert.deepEqual(rebuilt.samples.map(s=>s.totalAscentMeters),output.samples.map(s=>s.totalAscentMeters));
});
test('high-precision altitudes stay unchanged and finite-source evidence takes precedence', () => {
  const precise = series([100.1,100.2,100.3,100.4,100.5]); assert.equal(smooth(precise),precise);
  const short = series([100,101]); assert.equal(smooth(short),short);
});
test('native gap, missing-altitude, track-segment and pause boundaries do not blend plateaus', () => {
  for (const variant of ['missing','segment','pause','gap']) {
    let input = series([100,100,100,200,200,200]);
    if (variant==='missing') input.samples[3].altitudeMeters=undefined;
    if (variant==='segment') input.samples.forEach((sample,i)=>{sample.trackSegmentIndex=i<3?0:1;});
    if (variant==='gap') input.samples.forEach((sample,i)=>{if(i>=3)sample.elapsed+=3;});
    if (variant==='pause') input.pausedRanges=[{start:2,duration:5}];
    const output=smooth(input);
    assert.equal(output.samples[2].altitudeMeters,100,variant);
    assert.equal(output.samples[4].altitudeMeters,200,variant);
  }
});
