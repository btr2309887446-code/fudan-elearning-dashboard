/**
 * 把 canvas.dart 里所有 getAllPages 调用点改成新的「显式传解析函数」签名。
 *
 * 背景：`getAllPages<T>` 原先是 `data.whereType<T>()`，对 JSON 解出来的
 * Map 永远匹配不上，导致作业/作业分组/课程昵称恒为空。
 * 新签名要求必传 `T Function(Map)`，类型系统就能挡住这类错误。
 *
 *   node recon/patch-getallpages.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';

const p = 'D:/vit/杂/elearning/flutter_app/lib/core/canvas.dart';
let s = readFileSync(p, 'utf8');
let n = 0;

/** 精确替换，返回是否命中。 */
function sub(from, to, label) {
  if (!s.includes(from)) {
    console.log(`  ✗ 没找到: ${label}`);
    return;
  }
  s = s.split(from).join(to);
  n += 1;
  console.log(`  ✓ ${label}`);
}

// 1) 模型类型的三处：补 fromJson
sub(
  [
    'getAllPages<CanvasAssignmentGroup>(',
    "    '/api/v1/courses/$courseId/assignment_groups',",
    "    {'per_page': 100},",
    '  );',
  ].join('\n'),
  [
    'getAllPages(',
    "        '/api/v1/courses/$courseId/assignment_groups',",
    "        {'per_page': 100},",
    '        CanvasAssignmentGroup.fromJson,',
    '      );',
  ].join('\n'),
  'getAssignmentGroups'
);

sub(
  [
    'getAllPages<CanvasAssignment>(',
    "        '/api/v1/courses/$courseId/assignments',",
    "        {'include': ['submission'], 'per_page': 100, 'order_by': 'due_at'},",
    '      );',
  ].join('\n'),
  [
    'getAllPages(',
    "        '/api/v1/courses/$courseId/assignments',",
    "        {'include': ['submission'], 'per_page': 100, 'order_by': 'due_at'},",
    '        CanvasAssignment.fromJson,',
    '      );',
  ].join('\n'),
  'getAssignments'
);

sub(
  [
    'getAllPages<CanvasNickname>(',
    "        '/api/v1/users/self/course_nicknames',",
    "        {'per_page': 100},",
    '      );',
  ].join('\n'),
  [
    'getAllPages(',
    "        '/api/v1/users/self/course_nicknames',",
    "        {'per_page': 100},",
    '        CanvasNickname.fromJson,',
    '      );',
  ].join('\n'),
  'getCourseNicknames'
);

// 2) Map 类型的三处：恒等解析
const mapCalls = s.split('getAllPages<Map<String, dynamic>>(').length - 1;
s = s.split('getAllPages<Map<String, dynamic>>(').join('getAllPages(');
n += mapCalls;
console.log(`  ✓ Map 调用点 ${mapCalls} 处（去掉显式泛型）`);

// 3) 给 Map 调用点补恒等解析函数
s = s.replace(
  /(getAllPages\(\s*\n\s*'[^']*',\s*\n\s*\{[^}]*\},\s*\n)(\s*\);)/g,
  (m, head, tail) => `${head}        (m) => m,\n${tail}`
);

writeFileSync(p, s, 'utf8');
console.log(`共 ${n} 处`);
