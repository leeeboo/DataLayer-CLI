// Add isolation within the registering page's scope; no cache or external proxy.
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('message',event=>{if(event.data?.type==='dls-claim')event.waitUntil(self.clients.claim());});
self.addEventListener('fetch',event=>{
  const url=new URL(event.request.url);
  if(url.origin!==self.location.origin)return;
  const prefix=new URL('./download/',self.location.href).pathname;
  if(url.pathname.startsWith(prefix)){
    const match=/^([a-f0-9-]{36}\.mp4)\/([^/]+)$/.exec(url.pathname.slice(prefix.length));
    if(!match||event.request.method!=='GET'){event.respondWith(new Response(null,{status:404}));return;}
    let respond;const response=new Promise(resolve=>{respond=resolve;});
    const job=navigator.locks.request(`dls-hevc-${match[1]}`,{mode:'shared'},async()=>{
      try{
        const root=await(await navigator.storage.getDirectory()).getDirectoryHandle('dls-hevc-exports');
        const file=await(await root.getFileHandle(match[1])).getFile();
        let start=0,end=file.size-1,status=200;
        const filename=encodeURIComponent(decodeURIComponent(match[2])).replace(/['()*]/g,c=>`%${c.charCodeAt(0).toString(16).toUpperCase()}`);
        const headers=new Headers({'Content-Type':'video/mp4','Accept-Ranges':'bytes','Content-Disposition':`attachment; filename*=UTF-8''${filename}`,'Cross-Origin-Resource-Policy':'same-origin'});
        const range=event.request.headers.get('Range');
        if(range){
          const parts=/^bytes=(\d*)-(\d*)$/.exec(range);
          if(!parts||(!parts[1]&&!parts[2]))throw Error('invalidRange');
          if(parts[1]){start=Number(parts[1]);if(parts[2])end=Math.min(end,Number(parts[2]));}
          else start=Math.max(0,file.size-Number(parts[2]));
          if(!Number.isSafeInteger(start)||!Number.isSafeInteger(end)||start<0||start>end||start>=file.size){respond(new Response(null,{status:416,headers:{'Content-Range':`bytes */${file.size}`}}));return;}
          status=206;headers.set('Content-Range',`bytes ${start}-${end}/${file.size}`);
        }
        headers.set('Content-Length',String(end-start+1));
        const reader=file.slice(start,end+1).stream().getReader();let complete,remaining=end-start+1;
        const done=new Promise(resolve=>{complete=resolve;});
        const body=new ReadableStream({async pull(controller){try{const part=await reader.read();if(part.done){controller.close();complete();}else{controller.enqueue(part.value);remaining-=part.value.byteLength;if(remaining===0){controller.close();complete();await reader.cancel();}}}catch(error){controller.error(error);complete();}},cancel(reason){complete();return reader.cancel(reason);}});
        respond(new Response(body,{status,headers}));
        // Keep deletion blocked until the download or seek finishes reading disk.
        await done;
      }catch(error){respond(new Response(null,{status:404,headers:{'X-DLS-Storage-Error':error.name}}));}
    }).catch(()=>respond(new Response(null,{status:500})));
    event.waitUntil(job);event.respondWith(response);return;
  }
  event.respondWith((async()=>{
    const response=await fetch(event.request);
    if(response.type==='opaque'||response.status===0)return response;
    const headers=new Headers(response.headers);
    headers.set('Cross-Origin-Opener-Policy','same-origin');
    headers.set('Cross-Origin-Embedder-Policy','require-corp');
    // Revalidated module requests can return 304 with an empty stream in WebKit.
    const body=[204,205,304].includes(response.status)?null:response.body;
    return new Response(body,{status:response.status,statusText:response.statusText,headers});
  })());
});
