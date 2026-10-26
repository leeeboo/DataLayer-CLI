import {test} from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {exportConfig} from '../export/config.mjs';
import {alphaMP4,createAlphaMP4,writeAll,nals,nalType,nalLayer} from '../export/mp4.mjs';
import {languages,translations} from '../export/i18n.mjs';
const valid={size:'1920x1080',fps:30,start:60,duration:3,bitrate:8};
test('export validates source range, dimensions, bitrate and frame-accurate duration',()=>{
  assert.deepEqual(exportConfig(valid,100),{width:1920,height:1080,fps:30,start:60,frames:90,kbps:8000});
  assert.equal(exportConfig({...valid,duration:.101},100).frames,4);
  assert.equal(exportConfig({...valid,duration:1.001,fps:15,bitrate:.1},100).kbps,100);
  assert.equal(exportConfig({...valid,start:0,duration:6325.217},6325.217).frames,189757);
  for(const change of [{size:'3840x2160'},{size:'1919x1080'},{size:'1920x1920'},{size:'1x1'},{size:'bad'},{fps:29.97},{fps:0},{fps:31},{start:-1},{start:99},{duration:0},{duration:101},{bitrate:0},{bitrate:101},{bitrate:Infinity},{start:NaN}])assert.throws(()=>exportConfig({...valid,...change},100));
  assert.throws(()=>exportConfig({...valid,start:0,duration:2**32},2**32));
});
test('trimmed exports keep original timestamps and reject content outside the selected range',()=>{
  const range={start:60.25,end:63.253},config=exportConfig({...valid,start:range.start,duration:3.003},100,range);
  assert.equal(config.start,60.25);assert.equal(config.frames,91);
  assert(config.start+(config.frames-1)/config.fps<range.end);
  assert.equal(exportConfig({...valid,start:63.153,duration:.1},100,range).frames,3);
  for(const change of [{start:60},{start:63,duration:1},{start:0,duration:3}])assert.throws(()=>exportConfig({...valid,...change},100,range));
  for(const invalid of [{start:-1,end:90},{start:60,end:101},{start:61,end:60},{start:60,end:60},{start:NaN,end:90},{start:0,end:Infinity}])assert.throws(()=>exportConfig(valid,100,invalid));
});
test('all twelve export locales provide every key and preserve progress placeholders',()=>{
  assert.deepEqual(Object.keys(translations).sort(),Object.keys(languages).sort());
  for(const locale of Object.values(translations)){
    assert.deepEqual(Object.keys(locale),Object.keys(translations.en));
    for(const [key,value] of Object.entries(locale)){
      assert(value.trim());assert.deepEqual([...value.matchAll(/\{\w+\}/g)].map(m=>m[0]).sort(),[...translations.en[key].matchAll(/\{\w+\}/g)].map(m=>m[0]).sort());
    }
  }
});
test('included x265 source hash is the audited release source',()=>{
  const bytes=readFileSync(new URL('../export/encoder/x265_4.1.tar.gz',import.meta.url));
  assert.equal(createHash('sha256').update(bytes).digest('hex'),'a31699c6a89806b74b0151e5e6a7df65de4b49050482fe5ebf8a4379d7af8f29');
});
function boxes(data,start=0,end=data.length){
  const result=[];
  for(let p=start;p<end;){const extended=data.readUInt32BE(p)===1,length=extended?Number(data.readBigUInt64BE(p+8)):data.readUInt32BE(p),head=extended?16:8;assert(length>=head&&p+length<=end);result.push({type:data.toString('ascii',p+4,p+8),start:p+head,end:p+length});p+=length;}
  return result;
}
function child(data,parent,type){const value=boxes(data,parent.start,parent.end).find(b=>b.type===type);assert(value,`missing ${type}`);return value;}
test('shipped WASM encodes both layers for every frame; MP4 retains headers, Alpha SEI, durations and sample sizes',async()=>{
  const result=JSON.parse(execFileSync(process.execPath,[fileURLToPath(new URL('./wasm-fixture.mjs',import.meta.url))],{timeout:30000,encoding:'utf8'}));
  const headers=Buffer.from(result.headers,'base64'),samples=result.frames.map(f=>Buffer.from(f,'base64'));
  const units=nals(headers);
  for(const [type,layer] of [[32,0],[33,0],[33,1],[34,0],[34,1],[39,0]])assert(units.some(n=>nalType(n)===type&&nalLayer(n)===layer));
  const sei=units.find(n=>nalType(n)===39);assert.equal(sei[2],165); // HEVC alpha_channel_info SEI payload type.
  for(const sample of samples)for(const layer of [0,1])assert(nals(sample).some(n=>nalType(n)<32&&nalLayer(n)===layer));
  const blob=alphaMP4({headers,samples,width:64,height:64,fps:30}),data=Buffer.from(await blob.arrayBuffer()),top=boxes(data);
  assert.equal(blob.type,'video/mp4');assert.equal(data.toString('ascii',8,12),'isom');assert(data.includes(Buffer.from('muxa')));
  const mdat=top.find(b=>b.type==='mdat');assert.deepEqual(data.subarray(mdat.start,mdat.end),Buffer.concat(samples));
  const moov=top.find(b=>b.type==='moov'),mdia=child(data,child(data,moov,'trak'),'mdia'),mdhd=child(data,mdia,'mdhd');
  assert.equal(data.readUInt32BE(mdhd.start+12),30);assert.equal(data.readUInt32BE(mdhd.start+16),3);
  const stbl=child(data,child(data,mdia,'minf'),'stbl'),stsz=child(data,stbl,'stsz');
  assert.equal(data.readUInt32BE(stsz.start+8),3);assert.deepEqual(samples.map((_,i)=>data.readUInt32BE(stsz.start+12+i*4)),samples.map(b=>b.length));
  const stsd=child(data,stbl,'stsd'),hvc1=boxes(data,stsd.start+8,stsd.end)[0];assert.equal(hvc1.type,'hvc1');
  const hvcc=boxes(data,hvc1.start+78,hvc1.end).find(b=>b.type==='hvcC');assert(hvcc);assert.equal(data[hvcc.start],1);assert.equal(data[hvcc.start+22],4);assert.equal(data.readUInt16BE(hvcc.start+19),0);
  assert.throws(()=>alphaMP4({headers,samples:[],width:64,height:64,fps:30}));
  assert.throws(()=>alphaMP4({headers:new Uint8Array(),samples,width:64,height:64,fps:30}));
  const baseOnly=Buffer.from([0,0,0,3,2,1,128]);
  assert.throws(()=>alphaMP4({headers,samples:[baseOnly],width:64,height:64,fps:30}));
  for(const bad of [new Uint8Array([0]),new Uint8Array([0,0,0,20,1,1]),new Uint8Array([0,0,0,0])])assert.throws(()=>nals(bad));
  const long=createAlphaMP4({headers,width:1920,height:1080,fps:30,frames:70000}),sample=new Uint8Array(65536),view=new DataView(sample.buffer);
  for(const at of [0,32768]){view.setUint32(at,32764);sample[at+4]=2;sample[at+5]=at?9:1;}
  assert.throws(()=>long.finish());
  for(let i=0;i<70000;i++)long.add(sample);
  const tail=Buffer.from(long.finish()),mdatOffset=long.header.length-16;
  assert.equal(new DataView(long.header.buffer).getBigUint64(mdatOffset+8),BigInt(70000*65536+16));
  assert(new DataView(long.header.buffer).getBigUint64(mdatOffset+8)>0xffffffffn);
  const longMdia=child(tail,child(tail,boxes(tail)[0],'trak'),'mdia'),longStbl=child(tail,child(tail,longMdia,'minf'),'stbl');
  assert.equal(tail.readUInt32BE(child(tail,longStbl,'stsz').start+8),70000);
  assert.equal(tail.readUInt32BE(child(tail,longMdia,'mdhd').start+16),70000);
  assert.throws(()=>long.add(sample));assert.throws(()=>long.finish());
});

