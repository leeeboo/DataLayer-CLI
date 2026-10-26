// Minimal single-track, constant-rate HEVC Alpha muxer. Samples retain both layers.
const bytes = (...items) => {
  const arrays = items.map(x => typeof x === 'string' ? new TextEncoder().encode(x) : x);
  const out = new Uint8Array(arrays.reduce((n,a)=>n+a.length,0)); let offset=0;
  for(const a of arrays){out.set(a,offset);offset+=a.length;} return out;
};
const u16 = n => new Uint8Array([n>>>8,n&255]);
const u32 = n => new Uint8Array([n>>>24,(n>>>16)&255,(n>>>8)&255,n&255]);
const packed32 = values => {const out=new Uint8Array(values.length*4),view=new DataView(out.buffer);values.forEach((n,i)=>view.setUint32(i*4,n));return out;};
const zeros = n => new Uint8Array(n);
const box = (type,...parts) => {const data=bytes(...parts);return bytes(u32(data.length+8),type,data);};
const full = (type,flags,...parts) => box(type,u32(flags),...parts);
const matrix = bytes(...[65536,0,0,0,65536,0,0,0,1073741824].map(u32));
export function nals(sample) {
  const result=[];
  for(let i=0;i<sample.length;){
    if(i+4>sample.length)throw Error('invalidNAL');
    const length=new DataView(sample.buffer,sample.byteOffset+i,4).getUint32(0);
    if(length<2||i+4+length>sample.length)throw Error('invalidNAL');
    result.push(sample.subarray(i+4,i+4+length));i+=4+length;
  }return result;
}
export const nalType = nal => (nal[0]>>>1)&63;
export const nalLayer = nal => ((nal[0]&1)<<5)|(nal[1]>>>3);
function config(headers) {
  const units=nals(headers), sps=units.find(n=>nalType(n)===33&&nalLayer(n)===0);
  for(const [type,layers] of [[32,[0]],[33,[0,1]],[34,[0,1]],[39,[0]]])for(const layer of layers)
    if(!units.some(n=>nalType(n)===type&&nalLayer(n)===layer))throw Error('missingAlpha');
  const rbsp=[];
  for(let i=2;i<sps.length;i++){if(i>=4&&sps[i]===3&&sps[i-1]===0&&sps[i-2]===0)continue;rbsp.push(sps[i]);}
  if(rbsp.length<13)throw Error('invalidSPS');
  const arrays=[32,33,34,39].map(type=>{
    const set=units.filter(n=>nalType(n)===type);
    return bytes(new Uint8Array([128|type]),u16(set.length),...set.map(n=>bytes(u16(n.length),n)));
  });
  // MP4 sample timing is authoritative; hvcC's optional rate is in frames/256s.
  return box('hvcC',new Uint8Array([1]),new Uint8Array(rbsp.slice(1,13)),u16(0xf000),new Uint8Array([0xfc,0xfd,0xf8,0xf8]),u16(0),new Uint8Array([15,arrays.length]),...arrays);
}
export function createAlphaMP4({headers,width,height,fps,frames}) {
  if(!Number.isInteger(width)||!Number.isInteger(height)||width<64||height<64||width%2||height%2||width>1920||height>1920||width*height>2073600||!Number.isInteger(fps)||fps<1||fps>30||!Number.isSafeInteger(frames)||frames<1||frames>0xffffffff)throw Error('invalidExport');
  const sizes=[],sync=[],duration=frames;
  let size=0,finished=false;
  const ftyp=box('ftyp','isom',u32(512),'isom','iso6','mp41','muxa');
  // A 64-bit mdat size supports long activities beyond 4 GiB.
  const header=bytes(ftyp,u32(1),'mdat',zeros(8));
  const hvcc=config(headers);
  function add(sample) {
    if(finished||sizes.length>=frames||!sample.length||sample.length>0xffffffff||!Number.isSafeInteger(size+sample.length))throw Error('invalidSample');
    const units=nals(sample);
    for(const layer of [0,1])if(!units.some(n=>nalType(n)<=31&&nalLayer(n)===layer))throw Error('missingAlpha');
    if(units.some(n=>nalLayer(n)===0&&nalType(n)>=16&&nalType(n)<=23))sync.push(sizes.length+1);
    sizes.push(sample.length);size+=sample.length;
  }
  function finish() {
  if(finished||sizes.length!==frames)throw Error('incompleteExport');finished=true;
  new DataView(header.buffer).setBigUint64(ftyp.length+8,BigInt(size+16));
  const hvc1=box('hvc1',zeros(6),u16(1),zeros(16),u16(width),u16(height),u32(0x480000),u32(0x480000),u32(0),u16(1),zeros(32),u16(24),u16(65535),hvcc,box('colr','nclx',u16(1),u16(1),u16(1),zeros(1)));
  const stbl=box('stbl',full('stsd',0,u32(1),hvc1),full('stts',0,u32(1),u32(duration),u32(1)),full('stsc',0,u32(1),u32(1),u32(duration),u32(1)),full('stsz',0,u32(0),u32(duration),packed32(sizes)),full('stco',0,u32(1),u32(header.length)),full('stss',0,u32(sync.length),packed32(sync)));
  const mdia=box('mdia',full('mdhd',0,zeros(8),u32(fps),u32(duration),u16(0x55c4),u16(0)),full('hdlr',0,u32(0),'vide',zeros(12),'DataLayer Alpha\0'),box('minf',full('vmhd',1,zeros(8)),box('dinf',full('dref',0,u32(1),full('url ',1))),stbl));
  const trak=box('trak',full('tkhd',7,zeros(8),u32(1),u32(0),u32(duration),zeros(16),matrix,u32(width*65536),u32(height*65536)),mdia);
  const moov=box('moov',full('mvhd',0,zeros(8),u32(fps),u32(duration),u32(65536),u16(256),zeros(10),matrix,zeros(24),u32(2)),trak);
  sizes.length=sync.length=0;return moov;
  }
  return {header,add,finish};
}
export function alphaMP4({samples,...settings}) {
  const mux=createAlphaMP4({...settings,frames:samples.length});
  samples.forEach(mux.add);const tail=mux.finish();
  return new Blob([mux.header,...samples,tail],{type:'video/mp4'});
}
export function writeAll(handle,data,at) {
  let offset=0;
  while(offset<data.length){const count=handle.write(data.subarray(offset),{at:at+offset});if(!Number.isInteger(count)||count<=0||count>data.length-offset)throw Error('storageWrite');offset+=count;}
}
