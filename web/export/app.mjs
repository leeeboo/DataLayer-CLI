// Keep existing bookmarks working; export now lives inside the layout editor.
const editor=new URL('../',location.href),language=new URLSearchParams(location.search).get('lang');
if(language)editor.searchParams.set('lang',language);
location.replace(editor);
