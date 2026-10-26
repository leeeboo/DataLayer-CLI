export async function prepareIsolation(script) {
  if(!isSecureContext||!navigator.serviceWorker)return false;
  const current=navigator.serviceWorker.controller?.scriptURL===script.href;
  if(!current) {
    let changed,timer;
    const control=new Promise((resolve,reject)=>{
      changed=()=>{if(navigator.serviceWorker.controller?.scriptURL===script.href)resolve();};
      timer=setTimeout(()=>reject(Error('isolationTimeout')),10000);
      navigator.serviceWorker.addEventListener('controllerchange',changed);
    });
    try {await Promise.all([navigator.serviceWorker.register(script,{scope:new URL('./',script).href,type:'module',updateViaCache:'none'}),control]);}
    catch {return false;}
    finally {clearTimeout(timer);navigator.serviceWorker.removeEventListener('controllerchange',changed);}
  }
  if(!globalThis.crossOriginIsolated) {
    if(!current){location.reload();await new Promise(()=>{});}
    return false;
  }
  return typeof SharedArrayBuffer!=='undefined'&&typeof WebAssembly!=='undefined'&&typeof Worker!=='undefined'&&!!navigator.storage?.getDirectory&&!!navigator.locks;
}
