import {clone} from '../model.mjs?v=20261025-weather';
import {previewAt} from '../telemetry.mjs?v=20261025-weather';
import {translate} from './i18n.mjs?v=20261026-trim1';
import {exportConfig} from './config.mjs?v=20261026-trim1';
import {paint,encodeOverlay,exportFilename} from './encoder-client.mjs?v=20261026-integrated1';
import {cleanupExports} from './storage.mjs?v=20261026-full1';

export function createEditorExport({language,source,beforeOpen,report,canEncode}) {
  const $=id=>document.getElementById(`export-${id}`),dialog=$('dialog');
  const t=(key,details)=>translate(language(),key,details);
  let controller,downloadFile,generation=0,lastActivity,lastRange,statusMessage;
  function status(key,error=false,details){statusMessage={key,error,details};$('status').textContent=t(key,details);$('status').classList.toggle('error',error);}
  function labels(){
    document.getElementById('web-export').textContent=t('exportVideo');
    dialog.querySelectorAll('[data-export-t]').forEach(node=>node.textContent=t(node.dataset.exportT));
    const {activity,range,rangeLabel}=source();
    $('range').textContent=activity?rangeLabel:'';
    $('full').textContent=t(activity&&(range.start>0||range.end<activity.duration)?'trimSelection':'exportFullActivity');
    $('close').setAttribute('aria-label',t('exportClose'));$('preview').setAttribute('aria-label',t('canvasLabel'));
    if(statusMessage)status(statusMessage.key,statusMessage.error,statusMessage.details);
  }
  function discard(){if(downloadFile){downloadFile.remove().catch(()=>{});downloadFile=undefined;}$('download').hidden=true;$('download').removeAttribute('href');$('result').textContent='';}
  function lock(value){for(const node of dialog.querySelectorAll('input,select,button'))node.disabled=value;$('cancel').disabled=false;$('cancel').hidden=!value;$('encode').disabled=value||!canEncode;}
  function rangeLimits(){const {range}=source();$('start').min=String(range.start);$('start').max=String(range.end);$('duration').max=String(Number((range.end-Number($('start').value)).toFixed(9)));}
  function selectRange(){const {range}=source();$('start').value=String(range.start);$('duration').value=String(Number((range.end-range.start).toFixed(9)));rangeLimits();}
  async function preview(){
    const current=++generation,{preset,activity,range}=source(),start=$('start').valueAsNumber;if(!activity||!Number.isFinite(start)||start<range.start||start>range.end)return;
    try{const [w,h]=$('size').value.split('x').map(Number),canvas=document.createElement('canvas');await paint(canvas,preset.layout,w,h,previewAt(activity,start));if(current!==generation||controller)return;const target=$('preview');target.width=w;target.height=h;target.getContext('2d').drawImage(canvas,0,0);}
    catch{if(current===generation)status('exportError',true);}
  }
  document.getElementById('web-export').onclick=async()=>{
    if(!beforeOpen())return;
    const {preset,activity,activityLabel,range,width,height}=source();
    if(!activity){report(t('exportNeedsActivity'),true);document.getElementById('import-activity').focus();return;}
    discard();$('layout').textContent=preset.name;$('activity').textContent=activityLabel;
    const rangeKey=`${range.start}:${range.end}`;
    if(activity!==lastActivity||rangeKey!==lastRange){lastActivity=activity;lastRange=rangeKey;selectRange();}
    const size=`${width}x${height}`;if([...$('size').options].some(o=>o.value===size))$('size').value=size;
    labels();lock(false);$('encode').disabled=true;status(canEncode?'ready':'exportUnsupported',!canEncode);dialog.showModal();preview();
    if(canEncode)try{await cleanupExports();if(!controller)$('encode').disabled=false;}catch{status('exportStorageError',true);$('encode').disabled=true;}
  };
  $('close').onclick=()=>dialog.close();
  dialog.addEventListener('close',()=>{++generation;document.getElementById('web-export').focus({preventScroll:true});});
  dialog.addEventListener('cancel',event=>{if(controller){event.preventDefault();controller.abort();}});
  $('cancel').onclick=()=>controller?.abort();
  for(const id of ['size','fps','start','duration','bitrate'])$(id).onchange=()=>{rangeLimits();discard();preview();};
  $('full').onclick=()=>{const {activity}=source();if(!activity)return;selectRange();discard();preview();};
  $('form').onsubmit=async event=>{
    event.preventDefault();if(controller)return;
    const {preset,activity,range}=source();if(!activity){status('exportNeedsActivity',true);return;}
    let settings;try{settings=exportConfig(Object.fromEntries(['size','fps','start','duration','bitrate'].map(id=>[id,$(id).value])),activity.duration,range);}catch{status('exportInvalid',true);return;}
    discard();controller=new AbortController();const signal=controller.signal;lock(true);++generation;
    try{
      const {file,size,seconds}=await encodeOverlay({layout:clone(preset.layout),activity,settings,signal,onProgress:({canvas,...progress})=>{
        const target=$('preview');if(target.width!==settings.width)target.width=settings.width;if(target.height!==settings.height)target.height=settings.height;const context=target.getContext('2d');context.clearRect(0,0,target.width,target.height);context.drawImage(canvas,0,0);status('exportProgress',false,progress);
      }});
      downloadFile=file;$('download').href=new URL(`./download/${file.name}/${encodeURIComponent(exportFilename(preset.name))}`,location.href).href;$('download').hidden=false;
      $('result').textContent=t('exportDone',{frames:settings.frames,duration:(settings.frames/settings.fps).toFixed(3),seconds:seconds.toFixed(2),speed:(settings.frames/seconds).toFixed(2),size:(size/1048576).toFixed(2)});status('ready');
    }catch(error){status(signal.aborted?'exportCancelled':error.message==='exportStorageError'||error.name==='QuotaExceededError'?'exportStorageError':'exportError',!signal.aborted);}
    finally{controller=undefined;lock(false);}
  };
  window.addEventListener('pagehide',event=>{controller?.abort();if(!event.persisted)discard();});
  return {renderLabels:labels,get running(){return !!controller;}};
}
