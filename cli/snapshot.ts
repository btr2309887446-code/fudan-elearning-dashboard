/**
 * End-to-end CLI: log in to Fudan eLearning and dump everything the desktop app
 * will render.
 *
 *   node cli/snapshot.ts                       # prompts for 学号 / 密码
 *   node cli/snapshot.ts --user 23123456       # prompts for the password only
 *   node cli/snapshot.ts --reuse               # reuse the saved session
 *   node cli/snapshot.ts --out snapshot.json
 */

import { spawn } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { parseArgs } from 'node:util';
import { buildSnapshot } from '../src/core/aggregate.ts';
import { CookieJar } from '../src/core/cookies.ts';
import { describeCanvasError, LoginError } from '../src/core/errors.ts';
import { loadSession, makeClient, saveSession, verifySession } from '../src/core/session.ts';
import { beginLogin, checkCaptcha, completeLogin } from '../src/core/uis.ts';
import { ask, askHidden } from './prompt.ts';

const { values } = parseArgs({
  options: {
    user: { type: 'string' },
    password: { type: 'string' },
    out: { type: 'string', default: 'snapshot.json' },
    session: { type: 'string', default: '.session.json' },
    reuse: { type: 'boolean', default: false },
    active: { type: 'boolean', default: false },
    json: { type: 'boolean', default: false },
    help: { type: 'boolean', default: false },
  },
  allowPositionals: false,
});

if (values.help) {
  console.log(`用法: node cli/snapshot.ts [选项]

  --user <学号>       学号（不填则交互询问）
  --password <密码>   密码（不填则安全地交互输入；不建议写在这里）
  --reuse             复用 .session.json 里的会话，不重新登录
  --active            只取当前学期在修的课程
  --out <文件>        快照输出路径（默认 snapshot.json）
  --session <文件>    会话缓存路径（默认 .session.json）
  --json              直接把快照 JSON 打到标准输出
  --help              显示本帮助`);
  process.exit(0);
}

let jar: CookieJar | null = null;
let username = values.user;
let displayName: string | undefined;

// --- reuse an existing session if asked, or if it still works --------------
if (values.reuse) {
  const saved = loadSession(values.session);
  if (!saved) {
    console.error(`没有找到会话文件 ${values.session}，请先正常登录一次。`);
    process.exit(1);
  }
  const profile = await verifySession(makeClient(saved.jar));
  if (!profile) {
    console.error('保存的会话已失效，请重新登录（去掉 --reuse）。');
    process.exit(1);
  }
  jar = saved.jar;
  username = saved.file.username ?? username;
  displayName = profile.name;
  console.log(`复用会话成功：${profile.name}（保存于 ${saved.file.savedAt}）`);
}

// --- otherwise do a real login ---------------------------------------------
if (!jar) {
  username = username ?? (await ask('学号: '));
  let password = values.password;
  if (!password) {
    password = await askHidden('密码（输入时不显示）: ');
  }
  if (!username || !password) {
    console.error('学号和密码都必须提供。');
    process.exit(1);
  }

  console.log('\n正在登录复旦统一身份认证…');
  try {
    const ctx = await beginLogin();

    // Ask whether a captcha is pending BEFORE spending an attempt: the provider
    // locks accounts after a few failures.
    const captcha = await checkCaptcha(ctx, username);
    let captchaCode: string | undefined;

    if (captcha.required) {
      console.log('认证服务器要求输入验证码。');
      if (captcha.image?.startsWith('data:image')) {
        const file = join(process.cwd(), 'captcha.png');
        writeFileSync(file, Buffer.from(captcha.image.split(',')[1] ?? '', 'base64'));
        console.log(`验证码图片已保存到 ${file}，正在尝试打开…`);
        try {
          spawn('cmd', ['/c', 'start', '', file], { detached: true, stdio: 'ignore' }).unref();
        } catch {
          console.log('（自动打开失败，请手动查看该图片）');
        }
      }
      captchaCode = await ask('请输入图中验证码: ');
      if (!captchaCode) {
        console.error('未输入验证码，已中止（未消耗登录次数）。');
        process.exit(2);
      }
    }

    const result = await completeLogin(ctx, { username, password, captchaCode });
    jar = result.jar;
    console.log(`登录成功（${result.elapsedMs} ms），最终落点：${result.finalUrl}`);
  } catch (err) {
    if (err instanceof LoginError) {
      console.error(`\n登录失败：${err.message}`);
      if (err.detail) console.error(`详细信息：${err.detail}`);
      process.exit(2);
    }
    console.error(`\n登录时发生意外错误：${(err as Error).message}`);
    process.exit(2);
  }

  const client = makeClient(jar);
  const profile = await verifySession(client);
  if (!profile) {
    console.error('登录流程走完了，但 Canvas 会话无效（cookie 没拿到或已过期）。');
    process.exit(3);
  }
  displayName = profile.name;
  console.log(`已通过 Canvas 验证身份：${profile.name}（ID ${profile.id}）`);
  saveSession(values.session, jar, { username, displayName });
  console.log(`会话已保存到 ${values.session}（只存 Cookie，不存密码）`);
}

