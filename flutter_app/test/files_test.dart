/// 课程文件核心逻辑测试。
///
/// 用例与桌面端 `cli/test-files.ts` 一一对应——两端是各自实现的，
/// 只有这些断言都一样，才能保证行为真的一致。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fudan_elearning/core/files.dart';

CanvasFolder folder(int id, String name, {int? parent, int? position}) => CanvasFolder(
      id: id,
      name: name,
      parentFolderId: parent,
      position: position,
    );

CanvasFile file(int id, int? folderId, String name, {int size = 0}) => CanvasFile(
      id: id,
      folderId: folderId,
      displayName: name,
      filename: name,
      contentType: 'application/pdf',
      url: 'https://example.test/files/$id/download',
      size: size,
    );

void main() {
  group('sanitizeSegment 跨平台非法字符', () {
    test('Windows 非法字符换成下划线', () {
      expect(sanitizeSegment('第1章: 绪论?.pdf'), '第1章_ 绪论_.pdf');
      expect(sanitizeSegment('a/b\\c.txt'), 'a_b_c.txt');
      expect(sanitizeSegment('《报告》<v2>"final".docx'), '《报告》_v2__final_.docx');
      expect(sanitizeSegment('a|b*c.txt'), 'a_b_c.txt');
    });

    test('去掉结尾的点与空格', () {
      expect(sanitizeSegment('讲义...'), '讲义');
      expect(sanitizeSegment('讲义   '), '讲义');
      expect(sanitizeSegment('讲义 . . '), '讲义');
    });

    test('控制字符与连续空白', () {
      expect(sanitizeSegment('a\u0000b\u001fc.txt'), 'a_b_c.txt');
      expect(sanitizeSegment('第 1   章'), '第 1 章');
    });

    test('空值与全非法字符兜底', () {
      expect(sanitizeSegment(''), '_');
      expect(sanitizeSegment('...'), '_');
      expect(sanitizeSegment('   '), '_');
    });

    test('Windows 保留设备名加前缀', () {
      expect(sanitizeSegment('CON'), '_CON');
      expect(sanitizeSegment('con.txt'), '_con.txt');
      expect(sanitizeSegment('NUL'), '_NUL');
      expect(sanitizeSegment('COM1.pdf'), '_COM1.pdf');
      expect(sanitizeSegment('lpt9'), '_lpt9');
      expect(sanitizeSegment('CONSOLE.txt'), 'CONSOLE.txt');
      expect(sanitizeSegment('COM10.txt'), 'COM10.txt');
    });

    test('超长截断并保留扩展名', () {
      final cut = sanitizeSegment('${'a' * 300}.pdf');
      expect(cut.length, lessThanOrEqualTo(120));
      expect(cut.endsWith('.pdf'), isTrue);
    });

    test('中文与 emoji 原样保留', () {
      expect(sanitizeSegment('数据结构讲义'), '数据结构讲义');
      expect(sanitizeSegment('笔记📝.txt'), '笔记📝.txt');
    });
  });

  group('sanitizePath 整条路径', () {
    test('分段净化', () {
      expect(sanitizePath('课件/第1章: 绪论/a?.pdf'), '课件/第1章_ 绪论/a_.pdf');
    });
    test('去掉空段', () => expect(sanitizePath('a//b///c.txt'), 'a/b/c.txt'));
    test('阻止路径穿越', () => expect(sanitizePath('../../etc/passwd'), 'etc/passwd'));
    test('去掉单独的 .', () => expect(sanitizePath('a/./b.txt'), 'a/b.txt'));
    test('全是穿越段', () => expect(sanitizePath('../..'), ''));
  });

  group('dedupePaths 去重', () {
    test('无冲突时原样返回', () {
      expect(dedupePaths(['a.pdf', 'b.pdf']), ['a.pdf', 'b.pdf']);
    });
    test('同名加序号', () {
      expect(dedupePaths(['报告.docx', '报告.docx', '报告.docx']),
          ['报告.docx', '报告 (2).docx', '报告 (3).docx']);
    });
    test('忽略大小写冲突', () {
      expect(dedupePaths(['Notes.pdf', 'notes.pdf']), ['Notes.pdf', 'notes (2).pdf']);
    });
    test('不同目录不算冲突', () {
      expect(dedupePaths(['A/x.pdf', 'B/x.pdf']), ['A/x.pdf', 'B/x.pdf']);
    });
    test('扩展名与主干都保留', () {
      expect(dedupePaths(['期末 复习.tar.gz', '期末 复习.tar.gz']),
          ['期末 复习.tar.gz', '期末 复习.tar (2).gz']);
    });
    test('无扩展名的文件', () {
      expect(dedupePaths(['README', 'README']), ['README', 'README (2)']);
    });
    test('点开头的隐藏文件不被拆坏', () {
      expect(dedupePaths(['.gitignore', '.gitignore']), ['.gitignore', '.gitignore (2)']);
    });
  });

  group('naturalCompare 自然序', () {
    test('数字按数值比', () {
      expect(naturalCompare('第2章', '第10章'), lessThan(0));
      expect(naturalCompare('file1', 'file2'), lessThan(0));
      expect(naturalCompare('9', '10'), lessThan(0));
    });
    // 非数字部分用码位序：作(U+4F5C) < 课(U+8BFE)，所以「作业」在前。
    // 与桌面端刻意保持一致——Dart 没有内置拼音排序，
    // 两端若一个按拼音、一个按码位，同一份文件顺序会不一样。
    test('中文按码位，与桌面端一致', () => expect(naturalCompare('课件', '作业'), greaterThan(0)));
    test('相同返回 0', () => expect(naturalCompare('a1', 'a1'), 0));
    test('前缀短的在前', () => expect(naturalCompare('a', 'a1'), lessThan(0)));
  });

  group('buildFileTree 目录树', () {
    test('层级、路径与统计', () {
      final tree = buildFileTree(
        [
          folder(10, '课件', position: 1),
          folder(11, '第一章', parent: 10, position: 1),
          folder(12, '作业', position: 2),
        ],
        [
          file(1, 10, '大纲.pdf', size: 1000),
          file(2, 11, '第1章.pdf', size: 2000),
          file(3, 12, '作业一.docx', size: 3000),
          file(4, null, '根目录文件.txt', size: 500),
        ],
      );

      expect(tree.children.length, 3);
      expect(tree.children.map((c) => '${c.kind}:${c.name}').toList(),
          ['folder:课件', 'folder:作业', 'file:根目录文件.txt']);

      final kejian = tree.children.firstWhere((c) => c.name == '课件');
      expect(kejian.children.length, 2);
      expect(kejian.children.first.path, '课件/第一章');

      final ch1 = flattenFiles(tree).firstWhere((f) => f.name == '第1章.pdf');
      expect(ch1.path, '课件/第一章/第1章.pdf');

      final rootFile = flattenFiles(tree).firstWhere((f) => f.name == '根目录文件.txt');
      expect(rootFile.path, '根目录文件.txt');

      expect(flattenFiles(tree).length, 4);
      final stats = treeStats(tree);
      expect(stats.count, 4);
      expect(stats.bytes, 6500);
    });

    test('文件夹名被净化', () {
      final tree = buildFileTree([folder(20, 'a/b:c')], []);
      expect(tree.children.first.name, 'a_b_c');
    });

    test('父文件夹缺失时挂到根，不丢节点', () {
      final tree = buildFileTree([folder(30, '孤儿', parent: 999)], []);
      expect(tree.children.length, 1);
      expect(tree.children.first.path, '孤儿');
    });

    test('中文章节按 position 排，而非拼音', () {
      // 这是实际踩到的问题：拼音序会把「第二章」排在「第一章」前面。
      final tree = buildFileTree(
        [folder(1, '第二章 线性表', position: 2), folder(2, '第一章 绪论', position: 1)],
        [],
      );
      expect(tree.children.map((c) => c.name).toList(), ['第一章 绪论', '第二章 线性表']);
    });

    test('无 position 时数字按自然序', () {
      final tree = buildFileTree([folder(3, '第10章'), folder(4, '第2章'), folder(5, '第1章')], []);
      expect(tree.children.map((c) => c.name).toList(), ['第1章', '第2章', '第10章']);
    });

    test('position 优先于名称，有 position 的靠前', () {
      expect(buildFileTree([folder(6, 'A', position: 5), folder(7, 'B', position: 1)], [])
          .children
          .map((c) => c.name)
          .toList(), ['B', 'A']);
      expect(buildFileTree([folder(8, '无位'), folder(9, '有位', position: 3)], [])
          .children
          .map((c) => c.name)
          .toList(), ['有位', '无位']);
    });

    test('深层子节点的 path 在父节点挂载后依然正确', () {
      // 回归：path 若用「替换对象」的方式设置，先挂到父节点下的引用会失效。
      final tree = buildFileTree(
        [
          folder(1, 'A', position: 1),
          folder(2, 'B', parent: 1, position: 1),
          folder(3, 'C', parent: 2, position: 1),
        ],
        [file(9, 3, 'deep.pdf')],
      );
      final deep = flattenFiles(tree).first;
      expect(deep.path, 'A/B/C/deep.pdf');
      final a = tree.children.first;
      expect(a.path, 'A');
      expect(a.children.first.path, 'A/B');
      expect(a.children.first.children.first.path, 'A/B/C');
    });
  });

  group('planDownloadPaths 下载路径', () {
    test('学期 / 课程 / 子文件夹', () {
      final plan = planDownloadPaths('2026-2027 学年第一学期', 'CS100113.02 程序设计基础', [
        (folderPath: '课件/第一章', fileName: '绪论.pdf', file: file(1, null, '绪论.pdf')),
        (folderPath: '', fileName: '大纲.pdf', file: file(2, null, '大纲.pdf')),
      ]);
      expect(plan[0].relativePath,
          '2026-2027 学年第一学期/CS100113.02 程序设计基础/课件/第一章/绪论.pdf');
      expect(plan[1].relativePath, '2026-2027 学年第一学期/CS100113.02 程序设计基础/大纲.pdf');
    });

    test('学期与课程名里的非法字符也净化', () {
      final plan = planDownloadPaths('2026/2027 学年', 'A:B 课程', [
        (folderPath: '', fileName: 'x.pdf', file: file(3, null, 'x.pdf')),
      ]);
      expect(plan[0].relativePath, '2026_2027 学年/A_B 课程/x.pdf');
    });

    test('不同子目录同名不冲突', () {
      final plan = planDownloadPaths('T', 'C', [
        (folderPath: 'A', fileName: 'same.pdf', file: file(4, null, 's.pdf')),
        (folderPath: 'B', fileName: 'same.pdf', file: file(5, null, 's.pdf')),
      ]);
      expect(plan.map((p) => p.relativePath).toList(), ['T/C/A/same.pdf', 'T/C/B/same.pdf']);
    });

    test('同目录重名加序号', () {
      final plan = planDownloadPaths('T', 'C', [
        (folderPath: 'A', fileName: 'same.pdf', file: file(6, null, 's.pdf')),
        (folderPath: 'A', fileName: 'same.pdf', file: file(7, null, 's.pdf')),
      ]);
      expect(plan.map((p) => p.relativePath).toList(),
          ['T/C/A/same.pdf', 'T/C/A/same (2).pdf']);
    });
  });

  group('formatBytes', () {
    test('各量级', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-1), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });
  });

  group('Canvas 响应映射', () {
    test('content-type 带连字符的字段能读到', () {
      final f = CanvasFile.fromJson({
        'id': 7,
        'folder_id': 3,
        'display_name': '讲义.pdf',
        'filename': 'lecture.pdf',
        'content-type': 'application/pdf',
        'url': 'https://x.test/f/7',
        'size': 1234,
        'locked': false,
        'hidden': false,
      });
      expect(f.contentType, 'application/pdf');
      expect(f.displayName, '讲义.pdf');
      expect(f.folderId, 3);
      expect(f.size, 1234);
    });

    test('缺 display_name 时退回 filename', () {
      final f = CanvasFile.fromJson({'id': 8, 'filename': 'a.pdf', 'url': 'u'});
      expect(f.displayName, 'a.pdf');
    });

    test('folder 的 position 能读到', () {
      final f = CanvasFolder.fromJson({'id': 1, 'name': '课件', 'position': 3});
      expect(f.position, 3);
    });

    test('locked_for_user 也算锁定', () {
      final f = CanvasFile.fromJson({'id': 9, 'url': 'u', 'locked_for_user': true});
      expect(f.locked, isTrue);
    });
  });
}
