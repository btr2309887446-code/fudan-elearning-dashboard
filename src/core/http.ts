/**
 * Small fetch wrapper with a cookie jar and explicit redirect handling.
 *
 * Redirects are walked by hand because the UIS login chain sets cookies at
 * several hops (elearning -> idp -> SPA) and we must capture every one of them
 * in the right order.
 */

import { CookieJar } from './cookies.ts';

export const DEFAULT_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

export interface HttpResponse {
  status: number;
  url: string;
  headers: Headers;
  body: string;
}

export interface RequestOptions {
  method?: string;
  headers?: Record<string, string>;
  body?: string;
  /** follow 3xx responses (default true) */
  follow?: boolean;
  maxRedirects?: number;
  timeoutMs?: number;
  /** treat 4xx/5xx as a normal return value instead of throwing (default true) */
  allowErrorStatus?: boolean;
}

export interface HttpTrace {
  method: string;
  url: string;
  status: number;
  location?: string;
  setCookie?: string[];
}

const REDIRECT_STATUS = new Set([301, 302, 303, 307, 308]);

export class HttpClient {
  readonly jar: CookieJar;
  readonly userAgent: string;
  readonly trace: HttpTrace[] = [];

  constructor(jar: CookieJar = new CookieJar(), userAgent: string = DEFAULT_UA) {
    this.jar = jar;
    this.userAgent = userAgent;
  }

  /** One request, no redirect following. Cookies are stored but not yet sent on this hop. */
  async raw(url: string, opts: RequestOptions = {}): Promise<HttpResponse> {
    const method = (opts.method ?? 'GET').toUpperCase();
    const headers: Record<string, string> = {
      'User-Agent': this.userAgent,
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      ...(opts.headers ?? {}),
    };
    const cookie = this.jar.getCookieHeader(url);
    if (cookie) headers['Cookie'] = cookie;
    if (opts.body !== undefined && !Object.keys(headers).some((h) => h.toLowerCase() === 'content-length')) {
      headers['Content-Length'] = String(Buffer.byteLength(opts.body));
    }

    const timeout = opts.timeoutMs ?? 20_000;
    let res: Response;
    try {
      res = await fetch(url, {
        method,
        headers,
        body: opts.body,
        redirect: 'manual',
        signal: AbortSignal.timeout(timeout),
      });
    } catch (err) {
      const cause = (err as { cause?: Error }).cause;
      const why = cause?.message ?? (err as Error).message;
      throw new Error(`请求失败 ${method} ${url}：${why}`);
    }

    const setCookie = res.headers.getSetCookie();
    if (setCookie.length) this.jar.setFromResponse(url, setCookie);

    const body = await res.text();
    this.trace.push({
      method,
      url,
      status: res.status,
      location: res.headers.get('location') ?? undefined,
      setCookie: setCookie.length ? setCookie.map((c) => c.split(';')[0]) : undefined,
    });

    return { status: res.status, url, headers: res.headers, body };
  }

  /** Request plus redirect walking. 303 (and 301/302 after POST) switch to GET. */
  async request(url: string, opts: RequestOptions = {}): Promise<HttpResponse> {
    const maxRedirects = opts.maxRedirects ?? 12;
    let currentUrl = url;
    let method = (opts.method ?? 'GET').toUpperCase();
    let body = opts.body;
    let res = await this.raw(currentUrl, { ...opts, method, body });

    let hops = 0;
    while (REDIRECT_STATUS.has(res.status) && (opts.follow ?? true) && hops < maxRedirects) {
      const location = res.headers.get('location');
      if (!location) break;
      const next = new URL(location, currentUrl).toString();

      // Preserve the method only for 307/308; everything else degrades to GET
      // and drops the body, matching browser behaviour.
      if (res.status !== 307 && res.status !== 308) {
        if (method !== 'GET' && method !== 'HEAD') {
          method = 'GET';
          body = undefined;
        }
      }

      currentUrl = next;
      hops += 1;
      res = await this.raw(currentUrl, { ...opts, method, body });
    }
    return res;
  }

  /** Convenience: POST a JSON body. */
  async postJson(
    url: string,
    payload: unknown,
    opts: RequestOptions = {}
  ): Promise<HttpResponse> {
    return this.request(url, {
      ...opts,
      method: 'POST',
      body: JSON.stringify(payload),
      headers: {
        'Content-Type': 'application/json;charset=UTF-8',
        Accept: 'application/json, text/plain, */*',
        ...(opts.headers ?? {}),
      },
    });
  }

  /** Convenience: POST an application/x-www-form-urlencoded body. */
  async postForm(
    url: string,
    fields: Record<string, string>,
    opts: RequestOptions = {}
  ): Promise<HttpResponse> {
    const body = new URLSearchParams(fields).toString();
    const origin = new URL(url).origin;
    return this.request(url, {
      ...opts,
      method: 'POST',
      body,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Origin: origin,
        Referer: origin + '/',
        ...(opts.headers ?? {}),
      },
    });
  }
}
