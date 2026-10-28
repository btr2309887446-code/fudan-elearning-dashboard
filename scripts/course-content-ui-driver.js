(async () => {
  const wait = (ms = 70) => new Promise(r => setTimeout(r, ms));
  const assert = (v, message) => { if (!v) throw Error(message); };
  const until = async (predicate, label) => {
    for (let i = 0; i < 100; i++) { if (predicate()) return; await wait(60); }
    throw Error(`${label}: ${document.body.innerText.slice(-1500)}`);
  };
  const visible = el => el && el.getClientRects().length > 0;
  const button = text => [...document.querySelectorAll('button')].find(el => visible(el) && el.textContent.trim() === text);
  const click = async text => { const el = button(text); assert(el && !el.disabled, `Button available: ${text}`); el.focus(); el.click(); await wait(); };
  const setValue = async (el, value) => {
    assert(el, 'input exists');
    const proto = el instanceof HTMLSelectElement ? HTMLSelectElement.prototype : el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
    el.dispatchEvent(new Event(el instanceof HTMLSelectElement ? 'change' : 'input', { bubbles: true })); await wait();
  };
  await until(() => document.querySelector('.workspace'), 'Workspace starts');
  const snapshot = await window.elearning.data.cached();
  assert(snapshot.profile.name === '示例同学', 'Only synthetic account');
  const connected = await window.elearning.lectures.state(snapshot.profile.id);
  assert(connected.ok && connected.data.courses.length, 'Bundled worker and SQLite start');
  const courseId = connected.data.bindings[0].canvasCourseId;
  const course = snapshot.courses.find(c => c.id === courseId);
  if (SMOKE_VIEW === 'changes') {
    document.querySelector('.ws-nav [title="变化中心"]').click(); await wait();
    await setValue(document.querySelector('[aria-label="学期"]'), 'all');
    const change = [...document.querySelectorAll('button')].find(el => el.textContent.includes('虚构课堂摘要更新')); change.click(); await wait();
    assert(!document.querySelector('.ws-detail').textContent.includes('b'.repeat(64)), 'Change details do not expose hashes');
    await click('打开课堂笔记'); await until(() => document.querySelector('.cc-article .katex'), 'Change deep link opens original lecture');
    return 'COURSE_UI_PASS changes';
  }
  document.querySelector('.ws-nav [title="课程"]').click(); await wait();
  await setValue(document.querySelector('[aria-label="学期"]'), 'all');
  const row = [...document.querySelectorAll('.ws-row-main')].find(el => el.textContent.includes(course.displayName));
  assert(row, 'Mapped course exists'); row.focus(); row.click();
  await until(() => document.querySelector('[data-testid="course-overview"] .cc-simple-list'), 'Overview loads');
  await until(() => document.querySelector('.cc-intro').textContent.includes('示例教师'), 'Official introduction and teacher');
  assert(document.querySelectorAll('.ws-course-tabs [role="tab"]').length === 5, 'Five course tabs');
  assert(document.querySelector('.cc-overview').textContent.includes('最近课堂笔记'), 'Course overview contains latest notes');
  if (SMOKE_VIEW === 'overview') return 'COURSE_UI_PASS overview';
  await until(() => [...document.querySelectorAll('.cc-overview button')].some(el => el.textContent.includes('第 4 讲')), 'Latest lecture arrives');
  const note = [...document.querySelectorAll('.cc-overview .cc-simple-list button')].find(el => el.textContent.includes('第 4 讲'));
  assert(note, 'Latest lecture shown first'); note.focus(); note.click();
  await until(() => document.querySelector('.cc-article .katex'), 'Math renders in reader');
  assert(!visible(document.querySelector('.ws-panes')), 'Reader replaces narrow detail');
  const lectureTitle = document.querySelector('.cc-article-heading h1').textContent;
  const body = document.querySelector('.cc-article');
  assert(body.textContent.includes('课程事项提醒') && document.querySelectorAll('.cc-classroom-items button').length >= 2, 'Classroom actions reuse summary text');
  await click('原始转写');
  assert(document.querySelector('.cc-transcript')?.textContent.includes('虚构'), 'Transcript opens');
  await click('PPT 文字');
  assert(document.querySelectorAll('.cc-ppt-page').length === 2, 'OCR pages open');
  await click('课堂摘要');
  const tab = document.querySelector('.cc-reading-tabs [aria-selected="true"]');
  tab.focus(); tab.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true })); await wait();
  assert(document.activeElement.textContent === '原始转写', 'Reader tabs support keyboard');
  await click('课堂摘要');
  if (SMOKE_VIEW === 'flow') {
    const action = document.querySelector('.cc-classroom-items button'); action.focus(); action.click();
    await until(() => document.querySelector('dialog[open]'), 'Task editor opens');
    const title = document.querySelector('dialog input[maxlength]');
    assert(document.activeElement === title, 'Task dialog initially focuses title');
    assert(document.querySelector('dialog input[type="datetime-local"]').value === '', 'No inferred deadline');
    assert(document.querySelector('dialog textarea').value.includes('阅读本章'), 'Selected action is retained');
    const original = title.value;
    button('保存任务').click(); button('保存任务')?.click();
    if (!SMOKE_PACKAGED) {
    await until(() => document.querySelector('dialog [role="alert"]')?.textContent.includes('演示'), 'First save fails explicitly');
    assert(title.value === original && document.querySelector('dialog[open]'), 'Failure preserves all input');
    let data = await window.elearning.workspace.get(snapshot.profile.id);
    assert(!data.data.series.some(s => s.title === original), 'Failed save did not persist');
    await click('保存任务');
    }
    await until(() => !document.querySelector('dialog[open]'), 'Retry succeeds');
    const data = await window.elearning.workspace.get(snapshot.profile.id);
    const created = data.data.series.filter(s => s.title === original);
    assert(created.length === 1 && created[0].lectureSource.title === lectureTitle && !created[0].dueAt, 'Exactly one task retains source and no deadline');
    assert(document.querySelector('.cc-article-heading h1').textContent === lectureTitle, 'Save keeps reading context');
    await click('查看任务');
    const sourceButton = [...document.querySelectorAll('button')].find(el => visible(el) && el.textContent.startsWith('返回课堂笔记：'));
    assert(sourceButton, 'Task has a source return link'); sourceButton.click();
    await until(() => document.querySelector('.cc-article-heading h1')?.textContent === lectureTitle, 'Source returns to original lecture');
    const textNode = document.querySelector('.cc-article p').firstChild;
    const range = document.createRange(); range.selectNodeContents(textNode);
    window.getSelection().removeAllRanges(); window.getSelection().addRange(range);
    document.dispatchEvent(new Event('selectionchange')); await wait();
    await click('选中文字建任务'); await until(() => document.querySelector('dialog[open]'), 'Selection can create a draft');
    await click('取消'); await until(() => !document.querySelector('dialog[open]'), 'Cancel restores reader');
  }
  if (SMOKE_VIEW === 'settings') {
    document.querySelector('.ws-nav [title="设置"]').click();
    await until(() => document.querySelector('.cc-binding-row'), 'Connection settings and mappings');
    assert(document.querySelector('.cc-check input').checked === false, 'Remembering secrets is opt in');
    const first = document.querySelector('.cc-binding-row');
    await setValue(first.querySelector('select'), '');
    const unbind = [...first.querySelectorAll('button')].find(b => b.textContent === '解除关联'); unbind.click();
    await until(() => first.textContent.includes('待关联') || first.textContent.includes('推荐'), 'Unbinding persists');
    await setValue(first.querySelector('select'), String(courseId));
    const bind = [...first.querySelectorAll('button')].find(b => b.textContent === '确认关联'); bind.click();
    await until(() => first.textContent.includes('已关联'), 'Explicit rebind succeeds');
    const data = await window.elearning.workspace.get(snapshot.profile.id);
    assert(!data.data.changes.some(c => c.kind === 'lecture'), 'Remapping does not flood changes');
  } else {
    await document.fonts.ready;
    const scroller = document.querySelector('.cc-reading-scroll'); scroller.scrollTop = 120; await wait();
    const savedScroll = scroller.scrollTop;
    await click('‹ 返回课程');
    assert(document.activeElement === note || document.activeElement.getAttribute('role') === 'tab', 'Return restores focus');
    const reopen = [...document.querySelectorAll('.cc-overview button')].find(el => el.textContent.includes(lectureTitle));
    reopen.click(); await until(() => document.querySelector('.cc-article .katex'), 'Reader reopens'); await wait(150);
    await until(() => Math.abs(document.querySelector('.cc-reading-scroll').scrollTop - savedScroll) < 4, 'Reading position restored');
    document.querySelector('.cc-reading-scroll').scrollTop = 0;
  }
  assert(document.documentElement.scrollWidth <= innerWidth + 1, 'No horizontal page overflow');
  for (const el of document.querySelectorAll('.cc-reader-header button,.cc-reading-toolbar button')) {
    if (!visible(el)) continue;
    const box = el.getBoundingClientRect();
    assert(box.left >= 0 && box.right <= innerWidth + 1 && box.bottom <= innerHeight + 1, 'Toolbar buttons fit viewport');
  }
  return `COURSE_UI_PASS ${SMOKE_VIEW}`;
})();
