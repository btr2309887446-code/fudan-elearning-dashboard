// Drive the UI into a specific screen before the smoke screenshot is taken.
// SMOKE_VIEW is injected by the main process (the renderer has no `process`).
(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const target = typeof SMOKE_VIEW === 'string' ? SMOKE_VIEW : 'dashboard';

  const cards = () => document.querySelectorAll('.course-card');
  const navs = () => Array.from(document.querySelectorAll('.sb-item'));
  const terms = () => document.querySelectorAll('.sb-term');
  const ignoreSwitch = () => document.querySelector('.switch');
  const themeBtn = () =>
    Array.from(document.querySelectorAll('.icon-btn')).find((b) =>
      (b.getAttribute('title') || '').includes('色')
    );

  const navTo = (word) => {
    const t = navs().find((b) => b.textContent.includes(word));
    if (t) t.click();
    return !!t;
  };

  // .content 才是滚动容器，scrollIntoView 在这里不起作用（它不动 scrollTop），
  // 所以按元素相对容器的位置手动设 scrollTop。
  const scrollToEl = (el, pad = 12) => {
    const box = document.querySelector('.content');
    if (!box || !el) return false;
    const a = el.getBoundingClientRect();
    const b = box.getBoundingClientRect();
    box.scrollTop += a.top - b.top - pad;
    return true;
  };

  const filesSection = () =>
    Array.from(document.querySelectorAll('.section-head h2')).find((h) =>
      h.textContent.includes('课程文件')
    );

  // 窗口高度受屏幕限制，装不下整页。缩小页面让文件区完整可见。
  // 只影响截图，不影响真实布局。
  const setZoom = (z) => {
    document.body.style.zoom = String(z);
  };

  // Idempotent: the theme preference persists between runs, so ensure the
  // wanted theme instead of blindly toggling.
  const ensureTheme = async (want) => {
    if (document.documentElement.dataset.theme !== want) {
      const b = themeBtn();
      if (b) b.click();
      await sleep(450);
    }
    return document.documentElement.dataset.theme;
  };

  let done = 'noop';

  // Computed-style probe: verifies the theme without relying on a screenshot,
  // because capturePage returns stale frames when the window is not focused.
  if (target === 'probe') {
    const cs = (sel, prop) => {
      const el = document.querySelector(sel);
      return el ? getComputedStyle(el)[prop] : 'none';
    };
    return [
      'theme=' + document.documentElement.dataset.theme,
      'body=' + getComputedStyle(document.body).backgroundColor,
      'sidebar=' + cs('.sidebar', 'backgroundColor'),
      'card=' + cs('.course-card', 'backgroundColor'),
      'stat=' + cs('.stat', 'backgroundColor'),
      'title=' + cs('.page-title', 'color'),
    ].join(' | ');
  }

  // Reset any scroll the app may have picked up, so the capture shows the top.
  const resetScroll = () => {
    const content = document.querySelector('.content');
    if (content) content.scrollTop = 0;
  };
  resetScroll();
  await sleep(60);

  if (target === 'dashboard') {
    done = 'dashboard';
  } else if (target === 'course') {
    if (cards().length > 0) {
      cards()[0].click();
      done = 'course';
    }
  } else if (target === 'timeline') {
    done = 'timeline:' + navTo('作业');
  } else if (target === 'files') {
    // 进入第一门课，滚到「课程文件」那一节。
    if (cards().length > 0) {
      cards()[0].click();
      await sleep(1600);
      const filesHead = filesSection();
      if (filesHead) {
        setZoom(0.62);
        await sleep(700);
        const panel = filesHead.closest('.panel');
        scrollToEl(panel || filesHead);
        await sleep(700);
        const rows = document.querySelectorAll('.file-row').length;
        const stats = document.querySelector('.section-head .section-note');
        const box = document.querySelector('.content');
        done = `files; rows=${rows}; note=${stats ? stats.textContent.trim() : 'none'}; scrollTop=${box ? Math.round(box.scrollTop) : '?'}`;
      } else {
        done = 'files: section not found';
      }
    } else {
      done = 'files: no course card';
    }
  } else if (target === 'filesSelect') {
    // 勾选若干文件，检查「下载选中」工具条是否出现。
    if (cards().length > 0) {
      cards()[0].click();
      await sleep(1600);
      const boxes = Array.from(document.querySelectorAll('.file-check'));
      let clicked = 0;
      for (const b of boxes) {
        if (clicked >= 3) break;
        b.click();
        clicked += 1;
      }
      await sleep(500);
      const bar = document.querySelector('.files-toolbar');
      scrollToEl(bar, 90);
      await sleep(500);
      done = `filesSelect; checked=${clicked}; toolbar=${bar ? bar.textContent.trim() : 'none'}`;
    }
  } else if (target === 'filesDownload') {
    // 触发一次演示下载，检查进度条是否渲染。
    if (cards().length > 0) {
      cards()[0].click();
      await sleep(1600);
      const filesHead = filesSection();
      if (filesHead) scrollToEl(filesHead.closest('.panel') || filesHead);
      await sleep(400);
      const all = Array.from(document.querySelectorAll('.btn')).find((b) =>
        b.textContent.includes('下载本课全部')
      );
      if (all) {
        all.click();
        await sleep(2600);
        const bar = document.querySelector('.dl-progress');
        scrollToEl(bar, 140);
        await sleep(600);
        const head = document.querySelector('.dl-progress-head');
        done = `filesDownload; progress=${head ? head.textContent.trim() : 'none'}`;
      } else {
        done = 'filesDownload: button not found';
      }
    }
  } else if (target === 'unsubmitted') {
    // 首页新增的「未提交的作业」板块。
    setZoom(0.72);
    await sleep(600);
    const heads = Array.from(document.querySelectorAll('.panel-title'));
    const h = heads.find((x) => x.textContent.includes('未提交的作业'));
    if (h) {
      scrollToEl(h.closest('.panel'));
      await sleep(600);
      const rows = document.querySelectorAll('.todo-group .tl-item').length;
      const groups = Array.from(document.querySelectorAll('.todo-group-title')).map((g) => g.textContent.trim());
      const toggles = document.querySelectorAll('.dash-toggle').length;
      const on = document.querySelectorAll('.dash-toggle.on').length;
      done = `unsubmitted; rows=${rows}; groups=${JSON.stringify(groups)}; toggles=${on}/${toggles}`;
    } else {
      done = 'unsubmitted: section not found';
    }
  } else if (target === 'customise') {
    // 关掉两个板块，验证开关生效。
    const btns = Array.from(document.querySelectorAll('.dash-toggle'));
    const off = (label) => {
      const b = btns.find((x) => x.textContent.includes(label));
      if (b && b.classList.contains('on')) b.click();
      return !!b;
    };
    const a = off('得分与关注');
    const b = off('课程卡片');
    await sleep(800);
    const panelTitles = Array.from(document.querySelectorAll('.panel-title')).map((p) => p.textContent.trim());
    const hasChart = panelTitles.some((t) => t.includes('各课程当前得分'));
    const hasGrid = !!document.querySelector('.course-grid');
    const on = document.querySelectorAll('.dash-toggle.on').length;
    done = `customise; hit=${a},${b}; chartGone=${!hasChart}; gridGone=${!hasGrid}; stillOn=${on}`;
  } else if (target === 'detail') {
    // 打开一条作业详情浮层。
    setZoom(0.72);
    await sleep(600);
    const items = Array.from(document.querySelectorAll('.todo-group .tl-item'));
    // 挑一条演示数据里带说明的，否则浮层只能显示「没有附说明」。
    const pick =
      items.find((el) => el.textContent.includes('级数')) ||
      items.find((el) => el.textContent.includes('光电效应')) ||
      items[0];
    if (pick) {
      pick.click();
      await sleep(2500);
      const modal = document.querySelector('.modal');
      if (modal) {
        const title = modal.querySelector('.modal-title');
        const summary = modal.querySelector('.summary-text');
        const src = modal.querySelector('.summary-head');
        const paras = modal.querySelectorAll('.desc-body p').length;
        done = `detail; title=${title ? title.textContent.slice(0, 26) : '?'}; src=${src ? src.textContent.trim().slice(0, 20) : '?'}; summaryLen=${summary ? summary.textContent.length : 0}; paras=${paras}`;
      } else {
        done = 'detail: modal not found';
      }
    } else {
      done = 'detail: no unsubmitted item on page';
    }
  } else if (target === 'settings') {
    // 打开设置浮层。
    const btn = Array.from(document.querySelectorAll('.icon-btn')).find((b) =>
      (b.getAttribute('title') || '').includes('设置')
    );
    if (btn) {
      btn.click();
      await sleep(1400);
      const modal = document.querySelector('.modal');
      const presets = document.querySelectorAll('.dash-toggle').length;
      const fields = document.querySelectorAll('.field input').length;
      done = `settings; modal=${!!modal}; presets=${presets}; fields=${fields}`;
    } else {
      done = 'settings: button not found';
    }
  } else if (target === 'order') {
    // 把「数据警告」一路顶到最前，再用实际渲染位置验证视觉顺序真的变了。
    const visualOrder = () =>
      Array.from(document.querySelectorAll('.dash-body > *'))
        .filter((el) => !el.classList.contains('dash-customise'))
        .sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top)
        .map((el) => (el.textContent || '').trim().slice(0, 6));

    const before = visualOrder();
    const chips = Array.from(document.querySelectorAll('.dash-toggle'));
    // 必须挑一个「当前真的渲染出来」的板块：数据警告在演示数据里没有内容，
    // 移它不会产生任何视觉变化，测了等于没测。
    const target = chips.find((c) => c.textContent.includes('课程卡片'));
    if (!target) {
      done = 'order: 课程卡片 chip not found';
    } else {
      const up = target.querySelectorAll('.dash-move')[0];
      for (let i = 0; i < 6; i++) {
        up.click();
        await sleep(160);
      }
      await sleep(700);
      const after = visualOrder();
      done = `order; before=${JSON.stringify(before.slice(0, 3))}; after=${JSON.stringify(after.slice(0, 3))}; moved=${before[0] !== after[0]}`;
    }
  } else if (target === 'motion') {
    // 动效没法靠截图验证。这里直接包一层 startViewTransition，
    // 看它有没有被调用、ready 有没有兑现——比事后猜 getAnimations 可靠。
    const hasVT = typeof document.startViewTransition === 'function';
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    let vtCalled = false;
    let vtReady = false;
    let vtFinished = false;
    let vtError = '';
    if (hasVT) {
      const orig = document.startViewTransition.bind(document);
      document.startViewTransition = (cb) => {
        vtCalled = true;
        const t = orig(cb);
        t.ready.then(() => (vtReady = true)).catch((e) => (vtError = 'ready:' + e));
        t.finished.then(() => (vtFinished = true)).catch(() => {});
        return t;
      };
    }

    const themeBtn = Array.from(document.querySelectorAll('.icon-btn')).find((b) =>
      (b.getAttribute('title') || '').includes('切换到')
    );

    const before = document.documentElement.dataset.theme;
    if (!themeBtn) {
      done = `motion: theme button not found (hasVT=${hasVT})`;
    } else {
      const r = themeBtn.getBoundingClientRect();
      themeBtn.dispatchEvent(
        new MouseEvent('click', {
          bubbles: true,
          clientX: r.left + r.width / 2,
          clientY: r.top + r.height / 2,
        })
      );
      await sleep(300);
      const after = document.documentElement.dataset.theme;
      // clip-path 动画挂在伪元素上，从根元素带 subtree 才查得到
      const anims = document.documentElement.getAnimations({ subtree: true });
      const vt = anims.filter((a) => (a.effect && a.effect.pseudoElement || '').includes('view-transition'));
      const clip = vt.map((a) => {
        const kf = a.effect.getKeyframes ? a.effect.getKeyframes() : [];
        return kf.map((k) => k.clipPath).filter(Boolean).join(' -> ');
      }).filter(Boolean)[0] || '';
      done = `motion; hasVT=${hasVT}; theme=${before}->${after}; called=${vtCalled}; anims=${vt.length}; clip=${clip.slice(0, 34)}`;
      await sleep(700);

      // 再验证弹层：打开作业详情，看 .modal 上有没有正在跑的动画。
      setZoom(0.72);
      await sleep(400);
      const item = Array.from(document.querySelectorAll('.todo-group .tl-item'))[0];
      if (item) {
        item.click();
        await sleep(120);
        const modal = document.querySelector('.modal');
        const backdrop = document.querySelector('.modal-backdrop');
        const modalAnims = modal ? modal.getAnimations().map((a) => a.animationName).join(',') : 'none';
        const bdAnims = backdrop ? backdrop.getAnimations().map((a) => a.animationName).join(',') : 'none';
        done += ` || modal: anims=[${modalAnims}] backdrop=[${bdAnims}]`;

        // 关掉时应当先挂 closing 再卸载
        const closeBtn = Array.from(document.querySelectorAll('.modal .btn')).find((b) =>
          b.textContent.includes('关闭')
        );
        if (closeBtn) {
          closeBtn.click();
          await sleep(60);
          done += ` closing=${!!document.querySelector('.modal-backdrop.closing')}`;
          await sleep(300);
          done += ` gone=${!document.querySelector('.modal')}`;
        }
      }
    }
  } else if (target === 'ignore') {
    // 「无需提交」标记：点一条未交作业 → 标记 → 它应当从未交清单里消失。
    const countRows = () => document.querySelectorAll('.todo-group .tl-item').length;
    const before = countRows();
    const item = document.querySelector('.todo-group .tl-item');
    if (!item) {
      done = 'ignore: 未交清单是空的';
    } else {
      const title = (item.querySelector('.tl-title') || {}).textContent || '';
      item.click();
      await sleep(500);

      const btn = Array.from(document.querySelectorAll('.modal-foot .btn')).find((b) =>
        b.textContent.includes('无需提交')
      );
      if (!btn) {
        done = `ignore: 详情页没有「无需提交」按钮 (按钮=${Array.from(document.querySelectorAll('.modal-foot .btn')).map((b) => b.textContent.trim()).join('|')})`;
      } else {
        btn.click();
        await sleep(400);
        const marked = !!Array.from(document.querySelectorAll('.modal-foot .btn')).find((b) =>
          b.textContent.includes('已标记')
        );
        // 关掉详情
        const closeBtn = Array.from(document.querySelectorAll('.modal-foot .btn')).find((b) =>
          b.textContent.includes('关闭')
        );
        if (closeBtn) closeBtn.click();
        await sleep(500);
        const after = countRows();
        done = `ignore; marked=${marked}; rows ${before}->${after}; removed=${after === before - 1}; title=${title.trim().slice(0, 12)}`;
      }
    }
  } else if (target === 'settingsPanel') {
    // 设置面板：外观页应当有主题按钮与板块列表，主界面不该再有板块栏。
    const openBtn = Array.from(document.querySelectorAll('.icon-btn')).find((b) =>
      (b.getAttribute('title') || '').includes('设置')
    );
    const strayBar = !!document.querySelector('.dash-customise');
    const strayTheme = Array.from(document.querySelectorAll('.icon-btn')).some((b) =>
      (b.getAttribute('title') || '').includes('深浅')
    );
    if (!openBtn) {
      done = 'settingsPanel: 找不到设置按钮';
    } else {
      openBtn.click();
      await sleep(500);
      const tabs = Array.from(document.querySelectorAll('.settings-tab')).map((t) => t.textContent.trim());
      const rows = document.querySelectorAll('.settings-section-row').length;
      const themeBtn = Array.from(document.querySelectorAll('.modal .btn')).find((b) =>
        b.textContent.includes('切换到')
      );
      done = `settingsPanel; tabs=[${tabs.join(',')}]; sectionRows=${rows}; themeBtn=${!!themeBtn}; 主界面板块栏=${strayBar}; 主界面主题钮=${strayTheme}`;
      await sleep(400);
    }
  } else if (target === 'darkReload') {
    // Seed localStorage, then reload so the very first paint is already dark -
    // capturePage only reliably returns the first composed frame here.
    localStorage.setItem('elearning.theme', 'dark');
    location.reload();
    return 'reloading into dark';
  } else if (target === 'dark') {
    const t = await ensureTheme('dark');
    await sleep(3000);
    done = `dark themeAttr=${document.documentElement.dataset.theme} (was ${t}) bodyBg=${getComputedStyle(document.body).backgroundColor}`;
  } else if (target === 'darkCourse') {
    await ensureTheme('dark');
    if (cards().length > 0) cards()[0].click();
    done = 'darkCourse; themeAttr=' + document.documentElement.dataset.theme;
  } else if (target === 'darkTimeline') {
    await ensureTheme('dark');
    navTo('作业');
    done = 'darkTimeline; themeAttr=' + document.documentElement.dataset.theme;
  } else if (target === 'ignore') {
    const s = ignoreSwitch();
    if (s && !s.classList.contains('on')) s.click();
    await sleep(300);
    navTo('作业');
    done = 'ignore+timeline';
  } else if (target === 'allterms') {
    const t = terms();
    if (t.length > 0) {
      t[0].click();
      done = 'all:' + t[0].textContent;
    }
  } else if (target === 'term1') {
    const t = terms();
    if (t.length > 1) {
      t[1].click();
      done = 'term:' + t[1].textContent;
    }
  }

  resetScroll();
  await sleep(120);

  const content = document.querySelector('.content');
  const stats = document.querySelector('.stat-grid');
  const chart = document.querySelector('.two-col');
  const rect = (el) => {
    if (!el) return 'none';
    const r = el.getBoundingClientRect();
    return `${Math.round(r.top)},${Math.round(r.height)}`;
  };
  const layout = content
    ? `content[top=${Math.round(content.getBoundingClientRect().top)},scrollTop=${Math.round(content.scrollTop)},scrollH=${content.scrollHeight},clientH=${content.clientHeight}] stats[${rect(stats)}] twoCol[${rect(chart)}]${panels(chart)}`
    : 'no content';

  return [done, 'cards=' + cards().length, layout].join(' | ');
})();

/**
 * 量一下 two-col 里两块面板各自的高度。
 *
 * 用户反馈「需要关注」比旁边的得分图高出一大截，所以要有个能直接读的证据，
 * 而不是靠肉眼看截图。
 */
function panels(twoCol) {
  if (!twoCol) return '';
  const kids = Array.from(twoCol.children);
  if (kids.length < 2) return '';
  const h = kids.map((el) => Math.round(el.getBoundingClientRect().height));
  const equal = Math.abs(h[0] - h[1]) <= 2;
  return ` panels=[${h.join(',')}] equal=${equal}`;
}
