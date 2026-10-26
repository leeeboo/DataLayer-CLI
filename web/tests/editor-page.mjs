import {expect} from '@playwright/test';
export async function openEditor(page,url='./?lang=en') {
  await page.goto(url);
  await expect(page.locator('html')).toHaveAttribute('data-editor-ready','true',{timeout:20000});
}

// WebKit cannot route fetches from a controlled page reliably; mock only the weather transport.
export async function mockWeather(page,handler) {
  await page.exposeFunction('__dlsWeatherReply',async data=>{
    let reply;
    await handler({request:()=>({url:()=>data.url,headers:()=>data.headers,fetchOptions:data.options}),fulfill:async value=>{reply=value;},abort:async()=>{reply={networkError:true};}});
    return reply;
  });
  function install(){
    if(window.__dlsWeatherMockInstalled)return;window.__dlsWeatherMockInstalled=true;
    const original=window.fetch.bind(window);
    window.fetch=(input,options={})=>{
      const url=new URL(input instanceof Request?input.url:String(input),location.href);
      if(url.origin!=='https://api.openweathermap.org')return original(input,options);
      return new Promise((resolve,reject)=>{
        const signal=options.signal,abort=()=>reject(new DOMException('Aborted','AbortError'));
        if(signal?.aborted){abort();return;}signal?.addEventListener('abort',abort,{once:true});
        window.__dlsWeatherReply({url:url.href,headers:Object.fromEntries(new Headers(options.headers)),options:{credentials:options.credentials,referrerPolicy:options.referrerPolicy,redirect:options.redirect,cache:options.cache}}).then(reply=>{
          signal?.removeEventListener('abort',abort);if(signal?.aborted)return;
          if(reply.networkError)reject(new TypeError('Failed to fetch'));else resolve(new Response(reply.body,{status:reply.status??200,headers:reply.headers}));
        },error=>{signal?.removeEventListener('abort',abort);reject(error);});
      });
    };
  }
  await page.addInitScript(install);await page.evaluate(install);
}
