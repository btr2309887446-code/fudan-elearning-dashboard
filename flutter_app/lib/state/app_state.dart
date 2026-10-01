/// 应用状态。
///
/// 界面只跟这一层打交道，网络与认证细节都封在 core 里。
/// 这样 widget 测试可以塞入演示数据或假传输层，完全不联网。

library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/aggregate.dart';
import '../core/canvas.dart';
import '../core/cookies.dart';
import '../core/demo.dart';
import '../core/errors.dart';
import '../core/files.dart';
import '../core/http.dart';
import '../core/rsa.dart';
import '../core/scoring.dart';
import '../core/session.dart';
import '../core/summary.dart';
import '../core/types.dart';
import '../core/uis.dart';
import '../platform/downloads.dart';
import '../platform/file_io.dart';

/// 编译期开关：`flutter run --dart-define=DEMO=true` 用演示数据启动。
const bool kDemoMode = bool.fromEnvironment('DEMO');

class AppPrefs {
  const AppPrefs({
    this.themeMode = ThemeMode.system,
    this.hideUnsubmitted = false,
    this.enrollmentState = 'all',
    this.rememberedUsername = '',
    this.rememberPassword = false,
    this.dashboardSections = const {},
    this.llm = defaultLlm,
  });

  final ThemeMode themeMode;

  /// 隐藏尚未提交的作业。只影响显示，不影响得分计算。
  final bool hideUnsubmitted;
  final String enrollmentState;
  final String rememberedUsername;
  final bool rememberPassword;

  /// 首页各板块的显示开关；缺省视为全开。
  final Map<String, bool> dashboardSections;

  /// 作业简介用的大模型接口；未配置时降级为截取描述前 100 字。
  final LlmConfig llm;

  AppPrefs copyWith({
    ThemeMode? themeMode,
    bool? hideUnsubmitted,
    String? enrollmentState,
    String? rememberedUsername,
    bool? rememberPassword,
    Map<String, bool>? dashboardSections,
    LlmConfig? llm,
  }) =>
      AppPrefs(
        themeMode: themeMode ?? this.themeMode,
        hideUnsubmitted: hideUnsubmitted ?? this.hideUnsubmitted,
        enrollmentState: enrollmentState ?? this.enrollmentState,
        rememberedUsername: rememberedUsername ?? this.rememberedUsername,
        rememberPassword: rememberPassword ?? this.rememberPassword,
        dashboardSections: dashboardSections ?? this.dashboardSections,
        llm: llm ?? this.llm,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'hideUnsubmitted': hideUnsubmitted,
        'enrollmentState': enrollmentState,
        'rememberedUsername': rememberedUsername,
        'rememberPassword': rememberPassword,
        'dashboardSections': dashboardSections,
        'llm': llm.toJson(),
      };

  factory AppPrefs.fromJson(Map<String, dynamic> json) => AppPrefs(
        themeMode: ThemeMode.values.firstWhere(
          (m) => m.name == json['themeMode'],
          orElse: () => ThemeMode.system,
        ),
        hideUnsubmitted: json['hideUnsubmitted'] == true,
        enrollmentState: (json['enrollmentState'] as String?) ?? 'all',
        rememberedUsername: (json['rememberedUsername'] as String?) ?? '',
        rememberPassword: json['rememberPassword'] == true,
        dashboardSections: ((json['dashboardSections'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v == true)),
        llm: json['llm'] is Map<String, dynamic>
            ? LlmConfig.fromJson(json['llm'] as Map<String, dynamic>)
            : defaultLlm,
      );
}

/// 登录准备阶段的结果：告诉界面要不要显示验证码。
class LoginPrep {
  const LoginPrep({required this.captchaRequired, this.captchaImage});
  final bool captchaRequired;
  final String? captchaImage;
}

class AppState extends ChangeNotifier {
  AppState({required this.store, this.secure, this.demo = kDemoMode});

  final KeyValueStore store;
  final SecretStoreLike? secure;
  final bool demo;

  late final SessionRepository _repo = SessionRepository(store);

  AppPrefs prefs = const AppPrefs();
  CookieJar? _jar;
  LoginContext? _pendingLogin;

  Snapshot? snapshot;
  bool busy = false;
  bool booting = true;
  String? error;
  String? notice;
  ({int done, int total, String label})? progress;

