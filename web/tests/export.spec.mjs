import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import {syntheticFIT} from './media-fixtures.mjs';
import {languages,translations} from '../export/i18n.mjs';
import {createDocument} from '../model.mjs';
import {nals,nalLayer,nalType} from '../export/mp4.mjs';
async function open(page,lang='en'){
  await page.goto(`./export/?lang=${lang}`);
  await expect.poll(()=>page.evaluate(()=>crossOriginIsolated&&!!navigator.serviceWorker.controller).catch(()=>false),{timeout:20000}).toBe(true);
  await expect(page.locator('#language')).toBeEnabled();
}
async function activity(page){
  await page.locator('#activity-file').setInputFiles({name:'activity.fit',mimeType:'application/octet-stream',buffer:syntheticFIT});
  await expect(page.locator('#export')).toBeEnabled();
}
async function configure(page,{duration='.2',bitrate='8',size='1280x720',start='0'}={}){
  await page.locator('#size').selectOption(size);await page.locator('#duration').fill(duration);await page.locator('#start').fill(start);await page.locator('#bitrate').fill(bitrate);await page.locator('#bitrate').press('Tab');
}
async function encode(page){
  await page.locator('#export').click();await expect(page.locator('#download')).toBeVisible({timeout:30000});
  const next=page.waitForEvent('download');await page.locator('#download').click();const result=await next;
  expect(result.suggestedFilename()).toBe('703-hevc-alpha.mp4');return readFile(await result.path());
}
function boxes(data,start=0,end=data.length){const all=[];for(let p=start;p<end;){const size=data.readUInt32BE(p);expect(size).toBeGreaterThanOrEqual(8);expect(p+size).toBeLessThanOrEqual(end);all.push({type:data.toString('ascii',p+4,p+8),start:p+8,end:p+size});p+=size;}return all;}
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
}
function health(page){const errors=[],requests=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});page.on('request',r=>{if(!['GET','HEAD'].includes(r.method()))requests.push(r.url());});return {errors,requests};}

test('prototype loads, localizes all twelve languages and fits a mobile viewport',async({page})=>{
  const result=health(page);await open(page);
  await expect(page.locator('#layout-name')).toHaveText('703');await expect(page.locator('#export')).toBeDisabled();
  expect(await page.locator('.export-canvas').evaluate(n=>getComputedStyle(n).backgroundImage)).not.toBe('none');
  expect((await page.locator('#language').boundingBox()).width).toBeLessThanOrEqual(180);
  for(const locale of Object.keys(languages)){
    await page.locator('#language').selectOption(locale);
    await expect(page.locator('html')).toHaveAttribute('lang',locale);await expect(page.locator('h1')).toHaveText(translations[locale].exportTitle);
    await expect(page.locator('#export')).toHaveText(translations[locale].exportStartButton);
  }
  await page.setViewportSize({width:390,height:844});
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  expect(result.errors).toEqual([]);expect(result.requests).toEqual([]);
});

test('703 FIT export preserves both layers, exact frame duration and bitrate selection without uploads',async({page,browserName})=>{
  const result=health(page);await open(page);await activity(page);await configure(page,{bitrate:'1'});
  const low=await encode(page);inspect(low,6,30);
  await configure(page,{bitrate:'8',duration:'.23334'});const high=await encode(page);inspect(high,8,30);
  await expect(page.locator('#result')).toContainText('8 frames');await expect(page.locator('#result')).toContainText('0.267 s');
  expect(high.length).toBeGreaterThan(low.length);
  if(browserName==='webkit'&&process.platform==='darwin'){
    const decoded=await page.evaluate(async()=>{
      const reference=document.getElementById('preview'),ctx=reference.getContext('2d'),source=ctx.getImageData(0,0,reference.width,reference.height).data;
      const points=[];
      for(const target of [0,128,255]){let at=-1;for(let i=3;i<source.length;i+=4){if(source[i]===target){at=(i-3)/4;break;}}if(at<0)throw Error('missing reference Alpha');points.push(at);}
      const video=document.createElement('video');video.muted=true;video.src=document.getElementById('download').href;
      await new Promise((resolve,reject)=>{video.onloadeddata=resolve;video.onerror=()=>reject(Error('decode failed'));});
      await new Promise(resolve=>{video.onseeked=resolve;video.currentTime=7/30;});
      const canvas=document.createElement('canvas');canvas.width=reference.width;canvas.height=reference.height;
      const c=canvas.getContext('2d');c.drawImage(video,0,0);const output=c.getImageData(0,0,canvas.width,canvas.height).data;
      return {alpha:points.map(p=>[source[p*4+3],output[p*4+3]]),duration:video.duration};
    });
    for(const [source,actual]of decoded.alpha)expect(Math.abs(source-actual)).toBeLessThanOrEqual(12);
    expect(decoded.duration).toBeCloseTo(8/30,5);
  }
  expect(result.errors).toEqual([]);expect(result.requests).toEqual([]);
});

