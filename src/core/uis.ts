/**
 * Fudan unified identity authentication (id.fudan.edu.cn) -> Canvas session.
 *
 * The chain below was read off the provider's own front-end bundle
 * (id.fudan.edu.cn/ac/js/chunk-71ba4ca7) and verified live against the real
 * endpoints, so the request shapes match what the official page sends:
 *
 *   1. GET  elearning.fudan.edu.cn/login/cas
 *        -> 302 id.fudan.edu.cn/idp/authCenter/authenticate?service=...
 *        -> 302 id.fudan.edu.cn/ac/#/index?lck=...&entityId=...&theme=...
 *   2. POST id.fudan.edu.cn/idp/authn/getJsPublicKey   {}          -> { data: <SPKI base64> }
 *   3. POST id.fudan.edu.cn/idp/authn/queryAuthMethods {lck,entityId}
 *        -> { data:[{moduleCode,moduleCodes,authChainCode,...}], requestType, second, code }
 *   4. POST id.fudan.edu.cn/idp/authn/verifyCodeIsNeed
 *        {lang,loginName,chainCode,authModuleCode} -> { pic, result }   (result=true => captcha)
 *   5. POST id.fudan.edu.cn/idp/authn/authExecute
 *        { authModuleCode, authChainCode, entityId, requestType, lck,
 *          authPara:{ loginName, password:<RSA/PKCS#1 v1.5 base64>, verifyCode } }
 *        -> { code:200, loginToken } | { code:40xx, message }
 *   6. POST id.fudan.edu.cn/idp/authCenter/authnEngine?locale=zh-CN
 *        form-urlencoded { loginToken } -> HTML holding #logon[action] and #ticket[value]
 *   7. GET  <logon action>?ticket=...  -> Canvas session cookie
 *
 * Step 4 exists purely as a safety net: the provider locks accounts after a few
 * bad attempts, so we ask whether a captcha is pending BEFORE spending one.
 */

import { constants, publicEncrypt } from 'node:crypto';
import { CookieJar } from './cookies.ts';
import { HttpClient } from './http.ts';
import { LoginError } from './errors.ts';

export const CANVAS_BASE = 'https://elearning.fudan.edu.cn';
export const CANVAS_HOST = 'elearning.fudan.edu.cn';
export const ID_HOST = 'id.fudan.edu.cn';
export const ID_BASE = `https://${ID_HOST}`;

const LOGIN_ENTRY = `${CANVAS_BASE}/login/cas`;
const LOCALE = 'zh-CN';
const LANG = 'zh_CN';

export interface LoginResult {
  jar: CookieJar;
  finalUrl: string;
  elapsedMs: number;
  trace: string[];
}

/** Everything discovered before a password is ever sent. */
export interface LoginContext {
  jar: CookieJar;
  http: HttpClient;
  spaUrl: string;
  lck: string;
  entityId: string;
  chainCode: string;
  authModuleCode: string;
  requestType: string;
  publicKey: string;
}

export interface CaptchaState {
  required: boolean;
  /** data: URL of the captcha image, when one is pending. */
  image?: string;
}

export interface Credentials {
  username: string;
  password: string;
  /** Only needed when CaptchaState.required is true. */
  captchaCode?: string;
}

// ---------------------------------------------------------------------------
// HTML helpers
// ---------------------------------------------------------------------------

const ENTITIES: Record<string, string> = {
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&apos;': "'",
  '&nbsp;': ' ',
};

