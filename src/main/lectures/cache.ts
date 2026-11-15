import { mkdir, open, rename, unlink, readdir, stat } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { randomUUID } from 'node:crypto';

export async function atomicCache(path: string, data: Uint8Array, guard: () => void) {
  guard(); await mkdir(dirname(path), { recursive: true }); guard();
  const temporary = `${path}.${randomUUID()}.tmp`;
  try {
    const file = await open(temporary, 'wx');
    try { await file.writeFile(data); await file.sync(); } finally { await file.close(); }
    guard(); await rename(temporary, path); guard();
  } finally { await unlink(temporary).catch(() => {}); }
}
export async function cacheExists(paths: string[]): Promise<boolean> {
  for (const path of paths) { try { if (!(await stat(path)).isFile()) return false; } catch { return false; } }
  return true;
}
export async function collectCache(folder: string, hashes: string[], guard: () => void) {
  const keep = new Set(hashes);
  for (const name of await readdir(folder)) {
    const match = /^([a-f0-9]{64})\.enc(?:\.index)?$/.exec(name);
    if (!match || keep.has(match[1])) continue;
    guard(); await unlink(join(folder,name));
  }
}
