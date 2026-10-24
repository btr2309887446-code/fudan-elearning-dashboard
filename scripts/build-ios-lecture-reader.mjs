// Reproducible, offline WKWebView resource. User markdown is rendered as React nodes, never HTML.
import { build } from 'esbuild';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const source = `
import React from 'react';
import {createRoot} from 'react-dom/client';
import {flushSync} from 'react-dom';
import Markdown from 'react-markdown';
import gfm from 'remark-gfm';
import math from 'remark-math';
import katex from 'rehype-katex';
const h=React.createElement, root=createRoot(document.getElementById('note'));
const positions=new Map(); let key='';
window.renderNote=(value)=>{
 if(key)positions.set(key,window.scrollY); const changed=key!==value.key;key=value.key;
 document.documentElement.style.colorScheme=value.dark?'dark':'light';
 document.documentElement.dataset.theme=value.dark?'dark':'light';
 document.documentElement.style.fontSize=value.size+'px';
 let index=0;const headings=[];
 const heading=(tag)=>({children})=>{const id='heading-'+(++index);headings.push({id,children});return h(tag,{id},children);};
 const text=value.text.replace(/\\\\\\[([\\s\\S]*?)\\\\\\]/g,(_,s)=>'$$'+s+'$$').replace(/\\\\\\((.*?)\\\\\\)/g,(_,s)=>'$'+s+'$');
 flushSync(()=>root.render(value.markdown?h(Markdown,{skipHtml:true,remarkPlugins:[gfm,math],rehypePlugins:[[katex,{trust:false,strict:false}]],components:{
 h1:heading('h2'),h2:heading('h2'),h3:heading('h3'),h4:heading('h4'),
 img:({alt})=>h('span',null,'〔'+(alt||'图片')+'〕'),
 a:({href,children})=>/^https:\\/\\//i.test(href||'')?h('a',{href},children):h('span',null,children),
 table:({children})=>h('div',{className:'table-scroll',role:'region','aria-label':'表格，可横向滚动',tabIndex:0},h('table',null,children))
 }},text):h('pre',null,value.text)));
 const toc=document.getElementById('toc');toc.replaceChildren();
 if(headings.length){const summary=document.createElement('summary');summary.textContent='本次课目录';toc.append(summary);for(const item of headings){const button=document.createElement('button');button.textContent=document.getElementById(item.id)?.textContent||'';button.onclick=()=>document.getElementById(item.id)?.scrollIntoView();toc.append(button);}}
 toc.hidden=!headings.length;
 if(changed)requestAnimationFrame(()=>window.scrollTo(0,positions.get(key)||0));
};
document.addEventListener('selectionchange',()=>window.webkit?.messageHandlers?.selection?.postMessage((window.getSelection()?.toString()||'').slice(0,10000)));
`;
const result = await build({stdin:{contents:source,resolveDir:process.cwd(),loader:'js'},bundle:true,write:false,minify:true,platform:'browser',target:'safari15',define:{'process.env.NODE_ENV':'"production"'}});
const cssPath = require.resolve('katex/dist/katex.min.css');
let css = readFileSync(cssPath,'utf8').replace(/url\(([^)]+)\)/g,(_,p)=>`url(data:application/octet-stream;base64,${readFileSync(resolve(dirname(cssPath),p.replace(/["']/g,''))).toString('base64')})`);
css += `:root{font-family:-apple-system,BlinkMacSystemFont,sans-serif;color:#1c1c1e;background:#fff;line-height:1.7;overflow-wrap:anywhere} :root[data-theme=dark]{color:#eee;background:#1c1c1e} body{max-width:760px;margin:auto;padding:20px} h2{font-size:1.35rem;margin-top:1.7em} h3{font-size:1.15rem} pre{white-space:pre-wrap;font:inherit} a{color:#007aff} table{border-collapse:collapse;min-width:100%} td,th{border:1px solid #8886;padding:8px;text-align:left} .table-scroll,.katex-display{overflow-x:auto;overflow-y:hidden;max-width:100%} .table-scroll{margin:1em 0} .katex-display>.katex{white-space:nowrap} details{border-bottom:1px solid #8885;padding:12px 0} button{display:block;background:transparent;border:0;color:#007aff;font:inherit;text-align:left;padding:8px;min-height:44px} button:active{background:#8883} :focus-visible{outline:2px solid #007aff;outline-offset:2px} code{font-size:.9em} @media(prefers-reduced-motion:reduce){*{scroll-behavior:auto}}`;
const html=`<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; font-src data:; img-src 'none'; connect-src 'none'"><style>${css}</style></head><body><details id="toc" hidden></details><main id="note"></main><script>${result.outputFiles[0].text.replace(/<\/script/gi,'<\\/script')}</script></body></html>`;
const path='flutter_app/ios/NativeRunner/lecture-reader.html';writeFileSync(path,html);console.log(`${path}: ${Buffer.byteLength(html)} bytes, no remote assets`);
