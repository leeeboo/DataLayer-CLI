import {clone} from '../model.mjs?v=20261025-weather';
import {previewAt} from '../telemetry.mjs?v=20261025-weather';
import {translate} from './i18n.mjs?v=20261119-tips';
import {exportConfig,frameRates,recommendedBitrate} from './config.mjs?v=20261119-4k';
import {paint,encodeOverlay,exportFilename} from './encoder-client.mjs?v=20261119-4k';
import {cleanupExports} from './storage.mjs?v=20261026-full1';

const clock=seconds=>{const s=Math.round(seconds*10)/10,h=Math.floor(s/3600),m=Math.floor(s%3600/60),rest=s%60;return `${h?`${h}:`:''}${String(m).padStart(h?2:1,'0')}:${rest.toFixed(rest%1?1:0).padStart(rest%1?4:2,'0')}`;};
const bytes=size=>size>=1e9?`${(size/1e9).toFixed(1)} GB`:size>=1e6?`${Math.max(1,Math.round(size/1e6))} MB`:`${Math.max(1,Math.round(size/1e3))} KB`;

export function createEditorExport({language,source,beforeOpen,report,canEncode}) {
  const $=id=>document.getElementById(`export-${id}`),dialog=$('dialog');
  const t=(key,details)=>translate(language(),key,details);
  let controller,downloadFile,generation=0,statusMessage,storage='pending';
  // Unusable buttons are disabled and explain why on hover.
  const reason=(node,why='')=>{node.disabled=!!why;node.title=why||node.getAttribute('aria-label')||node.textContent.trim();};
  function syncAvailability(){
    const {activity,loading}=source();
    reason(document.getElementById('web-export'),loading?t('whyActivityLoading'):!activity?t('exportNeedsActivity'):!canEncode?t('exportUnsupported'):'');
    if(controller)return;
    let why=!canEncode?t('exportUnsupported'):storage==='pending'?t('whyPreparing'):storage==='failed'?t('exportStorageError'):'';
    if(!why)try{settings();}catch{why=t('exportInvalid');}
    reason($('encode'),why);reason($('close'));
  }
  function status(key,error=false,details){statusMessage={key,error,details};$('status').textContent=t(key,details);$('status').classList.toggle('error',error);}
  const fields=()=>Object.fromEntries(['size','fps','bitrate'].map(id=>[id,$(id).value]));
  function settings(){const {activity,range}=source();if(!activity)throw Error('invalidExport');return exportConfig(fields(),activity.duration,range);}
  function summary(){
    try{const s=settings(),seconds=s.frames/s.fps;$('summary').textContent=t('exportSummary',{duration:clock(seconds),frames:s.frames,size:bytes(s.kbps*125*seconds)});}
    catch{$('summary').textContent='';}
    syncAvailability();
  }
  // Each resolution/frame-rate change fills a sensible default; the field stays editable.
  function recommend(){const [w,h]=$('size').value.split('x').map(Number),rate=frameRates[$('fps').value];if(rate)$('bitrate').value=String(recommendedBitrate(w,h,rate[0]/rate[1]));}
  function labels(){
    document.getElementById('web-export').textContent=t('exportVideo');
    dialog.querySelectorAll('[data-export-t]').forEach(node=>node.textContent=t(node.dataset.exportT));
    dialog.querySelectorAll('[data-export-label]').forEach(node=>node.label=t(node.dataset.exportLabel));
    const {activity,rangeLabel}=source();
    $('range').textContent=activity?rangeLabel:'';
    $('close').setAttribute('aria-label',t('exportClose'));$('preview').setAttribute('aria-label',t('canvasLabel'));
    summary();
    if(statusMessage)status(statusMessage.key,statusMessage.error,statusMessage.details);
  }
  function discard(){if(downloadFile){downloadFile.remove().catch(()=>{});downloadFile=undefined;}$('download').hidden=true;$('download').removeAttribute('href');$('encode').classList.add('primary');$('result').textContent='';}
  function lock(value){
    for(const node of dialog.querySelectorAll('input,select'))node.disabled=value;
    for(const node of dialog.querySelectorAll('button'))if(node!==$('cancel'))reason(node,value?t('whyExporting'):'');
    $('cancel').hidden=!value;$('encode').hidden=value;reason($('cancel'));
    if(!value)syncAvailability();
  }
  async function preview(){
    const current=++generation,{preset,activity,range}=source();if(!activity)return;
    try{const [w,h]=$('size').value.split('x').map(Number),canvas=document.createElement('canvas');await paint(canvas,preset.layout,w,h,previewAt(activity,range.start));if(current!==generation||controller)return;const target=$('preview');target.width=w;target.height=h;target.getContext('2d').drawImage(canvas,0,0);}
    catch{if(current===generation)status('exportError',true);}
  }
  document.getElementById('web-export').onclick=async()=>{
    if(!beforeOpen())return;
    const {preset,activity,activityLabel,width,height}=source();
    if(!activity){report(t('exportNeedsActivity'),true);document.getElementById('import-activity').focus();return;}
    discard();$('layout').textContent=preset.name;$('activity').textContent=activityLabel;
    const size=`${width}x${height}`;if([...$('size').options].some(o=>o.value===size))$('size').value=size;
    storage='pending';recommend();labels();lock(false);status(canEncode?'ready':'exportUnsupported',!canEncode);dialog.showModal();preview();
    if(canEncode)try{await cleanupExports();storage='ready';}catch{storage='failed';status('exportStorageError',true);}finally{syncAvailability();}
  };
  $('close').onclick=()=>dialog.close();
  dialog.addEventListener('close',()=>{++generation;document.getElementById('web-export').focus({preventScroll:true});});
  dialog.addEventListener('cancel',event=>{if(controller){event.preventDefault();controller.abort();}});
  $('cancel').onclick=()=>controller?.abort();
  $('size').onchange=()=>{recommend();discard();summary();preview();};
  $('fps').onchange=()=>{recommend();discard();summary();};
  $('bitrate').onchange=$('bitrate').oninput=()=>{discard();summary();};
  $('form').onsubmit=async event=>{
    event.preventDefault();if(controller)return;
    const {preset,activity}=source();if(!activity){status('exportNeedsActivity',true);return;}
    let config;try{config=settings();}catch{status('exportInvalid',true);return;}
    discard();controller=new AbortController();const signal=controller.signal;lock(true);++generation;
    try{
      const {file,size,seconds}=await encodeOverlay({layout:clone(preset.layout),activity,settings:config,signal,onProgress:({canvas,...progress})=>{
        const target=$('preview');if(target.width!==config.width)target.width=config.width;if(target.height!==config.height)target.height=config.height;const context=target.getContext('2d');context.clearRect(0,0,target.width,target.height);context.drawImage(canvas,0,0);status('exportProgress',false,progress);
      }});
      downloadFile=file;$('download').href=new URL(`./download/${file.name}/${encodeURIComponent(exportFilename(preset.name))}`,location.href).href;$('download').hidden=false;$('encode').classList.remove('primary');
      $('result').textContent=t('exportDone',{frames:config.frames,duration:(config.frames/config.fps).toFixed(3),seconds:seconds.toFixed(2),speed:(config.frames/seconds).toFixed(2),size:(size/1048576).toFixed(2)});status('ready');
    }catch(error){status(signal.aborted?'exportCancelled':error.message==='exportStorageError'||error.name==='QuotaExceededError'?'exportStorageError':'exportError',!signal.aborted);}
    finally{controller=undefined;lock(false);}
  };
  window.addEventListener('pagehide',event=>{controller?.abort();if(!event.persisted)discard();});
  return {renderLabels:labels,syncAvailability,get running(){return !!controller;}};
}
