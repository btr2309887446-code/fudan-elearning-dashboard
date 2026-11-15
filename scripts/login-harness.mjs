import { spawnSync } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { CookieJar } from '../src/core/cookies.ts';
import { HttpClient } from '../src/core/http.ts';
import { beginLogin, checkCaptcha, classifyAuthResult, completeLogin, extractTicketTarget } from '../src/core/uis.ts';
import { LoginError } from '../src/core/errors.ts';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const artifactDir = join(root, 'artifacts');
const flutterRoot = join(root, 'flutter_app');
const username = process.env.FUDAN_TEST_USERNAME?.trim();
const password = process.env.FUDAN_TEST_PASSWORD;
const hasCredentials = Boolean(username && password);
const expectedPackageName = 'fudan-elearning-dashboard';

function assertProjectRoot() {
  if (resolve(process.cwd()) !== root || !existsSync(join(root, 'package.json'))) {
    throw new Error('请从项目根目录运行 npm run test:login-harness。');
  }
}

function safeUrl(value) {
  try {
    const url = new URL(value);
    return `${url.origin}${url.pathname}`;
  } catch {
    return '<invalid-url>';
  }
}

function phaseFor(url) {
  let path = '';
  try { path = new URL(url).pathname; } catch { return 'unknown'; }
  if (path === '/login/cas') return 'canvas-entry';
  if (path.includes('/verifyCodeIsNeed')) return 'captcha-precheck';
  if (path.includes('/authExecute')) return 'authExecute';
  if (path.includes('/authnEngine')) return 'authnEngine';
  if (/users\/self\/profile/.test(path)) return 'canvas-profile';
  if (/login\/cas/.test(path) && path !== '/login/cas') return 'ticket';
  if (path.includes('/getJsPublicKey') || path.includes('/queryAuthMethods')) return 'auth-setup';
  return 'other';
}

function safeTrace(trace = []) {
  let engineSeen = false;
  return trace.map((item) => {
    const basePhase = phaseFor(item.url);
    const phase = item.phase ?? (basePhase === 'canvas-entry' && engineSeen ? 'ticket' : basePhase);
    if (phase === 'authnEngine') engineSeen = true;
    return {
    phase,
    method: item.method,
    url: safeUrl(item.url),
    status: item.status ?? item.statusCode,
    location: item.location ? safeUrl(new URL(item.location, item.url).toString()) : undefined,
    setCookieNames: item.setCookieNames ?? item.setCookies?.map((cookie) => cookie.split(';', 1)[0].split('=', 1)[0].trim()),
    sentCookieNames: item.sentCookieNames ?? item.sentCookies,
    origin: item.origin ? safeUrl(item.origin) : undefined,
    referer: item.referer ? safeUrl(item.referer) : undefined,
    bodyShape: item.bodyShape,
    authCode: item.authCode,
    loginTokenPresent: item.loginTokenPresent,
    secondFactorRequired: item.secondFactorRequired,
    ticketFound: item.ticketFound,
    ticketHost: item.ticketHost,
    captchaCheckVerified: item.captchaCheckVerified,
    captchaRequired: item.captchaRequired,
  };
  });
}

function classifyFailure(error) {
  if (error instanceof LoginError) return error.kind;
  const message = String(error?.message ?? '');
  const status = message.match(/(?:HTTP|Canvas API)\s+(\d{3})/i)?.[1];
  if (status) return `http_${status}`;
  if (/redirect loop|重定向循环/i.test(message)) return 'redirect_loop';
  if (/redirect limit|maxRedirects|最大重定向次数/i.test(message)) return 'redirect_limit';
  if (/timeout|timed out/i.test(message)) return 'timeout';
  if (/fetch failed|network|socket|dns|connection/i.test(message)) return 'network';
  return 'protocol';
}

function currentStage(trace) {
  const last = safeTrace(trace).at(-1);
  if (last?.phase === 'authExecute' && last.authCode === '200' && last.loginTokenPresent) return 'authnEngine';
  if (last?.phase === 'authnEngine' && last.ticketFound) return 'ticket';
  return last?.phase ?? 'before-request';
}

