(async () => {
  const wait = (ms=80) => new Promise(r=>setTimeout(r,ms));
  const assert = (condition,message) => { if(!condition) throw Error(message); };
  for(let n=0;n<60&&!document.querySelector('.workspace');n++) await wait();
  assert((await window.elearning.data.cached()).profile.id===90210,'synthetic profile');
  assert(typeof require==='undefined','renderer has no Node require');
  const prefs=await window.elearning.prefs.get(), llm=await window.elearning.llm.get();
  assert(!('llm' in prefs)&&!('encryptedPassword' in prefs),'public preference whitelist');
  const expectedKey=SMOKE_VIEW!=='revoked-backup';
  assert(llm.hasApiKey===expectedKey&&!('apiKey' in llm),'dedicated getter returns saved-state only');
  const remembered=await window.elearning.auth.remembered();
  assert(!('password' in remembered),'saved login password never crosses IPC');
  await window.elearning.prefs.set({llm:{apiKey:'invalid-override'},encryptedPassword:'invalid-override'});
  assert((await window.elearning.llm.get()).hasApiKey===expectedKey,'generic preference mutation cannot change the private key');
  let rejected=false;
  try { await window.elearning.llm.set({enabled:'invalid'}); } catch { rejected=true; }
  assert(rejected,'invalid IPC fields rejected before mutation');
  const today=()=>document.querySelector('.ws-intro span')?.textContent;
  const before=today();
  const trigger=[...document.querySelectorAll('button')].find(b=>b.textContent.trim()==='＋ 新建任务');
  trigger.click(); await wait();
  const title=document.querySelector('dialog input[maxlength]');
  Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(title,'跨天保留草稿');
  title.dispatchEvent(new Event('input',{bubbles:true})); await wait();
  const original=Date.now; Date.now=()=>original()+86400000;
  window.dispatchEvent(new Event('focus')); document.dispatchEvent(new Event('visibilitychange')); await wait(200);
  assert(today()!==before,'foreground resume updates day without a network sync');
  assert(title.value==='跨天保留草稿'&&document.querySelector('dialog[open]'),'clock tick preserves unsaved form');
  Date.now=original; window.dispatchEvent(new Event('focus')); await wait();
  return 'STABILITY_UI_PASS';
})()