// --- fetch ------------------------------------------------------------------
const client = makeClient(jar);
console.log('\n正在拉取课程与作业数据…');
const t0 = Date.now();
let snapshot;
try {
  snapshot = await buildSnapshot(client, {
    enrollmentState: values.active ? 'active' : 'all',
  });
} catch (err) {
  console.error(`拉取失败：${describeCanvasError(err)}`);
  process.exit(4);
}
console.log(`拉取完成，用时 ${((Date.now() - t0) / 1000).toFixed(1)} 秒`);

writeFileSync(values.out, JSON.stringify(snapshot, null, 2), 'utf8');

if (values.json) {
  console.log(JSON.stringify(snapshot, null, 2));
} else {
  // --- human summary -------------------------------------------------------
  console.log(`\n${'='.repeat(78)}`);
  console.log(`学生：${snapshot.profile.name}    快照时间：${snapshot.fetchedAt}`);
  console.log(`${'='.repeat(78)}`);

  const scored = snapshot.courses.filter((c) => c.currentScore !== null);
  if (scored.length) {
    const avg = scored.reduce((s, c) => s + (c.currentScore as number), 0) / scored.length;
    console.log(
      `\n共 ${snapshot.terms.length} 个学期 · ${snapshot.courses.length} 门课程（其中 ${scored.length} 门有得分）· 总平均：${avg.toFixed(2)}`
    );
  } else {
    console.log(`\n共 ${snapshot.terms.length} 个学期 · ${snapshot.courses.length} 门课程`);
  }

  // Group by semester: an average across semesters is not meaningful.
  for (const term of snapshot.terms) {
    const courses = snapshot.courses.filter((c) => c.termId === term.id);
    const graded = courses.filter((c) => c.currentScore !== null);
    const termAvg = graded.length
      ? graded.reduce((s, c) => s + (c.currentScore as number), 0) / graded.length
      : null;

    console.log(`\n── ${term.name}${term.isCurrent ? '  [当前学期]' : ''} ──`);
    console.log(
      `${courses.length} 门课程` +
        (termAvg !== null ? ` · 学期平均 ${termAvg.toFixed(2)}` : '') +
        (term.startAt ? ` · ${term.startAt.slice(0, 10)} 起` : '')
    );
    console.log(`\n${'课程'.padEnd(42)}${'当前分'.padStart(9)}${'等级'.padStart(7)}${'作业'.padStart(7)}${'缺交'.padStart(6)}`);
    console.log('-'.repeat(78));
    for (const c of courses) {
      const name = c.displayName.length > 38 ? c.displayName.slice(0, 37) + '…' : c.displayName;
      console.log(
        name.padEnd(42) +
          (c.currentScore !== null ? c.currentScore.toFixed(2) : '—').padStart(9) +
          (c.currentGrade ?? '—').padStart(7) +
          String(c.assignmentCount).padStart(7) +
          String(c.missingCount).padStart(6)
      );
    }
  }

  if (snapshot.todo.length) {
    console.log(`\n近期待办（${snapshot.todo.length} 项）：`);
    for (const t of snapshot.todo.slice(0, 12)) {
      const due = t.dueAt ? new Date(t.dueAt).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' }) : '无截止时间';
      console.log(`  [${due}] ${t.courseName} — ${t.title}`);
    }
  }

  if (snapshot.warnings.length) {
    console.log(`\n警告（${snapshot.warnings.length} 条）：`);
    for (const w of snapshot.warnings.slice(0, 10)) console.log(`  - ${w}`);
  }
  console.log(`\n完整快照已写入 ${values.out}`);
}
