import createAlphaEncoder from './encoder/x265.mjs';
let encoder;
const read = () => encoder.HEAPU8.slice(encoder._output_pointer(),encoder._output_pointer()+encoder._output_size());
self.onmessage = async ({data}) => {
  const {id,type,config,pixels,index}=data;
  try {
    let bytes;
    if(type==='open') {
      if(encoder)throw Error('encoderBusy');
      encoder=await createAlphaEncoder({printErr:()=>{}});
      if(encoder._open_encoder(config.width,config.height,config.fps,config.kbps)!==0)throw Error('encoderOpen');
      bytes=read();
    } else if(type==='frame') {
      if(!encoder||pixels.byteLength!==config.width*config.height*4)throw Error('invalidFrame');
      encoder.HEAPU8.set(new Uint8Array(pixels),encoder._input_pointer());
      if(encoder._encode_frame(index)!==1)throw Error('encoderFrame');
      bytes=read();
    } else if(type==='finish') {
      if(!encoder||encoder._encode_frame(-1)!==0||encoder._output_size()!==0)throw Error('encoderFlush');
      encoder._close_encoder();bytes=new Uint8Array();
    } else throw Error('invalidMessage');
    self.postMessage({id,bytes},[bytes.buffer]);
  } catch { self.postMessage({id,error:true}); }
};