  bool get loggedIn => _jar != null || demo;

  // --- 启动 ------------------------------------------------------------------

  Future<void> boot() async {
    booting = true;
    notifyListeners();

    await _loadPrefs();

    if (demo) {
      snapshot = buildDemoSnapshot();
      booting = false;
      notifyListeners();
      return;
    }

    // 先把上次的缓存显示出来，再联网刷新。
    final cached = await _repo.readSnapshot();
    if (cached != null) {
      try {
        final parsed = normaliseSnapshot(jsonDecode(cached) as Map<String, dynamic>);
        if (parsed != null) snapshot = parsed;
      } catch (_) {
        await _repo.clearSnapshot();
      }
    }

    final session = await _repo.readSession();
    if (session != null) {
      final jar = CookieJar.fromJsonString(session);
      final client = CanvasClient(HttpClientLite(jar: jar));
      try {
        await client.getProfile();
        _jar = jar;
      } catch (_) {
        _jar = null;
        notice = '登录状态已失效，重新登录后可刷新数据。你仍可查看上次同步的内容。';
      }
    }

    booting = false;
    notifyListeners();

    if (_jar != null) await refresh();
  }

  Future<void> _loadPrefs() async {
    final raw = await _repo.readPrefs();
    if (raw != null) {
      try {
        prefs = AppPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        prefs = const AppPrefs();
      }
    }
  }

  Future<void> _savePrefs() => _repo.writePrefs(jsonEncode(prefs.toJson()));

  Future<void> setThemeMode(ThemeMode mode) async {
    prefs = prefs.copyWith(themeMode: mode);
    notifyListeners();
    await _savePrefs();
  }

  Future<void> setHideUnsubmitted(bool value) async {
    prefs = prefs.copyWith(hideUnsubmitted: value);
    notifyListeners();
    await _savePrefs();
  }

  // --- 登录 ------------------------------------------------------------------

  /// 第一步：抵达认证服务器，并问清楚这次要不要验证码。
  ///
  /// 先问再交，是为了避免明知会失败还消耗一次尝试——学校会锁账号。
  Future<LoginPrep> prepareLogin(String username) async {
    error = null;
    _pendingLogin = await beginLogin(jar: CookieJar(), encryptor: rsaPkcs1Encrypt);
    final captcha = await checkCaptcha(_pendingLogin!, username);
    return LoginPrep(captchaRequired: captcha.required, captchaImage: captcha.image);
  }

  /// 第二步：真正消耗一次认证尝试。
  Future<bool> submitLogin({
    required String username,
    required String password,
    String? captchaCode,
    bool remember = false,
  }) async {
    try {
      error = null;
      final ctx = _pendingLogin ?? await beginLogin(jar: CookieJar(), encryptor: rsaPkcs1Encrypt);
      _pendingLogin = null;

      final result = await completeLogin(
        ctx,
        Credentials(username: username, password: password, captchaCode: captchaCode),
      );

      final client = CanvasClient(HttpClientLite(jar: result.jar));
      // 确认会话真的有效，再落盘。
      await client.getProfile();

      _jar = result.jar;
      await _repo.writeSession(result.jar.toJsonString());

      prefs = prefs.copyWith(rememberedUsername: username, rememberPassword: remember);
      await _savePrefs();

      final secrets = secure;
      if (secrets != null) {
        if (remember) {
          await secrets.writePassword(password);
        } else {
          await secrets.deletePassword();
        }
      }

      snapshot = null;
      notifyListeners();
      await refresh(force: true);
      return true;
    } catch (e) {
      error = e is LoginException ? e.message : describeCanvasError(e);
      notifyListeners();
      return false;
    }
  }

  Future<String?> rememberedPassword() async => secure?.readPassword();

  Future<void> logout() async {
    _jar = null;
    snapshot = null;
    await _repo.clearAll();
    final secrets = secure;
    if (secrets != null) await secrets.deletePassword();
    prefs = prefs.copyWith(rememberPassword: false);
    await _savePrefs();
    notifyListeners();
  }

  // --- 数据 ------------------------------------------------------------------

