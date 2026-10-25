import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { createDocument, createElement } from '../model.mjs';
import { languages, translations } from '../i18n.mjs';
import { syntheticVideo, syntheticFIT } from './media-fixtures.mjs';

const activity = `<?xml version="1.0"?><gpx xmlns="http://www.topografix.com/GPX/1/1" xmlns:t="urn:test"><trk><type>running</type><trkseg>${[0,2,4].map((n,i)=>`<trkpt lat="0" lon="${i*.0001}"><time>2026-01-01T00:00:0${n}+08:00</time><extensions><t:hr>${110+i*10}</t:hr><t:cad>84</t:cad><t:speed>4</t:speed><t:distance>${i*8}</t:distance><t:atemp>12</t:atemp></extensions></trkpt>`).join('')}</trkseg></trk></gpx>`;
async function template(page) {
  const source = createDocument('Media regression', true), e = createElement('heartRate');
  source.layout.elements = [e];
  await page.locator('#file').setInputFiles({name:'layout.dlspreset',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(source))});
  return source;
}
async function uploadActivity(page) {
  await page.locator('#activity-file').setInputFiles({name:'activity.gpx',mimeType:'application/gpx+xml',buffer:Buffer.from(activity)});
  await expect(page.locator('#activity-name')).toContainText('activity.gpx');
}
async function video(page) {
  await page.locator('#video-file').setInputFiles({name:'local.mp4',mimeType:'video/mp4',buffer:syntheticVideo});
  await expect(page.locator('#preview-video')).toBeVisible({timeout:20000});
  await expect(page.locator('#canvas')).toHaveAttribute('viewBox','0 0 320 180');
}
async function seek(page, value) {
  await page.locator('#seek').evaluate((node,value)=>{node.value=String(value);node.dispatchEvent(new Event('input',{bubbles:true}));},value);
  await expect.poll(()=>page.locator('#preview-video').evaluate(node=>node.currentTime)).toBeCloseTo(value,1);
}
async function download(page) {
  const pending=page.waitForEvent('download');await page.locator('#download').click();const result=await pending;
  expect(result.suggestedFilename()).toBe('layout.dlspreset');return JSON.parse(await readFile(await result.path(),'utf8'));
}

test('template labels and local preview controls are translated in all twelve languages',async({page})=>{
  for(const language of Object.keys(languages)){
    await page.goto(`./?lang=${language}`);
    await expect(page.locator('#import')).toHaveText(translations[language].import);
    await expect(page.locator('#download')).toHaveText(translations[language].download);
    await expect(page.locator('#import-video')).toHaveText(translations[language].importVideo);
    await expect(page.locator('#import-activity')).toHaveText(translations[language].importActivity);
    await expect(page.locator('#play')).toBeDisabled();
    await expect(page.locator('body')).not.toContainText(/\bJSON\b/);
  }
});

test('local H.264 video decodes behind gauges, plays, seeks, offsets and preserves the template',async({page})=>{
  const errors=[],writes=[];page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(!['GET','HEAD'].includes(r.method()))writes.push(r.method());});
  await page.goto('./?lang=en');const source=await template(page);await uploadActivity(page);await video(page);
  expect(await page.locator('#preview-video').getAttribute('src')).toMatch(/^blob:/);
  const pixel=await page.locator('#preview-video').evaluate(node=>{
    const canvas=document.createElement('canvas');canvas.width=1;canvas.height=1;const c=canvas.getContext('2d');c.drawImage(node,0,0,1,1);return [...c.getImageData(0,0,1,1).data];
  });
  for(const [index,value]of [48,80,128].entries())expect(Math.abs(pixel[index]-value)).toBeLessThan(15);
  await expect(page.locator('#canvas text').filter({hasText:/^110$/})).toHaveCount(1);
  await page.locator('#play').click();await expect(page.locator('#play')).toHaveText(translations.en.pause);
  await expect.poll(()=>page.locator('#preview-video').evaluate(node=>node.currentTime)).toBeGreaterThan(.4);
  await page.locator('#play').click();expect(await page.locator('#preview-video').evaluate(node=>node.paused)).toBe(true);
  await seek(page,2);await expect(page.locator('#canvas text').filter({hasText:/^120$/})).toHaveCount(1);
  await page.locator('#sync-offset').fill('2');
  await expect(page.locator('#canvas text').filter({hasText:/^130$/})).toHaveCount(1);
  await seek(page,0);await expect(page.locator('#canvas text').filter({hasText:/^120$/})).toHaveCount(1);
  await page.locator('#sync-offset').fill('-3');await page.locator('#sync-offset').press('Tab');await expect(page.locator('#range-warning')).toHaveText(translations.en.outsideActivity);
  await expect(page.locator('#undo')).toBeDisabled();expect(await download(page)).toEqual(source);
  expect(errors).toEqual([]);expect(writes).toEqual([]);
});

