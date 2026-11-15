(async () => {
  const wait = (ms = 100) => new Promise(r => setTimeout(r, ms));
  const assert = (value, label) => { if (!value) throw Error(label); };
  const visible = el => el && el.getClientRects().length > 0;
  const until = async (fn, label) => { for (let n = 0; n < 120; n++) { if (fn()) return; await wait(); } throw Error(`${label}: ${document.body.innerText.slice(-1200)}`); };
  const button = text => [...document.querySelectorAll('button')].find(b => visible(b) && b.textContent.trim() === text);
  const click = async text => { const b = button(text); assert(b && !b.disabled, `enabled: ${text}`); b.focus(); b.click(); await wait(); };
  const set = async (el, value) => { assert(el, 'field exists'); Object.getOwnPropertyDescriptor(el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : el instanceof HTMLSelectElement ? HTMLSelectElement.prototype : HTMLInputElement.prototype, 'value').set.call(el, value); el.dispatchEvent(new Event(el instanceof HTMLSelectElement ? 'change' : 'input', { bubbles: true })); await wait(); };
  await until(() => document.querySelector('.workspace'), 'workspace');
  const snapshot = await window.elearning.data.cached(); assert(snapshot.profile.id === 90210, 'synthetic only');
  const connection = await window.elearning.lectures.state(90210);
  const courseId = connection.data.bindings[0].canvasCourseId;
  const course = snapshot.courses.find(c => c.id === courseId);
  document.querySelector('.ws-nav [title="课程"]').click(); await wait();
  await set(document.querySelector('[aria-label="学期"]'), 'all');
  [...document.querySelectorAll('.ws-row-main')].find(b => b.textContent.includes(course.displayName)).click();
  await until(() => button('查看复习计划'), 'review overview entry'); await click('查看复习计划');
  await until(() => button('新建复习计划'), 'review workspace'); await click('新建复习计划');
  const title = document.querySelector('dialog input[data-initial-focus]'); assert(document.activeElement === title, 'initial focus');
  await set(title, '虚构期中复习');
  const today = new Date(Date.now() + 8 * 3600000); const exam = new Date(today.getTime() + 5 * 86400000).toISOString().slice(0, 10);
  await set(document.querySelector('dialog input[type=date]'), exam);
  await click('保存计划');
  if (!SMOKE_PACKAGED) { await until(() => document.querySelector('dialog [role=alert]')?.textContent.includes('磁盘'), 'save failure retained'); assert(title.value === '虚构期中复习', 'draft survives failure'); await click('保存计划'); }
  await until(() => !document.querySelector('dialog[open]'), 'plan saved');
  await click('添加知识点'); await set(document.querySelector('dialog [data-initial-focus]'), '虚构边界条件');
  await click('添加自测题'); await set(document.querySelector('dialog fieldset textarea'), '如何理解 $E=mc^2$？');
  await set(document.querySelectorAll('dialog fieldset textarea')[1], '根据课堂材料说明 $E=mc^2$。'); await click('保存知识点');
  await until(() => !document.querySelector('dialog[open]'), 'item saved');
  await click('开始自测'); await until(() => document.querySelector('dialog .katex'), 'formula rendered');
  assert(!document.querySelector('dialog details').open, 'answer hidden initially'); document.querySelector('dialog summary').click(); await wait();
  assert(document.querySelectorAll('dialog .katex').length >= 2, 'answer formula rendered');
  await set(document.querySelector('dialog select'), 'weak'); await wait(400);
  document.querySelector('dialog [aria-label="关闭对话框"]').click(); await wait();
  if (!SMOKE_PACKAGED) {
    await click('从课堂摘要生成'); await until(() => document.querySelector('dialog .rv-check input'), 'lecture selector'); document.querySelector('dialog .rv-check input').click(); await wait(); await click('查看生成范围');
    await until(() => button('发送摘要并生成'), 'AI preflight'); assert(document.querySelector('dialog').innerText.includes('example.invalid'), 'destination displayed');
    await click('发送摘要并生成'); await until(() => button('重试此批') && !button('重试此批').disabled, 'AI failure retry'); await click('重试此批');
    await until(() => button('保存选中 1 项') && !button('保存选中 1 项').disabled, 'AI preview'); await click('保存选中 1 项'); await until(() => !document.querySelector('dialog[open]'), 'AI items saved');
  }
  await click('跨课程排期'); await click('预览排期／重排'); await until(() => button('确认更新复习任务'), 'schedule preview');
  const before = await window.elearning.workspace.get(90210); assert(!before.data.series.some(s => s.reviewSource), 'preview does not create tasks');
  await click('确认更新复习任务'); await until(() => !document.querySelector('dialog[open]'), 'schedule commit');
  const saved = (await window.elearning.workspace.get(90210)).data; assert(saved.review.plans[0].items[0].mastery === 'weak', 'mastery persisted'); assert(saved.series.some(s => s.reviewSource), 'tasks generated');
  const reviewTask = saved.series.find(s => s.reviewSource);
  const completed = await window.elearning.workspace.mutate(90210, { type: 'complete', items: [{ seriesId: reviewTask.id, key: 'single' }], completed: true });
  assert(completed.ok && completed.data.review.plans[0].items[0].mastery === 'weak', 'completion does not change mastery');
  const undone = await window.elearning.workspace.mutate(90210, { type: 'complete', items: [{ seriesId: reviewTask.id, key: 'single' }], completed: false }); assert(undone.ok, 'undo completion');
  assert(document.querySelector('.rv-workspace').scrollWidth <= document.querySelector('.rv-workspace').clientWidth + 2, 'no horizontal overflow');
  return 'REVIEW_UI_PASS';
})()
