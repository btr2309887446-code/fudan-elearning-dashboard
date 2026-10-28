import { spawn } from 'node:child_process';
import { mkdirSync,mkdtempSync,writeFileSync,readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join,resolve } from 'node:path';
import assert from 'node:assert/strict';
for (const migration of ['primary-and-backup', 'backup-only']) {
const profile=mkdtempSync(join(tmpdir(),'elearning-stability-'));
const fake='synthetic-migration-key-never-real';
writeFileSync(join(profile,'prefs.json'),JSON.stringify({syncMinutes:0,...(migration==='primary-and-backup'?{llm:{apiKey:fake,enabled:true,baseUrl:'https://example.invalid',model:'synthetic'}}:{})}));
writeFileSync(join(profile,'prefs.json.bak'),JSON.stringify({llm:{apiKey:fake,enabled:true,baseUrl:'https://example.invalid',model:'synthetic'}}));
mkdirSync('artifacts/ui',{recursive:true});
const env={...process.env,ELEARNING_DEMO:'1',ELEARNING_DEMO_DIR:profile,ELEARNING_SMOKE:`artifacts/ui/stability-${migration}.png`,ELEARNING_SMOKE_DELAY:'700',ELEARNING_SMOKE_SETTLE:'200',ELEARNING_SMOKE_SCRIPT_FILE:resolve('scripts/stability-ui-driver.js')};
delete env.ELECTRON_RUN_AS_NODE;
const result=await new Promise((done,reject)=>{
  const child=spawn(resolve('node_modules/electron/dist/electron.exe'),['.'],{env,windowsHide:true});
  let output='';child.stdout.on('data',x=>output+=x);child.stderr.on('data',x=>output+=x);
  const timer=setTimeout(()=>child.kill(),45000);
  child.on('error',reject);child.on('exit',code=>{clearTimeout(timer);done({code,output});});
});
writeFileSync(`artifacts/ui/stability-${migration}.log`,result.output);
assert(result.code===0&&result.output.includes('STABILITY_UI_PASS'),result.output);
for(const name of ['prefs.json','prefs.json.bak','credentials.json']) assert(!readFileSync(join(profile,name),'utf8').includes(fake),`${name} contains plaintext`);
assert(!result.output.includes(fake),'diagnostics contain synthetic secret');
}
console.log('stability UI: sandbox, public credential boundaries, real safeStorage migration and foreground day change passed');