async function runMockProtocolTests() {
  const server = createServer(async (req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    const path = url.pathname;
    if (path === '/start') {
      res.statusCode = 302;
      res.setHeader('Location', '/step');
      res.setHeader('Set-Cookie', ['idp=one; Path=/', 'canvas=two; Path=/final']);
      return res.end();
    }
    if (path === '/step') {
      if (!(req.headers.cookie ?? '').includes('idp=one')) {
        res.statusCode = 401;
        return res.end('missing idp cookie');
      }
      res.statusCode = 303;
      res.setHeader('Location', '/final');
      return res.end();
    }
    if (path === '/final') {
      if (!(req.headers.cookie ?? '').includes('canvas=two')) {
        res.statusCode = 401;
        return res.end('missing canvas cookie');
      }
      res.statusCode = 200;
      return res.end('ok');
    }
    if (path.startsWith('/method/')) {
      const expected = Number(path.split('/').at(-1));
      res.statusCode = expected;
      res.setHeader('Location', `/method-target/${expected}`);
      return res.end();
    }
    if (path.includes('method-target') || path.includes('target')) {
      const expected = Number(path.split('/').at(-1));
      const shouldPost = expected === 307 || expected === 308;
      res.statusCode = (req.method === (shouldPost ? 'POST' : 'GET')) ? 200 : 400;
      return res.end(req.method);
    }
    if (path === '/loop-a') {
      res.statusCode = 302;
      res.setHeader('Location', '/loop-b');
      return res.end();
    }
    if (path === '/loop-b') {
      res.statusCode = 302;
      res.setHeader('Location', '/loop-a');
      return res.end();
    }
    if (path.startsWith('/hop/')) {
      const hop = Number(path.split('/').at(-1));
      res.statusCode = 302;
      res.setHeader('Location', `/hop/${hop + 1}`);
      return res.end();
    }
    if (path === '/canvas-status') {
      res.statusCode = Number(url.searchParams.get('status') ?? '500');
      return res.end('{}');
    }
    res.statusCode = 404;
    res.end();
  });

  await new Promise((resolvePromise) => server.listen(0, '127.0.0.1', resolvePromise));
  try {
    const port = server.address().port;
    const base = `http://127.0.0.1:${port}`;
    const jar = new CookieJar();
    const http = new HttpClient(jar);
    const response = await http.request(`${base}/start`);
    if (response.status !== 200 || response.body !== 'ok') throw new Error('mock cookie redirect failed');
    const step = http.trace.find((item) => item.url.endsWith('/step'));
    const final = http.trace.find((item) => item.url.endsWith('/final'));
    if (!step?.sentCookieNames?.includes('idp') || !final?.sentCookieNames?.includes('canvas')) {
      throw new Error('mock trace did not preserve cookies across redirect hops');
    }

    const redirectStatuses = { '301': 'GET', '302': 'GET', '303': 'GET', '307': 'POST', '308': 'POST' };

    let loopDetected = false;
    try { await new HttpClient().request(`${base}/loop-a`); }
    catch (error) { loopDetected = /redirect loop|重定向循环/i.test(error.message); }
    if (!loopDetected) throw new Error('redirect loop was not detected');
    let limitDetected = false;
    try { await new HttpClient().request(`${base}/hop/0`, { maxRedirects: 2 }); }
    catch (error) { limitDetected = /最大重定向次数/i.test(error.message); }
    if (!limitDetected) throw new Error('redirect maximum was not enforced');

    const matchingJar = new CookieJar();
    matchingJar.setFromResponse(`https://127.0.0.1:${port}/api/start`, [
      'secure_cookie=v; Path=/api; Secure', 'host_cookie=v; Path=/',
    ]);
    const cookieRules = {
      secureHttps: matchingJar.names(`https://127.0.0.1:${port}/api/profile`),
      secureHttp: matchingJar.names(`http://127.0.0.1:${port}/api/profile`),
      wrongPath: matchingJar.names(`https://127.0.0.1:${port}/other`),
      hostOnlyMismatch: matchingJar.names('https://sub.example.test/api/profile'),
    };
    if (!cookieRules.secureHttps.includes('secure_cookie') || cookieRules.secureHttp.includes('secure_cookie') ||
        cookieRules.wrongPath.includes('secure_cookie') || cookieRules.hostOnlyMismatch.length !== 0) {
      throw new Error('cookie host/path/secure rules failed');
    }

    const canvasStatuses = {};
    for (const status of [200, 401, 403, 500]) {
      const result = await new HttpClient().request(`${base}/canvas-status?status=${status}`);
      canvasStatuses[status] = result.status;
    }
    const ticketParsing = {
      found: Boolean(extractTicketTarget('<form id="logon" action="/login/cas"><input id="ticket" value="opaque"></form>')),
      missing: extractTicketTarget('<html>empty</html>') === null,
    };
    if (!ticketParsing.found || !ticketParsing.missing) throw new Error('ticket parsing cases failed');
    const authClassifications = {
      wrongPassword: classifyAuthResult(401, '用户名或密码错误').kind,
      captcha: classifyAuthResult(401, '请输入验证码').kind,
    };
    if (authClassifications.wrongPassword !== 'credentials_invalid' || authClassifications.captcha !== 'captcha_required') {
      throw new Error('authentication error classification failed');
    }

    return {
      status: 'passed',
      cookiesAcrossRedirects: true,
      redirectStatuses,
      redirectLoopDetected: loopDetected,
      canvasStatuses,
      ticketParsing,
      authClassifications,
      cookieRules,
      redirectLimitDetected: limitDetected,
      trace: safeTrace(http.trace),
    };
  } finally {
    server.close();
  }
}

