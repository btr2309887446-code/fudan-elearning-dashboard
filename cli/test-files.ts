/**
 * 课程文件核心逻辑的回归测试。
 *
 * 这些是最容易出错、也最难在真机上发现的部分：
 * 文件名净化（跨 Windows / macOS / Linux）、重名去重、目录树构建、路径规划。
 * 全部是纯函数，不需要网络或账号。
 *
 *   node cli/test-files.ts
 */

import {
  buildFileTree,
  dedupePaths,
  flattenFiles,
  formatBytes,
  naturalCompare,
  planDownloadPaths,
  sanitizePath,
  sanitizeSegment,
  treeStats,
  type CanvasFile,
  type CanvasFolder,
} from '../src/core/files.ts';

let passed = 0;
let failed = 0;

function check(name: string, ok: boolean, info = ''): void {
  if (ok) {
    passed += 1;
    console.log(`  OK   ${name}${info ? '  — ' + info : ''}`);
  } else {
    failed += 1;
    console.log(` FAIL  ${name}${info ? '  — ' + info : ''}`);
  }
}

function eq<T>(name: string, actual: T, expected: T): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  check(name, a === e, a === e ? '' : `得到 ${a}，期望 ${e}`);
}

// ---------------------------------------------------------------------------
console.log('=== 课程文件核心逻辑测试 ===\n');

// [1] 文件名净化 -----------------------------------------------------------
console.log('[1] sanitizeSegment：跨平台的非法字符');
{
  eq('Windows 非法字符换成下划线', sanitizeSegment('第1章: 绪论?.pdf'), '第1章_ 绪论_.pdf');
  eq('路径分隔符不残留', sanitizeSegment('a/b\\c.txt'), 'a_b_c.txt');
  eq('引号与尖括号', sanitizeSegment('《报告》<v2>"final".docx'), '《报告》_v2__final_.docx');
  eq('竖线与星号', sanitizeSegment('a|b*c.txt'), 'a_b_c.txt');

  // Windows 不允许结尾是点或空格
  eq('去掉结尾的点', sanitizeSegment('讲义...'), '讲义');
  eq('去掉结尾的空格', sanitizeSegment('讲义   '), '讲义');
  eq('结尾的点加空格都去掉', sanitizeSegment('讲义 . . '), '讲义');

  // 控制字符
  eq('控制字符', sanitizeSegment('a\u0000b\u001fc.txt'), 'a_b_c.txt');

  // 连续空白压缩
  eq('压缩连续空白', sanitizeSegment('第 1   章'), '第 1 章');

  // 空 / 全非法
  eq('空字符串兜底', sanitizeSegment(''), '_');
  eq('全是点兜底', sanitizeSegment('...'), '_');
  eq('纯空白兜底', sanitizeSegment('   '), '_');

  // 保留设备名
  eq('CON 加前缀', sanitizeSegment('CON'), '_CON');
  eq('con.txt 加前缀', sanitizeSegment('con.txt'), '_con.txt');
  eq('NUL 加前缀', sanitizeSegment('NUL'), '_NUL');
  eq('COM1 加前缀', sanitizeSegment('COM1.pdf'), '_COM1.pdf');
  eq('LPT9 加前缀', sanitizeSegment('lpt9'), '_lpt9');
  check('CONSOLE 不算保留名', sanitizeSegment('CONSOLE.txt') === 'CONSOLE.txt');
  check('COM10 不算保留名', sanitizeSegment('COM10.txt') === 'COM10.txt');

  // 超长截断
  const long = 'a'.repeat(300) + '.pdf';
  const cut = sanitizeSegment(long);
  check('超长文件名被截断', cut.length <= 120, `长度 ${cut.length}`);
  check('截断后保留扩展名', cut.endsWith('.pdf'), cut.slice(-10));

  // 中文与 emoji 原样保留
  eq('中文保留', sanitizeSegment('数据结构讲义'), '数据结构讲义');
  eq('emoji 保留', sanitizeSegment('笔记📝.txt'), '笔记📝.txt');
}

// [2] 路径净化 -------------------------------------------------------------
console.log('\n[2] sanitizePath：整条相对路径');
{
  eq('分段净化', sanitizePath('课件/第1章: 绪论/a?.pdf'), '课件/第1章_ 绪论/a_.pdf');
  eq('去掉空段', sanitizePath('a//b///c.txt'), 'a/b/c.txt');
  eq('阻止路径穿越', sanitizePath('../../etc/passwd'), 'etc/passwd');
  eq('去掉单独的 .', sanitizePath('a/./b.txt'), 'a/b.txt');
  eq('全是穿越段', sanitizePath('../..'), '');
}