test('disk writes handle partial writes and reject short or failed output',()=>{
  const output=new Uint8Array(19),source=new Uint8Array([1,2,3,4,5,6,7,8,9]);
  writeAll({write(data,{at}){const n=Math.min(2,data.length);output.set(data.subarray(0,n),at);return n;}},source,5);
  assert.deepEqual(output.subarray(5,14),source);
  for(const count of [0,-1,NaN,10])assert.throws(()=>writeAll({write:()=>count},source,0));
  assert.throws(()=>writeAll({write(){throw new DOMException('full','QuotaExceededError');}},source,0),{name:'QuotaExceededError'});
});

test('isolation rechecks registration and asks an existing worker to claim the new page',async()=>{
  const {runInNewContext}=await import('node:vm');
  const source=readFileSync(new URL('../export/isolation.mjs',import.meta.url),'utf8').replace('export async function','async function');
  for(const missedEvent of [false,true]){
    const script=new URL('https://example.test/isolation-worker.mjs?v=test'),listeners=new Map();let claims=0,reloads=0;
    const worker={scriptURL:script.href,postMessage(data){assert.equal(data.type,'dls-claim');claims++;serviceWorker.controller=worker;listeners.get('controllerchange')?.();}};
    const serviceWorker={controller:null,addEventListener:(name,fn)=>listeners.set(name,fn),removeEventListener:name=>listeners.delete(name),register:async(url,options)=>{assert.equal(options.type,'classic');if(missedEvent)serviceWorker.controller=worker;return {active:worker};}};
    const context={URL,isSecureContext:true,crossOriginIsolated:false,SharedArrayBuffer,WebAssembly,Worker:class{},navigator:{serviceWorker,storage:{getDirectory(){}},locks:{}},location:{reload(){reloads++;throw Error('reload with isolation headers');}},setTimeout:fn=>setTimeout(fn,25),clearTimeout};
    const prepare=runInNewContext(`${source};prepareIsolation`,context);
    await assert.rejects(prepare(script),/reload with isolation headers/);
    assert.equal(claims,missedEvent?0:1);assert.equal(reloads,1);assert.equal(listeners.size,0);
    context.crossOriginIsolated=true;assert.equal(await prepare(script),true);assert.equal(reloads,1);
  }
});