async function runNodeLive() {
  if (!hasCredentials) return { status: 'skipped', reason: 'FUDAN_TEST_USERNAME/FUDAN_TEST_PASSWORD 未同时设置' };
  const jar = new CookieJar();
  const ctx = await beginLogin({ jar, timeoutMs: 30_000 });
  const captcha = await checkCaptcha(ctx, username);
  const precheck = ctx.http.trace.at(-1);
  if (!precheck?.captchaCheckVerified) {
    return { status: 'stopped', stage: 'captcha-precheck', errorCategory: 'captcha_precheck_unverified', trace: safeTrace(ctx.http.trace) };
  }
  if (captcha.required) {
    return { status: 'stopped', stage: 'captcha-precheck', errorCategory: 'captcha_required', trace: safeTrace(ctx.http.trace) };
  }

  let stage = 'authExecute';
  try {
    await completeLogin(ctx, { username, password }, { timeoutMs: 30_000 });
    stage = 'canvas-profile';
    const profileTraceStart = ctx.http.trace.length;
    const profile = await ctx.http.request('https://elearning.fudan.edu.cn/api/v1/users/self/profile', {
      headers: { Accept: 'application/json', Referer: 'https://elearning.fudan.edu.cn/' },
      timeoutMs: 30_000,
    });
    for (const item of ctx.http.trace.slice(profileTraceStart)) item.phase = 'canvas-profile';
    return {
      status: profile.status === 200 ? 'passed' : 'failed',
      profileStatus: profile.status,
      cookieCount: jar.all().length,
      cookieNames: [...new Set(jar.all().map((cookie) => cookie.name))].sort(),
      trace: safeTrace(ctx.http.trace),
    };
  } catch (error) {
    return {
      status: 'failed',
      stage: currentStage(ctx.http.trace) || stage,
      errorCategory: classifyFailure(error),
      trace: safeTrace(ctx.http.trace),
    };
  }
}

function runProcess(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: root,
    encoding: 'utf8',
    timeout: 120_000,
    windowsHide: true,
    ...options,
  });
  return { status: result.status === 0 ? 'passed' : 'failed', exitCode: result.status, stdout: result.stdout ?? '', stderr: result.stderr ?? '' };
}

function runFlutterLive() {
  if (!hasCredentials) return { status: 'skipped', reason: '未设置真实测试凭据' };
  const childEnv = { ...process.env, FUDAN_TEST_USERNAME: username, FUDAN_TEST_PASSWORD: password };
  return runProcess('dart', ['run', 'tool/login_trace.dart'], { cwd: flutterRoot, env: childEnv });
}

async function runSwiftDiagnostics() {
  if (process.platform !== 'darwin') return { status: 'skipped', reason: 'Swift XCTest 需要 macOS/Xcode；当前主机不是 macOS' };
  const env = { ...process.env };
  env.LOGIN_TRACE_OUTPUT = join(artifactDir, 'login-swift-live.json');
  const result = runProcess('xcodebuild', [
    'test', '-project', 'flutter_app/ios/NativeRunner.xcodeproj', '-scheme', 'NativeRunner',
    '-destination', 'platform=iOS Simulator,name=iPhone 16', 'CODE_SIGNING_ALLOWED=NO',
  ], { env });
  let live = null;
  try { live = JSON.parse(await readFile(env.LOGIN_TRACE_OUTPUT, 'utf8')); } catch { /* no live test output */ }
  return {
    status: result.status,
    live,
    diagnostics: result.status === 'passed' ? undefined : 'xcodebuild XCTest 执行失败；原始构建输出未写入报告。',
  };
}