test('cancel, retry and invalid replacements preserve the working layout and activity',async({page})=>{
  const result=health(page);await open(page);await activity(page);await configure(page,{duration:'2'});
  await page.locator('#export').click();await expect(page.locator('#cancel')).toBeVisible();await expect(page.locator('#size')).toBeDisabled();
  await page.locator('#cancel').click();await expect(page.locator('#cancel')).toBeHidden();await expect(page.locator('#status')).toHaveText(translations.en.exportCancelled);
  await expect(page.locator('#download')).toBeHidden();await expect(page.locator('#export')).toBeEnabled();
  await page.locator('#activity-file').setInputFiles({name:'broken.fit',mimeType:'application/octet-stream',buffer:Buffer.from('broken')});
  await expect(page.locator('#status')).toHaveText(translations.en.exportError);await expect(page.locator('#activity-name')).toHaveText('activity.fit');
  await page.locator('#file').setInputFiles({name:'broken.dlspreset',mimeType:'application/octet-stream',buffer:Buffer.from('broken')});
  await expect(page.locator('#layout-name')).toHaveText('703');await configure(page,{duration:'.1'});inspect(await encode(page),3,30);
  expect(result.errors).toEqual([]);expect(result.requests).toEqual([]);
});

test('prototype service worker does not control the editor or load its WASM eagerly',async({page,context})=>{
  await open(page);const editor=await context.newPage(),wasm=[];editor.on('request',r=>{if(r.url().endsWith('.wasm'))wasm.push(r.url());});
  await editor.goto('./?lang=zh-CN');await expect(editor.locator('#web-export')).toHaveAttribute('href','./export/?lang=zh-CN');
  expect(await editor.evaluate(()=>navigator.serviceWorker.controller)).toBeNull();expect(await editor.evaluate(()=>crossOriginIsolated)).toBe(false);
  await expect(editor.locator('#canvas [data-index]')).toHaveCount(8);expect(wasm).toEqual([]);
});


test('an empty layout encodes fully transparent frames instead of an opaque fallback',async({page,browserName})=>{
  const result=health(page);await open(page);await activity(page);
  await page.locator('#file').setInputFiles({name:'blank.dlspreset',mimeType:'application/octet-stream',buffer:Buffer.from(JSON.stringify(createDocument('703',true)))});
  await configure(page,{duration:'.1'});inspect(await encode(page),3,30);
  if(browserName==='webkit'&&process.platform==='darwin'){
    const maximum=await page.evaluate(async()=>{
      const video=document.createElement('video');video.muted=true;video.src=document.getElementById('download').href;
      await new Promise((resolve,reject)=>{video.onloadeddata=resolve;video.onerror=reject;});
      const c=document.createElement('canvas');c.width=video.videoWidth;c.height=video.videoHeight;const ctx=c.getContext('2d');ctx.drawImage(video,0,0);
      const pixels=ctx.getImageData(0,0,c.width,c.height).data;let max=0;for(let i=3;i<pixels.length;i+=4)max=Math.max(max,pixels[i]);return max;
    });expect(maximum).toBe(0);
  }
  expect(result.errors).toEqual([]);expect(result.requests).toEqual([]);
});

test('WASM Alpha keeps full-range 0, 64, 128, 192 and 255 levels rather than video-range expansion',async({page,browserName})=>{
  const healthResult=health(page);await open(page);
  const result=await page.evaluate(async checkDecode=>{
    const worker=new Worker(new URL('./encode-worker.mjs',location.href),{type:'module'});let id=0;
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
      const {alphaMP4}=await import('./mp4.mjs');const blob=alphaMP4({headers,samples,...config});
      if(!checkDecode)return {size:blob.size};
      const url=URL.createObjectURL(blob),video=document.createElement('video');video.muted=true;video.src=url;
      await new Promise((resolve,reject)=>{video.onloadeddata=resolve;video.onerror=()=>reject(Error('decode failed'));});
      const painted=new Promise(resolve=>video.requestVideoFrameCallback(resolve));await video.play();await painted;video.pause();
      const canvas=document.createElement('canvas');canvas.width=320;canvas.height=64;const ctx=canvas.getContext('2d');ctx.drawImage(video,0,0);const pixels=ctx.getImageData(0,0,320,64).data;
      const alpha=levels.map((_,i)=>pixels[(32*320+i*64+32)*4+3]);URL.revokeObjectURL(url);return {size:blob.size,alpha};
    }finally{worker.terminate();}
  },browserName==='webkit'&&process.platform==='darwin');
  expect(result.size).toBeGreaterThan(1000);
  if(result.alpha)for(const [i,target] of [0,64,128,192,255].entries())expect(Math.abs(result.alpha[i]-target)).toBeLessThanOrEqual(2);
  expect(healthResult.errors).toEqual([]);
});
