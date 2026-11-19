// Common delivery rates; NTSC rates keep their exact 1001 denominator.
export const frameRates={'23.976':[24000,1001],'24':[24,1],'25':[25,1],'29.97':[30000,1001],'30':[30,1],'50':[50,1],'59.94':[60000,1001],'60':[60,1]};
export const maxDimension=3840,maxPixels=3840*2160;
// Sparse overlays: 8 Mbps at 1080p30, scaled sub-linearly by pixels and frame rate.
export function recommendedBitrate(width,height,fps) {
  return Math.max(2,Math.round(8*(width*height/2073600)**.75*(fps/30)**.6));
}
export function exportConfig({size,fps,bitrate},activityDuration,range={start:0,end:activityDuration}) {
  const match=/^(\d+)x(\d+)$/.exec(size),rate=Object.hasOwn(frameRates,String(fps))?frameRates[String(fps)]:undefined;
  if(!match||!rate)throw Error('invalidExport');
  const [width,height]=match.slice(1).map(Number),[fpsNum,fpsDen]=rate,rateValue=fpsNum/fpsDen;
  bitrate=Number(bitrate);
  if(![range.start,range.end,activityDuration].every(Number.isFinite)||range.start<0||range.end>activityDuration+1e-8||range.end-range.start<.1-1e-9)throw Error('invalidExport');
  if(![width,height,bitrate].every(Number.isFinite)||width<64||height<64||width>maxDimension||height>maxDimension||width%2||height%2||width*height>maxPixels||bitrate<.1||bitrate>100)throw Error('invalidExport');
  const frames=Math.ceil((range.end-range.start)*rateValue-1e-8);
  if(frames<1||frames*fpsDen>0xffffffff)throw Error('invalidExport');
  return {width,height,fps:rateValue,fpsNum,fpsDen,start:range.start,frames,kbps:Math.round(bitrate*1000)};
}