  Future<void> refresh({bool force = false}) async {
    if (demo) {
      snapshot = buildDemoSnapshot();
      notifyListeners();
      return;
    }
    final jar = _jar;
    if (jar == null) return;

    busy = true;
    error = null;
    progress = null;
    notifyListeners();

    try {
      final http = HttpClientLite(jar: jar);
      final client = CanvasClient(http);
      final built = await buildSnapshot(
        client,
        BuildSnapshotOptions(
          enrollmentState: prefs.enrollmentState,
          onProgress: (done, total, label) {
            progress = (done: done, total: total, label: label);
            notifyListeners();
          },
        ),
      );

      snapshot = built;
      notice = null;
      await _repo.writeSnapshot(jsonEncode(built.toJson()));
      await _repo.writeSession(jar.toJsonString());
    } catch (e) {
      if (e is CanvasException && e.isAuthFailure) {
        _jar = null;
        await _repo.clearSession();
        notice = '登录状态已失效，请重新登录。';
      } else {
        error = describeCanvasError(e);
      }
    } finally {
      busy = false;
      progress = null;
      notifyListeners();
    }
  }

  Future<void> clearCache() async {
    await _repo.clearAll();
    _jar = null;
    snapshot = null;
    notifyListeners();
  }

  // --- 课程文件 -------------------------------------------------------------

  /// 按课程 id 缓存已取回的文件树，避免反复展开收起时重复打接口。
  final Map<int, FileNode> _fileTrees = {};

  Future<FileNode> loadCourseFiles(int courseId, {bool force = false}) async {
    if (!force && _fileTrees.containsKey(courseId)) return _fileTrees[courseId]!;
    if (demo) {
      final tree = buildDemoFileTree(courseId);
      _fileTrees[courseId] = tree;
      return tree;
    }
    final jar = _jar;
    if (jar == null) throw StateError('尚未登录');
    final client = CanvasClient(HttpClientLite(jar: jar));
    final results = await Future.wait([
      client.getCourseFolders(courseId),
      client.getCourseFiles(courseId),
    ]);
    final tree = buildFileTree(
      results[0] as List<CanvasFolder>,
      results[1] as List<CanvasFile>,
    );
    _fileTrees[courseId] = tree;
    return tree;
  }

  /// 正在进行的下载，用于让界面显示「取消」。
  Downloader? _activeDownload;

  DownloadProgress? downloadProgress;
  bool get downloading => _activeDownload != null;

  void cancelDownload() {
    _activeDownload?.cancel();
    _activeDownload = null;
    notifyListeners();
  }

  /// 下载选中的文件；[fileIds] 为空表示整门课。
  ///
  /// 磁盘路径由这里统一算：学期 / 课程 / Canvas 子文件夹 / 文件名。
  Future<DownloadProgress?> downloadCourseFiles(int courseId, {List<int>? fileIds}) async {
    if (_activeDownload != null) return null;

    final tree = await loadCourseFiles(courseId);
    final all = flattenFiles(tree);
    final wanted = (fileIds != null && fileIds.isNotEmpty)
        ? all.where((n) => n.file != null && fileIds.contains(n.file!.id)).toList()
        : all;

    if (wanted.isEmpty) return null;

    final course = snapshot?.courses.firstWhere(
      (c) => c.id == courseId,
      orElse: () => CourseSummary(
        id: courseId,
        name: '课程 $courseId',
        displayName: '课程 $courseId',
        courseCode: '',
        termName: '未分学期',
      ),
    );
    final termName = (course?.termName.isNotEmpty ?? false) ? course!.termName : '未分学期';
    final courseName = (course?.displayName.isNotEmpty ?? false) ? course!.displayName : '课程 $courseId';

    final plan = planDownloadPaths(
      termName,
      courseName,
      wanted.map((n) {
        final slash = n.path.lastIndexOf('/');
        return (
          folderPath: slash < 0 ? '' : n.path.substring(0, slash),
          fileName: n.name,
          file: n.file!,
        );
      }).toList(),
    );

    final items = [
      for (var i = 0; i < plan.length; i++)
        DownloadItem(
          url: plan[i].file.url,
          relativePath: plan[i].relativePath,
          size: plan[i].file.size,
          name: wanted[i].name,
        ),
    ];

    if (demo) return _simulateDemoDownload(items);

    final jar = _jar;
    if (jar == null) throw StateError('尚未登录');

    final transport = IoFileTransport();
    final downloader = Downloader(
      transport: transport,
      sink: IoFileSink(),
      cookies: jar,
      onProgress: (p) {
        downloadProgress = p;
        notifyListeners();
      },
    );
    _activeDownload = downloader;

    try {
      final result = await downloader.run(items);
      downloadProgress = result;
      return result;
    } finally {
      _activeDownload = null;
      transport.close();
      notifyListeners();
    }
  }

