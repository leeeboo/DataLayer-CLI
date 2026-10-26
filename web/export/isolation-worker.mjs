// Isolation is confined to the prototype's directory; no cache or external proxy.
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('fetch',event=>{
  if(new URL(event.request.url).origin!==self.location.origin)return;
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