// [3] 重名去重 -------------------------------------------------------------
console.log('\n[3] dedupePaths：同目录重名');
{
  eq('无冲突时原样返回', dedupePaths(['a.pdf', 'b.pdf']), ['a.pdf', 'b.pdf']);

  eq(
    '同名加序号',
    dedupePaths(['报告.docx', '报告.docx', '报告.docx']),
    ['报告.docx', '报告 (2).docx', '报告 (3).docx']
  );

  eq(
    '忽略大小写冲突',
    dedupePaths(['Notes.pdf', 'notes.pdf']),
    ['Notes.pdf', 'notes (2).pdf']
  );

  eq(
    '不同目录不算冲突',
    dedupePaths(['A/x.pdf', 'B/x.pdf']),
    ['A/x.pdf', 'B/x.pdf']
  );

  eq(
    '扩展名与主干都保留',
    dedupePaths(['期末 复习.tar.gz', '期末 复习.tar.gz']),
    ['期末 复习.tar.gz', '期末 复习.tar (2).gz']
  );

  eq(
    '无扩展名的文件',
    dedupePaths(['README', 'README']),
    ['README', 'README (2)']
  );

  eq(
    '点开头的隐藏文件不被拆坏',
    dedupePaths(['.gitignore', '.gitignore']),
    ['.gitignore', '.gitignore (2)']
  );

  // 序号不能被后续的原始名字抢走
  eq(
    '序号冲突时继续递增',
    dedupePaths(['a.txt', 'a.txt', 'a (2).txt']),
    ['a.txt', 'a (2).txt', 'a (2) (2).txt']
  );
}

// [4] 目录树 ---------------------------------------------------------------
console.log('\n[4] buildFileTree：由扁平列表构建层级');
{
  const folders: CanvasFolder[] = [
    { id: 10, name: '课件', fullName: 'course files/课件', parentFolderId: null, filesCount: 2, foldersCount: 1, position: 1 },
    { id: 11, name: '第一章', fullName: 'course files/课件/第一章', parentFolderId: 10, filesCount: 1, foldersCount: 0, position: 1 },
    { id: 12, name: '作业', fullName: 'course files/作业', parentFolderId: null, filesCount: 1, foldersCount: 0, position: 2 },
  ];
  const mkFile = (id: number, folderId: number | null, name: string, size: number): CanvasFile => ({
    id,
    folderId,
    displayName: name,
    filename: name,
    contentType: 'application/pdf',
    url: `https://example.test/files/${id}/download`,
    size,
    createdAt: '',
    updatedAt: '',
    locked: false,
    hidden: false,
  });
  const files: CanvasFile[] = [
    mkFile(1, 10, '大纲.pdf', 1000),
    mkFile(2, 11, '第1章.pdf', 2000),
    mkFile(3, 12, '作业一.docx', 3000),
    mkFile(4, null, '根目录文件.txt', 500),
  ];

  const root = buildFileTree(folders, files);

  eq('根下有两个文件夹加一个文件', root.children.length, 3);

  const names = root.children.map((c) => `${c.kind}:${c.name}`);
  // 按 Canvas 的 position：课件(1) 在 作业(2) 之前。
  eq('排序：文件夹按 position', names, ['folder:课件', 'folder:作业', 'file:根目录文件.txt']);

  const kejian = root.children.find((c) => c.name === '课件')!;
  eq('课件下有子文件夹和文件', kejian.children.length, 2);
  eq('子文件夹路径正确', kejian.children[0].path, '课件/第一章');

  const ch1 = flattenFiles(root).find((f) => f.name === '第1章.pdf')!;
  eq('深层文件路径正确', ch1.path, '课件/第一章/第1章.pdf');

  const rootFile = flattenFiles(root).find((f) => f.name === '根目录文件.txt')!;
  eq('无归属的文件挂在根', rootFile.path, '根目录文件.txt');

  eq('摊平后共 4 个文件', flattenFiles(root).length, 4);

  const stats = treeStats(root);
  eq('统计文件数', stats.count, 4);
  eq('统计总字节', stats.bytes, 6500);

  // 文件夹名也需要净化
  const dirty = buildFileTree(
    [{ id: 20, name: 'a/b:c', fullName: '', parentFolderId: null, filesCount: 0, foldersCount: 0, position: null }],
    []
  );
  eq('文件夹名被净化', dirty.children[0].name, 'a_b_c');

  // 缺失父文件夹时不能丢节点
  const orphan = buildFileTree(
    [{ id: 30, name: '孤儿', fullName: '', parentFolderId: 999, filesCount: 0, foldersCount: 0, position: null }],
    []
  );
  eq('父文件夹缺失时挂到根', orphan.children.length, 1);
  eq('孤儿路径就是自身名字', orphan.children[0].path, '孤儿');
}

