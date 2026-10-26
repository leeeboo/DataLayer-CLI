import {languages,languageFrom,translate} from './i18n.mjs?v=20261026-alpha1';
import {clone,parseDocument,presets} from '../model.mjs?v=20261025-weather';
import {defaultPreset} from '../default-preset.mjs?v=20261025-default-layout';
import {fontsReady,renderLayout,svgDefinitions} from '../render.mjs?v=20261025-weather';
import {parseTelemetryFile,previewAt} from '../telemetry.mjs?v=20261025-weather';
import {exportConfig} from './config.mjs?v=20261026-alpha1';
import {alphaMP4} from './mp4.mjs?v=20261026-alpha2';
const $=id=>document.getElementById(id);
let language=languageFrom(new URLSearchParams(location.search).get('lang')||navigator.language);
const t=(key,details)=>translate(language,key,details);
let preset=clone(defaultPreset),activity,activityName='',running=false,canEncode=false,controller,downloadURL,drawGeneration=0,loadGeneration=0,templateGeneration=0;
const status=(key,error=false,details)=>{$('status').textContent=t(key,details);$('status').classList.toggle('error',error);};
function labels() {
  document.documentElement.lang=language;document.documentElement.dir=language==='ar'?'rtl':'ltr';document.title=`${t('exportTitle')} · DataLayer Studio`;
  document.querySelectorAll('[data-t]').forEach(n=>n.textContent=t(n.dataset.t));
  $('language').replaceChildren(...Object.entries(languages).map(([value,label])=>{const o=document.createElement('option');o.value=value;o.textContent=label;return o;}));
  $('language').value=language;$('language').setAttribute('aria-label',t('language'));$('preview').setAttribute('aria-label',t('canvasLabel'));
  $('editor-link').href=`../?lang=${language}`;$('layout-name').textContent=preset.name;
  $('activity-name').textContent=activityName||t('activityEmpty');
}
const config=()=>exportConfig(Object.fromEntries(['size','fps','start','duration','bitrate'].map(id=>[id,$(id).value])),activity?.duration??0);
async function paint(canvas,layout,width,height,frame) {
  await fontsReady;
  const scene=renderLayout(layout,width,height,frame);
  const markup=svgDefinitions+scene.filter((_,i)=>layout.elements[i].frame.isVisible).map(e=>e.svg).join('');
  const image=new Image();
  await new Promise((resolve,reject)=>{image.onload=resolve;image.onerror=()=>reject(Error('renderFailed'));image.src=`data:image/svg+xml;charset=utf-8,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">${markup}</svg>`)}`;});
  canvas.width=width;canvas.height=height;const context=canvas.getContext('2d',{willReadFrequently:true});
  context.clearRect(0,0,width,height);context.drawImage(image,0,0);return context;
}
async function preview() {
  const generation=++drawGeneration;
  try {
    const [w,h]=$('size').value.split('x').map(Number),start=Number($('start').value);
    const canvas=document.createElement('canvas');
    await paint(canvas,preset.layout,w,h,activity?previewAt(activity,Number.isFinite(start)?start:0):undefined);
    if(generation!==drawGeneration||running)return;
    const target=$('preview');target.width=w;target.height=h;target.getContext('2d').drawImage(canvas,0,0);
  } catch {if(generation===drawGeneration)status('exportError',true);}
}
function discardDownload() {if(downloadURL)URL.revokeObjectURL(downloadURL);downloadURL=undefined;$('download').hidden=true;$('download').removeAttribute('href');$('result').textContent='';}
function lock(value) {
  running=value;
  for(const node of document.querySelectorAll('input,select,button'))node.disabled=value;
  $('cancel').disabled=false;$('cancel').hidden=!value;$('export').disabled=value||!canEncode||!activity;
}
function encoderClient(signal) {
  const worker=new Worker(new URL('./encode-worker.mjs?v=20261026-alpha1',import.meta.url),{type:'module'});
  let nextID=0,pending,abortTimer;
  const fail=()=>{clearTimeout(abortTimer);if(pending){pending.reject(signal.aborted?new DOMException('Cancelled','AbortError'):Error('encoderFailed'));pending=undefined;}};
  worker.onerror=fail;
  worker.onmessage=({data})=>{if(pending&&data.id===pending.id){clearTimeout(abortTimer);const p=pending;pending=undefined;signal.aborted?p.reject(new DOMException('Cancelled','AbortError')):data.error?p.reject(Error('encoderFailed')):p.resolve(data.bytes);}};
  // Let an in-flight initialization/frame finish before terminating child threads.
  signal.addEventListener('abort',()=>{if(pending)abortTimer=setTimeout(()=>{worker.terminate();fail();},2000);else worker.terminate();},{once:true});
  return {request(type,data={},transfer=[]){return new Promise((resolve,reject)=>{if(signal.aborted){reject(new DOMException('Cancelled','AbortError'));return;}const id=++nextID;pending={id,resolve,reject};worker.postMessage({id,type,...data},transfer);});},close(){clearTimeout(abortTimer);worker.terminate();}};
}
$('export-form').onsubmit=async event=>{
  event.preventDefault();if(running)return;
  if(!activity){status('exportNeedsActivity',true);return;}
  let settings;try{settings=config();}catch{status('exportInvalid',true);return;}
  const layout=clone(preset.layout),source=activity,name=preset.name;
  discardDownload();controller=new AbortController();const signal=controller.signal;
  lock(true);++drawGeneration;
  const start=performance.now(),client=encoderClient(signal),samples=[];
  let compressed=0;
  try {
    const headers=await client.request('open',{config:settings});
    for(let i=0;i<settings.frames;i++) {
      if(signal.aborted)throw new DOMException('Cancelled','AbortError');
      const context=await paint($('preview'),layout,settings.width,settings.height,previewAt(source,settings.start+i/settings.fps));
      const pixels=context.getImageData(0,0,settings.width,settings.height).data.buffer;
      const bytes=await client.request('frame',{config:settings,index:i,pixels},[pixels]);
      compressed+=bytes.length;if(compressed>128*1024*1024)throw Error('exportTooLarge');samples.push(bytes);
      status('exportProgress',false,{frames:i+1,total:settings.frames,seconds:((performance.now()-start)/1000).toFixed(1)});
    }
    await client.request('finish');
    if(signal.aborted)throw new DOMException('Cancelled','AbortError');
    const blob=alphaMP4({headers,samples,...settings}),seconds=(performance.now()-start)/1000;
    downloadURL=URL.createObjectURL(blob);$('download').href=downloadURL;
    $('download').download=`${name.replace(/[\\/:*?"<>|\u0000-\u001f]/g,'_').slice(0,100)||'overlay'}-hevc-alpha.mp4`;$('download').hidden=false;
    $('result').textContent=t('exportDone',{frames:settings.frames,duration:(settings.frames/settings.fps).toFixed(3),seconds:seconds.toFixed(2),speed:(settings.frames/seconds).toFixed(2),size:(blob.size/1048576).toFixed(2)});
    status('ready');
  } catch(error) {status(signal.aborted?'exportCancelled':'exportError',!signal.aborted);}
  finally {client.close();samples.length=0;controller=undefined;lock(false);}
};
$('cancel').onclick=()=>controller?.abort();
$('import').onclick=()=>$('file').click();$('import-activity').onclick=()=>$('activity-file').click();
$('file').onchange=async()=>{
  const file=$('file').files[0];$('file').value='';if(!file||running)return;
  const generation=++templateGeneration;
  try {
    if(file.size>5*1024*1024)throw Error('tooLarge');
    const doc=parseDocument(await file.text());if(generation!==templateGeneration||running)return;preset=clone(presets(doc).find(p=>p.id===doc.defaultPresetID)??presets(doc)[0]);
    discardDownload();labels();await preview();status('ready');
  }catch{status('exportError',true);}
};
$('activity-file').onchange=async()=>{
  const file=$('activity-file').files[0];$('activity-file').value='';if(!file||running)return;
  const generation=++loadGeneration;
  try {
    const next=await parseTelemetryFile(file);if(generation!==loadGeneration||running)return;
    activity=next;activityName=file.name;$('start').value='0';$('duration').value=String(Math.min(3,activity.duration));
    discardDownload();labels();lock(false);await preview();status('ready');
  }catch{if(generation===loadGeneration)status('exportError',true);}
};
for(const id of ['size','fps','start','duration','bitrate'])$(id).onchange=()=>{discardDownload();preview();};
$('language').onchange=()=>{language=languageFrom($('language').value);labels();discardDownload();const url=new URL(location.href);url.searchParams.set('lang',language);history.replaceState(null,'',url);status('exportReady');};
window.addEventListener('pagehide',event=>{controller?.abort();if(!event.persisted&&downloadURL)URL.revokeObjectURL(downloadURL);});
labels();status('exportReady');preview();
for(const node of document.querySelectorAll('input,select,button'))node.disabled=true;
async function initialize() {
  if(!crossOriginIsolated) {
    if(!isSecureContext||!navigator.serviceWorker||navigator.serviceWorker.controller){lock(false);status('exportUnsupported',true);return;}
    status('exportIsolation');
    try {
      const control=new Promise((resolve,reject)=>{const timeout=setTimeout(()=>reject(Error('isolationTimeout')),10000);navigator.serviceWorker.addEventListener('controllerchange',()=>{clearTimeout(timeout);resolve();},{once:true});});
      await Promise.all([navigator.serviceWorker.register('./isolation-worker.mjs',{scope:'./',type:'module'}),control]);
      location.reload();return;
    }catch{lock(false);status('exportUnsupported',true);return;}
  }
  canEncode=typeof SharedArrayBuffer!=='undefined'&&typeof WebAssembly!=='undefined'&&typeof Worker!=='undefined';
  lock(false);status(canEncode?'exportReady':'exportUnsupported',!canEncode);
}
initialize();
