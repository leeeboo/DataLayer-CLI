import {openEditor,mockWeather} from './editor-page.mjs';
import {test as base,expect} from '@playwright/test';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {syntheticFIT} from './media-fixtures.mjs';
import {languages,translations} from '../export/i18n.mjs';
import {createDocument} from '../model.mjs';
import {nals,nalLayer,nalType} from '../export/mp4.mjs';
// WebKit needs persistent OPFS; its automation profiles share storage, so serialize.
const test=base.extend({context:async({playwright,browserName,baseURL,viewport},use)=>{
  const profile=await mkdtemp(join(tmpdir(),'dls-export-browser-'));
  const context=await playwright[browserName].launchPersistentContext(profile,{headless:true,baseURL,viewport});
  try{await use(context);}finally{await context.close();await rm(profile,{recursive:true,force:true});}
}});
test.describe.configure({mode:'default'});
async function open(page,lang='en'){await openEditor(page,`./?lang=${lang}`);}
async function activity(page){
  await page.locator('#activity-file').setInputFiles({name:'activity.fit',mimeType:'application/octet-stream',buffer:syntheticFIT});
  await expect(page.locator('#activity-name')).toContainText('activity.fit');await page.locator('#web-export').click();
  const capabilities=await page.evaluate(async()=>{
    const registration=await navigator.serviceWorker?.getRegistration();
    return {isolated:crossOriginIsolated,secure:isSecureContext,controller:navigator.serviceWorker?.controller?.scriptURL,active:registration?.active?.scriptURL,sharedArrayBuffer:typeof SharedArrayBuffer,worker:typeof Worker,storage:typeof navigator.storage?.getDirectory,locks:!!navigator.locks};
  });
  await expect(page.locator('#export-encode'),JSON.stringify(capabilities)).toBeEnabled();
}
async function configure(page,{duration='.2',bitrate='8',size='1280x720',start='0'}={}){
  await page.locator('#export-size').selectOption(size);await page.locator('#export-duration').fill(duration);await page.locator('#export-start').fill(start);await page.locator('#export-bitrate').fill(bitrate);await page.locator('#export-bitrate').press('Tab');
}
async function encode(page){
  await page.locator('#export-encode').click();await expect(page.locator('#export-download')).toBeVisible({timeout:30000});
  const next=page.waitForEvent('download');await page.locator('#export-download').click();const result=await next;
  expect(result.suggestedFilename()).toBe('703-hevc-alpha.mp4');return readFile(await result.path());
}
function boxes(data,start=0,end=data.length){const all=[];for(let p=start;p<end;){const extended=data.readUInt32BE(p)===1,size=extended?Number(data.readBigUInt64BE(p+8)):data.readUInt32BE(p),head=extended?16:8;expect(size).toBeGreaterThanOrEqual(head);expect(p+size).toBeLessThanOrEqual(end);all.push({type:data.toString('ascii',p+4,p+8),start:p+head,end:p+size});p+=size;}return all;}
function child(data,parent,type){const box=boxes(data,parent.start,parent.end).find(b=>b.type===type);expect(box).toBeTruthy();return box;}
function inspect(data,frames,fps){
  const top=boxes(data),moov=top.find(b=>b.type==='moov'),mdat=top.find(b=>b.type==='mdat');
  expect(data.includes(Buffer.from('muxa'))).toBe(true);
  const mdia=child(data,child(data,moov,'trak'),'mdia'),mdhd=child(data,mdia,'mdhd');
  expect(data.readUInt32BE(mdhd.start+12)).toBe(fps);expect(data.readUInt32BE(mdhd.start+16)).toBe(frames);
  const stbl=child(data,child(data,mdia,'minf'),'stbl'),stsz=child(data,stbl,'stsz');expect(data.readUInt32BE(stsz.start+8)).toBe(frames);
  let position=mdat.start;
  for(let i=0;i<frames;i++){
    const length=data.readUInt32BE(stsz.start+12+i*4),units=nals(data.subarray(position,position+length));
    for(const layer of [0,1])expect(units.some(n=>nalType(n)<32&&nalLayer(n)===layer)).toBe(true);
    position+=length;
  }
  expect(position).toBe(mdat.end);
  const stsd=child(data,stbl,'stsd'),hvc1=boxes(data,stsd.start+8,stsd.end)[0];
  const hvcc=boxes(data,hvc1.start+78,hvc1.end).find(b=>b.type==='hvcC');
  expect(data.readUInt16BE(hvcc.start+19)).toBe(0);
}
function health(page){const errors=[],requests=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});page.on('request',r=>{if(!['GET','HEAD'].includes(r.method()))requests.push(r.url());});return {errors,requests};}