// [4b] 排序：Canvas 的 position 与数字自然序 --------------------------------
console.log('\n[4b] 排序规则');
{
  const f = (id: number, name: string, pos: number | null): CanvasFolder => ({
    id,
    name,
    fullName: '',
    parentFolderId: null,
    filesCount: 0,
    foldersCount: 0,
    position: pos,
  });

  // 这是实际踩到的问题：拼音序会把「第二章」排在「第一章」前面。
  const zh = buildFileTree([f(1, '第二章 线性表', 2), f(2, '第一章 绪论', 1)], []);
  eq(
    '中文章节按 Canvas position，而非拼音',
    zh.children.map((c) => c.name),
    ['第一章 绪论', '第二章 线性表']
  );

  // 没有 position 时退回自然序：第2章 在 第10章 之前。
  const num = buildFileTree([f(3, '第10章', null), f(4, '第2章', null), f(5, '第1章', null)], []);
  eq(
    '无 position 时数字按自然序',
    num.children.map((c) => c.name),
    ['第1章', '第2章', '第10章']
  );

  // position 优先于名字
  const mixed = buildFileTree([f(6, 'A', 5), f(7, 'B', 1)], []);
  eq('position 优先于名称', mixed.children.map((c) => c.name), ['B', 'A']);

  // 有 position 的排在没 position 的前面
  const partial = buildFileTree([f(8, '无位', null), f(9, '有位', 3)], []);
  eq('有 position 的靠前', partial.children.map((c) => c.name), ['有位', '无位']);

  eq('自然序：2 在 10 之前', naturalCompare('第2章', '第10章') < 0, true);
  eq('自然序：1 在 2 之前', naturalCompare('file1', 'file2') < 0, true);
  eq('自然序：纯数字', naturalCompare('9', '10') < 0, true);
  // 非数字部分用码位序：作(U+4F5C) < 课(U+8BFE)，所以「作业」在前。
  eq('自然序：中文按码位，与 Dart 端一致', naturalCompare('课件', '作业') > 0, true);
  eq('自然序：相同返回 0', naturalCompare('a1', 'a1'), 0);
  eq('自然序：前缀短的在前', naturalCompare('a', 'a1') < 0, true);
}

// [5] 下载路径规划 ---------------------------------------------------------
console.log('\n[5] planDownloadPaths：学期 / 课程 / 子文件夹');
{
  const f = (id: number): CanvasFile => ({
    id,
    folderId: null,
    displayName: `f${id}`,
    filename: `f${id}`,
    contentType: '',
    url: '',
    size: 0,
    createdAt: '',
    updatedAt: '',
    locked: false,
    hidden: false,
  });

  const plan = planDownloadPaths('2026-2027 学年第一学期', 'CS100113.02 程序设计基础', [
    { folderPath: '课件/第一章', fileName: '绪论.pdf', file: f(1) },
    { folderPath: '', fileName: '大纲.pdf', file: f(2) },
  ]);

  eq('带子文件夹的路径', plan[0].relativePath, '2026-2027 学年第一学期/CS100113.02 程序设计基础/课件/第一章/绪论.pdf');
  eq('课程根下的路径', plan[1].relativePath, '2026-2027 学年第一学期/CS100113.02 程序设计基础/大纲.pdf');

  // 学期与课程名里的非法字符也要处理
  const plan2 = planDownloadPaths('2026/2027 学年', 'A:B 课程', [
    { folderPath: '', fileName: 'x.pdf', file: f(3) },
  ]);
  eq('学期与课程名被净化', plan2[0].relativePath, '2026_2027 学年/A_B 课程/x.pdf');

  // 跨目录重名不该被加序号
  const plan3 = planDownloadPaths('T', 'C', [
    { folderPath: 'A', fileName: 'same.pdf', file: f(4) },
    { folderPath: 'B', fileName: 'same.pdf', file: f(5) },
  ]);
  eq('不同子目录同名不冲突', plan3.map((p) => p.relativePath), [
    'T/C/A/same.pdf',
    'T/C/B/same.pdf',
  ]);

  // 同目录重名要加序号
  const plan4 = planDownloadPaths('T', 'C', [
    { folderPath: 'A', fileName: 'same.pdf', file: f(6) },
    { folderPath: 'A', fileName: 'same.pdf', file: f(7) },
  ]);
  eq('同目录重名加序号', plan4.map((p) => p.relativePath), [
    'T/C/A/same.pdf',
    'T/C/A/same (2).pdf',
  ]);
}

// [6] 字节格式化 -----------------------------------------------------------
console.log('\n[6] formatBytes');
{
  eq('0', formatBytes(0), '0 B');
  eq('负数兜底', formatBytes(-1), '0 B');
  eq('字节', formatBytes(512), '512 B');
  eq('KB', formatBytes(2048), '2.0 KB');
  eq('MB', formatBytes(5 * 1024 * 1024), '5.0 MB');
  eq('GB', formatBytes(3 * 1024 ** 3), '3.0 GB');
}

// ---------------------------------------------------------------------------
console.log(`\n=== 结果：${passed}/${passed + failed} 项通过 ===`);
if (failed > 0) {
  console.log(`${failed} 项失败`);
  process.exit(1);
}