test('unplayable replacement preserves the working video, and removal restores activity-only playback',async({page})=>{
  await page.goto('./?lang=en');await uploadActivity(page);await video(page);
  const source=await page.locator('#preview-video').getAttribute('src');
  await page.locator('#video-file').setInputFiles({name:'unsupported.mp4',mimeType:'video/mp4',buffer:Buffer.from('invalid container')});
  await expect(page.locator('#media-status')).toHaveText(translations.en.videoUnsupported,{timeout:20000});
  await expect(page.locator('#preview-video')).toHaveAttribute('src',source);
  await page.locator('#remove-video').click();await expect(page.locator('#preview-video')).toBeHidden();
  await expect(page.locator('#sync-offset')).toBeDisabled();await expect(page.locator('#play')).toBeEnabled();
  await page.locator('#play').click();await expect.poll(()=>page.locator('#seek').inputValue()).not.toBe('0');
  await page.locator('#play').click();await page.locator('#remove-activity').click();await expect(page.locator('#play')).toBeDisabled();
});

test('video without activity shows missing metrics and never borrows demo telemetry',async({page})=>{
  await page.goto('./?lang=en');await template(page);await video(page);
  await expect(page.locator('#preview-note')).toHaveText(translations.en.previewVideoOnly);
  await expect(page.locator('#canvas text').filter({hasText:/^148$/})).toHaveCount(0);
  await expect(page.locator('#canvas text').filter({hasText:/^--$/})).toHaveCount(1);
});

test('local FIT input drives real gauge values on the same wall-clock seek control',async({page})=>{
  await page.goto('./?lang=en');const source=await template(page);
  await page.locator('#activity-file').setInputFiles({name:'activity.fit',mimeType:'application/octet-stream',buffer:syntheticFIT});
  await expect(page.locator('#activity-name')).toContainText('3 samples');
  await expect(page.locator('#canvas text').filter({hasText:/^110$/})).toHaveCount(1);
  await page.locator('#seek').evaluate(node=>{node.value='4';node.dispatchEvent(new Event('input',{bubbles:true}));});
  await expect(page.locator('#canvas text').filter({hasText:/^130$/})).toHaveCount(1);
  expect(await download(page)).toEqual(source);
});

test('media arrow keys cannot move a gauge; selecting a layer still enables canvas nudge keys',async({page})=>{
  await page.goto('./?lang=en');const source=await template(page);await uploadActivity(page);await video(page);
  await page.locator('#canvas .hit').click();await page.locator('#seek').click();
  await page.locator('body').dispatchEvent('keydown',{key:'ArrowRight',bubbles:true});
  expect(await download(page)).toEqual(source);
  await page.locator('.layer-name').click();await page.keyboard.press('ArrowRight');
  expect((await download(page)).layout.elements[0].frame.x).toBeCloseTo(source.layout.elements[0].frame.x+1/320,8);
});