  /// 演示模式：不联网、不落盘，只把进度走一遍。
  Future<DownloadProgress> _simulateDemoDownload(List<DownloadItem> items) async {
    final progress = DownloadProgress(
      total: items.length,
      bytesTotal: items.fold(0, (s, i) => s + i.size),
    );
    downloadProgress = progress;
    notifyListeners();

    const steps = 12;
    for (final item in items) {
      progress.currentName = item.name;
      progress.currentTotal = item.size;
      progress.currentReceived = 0;
      for (var s = 0; s < steps; s++) {
        await Future<void>.delayed(const Duration(milliseconds: 45));
        final delta = item.size ~/ steps;
        progress.currentReceived += delta;
        progress.bytesReceived += delta;
        downloadProgress = progress.copy();
        notifyListeners();
      }
      progress.completed += 1;
    }
    progress.state = DownloadState.done;
    progress.currentName = '';
    progress.skipped = 1;
    downloadProgress = progress.copy();
    notifyListeners();
    return downloadProgress!;
  }

  // --- 首页板块 -------------------------------------------------------------

  /// 用系统浏览器打开 Canvas 网页版。
  ///
  /// 富文本说明、附件与提交入口只有网页版有，所以详情页留了这个出口。
  Future<void> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      error = '打不开浏览器：${e.toString().replaceFirst('Exception: ', '')}';
      notifyListeners();
    }
  }

  /// 板块开关。未出现的板块视为显示，这样新增板块时老用户也能看到。
  Future<void> toggleDashboardSection(String key) async {
    final next = Map<String, bool>.from(prefs.dashboardSections);
    next[key] = prefs.dashboardSections[key] == false;
    prefs = prefs.copyWith(dashboardSections: next);
    notifyListeners();
    await _savePrefs();
  }

  // --- 大模型配置 -----------------------------------------------------------

  Future<void> setLlm(LlmConfig cfg) async {
    prefs = prefs.copyWith(llm: cfg);
    notifyListeners();
    await _savePrefs();
  }

  // --- 作业详情与简介 -------------------------------------------------------

  /// 简介缓存，键是 [summaryCacheKey]。
  final Map<String, String> _summaryCache = {};

  static const int _summaryCacheLimit = 400;

  /// 取作业详情并生成 100 字以内简介。
  ///
  /// 完整说明按需拉取（快照里只有 600 字摘录）；[excerptHint] 是本地已有的摘录，
  /// 网络失败时用它兜底，不至于白屏。
  Future<({String description, String summary, String source, String? error})> loadAssignmentDetail({
    required int courseId,
    required int assignmentId,
    required String name,
    String? excerptHint,
  }) async {
    String description = '';

    if (demo) {
      description = excerptHint ?? '';
    } else {
      final jar = _jar;
      if (jar == null) {
        return (
          description: excerptHint ?? '',
          summary: fallbackSummary(excerptHint),
          source: 'fallback',
          error: '尚未登录',
        );
      }
      try {
        final client = CanvasClient(HttpClientLite(jar: jar));
        final a = await client.getAssignment(courseId, assignmentId);
        description = a.description ?? '';
      } catch (e) {
        return (
          description: excerptHint ?? '',
          summary: fallbackSummary(excerptHint),
          source: 'fallback',
          error: e.toString().replaceFirst('Exception: ', ''),
        );
      }
    }

    final key = summaryCacheKey(assignmentId, description);
    final cached = _summaryCache[key];
    if (cached != null) {
      return (description: description, summary: cached, source: 'fallback', error: null);
    }

    final result = await summarizeAssignment(name, description, prefs.llm);
    if (result.summary.isNotEmpty) {
      _summaryCache[key] = result.summary;
      if (_summaryCache.length > _summaryCacheLimit) {
        for (final k in _summaryCache.keys.take(_summaryCache.length - _summaryCacheLimit).toList()) {
          _summaryCache.remove(k);
        }
      }
    }
    return (
      description: description,
      summary: result.summary,
      source: result.source,
      error: result.error,
    );
  }
}
