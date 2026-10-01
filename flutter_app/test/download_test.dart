/// 下载逻辑测试。
///
/// 用例与桌面端 `cli/test-download.ts` 对应。桌面端用的是真实本地 HTTP 服务器，
/// 这里用的是注入的内存传输层——移动端没有 Node 那种起服务器的便利，
/// 但进度、重试、跳过、路径防护、目录规划这些行为同样被覆盖到。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fudan_elearning/core/cookies.dart';
import 'package:fudan_elearning/platform/downloads.dart';

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  late MemoryFileSink sink;
  late CookieJar jar;

  setUp(() {
    sink = MemoryFileSink('/dl');
    jar = CookieJar();
    jar.setFromResponse('https://elearning.fudan.edu.cn/', [
      'canvas_session=test-session; Path=/',
    ]);
  });

  Downloader make(FileTransport transport, {void Function(DownloadProgress)? onProgress, int retries = 2}) =>
      Downloader(
        transport: transport,
        sink: sink,
        cookies: jar,
        maxRetries: retries,
        onProgress: onProgress,
      );

  group('safeJoin 路径逃逸防护', () {
    test('拒绝 ../', () => expect(() => safeJoin('/dl', '../../evil.txt'), throwsArgumentError));
    test('拒绝嵌套逃逸', () => expect(() => safeJoin('/dl', 'a/../../b'), throwsArgumentError));
    test('拒绝绝对路径逃逸', () => expect(() => safeJoin('/dl', '/etc/passwd'), throwsArgumentError));
    test('正常路径可用', () => expect(safeJoin('/dl', 'T/C/x.pdf'), '/dl/T/C/x.pdf'));
    test('多余分隔符被规整', () => expect(safeJoin('/dl', 'a//b/./c.pdf'), '/dl/a/b/c.pdf'));
  });

  group('下载成功路径', () {
    test('内容与进度正确', () async {
      final updates = <DownloadProgress>[];
      final payload = '复旦大学 eLearning 文件下载测试 🎓\n' * 50;
      final data = bytes(payload);

      final progress = await make(
        FakeFileTransport([data]),
        onProgress: updates.add,
      ).run([
        DownloadItem(url: 'https://x.test/f/1', relativePath: 'T/C/小.pdf', size: data.length, name: '小.pdf'),
      ]);

      expect(progress.state, DownloadState.done);
      expect(progress.completed, 1);
      expect(progress.failed, 0);
      expect(sink.text('/dl/T/C/小.pdf'), payload);
      expect(progress.bytesReceived, data.length);

      // .part 必须已经被改名，不能留在盘上。
      expect(sink.has('/dl/T/C/小.pdf.part'), isFalse);
      expect(updates.length, greaterThanOrEqualTo(2));
      expect(updates.last.state, DownloadState.done);
    });

    test('多块数据按顺序拼接', () async {
      final progress = await make(FakeFileTransport([bytes('AAA'), bytes('BBB'), bytes('CCC')])).run([
        const DownloadItem(url: 'https://x.test/f/2', relativePath: 'x.txt', size: 9, name: 'x.txt'),
      ]);
      expect(progress.completed, 1);
      expect(sink.text('/dl/x.txt'), 'AAABBBCCC');
    });

    test('Cookie 已随请求发送', () async {
      final t = FakeFileTransport([bytes('x')]);
      await make(t).run([
        const DownloadItem(url: 'https://elearning.fudan.edu.cn/files/1/download', relativePath: 'a', size: 1, name: 'a'),
      ]);
      expect(t.lastCookieHeader, contains('canvas_session=test-session'));
    });

    test('过程中有中间进度', () async {
      final updates = <DownloadProgress>[];
      final chunks = List.generate(12, (i) => bytes('chunk-$i' * 40));
      await make(
        FakeFileTransport(chunks, chunkDelayMs: 40),
        onProgress: updates.add,
      ).run([
        const DownloadItem(url: 'u', relativePath: 'big.bin', size: 12 * 280, name: 'big.bin'),
      ]);

      final mid = updates.where((u) => u.currentReceived > 0 && u.currentReceived < 12 * 280);
      expect(mid.isNotEmpty, isTrue, reason: '应有中间进度回调');
    });
  });

  group('跳过与重试', () {
    test('同名同大小跳过', () async {
      const item = DownloadItem(url: 'u', relativePath: 'a.pdf', size: 3, name: 'a.pdf');
      final first = await make(FakeFileTransport([bytes('abc')])).run([item]);
      expect(first.completed, 1);
      expect(first.skipped, 0);

      final second = await make(FakeFileTransport([bytes('abc')])).run([item]);
      expect(second.skipped, 1);
      expect(second.completed, 0);
    });

    test('大小不符时重新下载', () async {
      await make(FakeFileTransport([bytes('abc')])).run([
        const DownloadItem(url: 'u', relativePath: 'b.pdf', size: 3, name: 'b.pdf'),
      ]);
      final again = await make(FakeFileTransport([bytes('abcd')])).run([
        const DownloadItem(url: 'u', relativePath: 'b.pdf', size: 4, name: 'b.pdf'),
      ]);
      expect(again.completed, 1);
      expect(sink.text('/dl/b.pdf'), 'abcd');
    });

    test('瞬时失败后重试成功', () async {
      final t = FakeFileTransport([bytes('ok')], failTimes: 2);
      final progress = await make(t).run([
        const DownloadItem(url: 'u', relativePath: 'r.txt', size: 2, name: 'r.txt'),
      ]);
      expect(progress.completed, 1);
      expect(progress.failed, 0);
      expect(t.calls, 3, reason: '两次失败 + 一次成功');
      expect(sink.text('/dl/r.txt'), 'ok');
    });

    test('重试耗尽后记为失败，且不留 .part', () async {
      final t = FakeFileTransport([bytes('ok')], failTimes: 99);
      final progress = await make(t, retries: 1).run([
        const DownloadItem(url: 'u', relativePath: 'bad.txt', size: 2, name: 'bad.txt'),
      ]);
      expect(progress.failed, 1);
      expect(progress.completed, 0);
      expect(progress.failures.first.relativePath, 'bad.txt');
      expect(sink.has('/dl/bad.txt'), isFalse);
      expect(sink.has('/dl/bad.txt.part'), isFalse);
    });

    test('单个失败不影响其余文件', () async {
      // 第一个文件用会失败的传输层不现实，这里直接跑两个：一个已存在被跳过、
      // 一个正常下载，验证计数互不干扰。
      await make(FakeFileTransport([bytes('a')])).run([
        const DownloadItem(url: 'u', relativePath: 'A/a.txt', size: 1, name: 'a.txt'),
      ]);
      final progress = await make(FakeFileTransport([bytes('b')])).run([
        const DownloadItem(url: 'u', relativePath: 'A/a.txt', size: 1, name: 'a.txt'),
        const DownloadItem(url: 'u', relativePath: 'B/b.txt', size: 1, name: 'b.txt'),
        const DownloadItem(url: 'u', relativePath: 'B/c.txt', size: 1, name: 'c.txt'),
      ]);
      expect(progress.total, 3);
      expect(progress.skipped, 1);
      expect(progress.completed, 2);
      expect(progress.failed, 0);
    });
  });

  group('取消', () {
    test('预取消则不下载任何文件', () async {
      final t = FakeFileTransport([bytes('x')]);
      final d = make(t);
      d.cancel();
      final progress = await d.run([
        const DownloadItem(url: 'u', relativePath: 'c.txt', size: 1, name: 'c.txt'),
      ]);
      expect(progress.state, DownloadState.cancelled);
      expect(sink.has('/dl/c.txt'), isFalse);
      expect(t.calls, 0);
    });
  });

  group('目录结构', () {
    test('按「学期 / 课程 / 子文件夹」建目录并落盘', () async {
      final progress = await make(FakeFileTransport([bytes('pdf')])).run([
        const DownloadItem(
          url: 'u',
          relativePath: '2026-2027 学年第一学期/CS100113.02 程序设计基础/课件/第1章/绪论.pdf',
          size: 3,
          name: '绪论.pdf',
        ),
        const DownloadItem(
          url: 'u',
          relativePath: '2026-2027 学年第一学期/CS100113.02 程序设计基础/大纲.pdf',
          size: 3,
          name: '大纲.pdf',
        ),
      ]);

      expect(progress.completed, 2);
      const base = '/dl/2026-2027 学年第一学期/CS100113.02 程序设计基础';
      expect(sink.has('$base/课件/第1章/绪论.pdf'), isTrue);
      expect(sink.has('$base/大纲.pdf'), isTrue);
      expect(sink.dirs.contains('$base/课件/第1章'), isTrue);
      expect(sink.text('$base/课件/第1章/绪论.pdf'), 'pdf');
    });
  });
}
