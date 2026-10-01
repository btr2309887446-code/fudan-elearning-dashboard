/// 课程文件的下载。
///
/// 与桌面端 `src/main/download.ts` 对应，但落盘位置受移动系统限制：
///
///  - **iOS**：应用文档目录。Info.plist 里开了 `UIFileSharingEnabled` 与
///    `LSSupportsOpeningDocumentsInPlace`，所以「文件」App 里能看到，
///    用户可以把整个文件夹拷到 iCloud 或别处。
///  - **Android**：应用专属外部目录
///    （`Android/data/<包名>/files/eLearning`）。targetSdk 36 下受分区存储
///    限制，不能直接写公共 Download 目录，否则要申请 MANAGE_EXTERNAL_STORAGE
///    这种很重的权限，不值得。
///
/// 取字节（[FileTransport]）与写文件（[FileSink]）都是注入的，
/// 所以进度、重试、跳过、路径规划这些逻辑都能在单元测试里跑，不需要真机。
library;

import 'dart:convert';
import 'dart:typed_data';

import '../core/cookies.dart';

/// 下载一个 URL，把响应体按块交出来。
abstract class FileTransport {
  /// [onData] 每收到一块调用一次，实现方必须 await 完成后再继续读，
  /// 否则取消与写盘顺序都会乱。
  Future<FileDownloadHandle> open(
    String url, {
    String? cookieHeader,
    required Future<void> Function(Uint8List chunk) onData,
    required bool Function() isCancelled,
  });
}

class FileDownloadHandle {
  const FileDownloadHandle({required this.completed, this.failures = const []});

  /// 是否成功传完。
  final bool completed;
  final List<DownloadFailure> failures;
}

class DownloadFailure {
  const DownloadFailure({required this.relativePath, required this.message});

  final String relativePath;
  final String message;

  @override
  String toString() => '$relativePath: $message';
}

/// 落盘接口。
abstract class FileSink {
  /// 下载根目录的绝对路径。
  Future<String> root();

  /// 目标文件是否已存在且大小一致（用于跳过重复下载）。
  Future<bool> existsWithSize(String absolutePath, int size);

  /// 确保 [absolutePath] 的父目录存在。
  Future<void> ensureDir(String absolutePath);

  /// 追加写入。
  Future<void> append(String absolutePath, Uint8List chunk);

  /// 写完收尾：把 `.part` 改成正式文件名。传入的是 `.part` 路径。
  Future<void> finish(String partPath);

  /// 中途放弃时清理 `.part`。
  Future<void> discard(String partPath);
}

class DownloadItem {
  const DownloadItem({
    required this.url,
    required this.relativePath,
    required this.size,
    required this.name,
  });

  final String url;
  final String relativePath;
  final int size;
  final String name;
}

enum DownloadState { running, done, cancelled }

class DownloadProgress {
  DownloadProgress({required this.total, required this.bytesTotal});

  final int total;
  final int bytesTotal;
  int completed = 0;
  int skipped = 0;
  int failed = 0;
  String currentName = '';
  int bytesReceived = 0;
  int currentReceived = 0;
  int currentTotal = 0;
  final List<DownloadFailure> failures = [];
  DownloadState state = DownloadState.running;

  DownloadProgress copy() => DownloadProgress(total: total, bytesTotal: bytesTotal)
    ..completed = completed
    ..skipped = skipped
    ..failed = failed
    ..currentName = currentName
    ..bytesReceived = bytesReceived
    ..currentReceived = currentReceived
    ..currentTotal = currentTotal
    ..failures.addAll(failures)
    ..state = state;
}

/// 路径逃逸防护：确认最终路径确实在根目录之内。
///
/// Canvas 理论上不可能给出 `../` 或绝对路径，但落盘前仍要再确认一次。
/// 绝对路径直接拒绝而不是当成相对路径处理——后者虽然也逃不出去，
/// 但会悄悄生成一个谁也没预期的嵌套目录，不如直接暴露问题。
String safeJoin(String root, String relativePath) {
  if (relativePath.startsWith('/') || _driveLetter.hasMatch(relativePath)) {
    throw ArgumentError('下载路径不能是绝对路径：$relativePath');
  }
  final rootAbs = _normalise(root);
  final prefix = rootAbs.endsWith('/') ? rootAbs : '$rootAbs/';
  final finalAbs = _normalise('$rootAbs/$relativePath');
  if (!finalAbs.startsWith(prefix)) {
    throw ArgumentError('路径越出下载目录：$relativePath');
  }
  return finalAbs;
}

final RegExp _driveLetter = RegExp(r'^[A-Za-z]:');

String _normalise(String path) {
  final absolute = path.startsWith('/');
  final parts = <String>[];
  for (final seg in path.replaceAll('\\', '/').split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(seg);
  }
  final joined = parts.join('/');
  return absolute ? '/$joined' : joined;
}

class Downloader {
  Downloader({
    required this.transport,
    required this.sink,
    required this.cookies,
    this.maxRetries = 2,
    this.onProgress,
  });

  final FileTransport transport;
  final FileSink sink;
  final CookieJar cookies;
  final int maxRetries;
  final void Function(DownloadProgress)? onProgress;

  bool _cancelled = false;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  void cancel() => _cancelled = true;

