/**
 * Packaging wrapper.
 *
 * electron-builder pulls its helper binaries (winCodeSign, nsis) from GitHub
 * release assets, which are frequently unreachable from mainland China. Point
 * it at a mirror unless the caller has already chosen one.
 *
 *   npm run dist            # build the NSIS installer
 *   npm run dist -- --dir   # unpacked build only (no installer)
 *
 * CI 上设 `DIST_NO_MIRROR=1` 可以跳过镜像、直连 GitHub——
 * GitHub Actions 到 GitHub Releases 是最快的路径，绕镜像反而慢，
 * 也少一个第三方依赖。
 */

import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';

const DEFAULT_MIRROR = 'https://npmmirror.com/mirrors/electron-builder-binaries/';
if (process.env.DIST_NO_MIRROR === '1') {
  console.log('[dist] DIST_NO_MIRROR=1，直连 GitHub 拉取 electron-builder 的辅助二进制');
} else if (!process.env.ELECTRON_BUILDER_BINARIES_MIRROR) {
  process.env.ELECTRON_BUILDER_BINARIES_MIRROR = DEFAULT_MIRROR;
  console.log(`[dist] using binaries mirror: ${DEFAULT_MIRROR}`);
}
console.log('[dist] electronDist is pinned in electron-builder.yml, so no Electron zip download is needed.');

const require = createRequire(import.meta.url);

let cli;
try {
  cli = require.resolve('electron-builder/out/cli/cli.js');
} catch {
  console.error('[dist] cannot resolve electron-builder; run `npm install` first.');
  process.exit(1);
}

const args = [cli, '--win', '--config', 'electron-builder.yml', ...process.argv.slice(2)];

// Spawn node directly rather than going through a shell: it avoids argument
// escaping issues and the DEP0190 warning, and stdio must be inherited so the
// child's progress output reaches the terminal.
const child = spawn(process.execPath, args, { stdio: 'inherit' });
child.on('exit', (code) => process.exit(code ?? 1));
child.on('error', (err) => {
  console.error('[dist] failed to launch electron-builder:', err.message);
  process.exit(1);
});
