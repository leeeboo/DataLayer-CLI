import { catalog, bounds as baseBounds } from './model.mjs?v=20261025-weather';
import { genericRGBToSRGB } from './render-color.mjs?v=20261025-weather';
import { drawSpecial } from './render-special.mjs?v=20261025-weather';

export const escapeXML = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' }[c]));
function nativeCSS(red, green, blue, alpha) {
  const converted = genericRGBToSRGB({red,green,blue,alpha});
  return `rgba(${converted.red*255},${converted.green*255},${converted.blue*255},${converted.alpha})`;
}
export const color = (value, fallback) => value ? nativeCSS(value.red,value.green,value.blue,value.alpha) : fallback;
const override = (value, fallback) => value?.trim() ? value : fallback;
const palette = Object.fromEntries(Object.entries({telemetryGreen:[.46,.97,.58,.98],electricBlue:[.45,.82,1,.98],amber:[1,.76,.35,.98],hotRed:[1,.38,.42,.98],cleanWhite:[.96,.98,1,.98]}).map(([key,value])=>[key,nativeCSS(...value)]));
const colors = {white:nativeCSS(.96,.98,1,.96),label:nativeCSS(.74,.80,.86,.92),muted:nativeCSS(.66,.72,.78,.82),track:nativeCSS(1,1,1,.14),panelStroke:nativeCSS(1,1,1,.14),tileStroke:nativeCSS(1,1,1,.16)};
const fontStyles = {
  helveticaNeue: ['Helvetica Neue,Arial,sans-serif', '400'], helveticaNeueBold: ['Helvetica Neue,Arial,sans-serif', '700'],
  menloBold: ['Menlo,Consolas,monospace', '700'], avenirNextCondensedHeavy: ['Avenir Next Condensed,Arial Narrow,sans-serif', '900'],
  futuraCondensedExtraBold: ['DLS Futura Condensed,Futura,Arial Narrow,sans-serif', '800'],
};
const localFaces = {
  'DLS Futura Condensed': ['Futura-CondensedExtraBold', '800'],
  'DLS Weather W3': ['HiraginoSans-W3', '300'], 'DLS Weather W6': ['HiraginoSans-W6', '600'],
  'DLS Weather W7': ['HiraginoSans-W7', '700'], 'DLS Weather W8': ['HiraginoSans-W8', '800'],
  'DLS Weather Snow': ['ZapfDingbatsITC', '400'], 'DLS Weather Fog': ['AppleSymbols', '400'],
};
const fontStyle = font => Array.isArray(font) ? font : fontStyles[font] ?? fontStyles.helveticaNeueBold;
// Pin CoreText's weather fallback faces: Firefox otherwise selects smaller symbol glyphs.
function weatherFont(font, symbol) {
  const style = fontStyle(font);
  if (font === 'menloBold') return style;
  if (symbol === '⚡︎') return ['Menlo,Consolas,monospace', font === 'helveticaNeue' ? '400' : '700'];
  const face = ['☀︎', '☁︎', '☂︎'].includes(symbol)
    ? `DLS Weather ${{helveticaNeue:'W3',helveticaNeueBold:'W6',avenirNextCondensedHeavy:'W7',futuraCondensedExtraBold:'W8'}[font] ?? 'W6'}`
    : symbol === '❄︎' ? 'DLS Weather Snow' : symbol === '≋' ? 'DLS Weather Fog' : null;
  return face ? [`${face},${style[0]}`, localFaces[face][1]] : style;
}
// Use installed system faces only; unavailable fonts keep the original browser fallback.
export const fontsReady = typeof document === 'undefined' || typeof FontFace === 'undefined' ? Promise.resolve() : (() => {
  return Promise.all(Object.entries(localFaces).map(([family, [name, weight]]) => {
    const face = new FontFace(family, `local("${name}")`, {weight});
    document.fonts.add(face);
    return face.load().catch(() => {});
  }));
})();
const measuring = typeof document === 'undefined' ? null : document.createElement('canvas').getContext('2d');
function metrics(value, size, font) {
  size = Math.max(.1, Math.round(size * 100) / 100);
  const [family, weight] = fontStyle(font);
  if (measuring) { measuring.font = `${weight} ${size}px ${family}`; return measuring.measureText(value); }
  // Node-only schema tests have no font engine; browser and native comparison use measured glyphs.
  return { width: String(value).length * size * .6, actualBoundingBoxAscent: size * .8, actualBoundingBoxDescent: size * .2 };
}
const measure = (value, size, font) => metrics(String(value), size, font).width;
const finite = value => typeof value === 'number' && Number.isFinite(value);
const decimal = (value, precision = 0) => finite(value) ? value.toFixed(Math.min(3, Math.max(0, precision))) : '--';
const distanceUnit = e => e.customization.distanceUnit ?? 'km';
function distance(value, e) { const unit = distanceUnit(e); return decimal(value == null ? null : value / (unit === 'm' ? 1 : unit === 'mi' ? 1609.344 : 1000), e.customization.valuePrecision ?? (unit === 'm' ? 0 : 2)); }
const distanceLabel = (value, e) => `${distance(value, e)} ${override(e.customization.unitOverride, distanceUnit(e))}`;
function speedValue(value, e) {
  if (!finite(value)) return '--.-';
  const precision = Math.min(2, Math.max(0, e.customization.valuePrecision ?? 1));
  return (value * 3.6).toFixed(precision).padStart(precision + 3, '0');
}
function clockDuration(elapsed) { const seconds = Math.max(0, Math.floor(elapsed)); return [Math.floor(seconds / 3600), Math.floor(seconds / 60) % 60, seconds % 60].map(v => String(v).padStart(2, '0')).join(':'); }
export const examplePreview = (() => {
  const sample = { elapsed: 2568, date: '2026-10-25T07:32:18Z', clock: '07:32:18', calendar: '2026/10/25', latitude: 30.0042, longitude: 120.0042,
    speedMetersPerSecond: 3.6, distanceMeters: 12800, altitudeMeters: 286, totalAscentMeters: 286, heartRate: 148, cadence: 176, totalCalories: 428,
    stepLengthMeters: 1.24, powerWatts: 248, verticalOscillationCentimeters: 8.2, groundContactTimeMilliseconds: 238, groundContactTimePercent: 42,
    groundContactTimeBalancePercent: 50, verticalRatioPercent: 6.6, respirationRateBreathsPerMinute: 32, stepSpeedLossPercent: 3.8,
    formPowerWatts: 72, airPowerWatts: 12, legSpringStiffnessKilonewtonsPerMeter: 11.2, temperatureCelsius: 21,
    weatherTemperatureCelsius: 21, weatherHumidityPercent: 85, weatherSummary: 'Clouds' };
  const samples = Array.from({length:61}, (_,i) => ({...sample, elapsed:i*60, distanceMeters:i*300, latitude:30+i*.0001+Math.sin(i*.18)*.0002, longitude:120+i*.0001, altitudeMeters:280+Math.sin(i*.25)*80, trackSegmentIndex:0}));
  return { sample, series:{samples,totalDistanceMeters:18000} };
})();
const metricKinds = new Set(Object.keys(catalog).filter(kind => !['speed','route','altitudeProfile','topProgress','timeDate'].includes(kind)));
const descriptions = {
  heartRate:['HR','heartRate','BPM',0], cadence:['CAD','cadence','SPM',0], calories:['CAL','totalCalories','KCAL',0], ascent:['ASC','totalAscentMeters','m',0],
  strideLength:['STRIDE','stepLengthMeters','m',2], power:['PWR','powerWatts','W',0], verticalOscillation:['VERT','verticalOscillationCentimeters','CM',1],
  groundContactTime:['GCT','groundContactTimeMilliseconds','MS',0], groundContactTimePercent:['GCT %','groundContactTimePercent','%',1],
  groundContactTimeBalance:['GCT BAL','groundContactTimeBalancePercent','%',1], verticalRatio:['VERT R','verticalRatioPercent','%',1],
  respirationRate:['RESP','respirationRateBreathsPerMinute','BR/MIN',1], stepSpeedLoss:['SSL','stepSpeedLossPercent','%',1],
  formPower:['FORM','formPowerWatts','W',0], airPower:['AIR','airPowerWatts','W',0], legSpringStiffness:['LSS','legSpringStiffnessKilonewtonsPerMeter','kN/m',1],
};
const icons = { strideLength:'STR', groundContactTimePercent:'GCT%', groundContactTimeBalance:'BAL', verticalRatio:'VR' };
const weatherIcons = {clear:'☀︎',clouds:'☁︎',rain:'☂︎',snow:'❄︎',thunderstorm:'⚡︎',fog:'≋',wind:'≈'};
function weatherIcon(c, summary) {
  if (weatherIcons[c.iconOverride]) return weatherIcons[c.iconOverride];
  const value = (summary ?? '').toLowerCase();
  const kind = value.includes('thunder') ? 'thunderstorm' : /rain|drizzle/.test(value) ? 'rain' : value.includes('snow') ? 'snow' : /mist|smoke|haze|dust|fog/.test(value) ? 'fog' : /squall|tornado/.test(value) ? 'wind' : value.includes('clear') ? 'clear' : 'clouds';
  return weatherIcons[kind];
}
function metricContent(e, sample) {
  const c = e.customization; let label, value, unit;
  if (e.kind === 'pace') {
    const seconds = sample.speedMetersPerSecond > .3 ? Math.round(1000 / sample.speedMetersPerSecond) : null;
    [label,value,unit] = ['PACE', seconds == null ? '--:--' : `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2,'0')}`, '/KM'];
  } else if (e.kind === 'distance') [label,value,unit] = ['DIST',distance(sample.distanceMeters,e),distanceUnit(e)];
  else if (e.kind === 'weather') {
    const temperature = c.manualWeatherTemperatureCelsius ?? sample.weatherTemperatureCelsius ?? sample.temperatureCelsius;
    const humidity = c.manualWeatherHumidityPercent ?? sample.weatherHumidityPercent;
    [label,value,unit] = ['WEATHER',`${temperature == null ? '--' : Math.round(temperature)}℃`,`${sample.weatherSummary ?? 'Weather'}${c.showsWeatherHumidity !== false && humidity != null ? `\n${humidity}%` : ''}`];
  } else {
    const [l,key,u,p] = descriptions[e.kind];
    const integer = ['heartRate','cadence','calories','power','formPower','airPower'].includes(e.kind);
    [label,value,unit] = [l, integer ? (finite(sample[key]) ? String(Math.round(sample[key])) : '--') : decimal(sample[key],c.valuePrecision ?? p),u];
  }
  return {label:override(c.labelOverride,label),value,unit:override(c.unitOverride,unit)};
}
function union(a,b) { const x=Math.min(a.x,b.x),y=Math.min(a.y,b.y); return {x,y,width:Math.max(a.x+a.width,b.x+b.width)-x,height:Math.max(a.y+a.height,b.y+b.height)-y}; }
export const svgDefinitions = '<defs><filter id="native-surface-shadow" x="-50%" y="-50%" width="200%" height="200%" color-interpolation-filters="sRGB"><feDropShadow dx="0" dy="2" stdDeviation="5" flood-color="#000" flood-opacity=".28"/></filter></defs>';
function environment(e,layout,W,H,preview) {
  const c=e.customization,b=baseBounds(e,W,H),r={...b,y:H-b.y-b.height},s=Math.max(.28,Math.min(W/1920,H/1080))*e.frame.scale;
  const accent=color(c.valueColor,palette[e.frame.style.accentColor ?? layout.style.accentColor]);
  const C={...colors,value:accent,label:color(c.labelColor,colors.label),unit:color(c.unitColor,colors.muted),icon:color(c.iconColor,color(c.labelColor,colors.label)),track:color(c.trackColor,colors.track)};
  let measured={...r};
  const addBounds = b => { measured=union(measured,b); };
  const text = (value,x,y,size,fill,font,anchor='start') => {
    value=String(value); const m=metrics(value,size,font), offset=anchor==='end'?m.width:anchor==='middle'?m.width/2:0;
    if(value) addBounds({x:x-offset-(m.actualBoundingBoxLeft??0),y:y-(m.actualBoundingBoxDescent??0),width:(m.actualBoundingBoxLeft??0)+(m.actualBoundingBoxRight??m.width),height:(m.actualBoundingBoxAscent??size*.8)+(m.actualBoundingBoxDescent??0)});
    const [family,weight]=fontStyle(font);
    return `<text x="${x}" y="${H-y}" fill="${fill}" font-size="${Math.round(size*100)/100}" font-family="${family}" font-weight="${weight}" text-anchor="${anchor}">${escapeXML(value)}</text>`;
  };
  const rect=(b,radius,fill,stroke=null,strokeWidth=1)=>`<rect x="${b.x}" y="${H-b.y-b.height}" width="${b.width}" height="${b.height}" rx="${Math.max(0,Math.min(radius,b.width/2,b.height/2))}" fill="${fill}"${stroke?` stroke="${stroke}" stroke-width="${strokeWidth}"`:''}/>`;
  const circle=(x,y,r,fill,stroke=null,strokeWidth=1)=>`<circle cx="${x}" cy="${H-y}" r="${r}" fill="${fill}"${stroke?` stroke="${stroke}" stroke-width="${strokeWidth}"`:''}/>`;
  const line=(x1,y1,x2,y2,stroke,width,extra='')=>`<line x1="${x1}" y1="${H-y1}" x2="${x2}" y2="${H-y2}" stroke="${stroke}" stroke-width="${width}" ${extra}/>`;
  const path=(d,stroke,width,fill='none',extra='')=>`<path d="${d}" transform="translate(0 ${H}) scale(1 -1)" fill="${fill}" stroke="${stroke}" stroke-width="${width}" stroke-linecap="round" stroke-linejoin="round" ${extra}/>`;
  const opacity=e.frame.style.panelOpacity??layout.style.panelOpacity;
  const surface=(b,radius,tile=false)=>{
    if(!c.showsPanel)return '';
    const fill=tile?nativeCSS(.024,.029,.034,Math.min(.92,Math.max(.10,opacity*.94))):nativeCSS(.018,.022,.026,Math.min(.95,Math.max(.12,opacity)));
    let result=`<g filter="url(#native-surface-shadow)">${rect(b,radius,fill)}</g>`;
    if(c.showsPanelBorder!==false){ result+=rect(b,radius,'none',tile?colors.tileStroke:colors.panelStroke,tile?Math.max(.7,.8*s):1); const inset=tile?11*s:18;
      if(b.width>inset*2)result+=rect({x:b.x+inset,y:b.y+b.height-1.25,width:b.width-inset*2,height:.8},.5,nativeCSS(1,1,1,tile?.18:.22)); }
    return result;
  };
  return {e,c,r,s,t:e.frame.style.textScale,H,W,layout,sample:preview.sample,series:preview.series,C,accent,measure,text,rect,circle,line,path,rgba:color,override,addBounds,
    withAlpha:(value,alpha)=>value.replace(/rgba\(([^,]+),([^,]+),([^,]+),[^)]+\)/,`rgba($1,$2,$3,${alpha})`),
    distance,distanceUnit,speedValue,usesImperialMeasurements:false,showGaugeTicks:c.showGaugeTicks??layout.style.showGaugeTicks,
    panel:(r,radius)=>surface(r,radius),tile:(r,radius)=>surface(r,radius,true),getBounds:()=>measured};
}
function metricGeometry(e,env,content,aligned=0) {
  const {c,r,s,t}=env,ls=10*s*t*c.labelScale,vs=23*s*t*c.valueScale,us=10*s*t*c.unitScale,is=(e.kind==='weather'?16:10)*s*t*c.iconScale;
  const lines=content.unit.split('\n'),weather=e.kind==='weather',topIcon=c.showsIcon&&!weather,top=(c.showsLabel||topIcon)?Math.max(ls,is):0;
  const gap=Math.max(2*s,us*.16)*(weather?(c.weatherIconSpacingScale??1):1);
  const unitHeight=c.showsUnit?(weather&&c.showsIcon?is:us)+(lines.length-1)*(us+gap):0;
  const unitWidth=c.showsUnit?Math.max(...lines.map((v,i)=>weather&&c.showsIcon&&i===0?env.measure(weatherIcon(c,v),is,weatherFont(c.iconFont,weatherIcon(c,v))):env.measure(v,us,c.unitFont))):0;
  const valueHeight=Math.max(vs,unitHeight),icon=override(c.iconOverride,icons[e.kind]??descriptions[e.kind]?.[0]??(e.kind==='distance'?'DIST':'PACE'));
  const naturalWidth=Math.max(r.width,28*s+env.measure(content.value,vs,c.valueFont)+(c.showsUnit?10*s:0)+unitWidth,28*s+(c.showsLabel?env.measure(content.label,ls,c.labelFont):0)+(topIcon?12*s+env.measure(icon,is,c.iconFont):0));
  const height=Math.max(r.height,9*s+top+(top?Math.max(6*s,vs*.18):0)+valueHeight+14*s);
  return {r:{x:r.x,y:r.y+r.height-height,width:Math.max(naturalWidth,aligned*e.frame.scale),height},ls,vs,us,is,top,valueHeight,lines,gap,icon,topIcon,naturalWidth};
}
function drawMetric(e,env,g,content) {
  const {c,s,C,text}=env,r=g.r,topBaseline=r.y+r.height-9*s-g.top*.78,valueBaseline=r.y+14*s+g.valueHeight*.24;
  let svg=env.tile(r,10*s);
  if(c.showsLabel)svg+=text(content.label,r.x+14*s,topBaseline,g.ls,C.label,c.labelFont);
  if(g.topIcon)svg+=text(g.icon,r.x+r.width-14*s,topBaseline,g.is,C.icon,c.iconFont,'end');
  svg+=text(content.value,r.x+14*s,valueBaseline,g.vs,C.value,c.valueFont);
  if(c.showsUnit){const step=Math.max(g.us,g.is*.72)+g.gap,first=valueBaseline+(g.lines.length-1)*step/2;
    g.lines.forEach((v,i)=>{const icon=e.kind==='weather'&&c.showsIcon&&i===0;svg+=text(icon?weatherIcon(c,v):v,r.x+r.width-14*s,first-i*step,icon?g.is:g.us,icon?C.icon:C.unit,icon?weatherFont(c.iconFont,weatherIcon(c,v)):c.unitFont,'end');});}
  return {svg,bounds:r};
}
function drawTime(e,env) {
  const {c,r,s,t,C,text,sample}=env,ls=11*s*t*c.labelScale,vs=24*s*t*c.valueScale,cs=22*s*t*c.unitScale,ds=18*s*t*c.unitScale,is=12*s*t*c.iconScale;
  const top=c.showsLabel||c.showsIcon?Math.max(ls,is):0,tg=top?Math.max(6*s,top*.25):0,vg=Math.max(8*s,vs*.28),ug=Math.max(8*s,cs*.28);
  const elapsed=clockDuration(sample.elapsed),clock=sample.clock??'--:--:--',date=sample.calendar??'----/--/--',label=override(c.labelOverride,'TIME'),icon=override(c.iconOverride,'TIME');
  const width=Math.max(r.width,Math.max(env.measure(elapsed,vs,c.valueFont),c.showsUnit?env.measure(clock,cs,c.unitFont):0,c.showsUnit?env.measure(date,ds,c.unitFont):0,c.showsLabel?env.measure(label,ls,c.labelFont):0)+(c.showsIcon?env.measure(icon,is,c.iconFont):0)+28*s);
  const height=Math.max(r.height,15*s+top+tg+vs+(c.showsUnit?vg+cs+ug+ds:0)+12*s),panel={x:r.x+r.width-width,y:r.y+r.height-height,width,height},right=panel.x+panel.width;
  let cursor=panel.y+panel.height-15*s,svg=env.panel(panel,12*s);
  if(c.showsIcon)svg+=text(icon,panel.x,cursor-top*.78,is,C.icon,c.iconFont);
  if(c.showsLabel)svg+=text(label,right,cursor-top*.78,ls,C.label,c.labelFont,'end');
  if(top)cursor-=top+tg;
  svg+=text(elapsed,right,cursor-vs*.78,vs,C.value,c.valueFont,'end');
  if(c.showsUnit){cursor-=vs+vg;svg+=text(clock,right,cursor-cs*.78,cs,C.unit,c.unitFont,'end');cursor-=cs+ug;svg+=text(date,right,cursor-ds*.78,ds,C.unit,c.unitFont,'end');}
  return {svg,bounds:panel};
}
function drawProgress(e,env) {
  const {c,r,s,t,C,text}=env,th=Math.max(.25,c.lineWidth*s),ls=15*s*t*(c.progressStartScale??c.labelScale),vs=12*s*t*(c.progressCurrentScale??c.valueScale),us=15*s*t*(c.progressEndScale??c.unitScale),is=12*s*t*c.iconScale;
  const top=Math.max(c.showsLabel?ls:0,c.showsUnit?us:0,c.showsIcon?is:0),bottom=c.showsLabel?vs:0,topGap=top?Math.max(5*s,top*.18):0;
  const knob=Math.max(4*s,th*.82*(c.progressKnobScale??1)),outer=knob+Math.max(2*s,knob*.28),extent=Math.max(th/2,outer,env.showGaugeTicks?th*1.225:th/2),bottomGap=bottom?Math.max(5*s,th*.35)*(c.progressValueMarginScale??1):0;
  const height=Math.max(r.height,8*s+top+topGap+extent*2+bottomGap+bottom+(bottom?7*s:0)),panel={x:r.x,y:r.y+r.height-height,width:r.width,height};
  const cy=top||bottom?panel.y+height-8*s-top-topGap-extent:panel.y+height/2,pad=Math.min(panel.width*.42,Math.max(0,72*s*(c.progressInsetScale??1))),track={x:panel.x+pad,y:cy-th/2,width:Math.max(1,panel.width-pad*2),height:th};
  const total=Math.max(env.series.totalDistanceMeters??0,env.sample.distanceMeters??0),current=Math.max(0,Math.min(env.sample.distanceMeters??0,total)),progress=total>0?current/total:0,knobX=track.x+track.width*progress;
  const bar=color(c.progressBarColor,C.value),start=color(c.progressStartColor,C.label),value=color(c.progressCurrentColor,C.value),end=color(c.progressEndColor,C.unit);
  let svg=env.panel({x:panel.x-10*s,y:panel.y-5*s,width:panel.width+20*s,height:panel.height+10*s},12*s);
  svg+=env.rect(track,th/2,C.track);if(progress>0)svg+=env.rect({...track,width:track.width*progress},th/2,bar);
  if(env.showGaugeTicks){const count=c.progressTickCount??Math.max(8,Math.min(80,Math.round(track.width/Math.max(1,28*s)))),stride=Math.max(1,Math.floor(count/10));
    for(let i=0;i<=count&&count>0;i++){const major=i%stride===0,h=th*(major?2.45:1.55),x=track.x+track.width*i/count;svg+=env.line(x,cy-h/2,x,cy+h/2,C.unit,Math.max(.75*s,th*(major?.12:.07)));}}
  svg+=env.circle(knobX,cy,outer,nativeCSS(.018,.022,.026,.30))+env.circle(knobX,cy,knob,color(c.progressBarColor,color(c.valueColor,C.white)))+env.circle(knobX,cy,outer,'none',bar,Math.max(1,th*.18));
  const baseline=panel.y+panel.height-8*s-top*.78;
  if(c.showsLabel){svg+=text(distanceLabel(0,e),track.x,baseline,ls,start,c.progressStartFont??c.labelFont);const v=distanceLabel(current,e),w=env.measure(v,vs,c.progressCurrentFont??c.valueFont);svg+=text(v,Math.min(track.x+track.width-w,Math.max(track.x,knobX-w/2)),cy-extent-bottomGap-vs*.78,vs,value,c.progressCurrentFont??c.valueFont);}
  if(c.showsUnit)svg+=text(distanceLabel(total,e),track.x+track.width,baseline,us,end,c.progressEndFont??c.unitFont,'end');
  if(c.showsIcon)svg+=text(override(c.iconOverride,'DIST'),Math.max(panel.x,track.x-52*s),baseline,is,C.icon,c.iconFont);
  env.addBounds(panel);if(c.showsPanel)env.addBounds({x:panel.x-10*s,y:panel.y-5*s,width:panel.width+20*s,height:panel.height+10*s});const radius=outer+Math.max(1,th*.18)/2;env.addBounds({x:knobX-radius,y:cy-radius,width:radius*2,height:radius*2});
  return {svg,bounds:env.getBounds()};
}
export function renderLayout(layout,width,height,preview=examplePreview) {
  preview={sample:preview.sample??examplePreview.sample,series:preview.series??examplePreview.series};
  const envs=layout.elements.map(e=>environment(e,layout,width,height,preview)),contents=layout.elements.map(e=>metricKinds.has(e.kind)?metricContent(e,preview.sample):null);
  const aligned=Math.max(0,...layout.elements.map((e,i)=>e.frame.isVisible&&contents[i]?metricGeometry(e,envs[i],contents[i]).naturalWidth/e.frame.scale:0));
  return layout.elements.map((e,i)=>{
    const env=envs[i];let result;
    if(contents[i])result=drawMetric(e,env,metricGeometry(e,env,contents[i],aligned),contents[i]);
    else if(e.kind==='timeDate')result=drawTime(e,env);
    else if(e.kind==='topProgress')result=drawProgress(e,env);
    else result={svg:drawSpecial(e,env)??'',bounds:env.getBounds()};
    const b=result.bounds;return {id:e.id,svg:`<g>${result.svg}</g>`,bounds:{x:b.x,y:height-b.y-b.height,width:b.width,height:b.height}};
  });
}
export function gaugeSVG(e,layout,width,height,preview=examplePreview) {
  const elements=layout.elements.some(item=>item.id===e.id)?layout.elements:[...layout.elements,e];
  return renderLayout({...layout,elements},width,height,preview).find(item=>item.id===e.id).svg;
}