test('703 FIT export preserves both layers, exact frame duration and bitrate selection without uploads',async({page,browserName})=>{
  const result=health(page);await open(page);await activity(page);await configure(page,{bitrate:'1'});
  const low=await encode(page);inspect(low,6,30);
  await configure(page,{bitrate:'8',duration:'.23334'});const high=await encode(page);inspect(high,8,30);
  await expect(page.locator('#export-result')).toContainText('8 frames');await expect(page.locator('#export-result')).toContainText('0.267 s');
  expect(high.length).toBeGreaterThan(low.length);
  if(browserName==='webkit'&&process.platform==='darwin'){
    const decoded=await page.evaluate(async bytes=>{
      const reference=document.getElementById('export-preview'),ctx=reference.getContext('2d'),source=ctx.getImageData(0,0,reference.width,reference.height).data;
      const points=[];
      for(const target of [0,128,255]){let at=-1;for(let i=3;i<source.length;i+=4){if(source[i]===target){at=(i-3)/4;break;}}if(at<0)throw Error('missing reference Alpha');points.push(at);}
      const url=URL.createObjectURL(new Blob([new Uint8Array(bytes)],{type:'video/mp4'}));
      const video=document.createElement('video');video.muted=true;video.src=url;
      await new Promise((resolve,reject)=>{video.onloadeddata=resolve;video.onerror=()=>reject(Error('decode failed'));});
      await new Promise(resolve=>{video.onseeked=resolve;video.currentTime=7/30;});
      const canvas=document.createElement('canvas');canvas.width=reference.width;canvas.height=reference.height;
      const c=canvas.getContext('2d');c.drawImage(video,0,0);const output=c.getImageData(0,0,canvas.width,canvas.height).data;
      const duration=video.duration;video.pause();video.removeAttribute('src');video.load();URL.revokeObjectURL(url);return {alpha:points.map(p=>[source[p*4+3],output[p*4+3]]),duration};
    },Array.from(high));
    for(const [source,actual]of decoded.alpha)expect(Math.abs(source-actual)).toBeLessThanOrEqual(12);
    expect(decoded.duration).toBeCloseTo(8/30,5);
  }
  expect(result.errors).toEqual([]);expect(result.requests).toEqual([]);
});

test('trimmed 703 FIT export matches the same original interval, including Alpha and fractional frames',async({page})=>{
  const result=health(page);await open(page);await activity(page);await configure(page,{start:'1.25',duration:'.23334',size:'1920x1080'});
  const reference=await encode(page);inspect(reference,8,30);await page.locator('#export-close').click();
  await page.locator('#trim-start').fill('1.25');await page.locator('#trim-start').press('Tab');await page.locator('#trim-end').fill('1.48334');await page.locator('#trim-end').press('Tab');
  await page.locator('#web-export').click();await expect(page.locator('#export-start')).toHaveValue('1.25');await expect(page.locator('#export-duration')).toHaveValue('0.23334');await expect(page.locator('#export-full')).toHaveText('Selected range');
  // Exercise the JavaScript boundary as well as the browser's numeric constraints.
  await page.locator('#export-start').fill('0');await page.locator('#export-form').dispatchEvent('submit');await expect(page.locator('#export-status')).toHaveText(translations.en.exportInvalid);await expect(page.locator('#export-download')).toBeHidden();
  await page.locator('#export-full').click();const trimmed=await encode(page);inspect(trimmed,8,30);expect(trimmed.equals(reference)).toBe(true);
  await page.locator('#export-close').click();await page.locator('#trim-reset').click();await page.locator('#web-export').click();await expect(page.locator('#export-start')).toHaveValue('0');await expect(page.locator('#export-duration')).toHaveValue('4');await expect(page.locator('#export-full')).toHaveText(translations.en.exportFullActivity);
  expect(result.errors).toEqual([]);expect(result.requests).toEqual([]);
});

