// Minimal single-track, constant-rate HEVC Alpha muxer. Samples retain both layers.
const bytes = (...items) => {
  const arrays = items.map(x => typeof x === 'string' ? new TextEncoder().encode(x) : x);
  const out = new Uint8Array(arrays.reduce((n,a)=>n+a.length,0)); let offset=0;
  for(const a of arrays){out.set(a,offset);offset+=a.length;} return out;
};
const u16 = n => new Uint8Array([n>>>8,n&255]);
const u32 = n => new Uint8Array([n>>>24,(n>>>16)&255,(n>>>8)&255,n&255]);
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
function config(headers,fps) {
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
  return box('hvcC',new Uint8Array([1]),new Uint8Array(rbsp.slice(1,13)),u16(0xf000),new Uint8Array([0xfc,0xfd,0xf8,0xf8]),u16(fps),new Uint8Array([15,arrays.length]),...arrays);
}
export function alphaMP4({headers,samples,width,height,fps}) {
  if(!Number.isInteger(width)||!Number.isInteger(height)||width<64||height<64||width%2||height%2||width>1920||height>1920||width*height>2073600||!Number.isInteger(fps)||fps<1||fps>30||!samples.length||samples.length>fps*60)throw Error('invalidExport');
  const duration=samples.length, sizes=samples.map(s=>s.length), size=sizes.reduce((a,b)=>a+b,0);
  if(size>128*1024*1024)throw Error('exportTooLarge');
  const sync=[];
  samples.forEach((sample,index)=>{
    const units=nals(sample);
    for(const layer of [0,1])if(!units.some(n=>nalType(n)<=31&&nalLayer(n)===layer))throw Error('missingAlpha');
    if(units.some(n=>nalLayer(n)===0&&nalType(n)>=16&&nalType(n)<=23))sync.push(index+1);
  });
  const ftyp=box('ftyp','isom',u32(512),'isom','iso6','mp41','muxa');
  const hvc1=box('hvc1',zeros(6),u16(1),zeros(16),u16(width),u16(height),u32(0x480000),u32(0x480000),u32(0),u16(1),zeros(32),u16(24),u16(65535),config(headers,fps),box('colr','nclx',u16(1),u16(1),u16(1),zeros(1)));
  const stbl=box('stbl',full('stsd',0,u32(1),hvc1),full('stts',0,u32(1),u32(duration),u32(1)),full('stsc',0,u32(1),u32(1),u32(duration),u32(1)),full('stsz',0,u32(0),u32(duration),...sizes.map(u32)),full('stco',0,u32(1),u32(ftyp.length+8)),full('stss',0,u32(sync.length),...sync.map(u32)));
  const mdia=box('mdia',full('mdhd',0,zeros(8),u32(fps),u32(duration),u16(0x55c4),u16(0)),full('hdlr',0,u32(0),'vide',zeros(12),'DataLayer Alpha\0'),box('minf',full('vmhd',1,zeros(8)),box('dinf',full('dref',0,u32(1),full('url ',1))),stbl));
  const trak=box('trak',full('tkhd',7,zeros(8),u32(1),u32(0),u32(duration),zeros(16),matrix,u32(width*65536),u32(height*65536)),mdia);
  const moov=box('moov',full('mvhd',0,zeros(8),u32(fps),u32(duration),u32(65536),u16(256),zeros(10),matrix,zeros(24),u32(2)),trak);
  return new Blob([ftyp,u32(size+8),'mdat',...samples,moov],{type:'video/mp4'});
}
