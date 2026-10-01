/**
 * Persisting the Canvas session.
 *
 * Only cookies are written - never the password. The cookie jar is stored as
 * JSON next to the app's user data so a restart does not force a new login.
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { CanvasClient } from './canvas.ts';
import { CookieJar, type Cookie } from './cookies.ts';
import { HttpClient } from './http.ts';
import type { CanvasProfile } from './types.ts';

export interface SessionFile {
  version: 1;
  savedAt: string;
  username?: string;
  displayName?: string;
  cookies: Cookie[];
}

export function saveSession(path: string, jar: CookieJar, extra: { username?: string; displayName?: string } = {}): void {
  const data: SessionFile = {
    version: 1,
    savedAt: new Date().toISOString(),
    username: extra.username,
    displayName: extra.displayName,
    cookies: jar.toJSON(),
  };
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(data, null, 2), 'utf8');
}

export function loadSession(path: string): { jar: CookieJar; file: SessionFile } | null {
  if (!existsSync(path)) return null;
  try {
    const file = JSON.parse(readFileSync(path, 'utf8')) as SessionFile;
    if (file.version !== 1 || !Array.isArray(file.cookies)) return null;
    return { jar: CookieJar.fromJSON(file.cookies), file };
  } catch {
    return null;
  }
}

export function makeClient(jar: CookieJar): CanvasClient {
  return new CanvasClient(new HttpClient(jar));
}

/**
 * Confirm the stored cookies still work.
 * Returns the profile on success, or null when the session has expired.
 */
export async function verifySession(client: CanvasClient): Promise<CanvasProfile | null> {
  try {
    return await client.getProfile();
  } catch {
    return null;
  }
}
