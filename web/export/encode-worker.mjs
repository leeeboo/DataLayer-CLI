import createAlphaEncoder from './encoder/x265.mjs?v=20261026-full1';
import {createAlphaMP4,writeAll} from './mp4.mjs?v=20261026-full1';
import {exportDirectory} from './storage.mjs?v=20261026-full1';
let encoder,memory,mux,handle,fileHandle,offset=0;
// Pthreads can grow shared memory without refreshing the exported HEAPU8 view.
const heap=()=>new Uint8Array(memory.buffer);
const read = () => heap().slice(encoder._output_pointer(),encoder._output_pointer()+encoder._output_size());
self.onmessage = async ({data}) => {
  const {id,type,config,pixels,index,fileName}=data;
  try {
    let result={};
    if(type==='open') {
      if(encoder)throw Error('encoderBusy');
      memory=new WebAssembly.Memory({initial:1024,maximum:8192,shared:true});
      const moduleURL=new URL('./encoder/x265.mjs?v=20261026-full1',import.meta.url);
      encoder=await createAlphaEncoder({wasmMemory:memory,mainScriptUrlOrBlob:moduleURL.href,locateFile:path=>new URL(`${path}?v=20261026-full1`,moduleURL).href,printErr:()=>{}});
      if(encoder._open_encoder(config.width,config.height,config.fps,config.kbps)!==0)throw Error('encoderOpen');
      if(!fileName){result.bytes=read();}else{
        if(!/^[a-f0-9-]{36}\.mp4$/.test(fileName))throw Error('invalidFile');
        fileHandle=await(await exportDirectory()).getFileHandle(fileName,{create:true});
        handle=await fileHandle.createSyncAccessHandle();handle.truncate(0);
        mux=createAlphaMP4({headers:read(),...config});writeAll(handle,mux.header,0);offset=mux.header.length;
      }
    } else if(type==='frame') {
      if(!encoder||pixels.byteLength!==config.width*config.height*4)throw Error('invalidFrame');
      heap().set(new Uint8Array(pixels),encoder._input_pointer());
      if(encoder._encode_frame(index)!==1)throw Error('encoderFrame');
      const bytes=read();
      if(mux){mux.add(bytes);writeAll(handle,bytes,offset);offset+=bytes.length;}else result.bytes=bytes;
      result.heapBytes=memory.buffer.byteLength;
    } else if(type==='finish') {
      if(!encoder||encoder._encode_frame(-1)!==0||encoder._output_size()!==0)throw Error('encoderFlush');
      encoder._close_encoder();
      if(mux){const tail=mux.finish();writeAll(handle,tail,offset);writeAll(handle,mux.header,0);handle.flush();handle.close();handle=undefined;result.size=offset+tail.length;}
      else result.bytes=new Uint8Array();
    } else throw Error('invalidMessage');
    self.postMessage({id,...result},result.bytes?[result.bytes.buffer]:[]);
  } catch(error) {if(handle){handle.close();handle=undefined;}self.postMessage({id,error:true,storageError:['QuotaExceededError','NotAllowedError','NotSupportedError','NoModificationAllowedError'].includes(error.name)});}
};
