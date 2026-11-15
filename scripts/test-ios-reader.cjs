const {app,BrowserWindow,session}=require('electron');
const {mkdtempSync}=require('node:fs');
const {tmpdir}=require('node:os');
const {join,resolve}=require('node:path');
app.setPath('userData',mkdtempSync(join(tmpdir(),'ios-reader-test-')));
app.whenReady().then(async()=>{
 const win=new BrowserWindow({show:false,width:430,height:932,webPreferences:{sandbox:true,contextIsolation:true}});
 let external=0;
 session.defaultSession.webRequest.onBeforeRequest((details,callback)=>{if(/^https?:/.test(details.url))external++;callback({cancel:/^https?:/.test(details.url)});});
 await win.loadFile(resolve('flutter_app/ios/NativeRunner/lecture-reader.html'));
 const result=await win.webContents.executeJavaScript(`(async()=>{
 const assert=(v,m)=>{if(!v)throw Error(m)};
 renderNote({key:'summary',markdown:true,dark:false,size:17,text:'## 重点\\n\\n$$x^2$$\\n\\n| a | b |\\n|---|---|\\n| c | d |\\n\\n<script>window.pwned=1</script>\\n\\n![image](https://example.com/track)\\n\\n[unsafe](javascript:alert(1))'});
 await new Promise(r=>requestAnimationFrame(r));
 assert(document.querySelector('.katex'),'formula');assert(document.querySelector('table'),'table');
 assert(!window.pwned&&!document.querySelector('img'),'untrusted HTML and remote images');
 assert(!document.querySelector('a[href^="javascript:"]'),'unsafe link');assert(document.querySelector('#toc button'),'table of contents');
 renderNote({key:'transcript',markdown:false,dark:true,size:22,text:'<script>literal transcript</script>'});
 assert(document.querySelector('pre').textContent.includes('<script>'),'literal transcript');
 assert(document.documentElement.dataset.theme==='dark','dark mode');assert(document.documentElement.style.fontSize==='22px','dynamic font');
 return '8 reader checks passed';})()`);
 if(external)throw Error('Unexpected remote resource request');
 console.log(result);app.exit(0);
}).catch(error=>{console.error(error);app.exit(1);});
