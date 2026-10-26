export function exportConfig({size,fps,start,duration,bitrate},activityDuration) {
  const match=/^(\d+)x(\d+)$/.exec(size);
  if(!match)throw Error('invalidExport');
  const [width,height]=match.slice(1).map(Number);
  [fps,start,duration,bitrate]=[fps,start,duration,bitrate].map(Number);
  if(![width,height,fps,start,duration,bitrate,activityDuration].every(Number.isFinite)||width<64||height<64||width>1920||height>1920||width%2||height%2||width*height>2073600||!Number.isInteger(fps)||fps<1||fps>30||start<0||duration<.1||Math.ceil(duration*fps-1e-8)>0xffffffff||start+duration>activityDuration+1e-8||bitrate<.1||bitrate>100)throw Error('invalidExport');
  return {width,height,fps,start,frames:Math.ceil(duration*fps-1e-8),kbps:Math.round(bitrate*1000)};
}
