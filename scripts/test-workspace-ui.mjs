import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";

// Each run has its own synthetic account files and never reads production userData.
mkdirSync("artifacts/ui", { recursive: true });
const cases = [
  ["feedback", 1366, 768, 1, "light"],
  ["reduced", 1366, 768, 1, "dark"],
  ["interaction", 1366, 768, 1, "light"],
  ["performance", 1366, 768, 1, "light"],
  ["today", 1366, 768, 1, "light"],
  ["tasks-wide", 1920, 1080, 1, "light"],
  ["tasks-narrow", 800, 600, 1, "light"],
  ["tasks-125", 1366, 768, 1.25, "light"],
  ["tasks-150", 1366, 768, 1.5, "dark"],
  ["calendar", 1366, 768, 1, "light"],
  ["changes", 1366, 768, 1, "light"],
  ["courses", 1366, 768, 1, "light"],
];
for (const [view, width, height, scale, theme] of cases.filter(c => !process.env.WORKSPACE_UI_CASE || c[0] === process.env.WORKSPACE_UI_CASE)) {
  const profile = mkdtempSync(join(tmpdir(), "elearning-ui-"));
  writeFileSync(join(profile, "prefs.json"), JSON.stringify({ theme }));
  if (view === 'performance') {
    mkdirSync(join(profile, 'accounts'));
    const series = Array.from({ length: 5000 }, (_, i) => ({ id: `perf-${i}`, title: `性能任务 ${i}`, notes: '', courseId: null, dueAt: null, repeat: 'none', weekdays: [], endDate: null, checklist: [], reminders: [], createdAt: new Date().toISOString(), exceptions: {} }));
    writeFileSync(join(profile, 'accounts', 'workspace-90210.json'), JSON.stringify({ version: 1, account: 90210, series, deadlines: {}, ignored: [], changes: [], baselines: {}, delivered: {} }));
  }

  const result = await new Promise((resolvePromise) => {
    const child = spawn(
      resolve("node_modules/electron/dist/electron.exe"),
      [["feedback", "reduced"].includes(view) ? "scripts/feedback-main.cjs" : ".", `--force-device-scale-factor=${scale}`],
      {
        windowsHide: true,
        env: {
          ...process.env,
          ELEARNING_DEMO: "1",
          ELEARNING_DEMO_DIR: profile,
          ELEARNING_SMOKE: `artifacts/ui/windows-${view}.png`,
          ELEARNING_SMOKE_WIDTH: String(
            Math.max(800, Math.round(width / scale)),
          ),
          ELEARNING_SMOKE_HEIGHT: String(
            Math.max(600, Math.round(height / scale)),
          ),
          ELEARNING_SMOKE_VIEW: view,
          ELEARNING_SMOKE_DELAY: "800",
          ELEARNING_SMOKE_SETTLE: "300",
          ELEARNING_SMOKE_SCRIPT_FILE: resolve(
            "scripts/workspace-ui-driver.js",
          ),
        },
      },
    );
    let output = "";
    child.stdout.on("data", (chunk) => (output += chunk));
    child.stderr.on("data", (chunk) => (output += chunk));
    const timeout = setTimeout(() => {
      child.kill();
    }, 45000);
    child.on("exit", (code) => {
      clearTimeout(timeout);
      resolvePromise({ code, output });
    });
  });
  if (
    !result.output.includes("WORKSPACE_UI_PASS") ||
    result.output.includes("driver threw") ||
    result.code !== 0
  ) {
    console.error(result.output);
    throw Error(`UI case failed: ${view}`);
  }
  console.log(
    `${view}: passed (${width}×${height}, ${scale * 100}%, ${theme})`,
  );
}