test('legacy export URLs open the integrated editor without loading WASM eagerly',async({page})=>{
  const wasm=[];page.on('request',r=>{if(r.url().includes('.wasm'))wasm.push(r.url());});
  await openEditor(page,'./export/?lang=zh-CN');await expect(page.locator('#web-export')).toHaveText('导出透明视频');
  expect(new URL(page.url()).pathname.endsWith('/export/')).toBe(false);expect(await page.evaluate(()=>crossOriginIsolated)).toBe(true);
  await expect(page.locator('#canvas [data-index]')).toHaveCount(8);expect(wasm).toEqual([]);
});

test('full activity selection crosses keyframes and memory growth without retaining compressed samples',async({page})=>{
  test.setTimeout(60000);const result=health(page);await open(page);await activity(page);
  await configure(page,{duration:'.1',start:'1'});await page.locator('#export-full').click();
  await expect(page.locator('#export-start')).toHaveValue('0');await expect(page.locator('#export-duration')).not.toHaveValue('.1');
  await page.evaluate(()=>{window.heaps=[];const Base=Worker;window.Worker=class extends Base{constructor(...args){super(...args);this.addEventListener('message',({data})=>{if(data.heapBytes)heaps.push(data.heapBytes);if(data.bytes)throw Error('compressed samples escaped streaming worker');});}};});
  await configure(page,{size:'1920x1080',duration:'3'});inspect(await encode(page),90,30);
  expect((await page.evaluate(()=>heaps)).length).toBe(90);
  expect(Math.max(...await page.evaluate(()=>heaps))).toBeLessThanOrEqual(512*1024*1024);
  await page.reload();await expect(page.locator('html')).toHaveAttribute('data-editor-ready','true',{timeout:20000});await activity(page);await expect(page.locator('#export-encode')).toBeEnabled();
  await expect.poll(()=>page.evaluate(async()=>{const root=await(await navigator.storage.getDirectory()).getDirectoryHandle('dls-hevc-exports');let count=0;for await(const _ of root.entries())count++;return count;})).toBe(0);
  expect(result.errors).toEqual([]);expect(result.requests).toEqual([]);
});

