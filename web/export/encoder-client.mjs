import {fontsReady,renderLayout,svgDefinitions} from '../render.mjs?v=20261025-weather';
import {previewAt} from '../telemetry.mjs?v=20261025-weather';
import {reserveExport} from './storage.mjs?v=20261026-full1';
export async function paint(canvas,layout,width,height,frame) {
  await fontsReady;
  const scene=renderLayout(layout,width,height,frame);
  const markup=svgDefinitions+scene.filter((_,i)=>layout.elements[i].frame.isVisible).map(e=>e.svg).join('');
  const image=new Image();
  await new Promise((resolve,reject)=>{image.onload=resolve;image.onerror=()=>reject(Error('renderFailed'));image.src=`data:image/svg+xml;charset=utf-8,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">${markup}</svg>`)}`;});
  if(canvas.width!==width)canvas.width=width;if(canvas.height!==height)canvas.height=height;const context=canvas.getContext('2d',{willReadFrequently:true});
  context.clearRect(0,0,width,height);context.drawImage(image,0,0);return context;
}
function encoderClient(signal) {
  const worker=new Worker(new URL('./encode-worker.mjs?v=20261026-full1',import.meta.url),{type:'module'});
  let nextID=0,pending,abortTimer;
  const fail=()=>{clearTimeout(abortTimer);if(pending){pending.reject(signal.aborted?new DOMException('Cancelled','AbortError'):Error('encoderFailed'));pending=undefined;}};
  worker.onerror=fail;
  worker.onmessage=({data})=>{if(pending&&data.id===pending.id){clearTimeout(abortTimer);const p=pending;pending=undefined;signal.aborted?p.reject(new DOMException('Cancelled','AbortError')):data.error?p.reject(Error(data.storageError?'exportStorageError':'encoderFailed')):p.resolve(data);}};
  // Let an in-flight initialization/frame finish before terminating child threads.
  signal.addEventListener('abort',()=>{if(pending)abortTimer=setTimeout(()=>{worker.terminate();fail();},2000);else worker.terminate();},{once:true});
  return {request(type,data={},transfer=[]){return new Promise((resolve,reject)=>{if(signal.aborted){reject(new DOMException('Cancelled','AbortError'));return;}const id=++nextID;pending={id,resolve,reject};worker.postMessage({id,type,...data},transfer);});},close(){clearTimeout(abortTimer);worker.terminate();}};
}

export async function encodeOverlay({layout,activity,settings,signal,onProgress}) {
  const started=performance.now(),canvas=document.createElement('canvas');
  let file,client;
  try {
    file=await reserveExport();client=encoderClient(signal);
    await client.request('open',{config:settings,fileName:file.name});
    const render=async index=>(await paint(canvas,layout,settings.width,settings.height,previewAt(activity,settings.start+index/settings.fps))).getImageData(0,0,settings.width,settings.height).data.buffer;
    let pixels=await render(0),lastPreview=0;
    for(let i=0;i<settings.frames;i++) {
      if(signal.aborted)throw new DOMException('Cancelled','AbortError');
      const encoded=client.request('frame',{config:settings,index:i,pixels},[pixels]);
      // Render one frame ahead; compressed samples remain in the disk writer.
      [,pixels]=await Promise.all([encoded,i+1<settings.frames?render(i+1):undefined]);
      const now=performance.now();
      if(now-lastPreview>=500||i+1===settings.frames){lastPreview=now;onProgress?.({frames:i+1,total:settings.frames,seconds:((now-started)/1000).toFixed(1),canvas});}
    }
    const {size}=await client.request('finish');
    if(signal.aborted)throw new DOMException('Cancelled','AbortError');
    const result={file,size,seconds:(performance.now()-started)/1000};file=undefined;return result;
  } finally {client?.close();if(file)await file.remove().catch(()=>{});canvas.width=canvas.height=1;}
}
export const exportFilename=name=>`${name.replace(/[\\/:*?"<>|\u0000-\u001f]/g,'_').slice(0,100).toWellFormed()||'overlay'}-hevc-alpha.mp4`;
