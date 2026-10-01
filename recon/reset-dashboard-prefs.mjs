/**
 * 清掉首页板块的开关与顺序偏好，恢复默认。
 *
 * 自动化测试（smoke-drive 的 order/customise 目标）会把这些写进真实的
 * prefs.json，拍文档截图前必须先清干净，否则图里是测试残留的状态。
 *
 * 只动这两个键，其余偏好（主题、记住的学号、大模型配置、下载目录）原样保留。
 *
 *   node recon/reset-dashboard-prefs.mjs
 */

import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const path = join(process.env.APPDATA ?? '', 'fudan-elearning-dashboard', 'prefs.json');

if (!existsSync(path)) {
  console.log('没有 prefs.json，无需处理');
  process.exit(0);
}

const prefs = JSON.parse(readFileSync(path, 'utf8'));
const before = {
  sections: JSON.stringify(prefs.dashboardSections ?? null),
  order: JSON.stringify(prefs.dashboardOrder ?? null),
  ignored: JSON.stringify(prefs.ignoredAssignments ?? null),
};

delete prefs.dashboardSections;
delete prefs.dashboardOrder;
delete prefs.ignoredAssignments;

writeFileSync(path, JSON.stringify(prefs, null, 2), 'utf8');
console.log('已清除：');
console.log('  dashboardSections  =', before.sections);
console.log('  dashboardOrder     =', before.order);
console.log('  ignoredAssignments =', before.ignored);
console.log('其余偏好保留：', Object.keys(prefs).join(', '));