test('large local downloads stream beyond 128 MiB, support ranges and survive cleanup while reading',async({page})=>{
  test.setTimeout(60000);await open(page);
  await page.evaluate(async()=>{
    const {reserveExport}=await import('./export/storage.mjs?v=20261026-full1');window.diskExport=await reserveExport();
    const source=`onmessage=async({data:name})=>{const root=await(await navigator.storage.getDirectory()).getDirectoryHandle('dls-hevc-exports');const file=await root.getFileHandle(name,{create:true});const h=await file.createSyncAccessHandle();const bytes=new Uint8Array(1024*1024).fill(7);for(let i=0;i<160;i++){bytes[0]=i;h.write(bytes,{at:i*bytes.length});}h.flush();h.close();postMessage(true);}`;
    const url=URL.createObjectURL(new Blob([source],{type:'text/javascript'})),worker=new Worker(url);
    try{await new Promise((resolve,reject)=>{worker.onmessage=resolve;worker.onerror=reject;worker.postMessage(diskExport.name);});}finally{worker.terminate();URL.revokeObjectURL(url);}
    const a=document.createElement('a');a.id='large-download';a.textContent='Download test';a.href=new URL(`./download/${diskExport.name}/large.mp4`,location.href);document.body.append(a);
    const end=await fetch(a.href,{headers:{Range:'bytes=-8'}});if(end.status!==206||(await end.arrayBuffer()).byteLength!==8)throw Error('invalid byte range');
    const invalid=await fetch(a.href,{headers:{Range:'bytes=999999999999-'}});if(invalid.status!==416)throw Error('invalid range accepted');
  });
  const pending=page.waitForEvent('download');await page.locator('#large-download').click();const download=await pending;
  const removal=page.evaluate(()=>diskExport.remove());
  const {createReadStream}=await import('node:fs'),{createHash}=await import('node:crypto');
  const actual=createHash('sha256');let size=0;
  for await(const part of createReadStream(await download.path())){actual.update(part);size+=part.length;}
  const expected=createHash('sha256'),chunk=Buffer.alloc(1024*1024,7);for(let i=0;i<160;i++){chunk[0]=i;expected.update(chunk);}
  expect(size).toBe(160*1024*1024);expect(actual.digest('hex')).toBe(expected.digest('hex'));await removal;
});

test('Unicode template names and quotes produce a usable local download',async({page})=>{
  await open(page);await activity(page);
  const name="中文'()-\ud800";
  await page.locator('#file').setInputFiles({name:'named.dlspreset',mimeType:'application/octet-stream',buffer:Buffer.from(JSON.stringify(createDocument(name,true)))});
  await configure(page,{duration:'.1'});await page.locator('#export-encode').click();await expect(page.locator('#export-download')).toBeVisible();
  const next=page.waitForEvent('download');await page.locator('#export-download').click();const result=await next;
  expect(result.suggestedFilename()).toBe("中文'()-�-hevc-alpha.mp4");inspect(await readFile(await result.path()),3,30);
});


test('an empty layout encodes fully transparent frames instead of an opaque fallback',async({page,browserName})=>{
  const result=health(page);await open(page);await activity(page);
  await page.locator('#file').setInputFiles({name:'blank.dlspreset',mimeType:'application/octet-stream',buffer:Buffer.from(JSON.stringify(createDocument('703',true)))});
  await configure(page,{duration:'.1'});const bytes=await encode(page);inspect(bytes,3,30);
  if(browserName==='webkit'&&process.platform==='darwin'){
    const maximum=await page.evaluate(async bytes=>{
      const url=URL.createObjectURL(new Blob([new Uint8Array(bytes)],{type:'video/mp4'}));
      const video=document.createElement('video');video.muted=true;video.src=url;
      await new Promise((resolve,reject)=>{video.onloadeddata=resolve;video.onerror=reject;});
      const c=document.createElement('canvas');c.width=video.videoWidth;c.height=video.videoHeight;const ctx=c.getContext('2d');ctx.drawImage(video,0,0);
      const pixels=ctx.getImageData(0,0,c.width,c.height).data;let max=0;for(let i=3;i<pixels.length;i+=4)max=Math.max(max,pixels[i]);video.removeAttribute('src');video.load();URL.revokeObjectURL(url);return max;
    },Array.from(bytes));expect(maximum).toBe(0);
  }
  expect(result.errors).toEqual([]);expect(result.requests).toEqual([]);
});