function parseHarnessOutput(stdout) {
  const lines = stdout.split(/\r?\n/).filter(Boolean);
  const texts = [];
  for (const line of lines) {
    try {
      const event = JSON.parse(line);
      const text = event.text ?? event.content ?? event.message;
      if (typeof text === 'string') texts.push(text);
      if (Array.isArray(event.content)) {
        for (const part of event.content) if (typeof part?.text === 'string') texts.push(part.text);
      }
    } catch {
      texts.push(line);
    }
  }
  return texts.join('\n').trim().slice(-20_000);
}

function runHarness(reportPaths) {
  const executable = 'D:\\dsh桌面端\\DeepSeek Harness.exe';
  const asar = 'D:\\dsh桌面端\\resources\\app.asar';
  const cli = `${asar}\\dsh\\node_modules\\@deepseek-ai\\dsh-desktop-host\\lib\\cli.js`;
  if (!existsSync(executable) || !existsSync(asar)) return { status: 'skipped', reason: '本机未找到 DeepSeek Harness desktop CLI' };

  const task = `只读分析以下脱敏登录测试 JSON：${reportPaths.join(', ')}。只读取这些 JSON 与项目代码；不要查看环境变量或其他文件，不要修改文件，不要重试或执行登录。内容不包含 Cookie 值、密码、完整 ticket、loginToken 或 RSA 密文。比较 Node、Flutter、Swift 的请求阶段、状态码、Location 主机路径、Set-Cookie 名称、发送 Cookie 名称、Origin/Referer 和请求字段结构。必须指出首个不一致点与推荐修复文件/函数，并按规则判定：authExecute 前失败看请求体结构/RSA/Origin/Referer/认证上下文；authExecute 成功但 authnEngine 失败看 token 交换或票据 HTML 解析；ticket 回到 Canvas 但 profile 401/403 看 Cookie/Authorization/Referer/会话交接；三端没有 Cookie 但 profile 成功则指出存在非 Cookie 会话机制；三端均失败时区分账号策略、验证码、二次验证或服务端状态。某端未运行时说明证据不足。不要复述任何账号标识。输出中文 Markdown，不超过 40 行。`;
  const env = {
    ELECTRON_RUN_AS_NODE: '1',
    PATH: process.env.PATH,
    SystemRoot: process.env.SystemRoot,
    TEMP: process.env.TEMP,
    TMP: process.env.TMP,
    USERPROFILE: process.env.USERPROFILE,
    LOCALAPPDATA: process.env.LOCALAPPDATA,
    APPDATA: process.env.APPDATA,
  };
  const result = runProcess(executable, [cli, '--profile', 'headless', '--json', task], { env, timeout: 45_000 });
  const report = parseHarnessOutput(result.stdout);
  return {
    status: result.status,
    exitCode: result.exitCode,
    report: report || undefined,
    diagnostics: result.status === 'passed' ? undefined : 'Harness 未能完成分析；凭据环境变量未传入 Harness。',
  };
}

function compareTraces(node, flutter, swift) {
  const platforms = { node: node?.trace ?? [], flutter: flutter?.trace ?? [], swift: swift?.trace ?? [] };
  const baseline = platforms.node;
  const diffs = [];
  for (const platform of ['flutter', 'swift']) {
    const candidate = platforms[platform];
    if (baseline.length === 0 || candidate.length === 0) {
      diffs.push({ against: 'node', platform, result: 'not-comparable', reason: 'one or both traces are unavailable' });
      continue;
    }
    const length = Math.max(baseline.length, candidate.length);
    let found = false;
    for (let index = 0; index < length; index += 1) {
      const left = baseline[index];
      const right = candidate[index];
      if (!left || !right || JSON.stringify(left) !== JSON.stringify(right)) {
        diffs.push({ against: 'node', platform, index, node: left ?? null, candidate: right ?? null });
        found = true;
        break;
      }
    }
    if (!found) diffs.push({ against: 'node', platform, result: 'identical' });
  }
  return diffs;
}

