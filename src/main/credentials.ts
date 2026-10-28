import { existsSync, mkdirSync, readFileSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { randomUUID } from 'node:crypto';
import { CookieJar } from '../core/cookies.ts';
import { loadSession as loadLegacySession, type SessionFile } from '../core/session.ts';

export interface SecretCodec {
  available(): boolean;
  encrypt(value: string): string;
  decrypt(value: string): string;
}

/** Desktop-only adapter. CLI session files never depend on Electron. */
export class CredentialStore {
  private values: Record<string, string> = {};
  private loaded = false;
  private readable = true;
  private durable: Record<string, string> = {};
  private revoked = new Set<string>();
  warning?: string;
  private path: string;
  private codec: SecretCodec;
  constructor(path: string, codec: SecretCodec) { this.path = path; this.codec = codec; }
  private load() {
    if (this.loaded) return;
    this.loaded = true;
    if (existsSync(`${this.path}.revoked`)) {
      const keys: unknown = JSON.parse(readFileSync(`${this.path}.revoked`, 'utf8'));
      if (!Array.isArray(keys) || keys.some(k => typeof k !== 'string')) throw Error('凭据注销记录损坏，请重新登录');
      this.revoked = new Set(keys);
    }
    if (!existsSync(this.path)) return;
    try {
      if (!this.codec.available()) throw Error('locked');
      const envelope = JSON.parse(readFileSync(this.path, 'utf8'));
      if (envelope.version !== 1 || typeof envelope.encrypted !== 'string') throw Error('format');
      const value: unknown = JSON.parse(this.codec.decrypt(envelope.encrypted));
      if (!value || typeof value !== 'object' || Array.isArray(value) || Object.values(value).some(v => typeof v !== 'string')) throw Error('format');
      this.values = value as Record<string, string>;
      for (const key of this.revoked) delete this.values[key];
      this.durable = { ...this.values };
    } catch {
      this.readable = false;
      this.warning = '无法解锁本机保存的凭据，原文件已保留；本次新凭据仅在程序运行期间使用。';
    }
  }
  get(key: string): string | undefined { this.load(); return this.values[key]; }
  persisted(key: string): boolean { this.load(); return this.readable && this.codec.available() && this.durable[key] === this.values[key]; }
  private saveRevocations() {
    mkdirSync(dirname(this.path), { recursive: true });
    const path = `${this.path}.revoked`, temporary = `${path}.${randomUUID()}.tmp`;
    try { writeFileSync(temporary, JSON.stringify([...this.revoked]), { encoding: 'utf8', flush: true }); renameSync(temporary,path); }
    finally { if(existsSync(temporary)) unlinkSync(temporary); }
  }
  set(key: string, value: string | undefined): boolean {
    this.load();
    const next = { ...this.values };
    if (value === undefined) delete next[key]; else next[key] = value;
    if (value === undefined) {
      this.revoked.add(key);
      this.saveRevocations();
    }
    if (!this.codec.available() || !this.readable) {
      this.values = next;
      this.warning ??= '系统安全存储暂不可用，凭据仅保留到本次退出，重启后需要重新填写。';
      return false;
    }
    const plain = JSON.stringify(next), encrypted = this.codec.encrypt(plain);
    if (this.codec.decrypt(encrypted) !== plain) throw Error('凭据加密验证失败，原数据已保留');
    mkdirSync(dirname(this.path), { recursive: true });
    const temporary = `${this.path}.${randomUUID()}.tmp`;
    try {
      writeFileSync(temporary, JSON.stringify({ version: 1, encrypted }), { encoding: 'utf8', flush: true });
      const check = JSON.parse(readFileSync(temporary, 'utf8'));
      if (this.codec.decrypt(check.encrypted) !== plain) throw Error('凭据保存验证失败');
      renameSync(temporary, this.path);
      const saved = JSON.parse(readFileSync(this.path, 'utf8'));
      if (this.codec.decrypt(saved.encrypted) !== plain) throw Error('凭据回读失败，旧数据尚未清理');
      this.values = next; this.durable = { ...next }; this.warning = undefined;
      if (value !== undefined && this.revoked.delete(key)) this.saveRevocations();
      return true;
    } finally { if (existsSync(temporary)) unlinkSync(temporary); }
  }
  /** Import is idempotent, including after interruption before plaintext cleanup. */
  import(key: string, value: string): boolean {
    const current = this.get(key);
    return this.set(key, current ?? value);
  }
  loadSession(legacyPath: string): { jar: CookieJar; file: SessionFile } | null {
    const cached = this.get('session');
    if (cached) {
      const file = JSON.parse(cached) as SessionFile;
      if (this.persisted('session')) this.clearLegacySession(legacyPath);
      return { file, jar: CookieJar.fromJSON(file.cookies) };
    }
    if (this.revoked.has('session')) return null;
    const legacy = loadLegacySession(legacyPath);
    if (!legacy) return null;
    try {
      if (this.import('session', JSON.stringify(legacy.file))) this.clearLegacySession(legacyPath);
    } catch { this.warning = '登录信息迁移未完成，原数据已保留，下次启动会重试。'; }
    return legacy;
  }
  saveSession(legacyPath: string, jar: CookieJar, extra: { username?: string; displayName?: string } = {}) {
    const file: SessionFile = { version: 1, savedAt: new Date().toISOString(), ...extra, cookies: jar.toJSON() };
    if (this.set('session', JSON.stringify(file))) this.clearLegacySession(legacyPath);
  }
  clearSession(legacyPath: string) {
    // Explicit logout must not allow a retained legacy file to log in again.
    this.set('session', undefined);
    this.clearLegacySession(legacyPath);
  }
  private clearLegacySession(path: string) {
    for (const name of [path, `${path}.bak`]) if (existsSync(name)) unlinkSync(name);
  }
}

const publicFields = new Set(['rememberUsername', 'username', 'rememberPassword', 'enrollmentState', 'hideUnsubmitted', 'theme', 'followSystem', 'syncMinutes', 'closeToTray', 'taskNotifications', 'changeNotifications', 'downloadRoot', 'dashboardSections', 'dashboardOrder', 'ignoredAssignments', 'refreshScope']);
const booleanFields = new Set(['rememberUsername', 'rememberPassword', 'hideUnsubmitted', 'followSystem', 'closeToTray', 'taskNotifications', 'changeNotifications']);
export function publicPreferences<T extends object>(value: T): Partial<T> {
  return Object.fromEntries(Object.entries(value).filter(([key]) => publicFields.has(key))) as Partial<T>;
}
export function preferencePatch(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error('设置格式无效');
  const result = publicPreferences(value) as Record<string, unknown>;
  for (const [key, item] of Object.entries(result)) {
    if (booleanFields.has(key) && typeof item !== 'boolean') throw Error('设置格式无效');
    if (['username', 'downloadRoot'].includes(key) && (typeof item !== 'string' || item.length > 32768)) throw Error('设置格式无效');
    if (key === 'theme' && !['light', 'dark'].includes(item as string)) throw Error('外观设置无效');
    if (key === 'syncMinutes' && ![0, 15, 30, 60].includes(item as number)) throw Error('同步间隔无效');
    if (key === 'enrollmentState' && !['active', 'all'].includes(item as string)) throw Error('课程范围无效');
    if (key === 'refreshScope' && !['current', 'all'].includes(item as string)) throw Error('同步范围无效');
    if (['dashboardOrder', 'ignoredAssignments'].includes(key) && (!Array.isArray(item) || item.length > 10000 || item.some(v => typeof v !== 'string'))) throw Error('列表设置无效');
    if (key === 'dashboardSections' && (!item || typeof item !== 'object' || Array.isArray(item) || Object.values(item).some(v => typeof v !== 'boolean'))) throw Error('板块设置无效');
  }
  return result;
}