test('WASM Alpha keeps full-range 0, 64, 128, 192 and 255 levels rather than video-range expansion',async({page,browserName})=>{
  const healthResult=health(page);await open(page);
  const result=await page.evaluate(async checkDecode=>{
    const worker=new Worker(new URL('./export/encode-worker.mjs',location.href),{type:'module'});let id=0;
    const request=(type,data={},transfer=[])=>new Promise((resolve,reject)=>{worker.onmessage=({data:reply})=>reply.error?reject(Error('encoder failed')):resolve(reply.bytes);worker.onerror=reject;worker.postMessage({id:++id,type,...data},transfer);});
    try{
      const config={width:320,height:64,fps:30,kbps:8000},headers=await request('open',{config}),samples=[];
      const levels=[0,64,128,192,255];
      for(let index=0;index<3;index++){
        const rgba=new Uint8Array(320*64*4);
        for(let i=0;i<320*64;i++){rgba[i*4]=rgba[i*4+1]=rgba[i*4+2]=100;rgba[i*4+3]=levels[Math.floor((i%320)/64)];}
        samples.push(await request('frame',{config,index,pixels:rgba.buffer},[rgba.buffer]));
      }
      await request('finish');
      const {alphaMP4}=await import('./export/mp4.mjs');const blob=alphaMP4({headers,samples,...config});
      if(!checkDecode)return {size:blob.size};
      const url=URL.createObjectURL(blob),video=document.createElement('video');video.muted=true;video.src=url;
      await new Promise((resolve,reject)=>{video.onloadeddata=resolve;video.onerror=()=>reject(Error('decode failed'));});
      const painted=new Promise(resolve=>video.requestVideoFrameCallback(resolve));await video.play();await painted;video.pause();
      const canvas=document.createElement('canvas');canvas.width=320;canvas.height=64;const ctx=canvas.getContext('2d');ctx.drawImage(video,0,0);const pixels=ctx.getImageData(0,0,320,64).data;
      const alpha=levels.map((_,i)=>pixels[(32*320+i*64+32)*4+3]);video.removeAttribute('src');video.load();URL.revokeObjectURL(url);return {size:blob.size,alpha};
    }finally{worker.terminate();}
  },browserName==='webkit'&&process.platform==='darwin');
  expect(result.size).toBeGreaterThan(1000);
  if(result.alpha)for(const [i,target] of [0,64,128,192,255].entries())expect(Math.abs(result.alpha[i]-target)).toBeLessThanOrEqual(2);
  expect(healthResult.errors).toEqual([]);
});

test('editor exports the current edited layout and loaded FIT in place without navigation',async({page,context,browserName})=>{
  const result=health(page);await openEditor(page);await page.locator('#activity-file').setInputFiles({name:'activity.fit',mimeType:'application/octet-stream',buffer:syntheticFIT});await expect(page.locator('#activity-name')).toContainText('activity.fit');
  const source=createDocument('Edited in the editor',true);
  await page.locator('#file').setInputFiles({name:'layout.dlspreset',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(source))});
  await expect(page.locator('#canvas [data-index]')).toHaveCount(0);
  const url=page.url(),pages=context.pages().length;
  await page.locator('#web-export').click();await expect(page.locator('#export-dialog')).toBeVisible();
  await expect(page.locator('#export-layout')).toHaveText('Edited in the editor');await expect(page.locator('#export-activity')).toContainText('activity.fit');
  await page.locator('#export-duration').fill('.1');await page.locator('#export-bitrate').fill('8');await page.locator('#export-bitrate').press('Tab');
  await page.locator('#export-encode').click();await expect(page.locator('#export-download')).toBeVisible({timeout:30000});
  const next=page.waitForEvent('download');await page.locator('#export-download').click();const file=await next;
  expect(file.suggestedFilename()).toBe('Edited in the editor-hevc-alpha.mp4');const bytes=await readFile(await file.path());inspect(bytes,3,30);
  if(browserName==='webkit'&&process.platform==='darwin'){
    const alpha=await page.evaluate(async bytes=>{const video=document.createElement('video'),url=URL.createObjectURL(new Blob([new Uint8Array(bytes)],{type:'video/mp4'}));video.muted=true;video.src=url;await new Promise((resolve,reject)=>{video.onloadeddata=resolve;video.onerror=reject;});const canvas=document.createElement('canvas');canvas.width=video.videoWidth;canvas.height=video.videoHeight;const ctx=canvas.getContext('2d');ctx.drawImage(video,0,0);const pixels=ctx.getImageData(0,0,canvas.width,canvas.height).data;let max=0;for(let i=3;i<pixels.length;i+=4)max=Math.max(max,pixels[i]);video.removeAttribute('src');video.load();URL.revokeObjectURL(url);return max;},Array.from(bytes));
    expect(alpha).toBe(0);
  }
  await page.locator('#export-close').click();await expect(page.locator('#export-dialog')).not.toBeVisible();
  await page.locator('#add-kind').selectOption('heartRate');await page.locator('#add').click();await expect(page.locator('#canvas [data-index]')).toHaveCount(1);
  await page.locator('#web-export').click();await page.locator('#export-duration').fill('.1');await page.locator('#export-bitrate').press('Tab');await page.locator('#export-encode').click();await expect(page.locator('#export-download')).toBeVisible({timeout:30000});
  await expect(page.locator('#activity-name')).toContainText('activity.fit');expect(page.url()).toBe(url);expect(context.pages()).toHaveLength(pages);
  expect(result.errors).toEqual([]);expect(result.requests).toEqual([]);
});