export function decodeEntities(input: string): string {
  return input
    .replace(/&(amp|lt|gt|quot|#39|apos|nbsp);/g, (m) => ENTITIES[m] ?? m)
    .replace(/&#(\d+);/g, (_, d: string) => String.fromCodePoint(Number(d)));
}

/** Find the first opening tag carrying `attr="value"`. */
export function findTagWithAttr(html: string, attr: string, value: string): string | null {
  const tagRe = /<[a-zA-Z][\w:-]*\b[^>]*>/g;
  let m: RegExpExecArray | null;
  while ((m = tagRe.exec(html)) !== null) {
    const tag = m[0];
    const a = new RegExp(`\\b${attr}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`, 'i').exec(tag);
    if (!a) continue;
    if ((a[1] ?? a[2] ?? a[3] ?? '') === value) return tag;
  }
  return null;
}

export function getAttr(tag: string, attr: string): string | null {
  const m = new RegExp(`\\b${attr}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`, 'i').exec(tag);
  if (!m) return null;
  return decodeEntities(m[1] ?? m[2] ?? m[3] ?? '');
}

/** Pull `#logon[action]` and `#ticket[value]` out of the authnEngine response. */
export function extractTicketTarget(html: string): { action: string; ticket: string } | null {
  const logon = findTagWithAttr(html, 'id', 'logon');
  const ticket = findTagWithAttr(html, 'id', 'ticket');
  if (!logon || !ticket) return null;
  const action = getAttr(logon, 'action');
  const value = getAttr(ticket, 'value');
  if (!action || !value) return null;
  return { action, ticket: value };
}

// ---------------------------------------------------------------------------
// RSA
// ---------------------------------------------------------------------------

export function toSpkiPem(base64Key: string): string {
  const body = base64Key.replace(/\s+/g, '');
  const lines = body.match(/.{1,64}/g) ?? [body];
  return `-----BEGIN PUBLIC KEY-----\n${lines.join('\n')}\n-----END PUBLIC KEY-----\n`;
}

/** RSA/ECB/PKCS#1 v1.5, matching jsencrypt's default in the official page. */
export function encryptPassword(password: string, spkiBase64: string): string {
  try {
    return publicEncrypt(
      { key: toSpkiPem(spkiBase64), padding: constants.RSA_PKCS1_PADDING },
      Buffer.from(password, 'utf8')
    ).toString('base64');
  } catch (err) {
    throw new LoginError('protocol', `密码加密失败：${(err as Error).message}`);
  }
}

// ---------------------------------------------------------------------------
// Step helpers
// ---------------------------------------------------------------------------

function parseIdpSpaUrl(url: string): { lck: string; entityId: string } | null {
  const hash = new URL(url).hash.replace(/^#/, '');
  if (!hash) return null;
  try {
    const parsed = new URL(ID_BASE + (hash.startsWith('/') ? hash : '/' + hash));
    const lck = parsed.searchParams.get('lck');
    const entityId = parsed.searchParams.get('entityId');
    if (!lck || !entityId) return null;
    return { lck, entityId };
  } catch {
    return null;
  }
}

export function classifyAuthResult(code: unknown, message: string | undefined): LoginError {
  const msg = (message ?? '').trim();
  if (msg.includes('用户名或密码错误') || msg.includes('密码有误')) {
    return new LoginError('credentials_invalid', '学号或密码不正确。', msg);
  }
  if (msg.includes('验证码')) {
    return new LoginError(
      'captcha_required',
      '统一身份认证要求输入验证码。请按提示填写验证码后重试。',
      msg
    );
  }
  if (msg.includes('锁定') || msg.includes('冻结')) {
    return new LoginError('account_locked', '账号已被锁定，请等待自动解锁或联系信息办。', msg);
  }
  if (msg.includes('维护')) {
    return new LoginError('maintenance', '统一身份认证正在维护，请稍后再试。', msg);
  }
  return new LoginError(
    'protocol',
    `统一身份认证返回了未预期的结果${code !== undefined ? `（code=${String(code)}）` : ''}。`,
    msg || '(无 message 字段)'
  );
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/** Steps 1-3: reach the IdP, fetch its public key, learn the auth chain. */
export async function beginLogin(options: { jar?: CookieJar; timeoutMs?: number } = {}): Promise<LoginContext> {
  const timeoutMs = options.timeoutMs ?? 20_000;
  const jar = options.jar ?? new CookieJar();
  jar.deleteByName('CASTGC');
  const http = new HttpClient(jar);

  const entry = await http.request(LOGIN_ENTRY, { timeoutMs });
  if (!entry.url.includes(ID_HOST)) {
    throw new LoginError(
      'protocol',
      entry.url.includes(CANVAS_HOST)
        ? '当前会话似乎已经登录，无需重新认证。'
        : `未跳转到统一身份认证（落点：${entry.url}）。`,
      entry.url
    );
  }

  const idp = parseIdpSpaUrl(entry.url);
  if (!idp) {
    throw new LoginError('protocol', '未能从统一身份认证页面解析出登录参数（lck / entityId）。', `落点: ${entry.url}`);
  }

  const pkRes = await http.postJson(`${ID_BASE}/idp/authn/getJsPublicKey`, {}, {
    timeoutMs,
    headers: { Origin: ID_BASE, Referer: entry.url },
  });
  let publicKey: string | null = null;
  try {
    publicKey = (JSON.parse(pkRes.body) as { data?: string }).data ?? null;
  } catch {
    /* handled below */
  }
  if (!publicKey) {
    throw new LoginError('protocol', '无法获取统一身份认证的加密公钥。', pkRes.body.slice(0, 300));
  }

  const qRes = await http.postJson(
    `${ID_BASE}/idp/authn/queryAuthMethods`,
    { lck: idp.lck, entityId: idp.entityId },
    { timeoutMs, headers: { Origin: ID_BASE, Referer: entry.url } }
  );

  let payload: {
    data?: { moduleCode?: string; moduleCodes?: string[]; authChainCode?: string; chainName?: string }[];
    requestType?: string;
    second?: boolean;
    code?: unknown;
    message?: string;
  };
  try {
    payload = JSON.parse(qRes.body);
  } catch {
    throw new LoginError('protocol', '统一身份认证返回了无法解析的认证方式列表。', qRes.body.slice(0, 300));
  }

  const methods = payload.data ?? [];
  if (methods.length === 0) {
    throw classifyAuthResult(payload.code, payload.message);
  }
  if (payload.second === true) {
    throw new LoginError('two_factor_required', '该账号启用了二次验证，本应用暂不支持。请先在浏览器完成一次登录。');
  }

  const pwdMethod = methods.find((m) => (m.moduleCodes ?? [m.moduleCode]).includes('userAndPwd'));
  if (!pwdMethod?.authChainCode) {
    const codes = methods.map((m) => m.moduleCode).join(', ') || '(空)';
    throw new LoginError('protocol', `该账号没有开放「用户名密码」认证方式（可用方式：${codes}）。`);
  }

  return {
    jar,
    http,
    spaUrl: entry.url,
    lck: idp.lck,
    entityId: idp.entityId,
    chainCode: pwdMethod.authChainCode,
    // The official page uses moduleCodes[0] of the selected method.
    authModuleCode: pwdMethod.moduleCodes?.[0] ?? pwdMethod.moduleCode ?? 'userAndPwd',
    requestType: payload.requestType ?? 'chain_type',
    publicKey,
  };
}

/**
 * Step 4: ask whether a captcha will be demanded.
 * Purely defensive - it never throws, so a failure here cannot block login.
 */
export async function checkCaptcha(ctx: LoginContext, username: string): Promise<CaptchaState> {
  try {
    const res = await ctx.http.postJson(
      `${ID_BASE}/idp/authn/verifyCodeIsNeed`,
      {
        lang: LANG,
        loginName: username,
        chainCode: ctx.chainCode,
        authModuleCode: ctx.authModuleCode,
      },
      { timeoutMs: 15_000, headers: { Origin: ID_BASE, Referer: ctx.spaUrl } }
    );
    const parsed = JSON.parse(res.body) as { result?: boolean; pic?: string };
    return { required: parsed.result === true, image: parsed.pic };
  } catch {
    return { required: false };
  }
}

/** Steps 5-7: spend one authentication attempt and land back on Canvas. */
export async function completeLogin(
  ctx: LoginContext,
  credentials: Credentials,
  options: { timeoutMs?: number } = {}
): Promise<LoginResult> {
  const timeoutMs = options.timeoutMs ?? 20_000;
  const t0 = Date.now();

  const execRes = await ctx.http.postJson(
    `${ID_BASE}/idp/authn/authExecute`,
    {
      authModuleCode: ctx.authModuleCode,
      authChainCode: ctx.chainCode,
      entityId: ctx.entityId,
      requestType: ctx.requestType,
      lck: ctx.lck,
      authPara: {
        loginName: credentials.username,
        password: encryptPassword(credentials.password, ctx.publicKey),
        verifyCode: credentials.captchaCode ?? '',
      },
    },
    { timeoutMs, headers: { Origin: ID_BASE, Referer: ctx.spaUrl } }
  );

  let body: { code?: unknown; message?: string; loginToken?: string | null; second?: boolean; data?: string };
  try {
    body = JSON.parse(execRes.body);
  } catch {
    throw new LoginError('protocol', '统一身份认证返回了无法解析的登录结果。', execRes.body.slice(0, 300));
  }

  const codeStr = String(body.code);
  if (body.second === true) {
    throw new LoginError('two_factor_required', '该账号需要二次验证，本应用暂不支持。');
  }
  if (codeStr !== '200' || !body.loginToken) {
    // 4340 means "go here instead" (policy / binding page).
    if (codeStr === '4340' && body.data) {
      throw new LoginError('protocol', '账号需要在统一身份认证页面完成额外设置，请先用浏览器登录一次。', body.data);
    }
    throw classifyAuthResult(body.code, body.message);
  }

  // Exchange the token for a CAS service ticket, then redeem it at Canvas.
  const engineRes = await ctx.http.postForm(
    `${ID_BASE}/idp/authCenter/authnEngine?locale=${LOCALE}`,
    { loginToken: body.loginToken },
    { timeoutMs, headers: { Referer: ctx.spaUrl } }
  );
  const target = extractTicketTarget(engineRes.body);
  if (!target) {
    throw new LoginError(
      'protocol',
      '登录成功，但从认证服务器返回的页面里找不到服务票据。',
      engineRes.body.replace(/\s+/g, ' ').slice(0, 400)
    );
  }

  const ticketUrl = new URL(target.action);
  ticketUrl.searchParams.set('ticket', target.ticket);
  const final = await ctx.http.request(ticketUrl.toString(), { timeoutMs });

  if (!final.url.includes(CANVAS_HOST)) {
    throw new LoginError('protocol', `票据校验后未回到 eLearning（落点：${final.url}）。`);
  }

  return {
    jar: ctx.jar,
    finalUrl: final.url,
    elapsedMs: Date.now() - t0,
    trace: ctx.http.trace.map((t) => `${t.method} ${t.url} [${t.status}]${t.location ? ' -> ' + t.location : ''}`),
  };
}

/** Convenience wrapper: begin -> (optional captcha pre-check) -> complete. */
export async function loginFudanUis(
  options: Credentials & { jar?: CookieJar; timeoutMs?: number; skipCaptchaCheck?: boolean }
): Promise<LoginResult> {
  if (!options.username || !options.password) {
    throw new LoginError('protocol', '学号和密码不能为空。');
  }
  const ctx = await beginLogin({ jar: options.jar, timeoutMs: options.timeoutMs });

  if (!options.skipCaptchaCheck && options.captchaCode === undefined) {
    const captcha = await checkCaptcha(ctx, options.username);
    if (captcha.required) {
      // Refuse to spend an attempt we know will fail.
      throw new LoginError(
        'captcha_required',
        '统一身份认证要求输入验证码，已中止以避免浪费登录次数。请重新登录并在提示时填写验证码。',
        captcha.image
      );
    }
  }

  return completeLogin(ctx, options, { timeoutMs: options.timeoutMs });
}
