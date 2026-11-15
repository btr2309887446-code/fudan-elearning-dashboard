// Run with Electron; target a built main entry and an isolated synthetic profile.
const { app } = require('electron');
const { writeFileSync } = require('node:fs');
const { performance } = require('node:perf_hooks');
if (process.env.ELEARNING_DEMO !== '1' || !process.env.ELEARNING_DEMO_DIR || !process.env.BENCHMARK_ENTRY || !process.env.BENCHMARK_OUTPUT) throw Error('Explicit isolated benchmark paths required');
const start = performance.now();
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const timeout = setTimeout(() => { console.error('Benchmark timed out'); app.exit(1); }, 45000);
app.on('browser-window-created', (_event, window) => {
  window.webContents.once('did-finish-load', () => void (async () => {
    for (let n = 0; n < 100; n++) {
      if (await window.webContents.executeJavaScript('!!document.querySelector(".workspace")')) break;
      if (n === 99) throw Error('Workspace did not mount');
      await delay(20);
    }
    const startupMs = performance.now() - start;
    // A hidden window with normal production throttling; synthetic data, no network.
    window.hide(); await delay(2000); app.getAppMetrics();
    const samples = [];
    for (let n = 0; n < 6; n++) {
      await delay(2000);
      const metrics = app.getAppMetrics();
      samples.push({ cpuPercent: metrics.reduce((sum, p) => sum + p.cpu.percentCPUUsage, 0),
        workingSetKiB: metrics.reduce((sum, p) => sum + p.memory.workingSetSize, 0) });
    }
    writeFileSync(process.env.BENCHMARK_OUTPUT, JSON.stringify({ startupMs, runtime: process.versions.electron, samples }, null, 2));
    clearTimeout(timeout); app.exit(0);
  })().catch(error => { console.error(error.message); app.exit(1); }));
});
require(process.env.BENCHMARK_ENTRY);