test('editor export follows all twelve languages and fits mobile without a second import',async({page})=>{
  const result=health(page);await openEditor(page);await page.locator('#activity-file').setInputFiles({name:'activity.fit',mimeType:'application/octet-stream',buffer:syntheticFIT});await expect(page.locator('#activity-name')).toContainText('activity.fit');
  for(const locale of Object.keys(languages)){
    await page.locator('#language').selectOption(locale);await page.locator('#web-export').click();
    await expect(page.locator('#export-title')).toHaveText(translations[locale].exportVideo);await expect(page.locator('#export-bitrate')).toHaveValue('8');
    await expect(page.locator('#export-activity')).toContainText('activity.fit');await page.locator('#export-close').click();
  }
  await page.setViewportSize({width:390,height:844});await page.locator('#web-export').click();
  expect(await page.locator('#export-dialog').evaluate(n=>n.scrollWidth<=n.clientWidth)).toBe(true);
  await page.keyboard.press('Escape');await expect(page.locator('#export-dialog')).not.toBeVisible();await expect(page.locator('#web-export')).toBeFocused();
  expect(result.errors).toEqual([]);
});

test('editor export requires real activity and preserves draft validation and keyboard cancellation',async({page})=>{
  await openEditor(page);await page.locator('#web-export').click();await expect(page.locator('#export-dialog')).not.toBeVisible();await expect(page.locator('#status')).toHaveText(translations.en.exportNeedsActivity);
  await activity(page);
  await page.evaluate(()=>{const Base=Worker;window.Worker=class extends Base{postMessage(data,...args){if(data.type==='frame'&&!window.editorFrameHeld){window.editorFrameHeld=true;return;}return super.postMessage(data,...args);}};});
  await page.locator('#export-duration').fill('1');await page.locator('#export-bitrate').press('Tab');await page.locator('#export-encode').click();await page.waitForFunction(()=>window.editorFrameHeld);
  await expect(page.locator('#export-close')).toBeDisabled();await page.keyboard.press('Escape');await expect(page.locator('#export-cancel')).toBeHidden();await expect(page.locator('#export-status')).toHaveText(translations.en.exportCancelled);
  await expect(page.locator('#export-dialog')).toBeVisible();await configure(page,{duration:'.1'});inspect(await encode(page),3,30);
  await page.locator('#export-close').click();await expect(page.locator('#canvas [data-index]')).toHaveCount(8);
  await page.locator('#activity-file').setInputFiles({name:'broken.fit',mimeType:'application/octet-stream',buffer:Buffer.from('broken')});await expect(page.locator('#media-status')).not.toBeEmpty();await expect(page.locator('#activity-name')).toContainText('activity.fit');
  await page.locator('#advanced').evaluate(node=>{node.open=true;});await page.locator('#custom-json').fill('{');await page.locator('#web-export').click();await expect(page.locator('#export-dialog')).not.toBeVisible();await expect(page.locator('#status')).toContainText((await import('../i18n.mjs')).translations.en.apply);
});

