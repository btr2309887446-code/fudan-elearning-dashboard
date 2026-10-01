/**
 * Errors that the UI can translate into actionable Chinese messages.
 *
 * The Fudan identity provider answers almost everything with HTTP 200 and a
 * human-readable `message` field, so we classify on those strings instead of
 * on status codes.
 */

export type LoginFailureKind =
  | 'credentials_invalid'
  | 'captcha_required'
  | 'two_factor_required'
  | 'account_locked'
  | 'maintenance'
  | 'network'
  | 'protocol'
  | 'session_expired';

export class LoginError extends Error {
  readonly kind: LoginFailureKind;
  readonly detail?: string;

  constructor(kind: LoginFailureKind, message: string, detail?: string) {
    super(message);
    this.name = 'LoginError';
    this.kind = kind;
    this.detail = detail;
  }
}

export class CanvasError extends Error {
  readonly status: number;
  readonly url: string;
  readonly body: string;

  constructor(status: number, url: string, body: string) {
    super(`Canvas API ${status} ${url}`);
    this.name = 'CanvasError';
    this.status = status;
    this.url = url;
    this.body = body.slice(0, 500);
  }

  /** The session died and the user has to sign in again. */
  get isAuthFailure(): boolean {
    return this.status === 401 || this.status === 403;
  }
}

/** Turn a Canvas error body into something readable. */
export function describeCanvasError(err: unknown): string {
  if (err instanceof CanvasError) {
    if (err.isAuthFailure) return '登录状态已失效，请重新登录。';
    try {
      const parsed = JSON.parse(err.body) as { errors?: { message?: string }[]; message?: string };
      const msg = parsed.errors?.[0]?.message ?? parsed.message;
      if (msg) return `Canvas 返回 ${err.status}：${msg}`;
    } catch {
      /* body was not JSON */
    }
    return `Canvas 返回 ${err.status}。`;
  }
  if (err instanceof Error) return err.message;
  return String(err);
}