  /// 进度节流：每块都回调会把界面刷爆。
  void _emit(DownloadProgress p, {bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastEmit).inMilliseconds < 180) return;
    _lastEmit = now;
    onProgress?.call(p.copy());
  }

  Future<DownloadProgress> run(List<DownloadItem> items) async {
    final progress = DownloadProgress(
      total: items.length,
      bytesTotal: items.fold(0, (s, i) => s + (i.size > 0 ? i.size : 0)),
    );
    _emit(progress, force: true);

    final root = await sink.root();

    for (final item in items) {
      if (_cancelled) break;

      progress.currentName = item.name;
      progress.currentReceived = 0;
      progress.currentTotal = item.size > 0 ? item.size : 0;
      _emit(progress, force: true);

      try {
        final skipped = await _fetchOne(item, root, progress);
        if (skipped) {
          progress.skipped += 1;
        } else {
          progress.completed += 1;
        }
      } catch (e) {
        if (_cancelled) break;
        progress.failed += 1;
        progress.failures.add(DownloadFailure(
          relativePath: item.relativePath,
          message: e.toString().replaceFirst('Exception: ', ''),
        ));
      }
      _emit(progress, force: true);
    }

    progress.state = _cancelled ? DownloadState.cancelled : DownloadState.done;
    progress.currentName = '';
    _emit(progress, force: true);
    return progress.copy();
  }

  /// 返回 true 表示因本地已存在而被跳过。
  Future<bool> _fetchOne(DownloadItem item, String root, DownloadProgress progress) async {
    final dest = safeJoin(root, item.relativePath);
    await sink.ensureDir(dest);

    if (item.size > 0 && await sink.existsWithSize(dest, item.size)) return true;

    final part = '$dest.part';
    Object? last;

    for (var attempt = 0; attempt <= maxRetries; attempt += 1) {
      if (_cancelled) break;
      try {
        await sink.discard(part);

        final handle = await transport.open(
          item.url,
          cookieHeader: cookies.cookieHeader(item.url),
          isCancelled: () => _cancelled,
          onData: (chunk) async {
            await sink.append(part, chunk);
            progress.currentReceived += chunk.length;
            progress.bytesReceived += chunk.length;
            _emit(progress);
          },
        );

        if (!handle.completed) {
          throw Exception(
            handle.failures.isNotEmpty ? handle.failures.first.message : '下载被中断',
          );
        }
        // 到这里数据已经全部落进 .part，改名成正式文件。
        await sink.finish(part);
        return false;
      } catch (e) {
        last = e;
        await sink.discard(part);
        if (_cancelled) break;
        if (attempt < maxRetries) {
          await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
        }
      }
    }
    throw Exception('${last ?? '下载失败'}');
  }
}

// ---------------------------------------------------------------------------
// 测试替身
// ---------------------------------------------------------------------------

/// 内存传输层。
class FakeFileTransport implements FileTransport {
  FakeFileTransport(this.chunks, {this.failTimes = 0, this.chunkDelayMs = 1});

  /// 每次请求要分块吐出的内容。
  final List<Uint8List> chunks;

  /// 前 N 次请求直接失败，用来验证重试。
  int failTimes;

  final int chunkDelayMs;

  int calls = 0;
  String? lastCookieHeader;

  @override
  Future<FileDownloadHandle> open(
    String url, {
    String? cookieHeader,
    required Future<void> Function(Uint8List chunk) onData,
    required bool Function() isCancelled,
  }) async {
    calls += 1;
    lastCookieHeader = cookieHeader;
    if (calls <= failTimes) {
      return const FileDownloadHandle(completed: false);
    }
    for (final c in chunks) {
      if (isCancelled()) return const FileDownloadHandle(completed: false);
      await onData(c);
      if (chunkDelayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: chunkDelayMs));
      }
    }
    return const FileDownloadHandle(completed: true);
  }
}

/// 内存落盘层，记录所有写过的路径与内容。
class MemoryFileSink implements FileSink {
  MemoryFileSink([this._root = '/mem']);

  final String _root;
  final Map<String, BytesBuilder> files = {};
  final Set<String> dirs = {};

  @override
  Future<String> root() async => _root;

  @override
  Future<bool> existsWithSize(String absolutePath, int size) async =>
      files[absolutePath]?.length == size;

  @override
  Future<void> ensureDir(String absolutePath) async {
    final slash = absolutePath.lastIndexOf('/');
    if (slash > 0) dirs.add(absolutePath.substring(0, slash));
  }

  @override
  Future<void> append(String absolutePath, Uint8List chunk) async {
    (files[absolutePath] ??= BytesBuilder()).add(chunk);
  }

  @override
  Future<void> finish(String partPath) async {
    if (!partPath.endsWith('.part')) return;
    final target = partPath.substring(0, partPath.length - 5);
    final data = files.remove(partPath);
    if (data != null) files[target] = data;
  }

  @override
  Future<void> discard(String partPath) async {
    files.remove(partPath);
  }

  /// 测试辅助：读回文本内容。
  String text(String absolutePath) =>
      utf8.decode(files[absolutePath]?.toBytes() ?? Uint8List(0));

  bool has(String absolutePath) => files.containsKey(absolutePath);
}