test('editor exports weather already loaded in its preview without another API request',async({page})=>{
  await openEditor(page);const source=createDocument('Weather in current layout',true),weather=(await import('../model.mjs')).createElement('weather');source.layout.elements=[weather];
  await page.locator('#file').setInputFiles({name:'layout.dlspreset',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(source))});
  const gpx=`<gpx><trk><trkseg>${[0,2,4].map(n=>`<trkpt lat="0" lon="0"><time>2026-01-01T00:00:0${n}Z</time><extensions><atemp>12</atemp></extensions></trkpt>`).join('')}</trkseg></trk></gpx>`;
  await page.locator('#activity-file').setInputFiles({name:'local.gpx',mimeType:'application/gpx+xml',buffer:Buffer.from(gpx)});await expect(page.locator('#activity-name')).toContainText('local.gpx');
  await page.locator('#trim-start').fill('1');await page.locator('#trim-start').press('Tab');await page.locator('#trim-end').fill('3');await page.locator('#trim-end').press('Tab');
  const alpha=()=>page.locator('#export-preview').evaluate(async canvas=>{const rgba=canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data,a=new Uint8Array(rgba.length/4);for(let i=0;i<a.length;i++)a[i]=rgba[i*4+3];return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',a))).join(',');});
  await page.locator('#web-export').click();await expect.poll(()=>page.locator('#export-preview').evaluate(c=>c.getContext('2d').getImageData(0,0,c.width,c.height).data.some((v,i)=>i%4===3&&v>0))).toBe(true);
  const before=await alpha();await page.locator('#export-close').click();let requests=0;
  await mockWeather(page,async route=>{requests++;await route.fulfill({headers:{'access-control-allow-origin':'*','content-type':'application/json'},body:JSON.stringify({data:[{dt:Date.parse('2026-01-01T00:00:00Z')/1000,temp:28.6,humidity:65,weather:[{main:'Rain'}]}]})});});
  await page.locator('.weather-settings summary').click();await page.locator('#weather-key').fill('TEST_KEY_NOT_A_REAL_CREDENTIAL');await page.locator('#load-weather').click();await expect(page.locator('#weather-status')).toHaveText((await import('../i18n.mjs')).translations.en.weatherLoaded);
  await page.locator('#web-export').click();await expect.poll(alpha).not.toBe(before);const expected=await alpha();
  await expect(page.locator('#export-start')).toHaveValue('1');await expect(page.locator('#export-duration')).toHaveValue('2');await expect(page.locator('#trim-end')).toHaveValue('3');
  await page.evaluate(()=>{const Base=Worker;window.Worker=class extends Base{postMessage(data,...args){if(data.type==='frame'&&data.index===0){const p=new Uint8Array(data.pixels),a=new Uint8Array(p.length/4);for(let i=0;i<a.length;i++)a[i]=p[i*4+3];window.exportedAlpha=crypto.subtle.digest('SHA-256',a).then(hash=>Array.from(new Uint8Array(hash)).join(','));}return super.postMessage(data,...args);}};});
  await page.locator('#export-duration').fill('.1');await page.locator('#export-bitrate').press('Tab');await page.locator('#export-encode').click();await expect(page.locator('#export-download')).toBeVisible({timeout:30000});
  expect(await page.evaluate(()=>window.exportedAlpha)).toBe(expected);expect(requests).toBe(1);await expect(page.locator('#weather-key')).toHaveValue('TEST_KEY_NOT_A_REAL_CREDENTIAL');
});
