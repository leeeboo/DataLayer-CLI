import {openEditor} from './editor-page.mjs';
import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import {createDocument,createElement} from '../model.mjs';
import {languages,translations} from '../i18n.mjs';
import {syntheticFIT} from './media-fixtures.mjs';

const activity=`<?xml version="1.0"?><gpx xmlns="http://www.topografix.com/GPX/1/1" xmlns:t="urn:test"><trk><type>running</type><trkseg>${[0,2,4].map((n,i)=>`<trkpt lat="0" lon="${i*.0001}"><time>2026-01-01T00:00:0${n}+08:00</time><extensions><t:hr>${110+i*10}</t:hr><t:cad>84</t:cad><t:speed>4</t:speed><t:distance>${i*8}</t:distance><t:atemp>12</t:atemp></extensions></trkpt>`).join('')}</trkseg></trk></gpx>`;
async function template(page){const source=createDocument('Activity regression',true);source.layout.elements=[createElement('heartRate')];await page.locator('#file').setInputFiles({name:'layout.dlspreset',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(source))});return source;}
async function uploadActivity(page){await page.locator('#activity-file').setInputFiles({name:'activity.gpx',mimeType:'application/gpx+xml',buffer:Buffer.from(activity)});await expect(page.locator('#activity-name')).toContainText('activity.gpx');}
async function seek(page,value){await page.locator('#seek').evaluate((node,value)=>{node.value=String(value);node.dispatchEvent(new Event('input',{bubbles:true}));},value);}
async function download(page){const pending=page.waitForEvent('download');await page.locator('#download').click();const result=await pending;expect(result.suggestedFilename()).toBe('layout.dlspreset');return JSON.parse(await readFile(await result.path(),'utf8'));}

test('activity-only controls are translated in all twelve languages with no local video input',async({page})=>{
  for(const language of Object.keys(languages)){
    await openEditor(page,`./?lang=${language}`);
    await expect(page.locator('#import')).toHaveText(translations[language].import);await expect(page.locator('#download')).toHaveText(translations[language].download);
    await expect(page.locator('.media-panel h2')).toHaveText(translations[language].previewSources);await expect(page.locator('#import-activity')).toHaveText(translations[language].importActivity);
    await expect(page.locator('video,#video-file,#import-video,#sync-offset')).toHaveCount(0);await expect(page.locator('#play')).toBeDisabled();await expect(page.locator('body')).not.toContainText(/\bJSON\b/);
  }
});

test('GPX activity plays, pauses and seeks real gauges without modifying the layout',async({page})=>{
  const errors=[],writes=[];page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(!['GET','HEAD'].includes(r.method()))writes.push(r.method());});
  await openEditor(page);const source=await template(page);await uploadActivity(page);await expect(page.locator('#canvas')).toHaveAttribute('viewBox','0 0 1920 1080');
  await expect(page.locator('#canvas text').filter({hasText:/^110$/})).toHaveCount(1);await page.locator('#play').click();await expect(page.locator('#play')).toHaveText(translations.en.pause);
  await expect.poll(async()=>Number(await page.locator('#seek').inputValue())).toBeGreaterThan(.4);await page.locator('#play').click();await expect(page.locator('#play')).toHaveText(translations.en.play);
  await seek(page,2);await expect(page.locator('#canvas text').filter({hasText:/^120$/})).toHaveCount(1);await seek(page,4);await expect(page.locator('#canvas text').filter({hasText:/^130$/})).toHaveCount(1);
  await expect(page.locator('#undo')).toBeDisabled();expect(await download(page)).toEqual(source);expect(errors).toEqual([]);expect(writes).toEqual([]);
});

test('invalid activity replacement preserves the loaded data and removing it resets playback',async({page})=>{
  await openEditor(page);const source=await template(page);await uploadActivity(page);await seek(page,2);
  await page.locator('#activity-file').setInputFiles({name:'broken.fit',mimeType:'application/octet-stream',buffer:Buffer.from('invalid FIT')});await expect(page.locator('#media-status')).toHaveText(translations.en.activityMalformed);
  await expect(page.locator('#activity-name')).toContainText('activity.gpx');await expect(page.locator('#seek')).toHaveValue('2');await expect(page.locator('#canvas text').filter({hasText:/^120$/})).toHaveCount(1);expect(await download(page)).toEqual(source);
  await page.locator('#remove-activity').click();await expect(page.locator('#play')).toBeDisabled();await expect(page.locator('#seek')).toHaveValue('0');await expect(page.locator('#preview-note')).toHaveText(translations.en.preview);
});

test('local FIT drives real gauge values on the activity seek control',async({page})=>{
  await openEditor(page);const source=await template(page);await page.locator('#activity-file').setInputFiles({name:'activity.fit',mimeType:'application/octet-stream',buffer:syntheticFIT});await expect(page.locator('#activity-name')).toContainText('5 samples');
  await expect(page.locator('#canvas text').filter({hasText:/^110$/})).toHaveCount(1);await seek(page,4);await expect(page.locator('#canvas text').filter({hasText:/^130$/})).toHaveCount(1);expect(await download(page)).toEqual(source);
});

test('activity seek arrows cannot nudge a gauge; layer selection still enables canvas keys',async({page})=>{
  await openEditor(page);const source=await template(page);await uploadActivity(page);await page.locator('#canvas .hit').click();await page.locator('#seek').click();await page.locator('body').dispatchEvent('keydown',{key:'ArrowRight',bubbles:true});expect(await download(page)).toEqual(source);
  await page.locator('.layer-name').click();await page.keyboard.press('ArrowRight');expect((await download(page)).layout.elements[0].frame.x).toBeCloseTo(source.layout.elements[0].frame.x+1/1920,8);
});

test('dropping a local movie is rejected without loading media or replacing the layout',async({page})=>{
  const errors=[];page.on('pageerror',e=>errors.push(e.message));await openEditor(page);const source=await template(page);
  await page.evaluate(()=>{const data=new DataTransfer();data.items.add(new File(['not a layout template'],'local.mp4',{type:'video/mp4'}));document.dispatchEvent(new DragEvent('drop',{bubbles:true,cancelable:true,dataTransfer:data}));});
  await expect(page.locator('#status')).toHaveClass(/error/);await expect(page.locator('video,input[accept*="video/"]')).toHaveCount(0);expect(await download(page)).toEqual(source);expect(errors).toEqual([]);
});
