import create from '../export/encoder/x265.mjs';
const m=await create({printErr:()=>{}}),read=()=>Buffer.from(m.HEAPU8.slice(m._output_pointer(),m._output_pointer()+m._output_size())).toString('base64');
for(const bad of [[63,64,30,1,1000],[3842,2160,30,1,1000],[3840,3840,30,1,1000],[64,64,61,1,1000],[64,64,60061,1001,1000],[64,64,30,0,1000]])if(m._open_encoder(...bad)!==-1)throw Error(`invalid input accepted: ${bad}`);
if(m._open_encoder(64,64,30000,1001,1000)!==0)throw Error('open failed');
const headers=read(),frames=[],rgba=new Uint8Array(64*64*4);
for(let i=0;i<64*64;i++){rgba[i*4]=100;rgba[i*4+1]=100;rgba[i*4+2]=100;rgba[i*4+3]=i%64<20?0:i%64<40?128:255;}
for(let i=0;i<3;i++){m.HEAPU8.set(rgba,m._input_pointer());if(m._encode_frame(i)!==1)throw Error('missing frame');frames.push(read());}
if(m._encode_frame(-1)!==0||m._output_size()!==0)throw Error('unflushed output');
m._close_encoder();console.log(JSON.stringify({headers,frames}));process.exit(0);
