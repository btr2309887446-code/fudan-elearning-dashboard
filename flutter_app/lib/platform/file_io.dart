/// 移动端的真实取字节 / 落盘实现。
///
/// 与 [FileTransport] / [FileSink] 的抽象对应，逻辑测试用的是内存替身，
/// 这里才是真正碰网络和文件系统的部分。
///
/// 下载目录：
///  - iOS：应用文档目录（Info.plist 开了文件共享，能在「文件」App 里看到）
///  - Android：应用专属外部目录，无需存储权限
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'downloads.dart';

const String _userAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

/// 用 dart:io 的 HttpClient 取文件。
///
/// 不用 `package:http`：它会把整个响应体读进内存，
/// 几百 MB 的课件视频会直接把应用撑爆。
class IoFileTransport implements FileTransport {
  IoFileTransport({HttpClient? client, this.timeout = const Duration(minutes: 30)})
      : _client = client ?? (HttpClient()..autoUncompress = false);

  final HttpClient _client;
  final Duration timeout;

  @override
  Future<FileDownloadHandle> open(
    String url, {
    String? cookieHeader,
    required Future<void> Function(Uint8List chunk) onData,
    required bool Function() isCancelled,
  }) async {
    HttpClientRequest req;
    try {
      req = await _client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 30));
    } catch (e) {
      return FileDownloadHandle(
        completed: false,
        failures: [DownloadFailure(relativePath: url, message: _describe(e))],
      );
    }

    req.followRedirects = true;
    req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    req.headers.set(HttpHeaders.acceptLanguageHeader, 'zh-CN,zh;q=0.9');
    req.headers.set(HttpHeaders.acceptHeader, '*/*');
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      req.headers.set(HttpHeaders.cookieHeader, cookieHeader);
    }

    HttpClientResponse res;
    try {
      res = await req.close().timeout(timeout);
    } catch (e) {
      return FileDownloadHandle(
        completed: false,
        failures: [DownloadFailure(relativePath: url, message: _describe(e))],
      );
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final hint = res.statusCode == 403 ? '（链接可能已过期，请刷新后重试）' : '';
      return FileDownloadHandle(
        completed: false,
        failures: [
          DownloadFailure(relativePath: url, message: 'HTTP ${res.statusCode}$hint'),
        ],
      );
    }

    try {
      await for (final chunk in res) {
        if (isCancelled()) return const FileDownloadHandle(completed: false);
        if (chunk.isEmpty) continue;
        await onData(Uint8List.fromList(chunk));
      }
    } catch (e) {
      return FileDownloadHandle(
        completed: false,
        failures: [DownloadFailure(relativePath: url, message: _describe(e))],
      );
    }

    return const FileDownloadHandle(completed: true);
  }

  void close() => _client.close(force: true);

  static String _describe(Object e) {
    if (e is SocketException) return '网络错误：${e.message}';
    if (e is TimeoutException) return '连接超时';
    if (e is HttpException) return e.message;
    return e.toString().replaceFirst('Exception: ', '');
  }
}

/// 用 dart:io 写文件。
class IoFileSink implements FileSink {
  IoFileSink({Directory? root, this.folderName = 'eLearning'}) : _explicitRoot = root;

  final Directory? _explicitRoot;
  final String folderName;
  Directory? _cached;

  @override
  Future<String> root() async {
    if (_cached != null) return _cached!.path;
    final base = _explicitRoot ?? await _defaultBase();
    final dir = Directory('${base.path}/$folderName');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cached = dir;
    return dir.path;
  }

  /// Android 用应用专属外部目录（用户能在文件管理器里找到，
  /// 且不需要任何存储权限）；iOS 用文档目录。
  static Future<Directory> _defaultBase() async {
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext;
    }
    return getApplicationDocumentsDirectory();
  }

  @override
  Future<bool> existsWithSize(String absolutePath, int size) async {
    final f = File(absolutePath);
    if (!await f.exists()) return false;
    return await f.length() == size;
  }

  @override
  Future<void> ensureDir(String absolutePath) async {
    final parent = File(absolutePath).parent;
    if (!await parent.exists()) await parent.create(recursive: true);
  }

  @override
  Future<void> append(String absolutePath, Uint8List chunk) async {
    // 用追加模式：每次只把这一块写进去，不在内存里攒整个文件。
    await File(absolutePath).writeAsBytes(chunk, mode: FileMode.append, flush: false);
  }

  @override
  Future<void> finish(String partPath) async {
    final target = partPath.endsWith('.part')
        ? partPath.substring(0, partPath.length - 5)
        : partPath;
    final targetFile = File(target);
    if (await targetFile.exists()) await targetFile.delete();
    await File(partPath).rename(target);
  }

  @override
  Future<void> discard(String partPath) async {
    final f = File(partPath);
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {
        // 清理失败不该让整个任务崩掉。
      }
    }
  }
}
