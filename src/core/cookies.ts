/**
 * Minimal RFC-6265-ish cookie jar.
 *
 * Deliberately self-contained: the Fudan UIS -> Canvas login chain spans two
 * registrable domains (id.fudan.edu.cn and elearning.fudan.edu.cn), so we need
 * full control over which cookie is sent where.
 */

export interface Cookie {
  name: string;
  value: string;
  /** lowercase host, no leading dot */
  domain: string;
  path: string;
  /** epoch ms; undefined means a session cookie */
  expires?: number;
  secure: boolean;
  httpOnly: boolean;
  /** true when the cookie came from Set-Cookie without a Domain attribute */
  hostOnly: boolean;
}

function normaliseDomain(raw: string): string {
  return raw.trim().toLowerCase().replace(/^\./, '');
}

function defaultPath(requestPath: string): string {
  if (!requestPath.startsWith('/')) return '/';
  const i = requestPath.lastIndexOf('/');
  return i <= 0 ? '/' : requestPath.slice(0, i);
}

function domainMatches(cookie: Cookie, host: string): boolean {
  const h = host.toLowerCase();
  if (cookie.hostOnly) return h === cookie.domain;
  return h === cookie.domain || h.endsWith('.' + cookie.domain);
}

function pathMatches(cookiePath: string, requestPath: string): boolean {
  if (requestPath === cookiePath) return true;
  if (!requestPath.startsWith(cookiePath)) return false;
  if (cookiePath.endsWith('/')) return true;
  return requestPath[cookiePath.length] === '/';
}

export class CookieJar {
  private cookies = new Map<string, Cookie>();

  private static key(c: Pick<Cookie, 'domain' | 'path' | 'name'>): string {
    return `${c.domain}\t${c.path}\t${c.name}`;
  }

  /** Parse and store every Set-Cookie header from one response. */
  setFromResponse(url: string, setCookieHeaders: readonly string[]): void {
    const u = new URL(url);
    for (const header of setCookieHeaders) this.setOne(u, header);
  }

  private setOne(u: URL, header: string): void {
    const segments = header.split(';');
    const first = segments.shift();
    if (!first) return;
    const eq = first.indexOf('=');
    if (eq < 0) return;

    const name = first.slice(0, eq).trim();
    const value = first.slice(eq + 1).trim();
    if (!name) return;

    let domain = normaliseDomain(u.hostname);
    let hostOnly = true;
    let path = defaultPath(u.pathname);
    let expires: number | undefined;
    let secure = false;
    let httpOnly = false;

    for (const seg of segments) {
      const i = seg.indexOf('=');
      const attr = (i < 0 ? seg : seg.slice(0, i)).trim().toLowerCase();
      const val = i < 0 ? '' : seg.slice(i + 1).trim();
      switch (attr) {
        case 'domain':
          if (val) {
            domain = normaliseDomain(val);
            hostOnly = false;
          }
          break;
        case 'path':
          if (val.startsWith('/')) path = val;
          break;
        case 'max-age': {
          const secs = Number.parseInt(val, 10);
          if (Number.isFinite(secs)) expires = Date.now() + secs * 1000;
          break;
        }
        case 'expires': {
          const t = Date.parse(val);
          if (Number.isFinite(t)) expires = t;
          break;
        }
        case 'secure':
          secure = true;
          break;
        case 'httponly':
          httpOnly = true;
          break;
        default:
          break;
      }
    }

    const cookie: Cookie = { name, value, domain, path, expires, secure, httpOnly, hostOnly };
    const key = CookieJar.key(cookie);

    // A cookie already past its expiry deletes the stored one.
    if (expires !== undefined && expires <= Date.now()) {
      this.cookies.delete(key);
      return;
    }
    this.cookies.set(key, cookie);
  }

  /** Build the Cookie request header for a URL, or undefined when empty. */
  getCookieHeader(url: string): string | undefined {
    const u = new URL(url);
    const now = Date.now();
    const matches: Cookie[] = [];

    for (const [key, c] of this.cookies) {
      if (c.expires !== undefined && c.expires <= now) {
        this.cookies.delete(key);
        continue;
      }
      if (c.secure && u.protocol !== 'https:') continue;
      if (!domainMatches(c, u.hostname)) continue;
      if (!pathMatches(c.path, u.pathname || '/')) continue;
      matches.push(c);
    }
    if (matches.length === 0) return undefined;

    // Longer paths first, per RFC 6265 section 5.4.
    matches.sort((a, b) => b.path.length - a.path.length);
    return matches.map((c) => `${c.name}=${c.value}`).join('; ');
  }

  names(url: string): string[] {
    const header = this.getCookieHeader(url);
    if (!header) return [];
    return header.split('; ').map((p) => p.slice(0, p.indexOf('=')));
  }

  has(name: string): boolean {
    for (const c of this.cookies.values()) if (c.name === name) return true;
    return false;
  }

  deleteByName(name: string): void {
    for (const [key, c] of this.cookies) if (c.name === name) this.cookies.delete(key);
  }

  clear(): void {
    this.cookies.clear();
  }

  all(): Cookie[] {
    return [...this.cookies.values()];
  }

  toJSON(): Cookie[] {
    return this.all();
  }

  static fromJSON(data: unknown): CookieJar {
    const jar = new CookieJar();
    if (Array.isArray(data)) {
      for (const raw of data) {
        const c = raw as Cookie;
        if (c && typeof c.name === 'string' && typeof c.domain === 'string') {
          jar.cookies.set(CookieJar.key(c), c);
        }
      }
    }
    return jar;
  }
}