test('root isolation worker installs the full handler synchronously at first evaluation',async()=>{
  const {runInNewContext}=await import('node:vm'),events=[];
  const context={URL,Headers,Response,fetch:async()=>new Response('ok'),navigator:{},
    self:{location:{origin:'https://example.test',href:'https://example.test/isolation-worker.mjs'},
      addEventListener:(name)=>events.push(name)},
    importScripts:url=>{assert.equal(new URL(url,'https://example.test/isolation-worker.mjs').pathname,'/export/isolation-worker.mjs');runInNewContext(readFileSync(new URL('../export/isolation-worker.mjs',import.meta.url),'utf8'),context);}};
  runInNewContext(readFileSync(new URL('../isolation-worker.mjs',import.meta.url),'utf8'),context);
  assert.deepEqual(events,['install','activate','message','fetch']);
});

test('isolation worker handles WebKit null-body revalidation statuses and never proxies another origin',async()=>{
  const {runInNewContext}=await import('node:vm');
  const listeners=new Map();let response,handled,claimed=0;
  const context={URL,Headers,Response,fetch:async()=>response,self:{clients:{claim:async()=>{claimed++;}},location:{origin:'https://example.test',href:'https://example.test/export/isolation-worker.mjs'},addEventListener:(name,callback)=>listeners.set(name,callback)}};
  runInNewContext(readFileSync(new URL('../export/isolation-worker.mjs',import.meta.url),'utf8'),context);
  let claim;listeners.get('message')({data:{type:'dls-claim'},waitUntil:task=>{claim=task;}});await claim;assert.equal(claimed,1);
  listeners.get('message')({data:{type:'other'},waitUntil:()=>assert.fail('unknown message must not claim clients')});assert.equal(claimed,1);
  for(const status of [200,204,205,304]){
    response={type:'basic',status,statusText:'',headers:new Headers(),body:new Response('module bytes').body};
    listeners.get('fetch')({request:{url:'https://example.test/export/encoder/x265.mjs'},respondWith:value=>{handled=value;}});
    const result=await handled;assert.equal(result.status,status);assert.equal(result.headers.get('Cross-Origin-Opener-Policy'),'same-origin');
    assert.equal(result.headers.get('Cross-Origin-Embedder-Policy'),'require-corp');
    if(status!==200)assert.equal(result.body,null);else assert.equal(await result.text(),'module bytes');
  }
  let externalHandled=false;listeners.get('fetch')({request:{url:'https://other.test/file'},respondWith:()=>{externalHandled=true;}});assert.equal(externalHandled,false);
});
