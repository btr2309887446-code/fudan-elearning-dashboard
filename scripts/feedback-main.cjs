// Test-only entry: use real demo persistence, delay replies and fail one save.
// Never loaded by production or by the normal demo entry point.
const { ipcMain, app } = require('electron');
if (process.env.ELEARNING_DEMO !== '1' || !process.env.ELEARNING_DEMO_DIR)
  throw Error('Feedback tests require an isolated demo profile');
const handle = ipcMain.handle.bind(ipcMain);
let saves = 0;
ipcMain.handle = (channel, listener) => handle(channel, async (event, ...args) => {
  if (channel === 'workspace:mutate') {
    if (args[1]?.type === 'save') {
      saves++;
      await new Promise(resolve => setTimeout(resolve, 600));
      if (saves === 1) return { ok: false, error: { kind: 'io', message: '演示：保存暂时失败，请重试' } };
    } else await new Promise(resolve => setTimeout(resolve, 250));
  }
  return listener(event, ...args);
});
if (process.env.ELEARNING_SMOKE_VIEW === 'reduced') app.commandLine.appendSwitch('force-prefers-reduced-motion');
require('../out/main/index.js');

// Optional test-only frame capture; encode offline to avoid real-time backpressure.
if (process.env.ELEARNING_RECORD_DIR) {
  const fs = require('node:fs');
  const path = require('node:path');
  const folder = process.env.ELEARNING_RECORD_DIR;
  let frame = 0;
  app.on('browser-window-created', (_event, window) => {
    window.once('ready-to-show', () => {
      const capture = async () => {
        if (window.isDestroyed() || fs.existsSync(path.join(folder, 'stop'))) return;
        if (fs.existsSync(path.join(folder, 'start'))) {
          const at = Date.now();
          const image = await window.webContents.capturePage();
          fs.writeFileSync(path.join(folder, `frame-${String(frame++).padStart(5, '0')}-${at}.jpg`), image.toJPEG(85));
        }
        setTimeout(() => void capture().catch(() => {}), 80);
      };
      void capture();
    });
  });
}
