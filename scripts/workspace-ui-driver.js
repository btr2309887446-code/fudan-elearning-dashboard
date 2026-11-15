// Executed in Electron's renderer by the existing isolated DEMO smoke harness.
(async () => {
  const wait = (ms = 80) => new Promise((r) => setTimeout(r, ms));
  const assert = (value, message) => {
    if (!value) throw new Error(message);
  };
  const findButton = (text) =>
    [...document.querySelectorAll("button")].find(
      (b) => b.textContent.trim() === text,
    ) ??
    [...document.querySelectorAll(".ws-nav button")].find((b) =>
      b.textContent.trim().startsWith(text),
    );
  const click = async (text) => {
    const b = findButton(text);
    assert(b, `Missing button: ${text}`);
    b.focus();
    b.click();
    await wait();
  };
  const value = async (el, v) => {
    assert(el, "Missing input");
    const proto =
      el instanceof HTMLSelectElement
        ? HTMLSelectElement.prototype
        : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(proto, "value").set.call(el, v);
    el.dispatchEvent(
      new Event(el instanceof HTMLSelectElement ? "change" : "input", {
        bubbles: true,
      }),
    );
    await wait();
  };
  for (let i = 0; i < 50 && !document.querySelector(".workspace"); i++)
    await wait(100);
  assert(document.querySelector(".workspace"), "Workspace did not load");
  const snap = await window.elearning.data.cached();
  assert(
    snap.profile.name === "示例同学",
    "UI tests must use synthetic account",
  );
  if (SMOKE_VIEW === 'feedback' || SMOKE_VIEW === 'reduced') {
    await click('☑任务');
    const trigger = findButton('＋ 新建任务'); trigger.focus();
    await click('＋ 新建任务');
    const title = document.querySelector('dialog input[maxlength]');
    assert(document.activeElement === title, 'Dialog focuses title');
    await value(title, '交互反馈测试');
    const reminder = document.querySelector('dialog input[placeholder="例如 0, 30, 1440"]');
    await value(reminder, '-1'); await click('保存任务');
    assert(document.querySelector('#task-form-error').textContent.includes('最多'), 'Invalid reminder shows inline error');
    await value(reminder, '');
    assert(!document.querySelector('#task-form-error').textContent.includes('最多'), 'Correcting input clears validation error');
    const save = findButton('保存任务');
    save.click(); save.click();
    await wait(100);
    assert(findButton('保存中…')?.disabled, 'Slow save shows progress and prevents duplicate submit');
    assert(document.querySelector('dialog input[maxlength]').disabled || document.querySelector('dialog input[maxlength]').matches(':disabled'), 'Pending form cannot be edited');
    await wait(650);
    assert(document.querySelector('dialog[open]'), 'Failed save keeps dialog');
    assert(title.value === '交互反馈测试', 'Failed save preserves input');
    assert(document.querySelector('dialog [role="alert"]').textContent.includes('演示'), 'Failure shown in form');
    let local = await window.elearning.workspace.get(snap.profile.id);
    assert(!local.data.series.some(s => s.title === '交互反馈测试'), 'Failure never persists or reports success');
    await click('保存任务');
    await wait(850);
    assert(!document.querySelector('dialog[open]'), 'Successful save closes dialog');
    local = await window.elearning.workspace.get(snap.profile.id);
    assert(local.data.series.filter(s => s.title === '交互反馈测试').length === 1, 'Double click creates only one task');
    assert(document.querySelector('.ws-detail h2')?.textContent === '交互反馈测试', 'New task detail selected');
    const id = local.data.series.find(s => s.title === '交互反馈测试').id;
    await click('标为完成');
    await wait(850);
    local = await window.elearning.workspace.get(snap.profile.id);
    assert(local.data.series.find(s => s.id === id).exceptions.single.completed, 'Completion persisted');
    assert(![...document.querySelectorAll('.ws-list-pane .ws-row-main')].some(e => e.textContent.includes('交互反馈测试')), 'Completed row exits filtered list');
    await click('撤销'); await wait(350);
    local = await window.elearning.workspace.get(snap.profile.id);
    assert(!local.data.series.find(s => s.id === id).exceptions.single.completed, 'Undo restores persisted state');
    await click('编辑'); await click('取消'); await wait(200);
    assert(!document.querySelector('dialog[open]'), 'Cancel animates then closes');
    assert(document.activeElement.textContent === '编辑', 'Focus restores to edit button');
    await click('← 返回列表');
    await click('月历'); await click('列表'); await click('月历'); await click('列表');
    assert(!document.querySelector('.ws-calendar'), 'Rapid switch settles on latest view');
    await click('▤课程'); document.querySelector('.ws-row-main').click(); await wait();
    const tabs = document.querySelectorAll('[role="tab"]'); tabs[0].focus();
    tabs[0].dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true })); await wait();
    assert(document.activeElement === tabs[1] && tabs[1].getAttribute('aria-selected') === 'true', 'Tabs support arrow navigation');
    if (SMOKE_VIEW === 'reduced') {
      assert(matchMedia('(prefers-reduced-motion: reduce)').matches, 'Reduced motion enabled');
      assert(document.getAnimations().length === 0, 'Reduced motion has no active animation');
    }
  } else if (SMOKE_VIEW === 'performance') {
    await click('☑任务');
    await value(document.querySelector('[aria-label="任务来源"]'), 'personal');
    assert(document.querySelectorAll('.ws-row').length === 100, '5000 tasks render only first page');
    const started = performance.now();
    await value(document.querySelector('[aria-label="搜索当前页面"]'), '性能任务 4999');
    assert(document.querySelectorAll('.ws-row').length === 1, '5000-task search finds exact match');
    assert(performance.now() - started < 1000, '5000-task search is responsive');
    document.querySelector('.ws-row input[type="checkbox"]').click(); await wait();
    assert(document.querySelector('.ws-bulk').textContent.includes('已选 1 项'), '5000-task selection works');
  } else if (SMOKE_VIEW === "interaction") {
    await click("☑任务");
    await click("＋ 新建任务");
    assert(document.querySelector("dialog[open]"), "Native dialog opened");
    await value(
      document.querySelector("dialog input[maxlength]"),
      "UI 回归任务",
    );
    await click("＋ 添加子任务");
    await value(
      document.querySelector('input[aria-label="子任务 1"]'),
      "检查期次",
    );
    await click("保存任务");
    for (let i = 0; i < 40 && document.querySelector("dialog[open]"); i++)
      await wait();
    assert(
      !document.querySelector("dialog[open]"),
      "Task persisted before dialog closed",
    );
    await value(document.querySelector('[aria-label="任务来源"]'), "personal");
    const b = [...document.querySelectorAll(".ws-row-main")].find((e) =>
      e.textContent.includes("UI 回归任务"),
    );
    assert(b, "Created personal task shown");
    b.click();
    await wait();
    const check = document.querySelector('.ws-detail input[type="checkbox"]');
    check.click();
    await wait(150);
    let local = await window.elearning.workspace.get(snap.profile.id);
    const series = local.data.series.find((s) => s.title === "UI 回归任务");
    assert(
      series.exceptions.single.checked.length === 1,
      "Checklist persisted",
    );
    await click("标为完成");
    local = await window.elearning.workspace.get(snap.profile.id);
    assert(
      local.data.series.find((s) => s.id === series.id).exceptions.single
        .completed,
      "Completion persisted",
    );
    await click("删除");
    assert(
      document.querySelector("dialog[open]"),
      "Delete confirmation required",
    );
    await click("取消");
    await wait(200);
    assert(document.querySelector(".ws-detail"), "Cancel preserves detail");
    await click("删除");
    await click("确认删除");
    await wait(150);
    local = await window.elearning.workspace.get(snap.profile.id);
    assert(
      local.data.series.find((s) => s.id === series.id).exceptions.single
        .deleted,
      "Deletion persisted",
    );
    await value(document.querySelector('[aria-label="任务来源"]'), "school");
    document.querySelector(".ws-row-main").click();
    await wait();
    const input = document.querySelector(".ws-deadline input");
    await value(input, "2027-01-15T18:00");
    await click("保存截止时间");
    await wait(150);
    local = await window.elearning.workspace.get(snap.profile.id);
    assert(
      Object.values(local.data.deadlines).includes("2027-01-15T10:00:00.000Z"),
      "Manual deadline persisted in UTC",
    );
    await click("恢复学校时间");
    await wait(150);
    local = await window.elearning.workspace.get(snap.profile.id);
    assert(
      Object.keys(local.data.deadlines).length === 0,
      "Clearing override restores school deadline",
    );
    await click("← 返回列表");
    await click("月历");
    assert(document.querySelector(".ws-calendar-grid"), "Calendar mounted");
    await click("列表");
    const mismatch = await window.elearning.workspace.get(snap.profile.id + 1);
    assert(!mismatch.ok, "Account mismatch rejected");
  } else if (SMOKE_VIEW.startsWith("tasks")) {
    await click("☑任务");
    document.querySelector(".ws-row-main").click();
    await wait(150);
  } else if (SMOKE_VIEW === "calendar") {
    await click("☑任务");
    await click("月历");
  } else if (SMOKE_VIEW === "changes") {
    await click("◷变化中心");
    document.querySelector(".ws-row-main")?.click();
    await wait();
  } else if (SMOKE_VIEW === "courses") {
    await click("▤课程");
    document.querySelector(".ws-row-main").click();
    await wait();
    await click("成绩");
  } else if (SMOKE_VIEW === "settings") {
    await click("⚙设置");
  }
  await wait(200);
  assert(
    document.documentElement.scrollWidth <= innerWidth + 1,
    "No horizontal page overflow",
  );
  assert(
    document.querySelector(".ws-toolbar").getBoundingClientRect().right <=
      innerWidth + 1,
    "Toolbar within window",
  );
  if (innerWidth < 960 && document.querySelector(".ws-detail"))
    assert(
      getComputedStyle(document.querySelector(".ws-list-pane")).display ===
        "none",
      "Narrow detail replaces list",
    );
  if (innerWidth >= 960 && document.querySelector(".ws-detail"))
    assert(
      document.querySelector(".ws-list-pane").getBoundingClientRect().width >=
        260,
      "List remains usable",
    );
  const result = {
    passed: true,
    view: SMOKE_VIEW,
    width: innerWidth,
    height: innerHeight,
    rows: document.querySelectorAll(".ws-row").length,
  };
  console.log("WORKSPACE_UI_PASS", JSON.stringify(result));
  return result;
})();
