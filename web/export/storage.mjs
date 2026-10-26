const directory='dls-hevc-exports';
const owned=name=>/^[a-f0-9-]{36}\.mp4$/.test(name);
export const exportDirectory=async()=> (await navigator.storage.getDirectory()).getDirectoryHandle(directory,{create:true});
export async function cleanupExports() {
  const root=await exportDirectory();
  for await(const [name,handle]of root.entries())if(owned(name)&&handle.kind==='file'){
    await navigator.locks.request(`dls-hevc-${name}`,{ifAvailable:true},async lock=>{
      if(lock)await root.removeEntry(name).catch(error=>{if(error.name!=='NotFoundError'&&error.name!=='NoModificationAllowedError')throw error;});
    });
  }
}
export async function reserveExport() {
  const root=await exportDirectory(),name=`${crypto.randomUUID()}.mp4`;
  let release,ready,reject;
  const acquired=new Promise((resolve,fail)=>{ready=resolve;reject=fail;});
  navigator.locks.request(`dls-hevc-${name}`,{mode:'shared'},async()=>{ready();await new Promise(resolve=>{release=resolve;});}).catch(reject);
  await acquired;
  return {name,async remove(){release();await navigator.locks.request(`dls-hevc-${name}`,async()=>{
    for(let attempt=0;;attempt++)try{await root.removeEntry(name);return;}catch(error){if(error.name==='NotFoundError')return;if(error.name!=='NoModificationAllowedError'||attempt===3)throw error;await new Promise(resolve=>setTimeout(resolve,25*4**attempt));}
  });}};
}