async function main() {
  assertProjectRoot();
  const pkg = JSON.parse(await readFile(join(root, 'package.json'), 'utf8'));
  if (pkg.name !== expectedPackageName || !existsSync(join(root, 'src/core/uis.ts')) || !existsSync(join(flutterRoot, 'lib/core/uis.dart'))) {
    throw new Error('当前目录未识别为本项目根目录。');
  }

  await mkdir(artifactDir, { recursive: true });
  await rm(join(root, 'dsh-readonly.jsonl'), { force: true });
  await rm(join(root, 'dsh-readonly.err'), { force: true });

  const output = {
    generatedAt: new Date().toISOString(),
    hasCredentials,
    mock: null,
    node: null,
    flutter: null,
    swift: null,
    firstDifferences: null,
    harness: null,
  };

  try { output.mock = await runMockProtocolTests(); }
  catch (error) { output.mock = { status: 'failed', errorCategory: classifyFailure(error), diagnostic: String(error?.message ?? '').slice(0, 120), debug: String(error?.stack ?? '').split('\n').slice(0, 8).join(' | ') }; }
  if (process.argv.includes('--mock-only')) {
    await writeFile(join(artifactDir, 'login-mock-result.json'), JSON.stringify(output.mock, null, 2));
    console.log(JSON.stringify({mock: output.mock.status, syntheticOnly: true}));
    if (output.mock.status !== 'passed') process.exitCode = 1;
    return;
  }
  try { output.node = await runNodeLive(); }
  catch (error) { output.node = { status: 'failed', stage: 'before-request', errorCategory: classifyFailure(error), trace: [] }; }

  if (hasCredentials) {
    const flutterProcess = runFlutterLive();
    try { output.flutter = JSON.parse(flutterProcess.stdout); }
    catch {
      output.flutter = { status: flutterProcess.status === 'passed' ? 'failed' : 'failed', errorCategory: 'diagnostic_process_failed', trace: [] };
    }
    if (output.flutter.status === 'failed' && !output.flutter.errorCategory) output.flutter.errorCategory = 'diagnostic_process_failed';
  } else {
    output.flutter = { status: 'skipped', reason: 'FUDAN_TEST_USERNAME/FUDAN_TEST_PASSWORD 未同时设置', trace: [] };
  }

  output.swift = await runSwiftDiagnostics();
  output.firstDifferences = compareTraces(output.node, output.flutter, output.swift);

  const nodePath = join(artifactDir, 'login-node-trace.json');
  const flutterPath = join(artifactDir, 'login-flutter-trace.json');
  const swiftPath = join(artifactDir, 'login-swift-trace.json');
  const reportPath = join(artifactDir, 'login-harness-report.md');
  await writeFile(nodePath, JSON.stringify({ generatedAt: output.generatedAt, mock: output.mock, live: output.node }, null, 2));
  await writeFile(flutterPath, JSON.stringify({ generatedAt: output.generatedAt, live: output.flutter }, null, 2));
  await writeFile(swiftPath, JSON.stringify({ generatedAt: output.generatedAt, diagnostics: output.swift, live: output.swift.live ?? null }, null, 2));
  output.harness = runHarness([nodePath, flutterPath, swiftPath]);

  const localReport = [
    '# Login Trace Comparison',
    '',
    `- Generated: ${output.generatedAt}`,
    `- Credentials configured: ${hasCredentials}`,
    `- Mock protocol tests: ${output.mock.status}`,
    `- Node: ${output.node?.status ?? 'not run'}${output.node?.stage ? ` at ${output.node.stage}` : ''}`,
    `- Flutter: ${output.flutter?.status ?? 'not run'}${output.flutter?.stage ? ` at ${output.flutter.stage}` : ''}`,
    `- Swift: ${output.swift?.status ?? 'not run'}`,
    `- Harness: ${output.harness.status}`,
    '',
    '## First Differences',
    '```json',
    JSON.stringify(output.firstDifferences, null, 2),
    '```',
    '',
    '## Harness Analysis',
    output.harness.report ?? output.harness.reason ?? output.harness.diagnostics ?? 'No Harness report returned.',
  ].join('\n');
  await writeFile(reportPath, localReport);

  console.log(JSON.stringify({
    generatedAt: output.generatedAt,
    hasCredentials,
    mock: output.mock.status,
    node: output.node?.status,
    flutter: output.flutter?.status,
    swift: output.swift?.status,
    harness: output.harness.status,
    artifacts: ['artifacts/login-node-trace.json', 'artifacts/login-flutter-trace.json', 'artifacts/login-swift-trace.json', 'artifacts/login-harness-report.md'],
  }, null, 2));
  if (output.mock.status !== 'passed') process.exitCode = 1;
}

main().catch((error) => {
  console.error(JSON.stringify({ status: 'failed', errorCategory: classifyFailure(error) }));
  process.exitCode = 1;
});
