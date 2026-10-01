/// Canvas LMS REST 客户端（elearning.fudan.edu.cn）。
///
/// 认证靠 UIS 登录产出的会话 Cookie，所以这里全是带 Cookie 的 GET。
/// Canvas 用 `Link: <...>; rel="next"` 头分页，[getAllPages] 会一直跟到底。

library;

import 'dart:convert';

import 'endpoints.dart';
import 'errors.dart';
import 'files.dart';
import 'http.dart';
import 'types.dart';

class CanvasClient {
  CanvasClient(this.http);

  final HttpClientLite http;

  /// 构造查询串，数组按 Canvas 习惯展开为 `key[]=v1&key[]=v2`。
  static String buildQuery(Map<String, Object?>? params) {
    if (params == null || params.isEmpty) return '';
    final parts = <String>[];
    params.forEach((key, value) {
      if (value == null) return;
      if (value is List) {
        for (final v in value) {
          if (v == null) continue;
          parts.add('${Uri.encodeQueryComponent('$key[]')}=${Uri.encodeQueryComponent('$v')}');
        }
      } else {
        parts.add('${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent('$value')}');
      }
    });
    return parts.isEmpty ? '' : '?${parts.join('&')}';
  }

  /// 从 Canvas 的 Link 头里取出 `rel="next"`。
  static String? parseNextLink(String? linkHeader) {
    if (linkHeader == null || linkHeader.isEmpty) return null;
    for (final part in linkHeader.split(',')) {
      final m = RegExp(r'<([^>]+)>\s*;\s*rel\s*=\s*"?([^";]+)"?').firstMatch(part.trim());
      if (m != null && m.group(2)!.trim() == 'next') return m.group(1);
    }
    return null;
  }

  Future<({dynamic data, String? link})> _fetchJson(String url) async {
    final res = await http.request(url, const HttpRequestOptions(
      timeout: Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
    ));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw CanvasException(res.statusCode, url, res.body);
    }

    dynamic data;
    try {
      data = jsonDecode(res.body);
    } catch (_) {
      final snippet = res.body.length > 200 ? res.body.substring(0, 200) : res.body;
      throw CanvasException(res.statusCode, url, '响应不是合法 JSON：$snippet');
    }
    return (data: data, link: res.header('link'));
  }

  Future<dynamic> get(String path, [Map<String, Object?>? params]) async {
    final url = path.startsWith('http') ? path : '$canvasBase$path${buildQuery(params)}';
    final res = await _fetchJson(url);
    return res.data;
  }

  /// 跟随 Canvas 分页直到取完（带页数上限以防意外）。
  ///
  /// [parse] 是**必填**的，这是刻意的：
  ///
  /// 原先的写法是 `data.whereType<T>()`，看起来聪明，实际上永远返回空——
  /// JSON 解出来的是 `Map<String, dynamic>`，`whereType<CanvasAssignment>()`
  /// 一个都匹配不上。结果就是作业和作业分组在任何平台上恒为空，
  /// 而课程还能正常显示（因为它恰好走了「先取 Map 再 map」的写法）。
  ///
  /// 改成显式传解析函数后，类型系统就挡住这类错误了：
  /// 想让 T 是模型类型，就必须给出 `T Function(Map)`；给不出就说明写错了。
  Future<List<T>> getAllPages<T>(
    String path,
    Map<String, Object?>? params,
    T Function(Map<String, dynamic>) parse, {
    int maxPages = 40,
  }) async {
    String? url = path.startsWith('http') ? path : '$canvasBase$path${buildQuery(params)}';
    final out = <T>[];
    var pages = 0;

    while (url != null && pages < maxPages) {
      final res = await _fetchJson(url);
      final data = res.data;
      if (data is List) {
        for (final item in data) {
          if (item is Map<String, dynamic>) out.add(parse(item));
        }
      }
      url = parseNextLink(res.link);
      pages++;
    }
    return out;
  }

  // --- 接口 ------------------------------------------------------------------

  Future<CanvasProfile> getProfile() async {
    final data = await get('/api/v1/users/self/profile');
    return CanvasProfile.fromJson(data as Map<String, dynamic>);
  }

  /// 当前用户的课程，内联自己的选课记录（成绩就在里面），并带上学期。
  ///
  /// `include[]=total_scores` 需要配合 enrollment_state 才会返回成绩，
  /// 所以显式传 'active'；传 'all' 时不加过滤。
  /// 另外把已结束的选课也合并进来——某些部署会把结课课程从默认列表里省略。
  Future<List<CanvasCourse>> getCourses({
    String enrollmentState = 'all',
    bool includeTotalScores = true,
  }) async {
    final includes = <String>['enrollments', 'term'];
    if (includeTotalScores) includes.add('total_scores');

    final base = await getAllPages(
      '/api/v1/courses',
      {'include': includes, 'per_page': 100},
        (m) => m,
    );
    final courses = base.map(CanvasCourse.fromJson).toList();

    if (enrollmentState == 'active') {
      final now = DateTime.now();
      return courses.where((c) {
        final end = c.endAt ?? c.term?.endAt;
        if (end == null) return true;
        final t = DateTime.tryParse(end);
        return t == null || t.isAfter(now);
      }).toList();
    }

    final merged = <int, CanvasCourse>{for (final c in courses) c.id: c};
    try {
      final completed = await getAllPages(
        '/api/v1/courses',
        {'include': includes, 'per_page': 100, 'enrollment_state': 'completed'},
        (m) => m,
      );
      for (final raw in completed) {
        final c = CanvasCourse.fromJson(raw);
        merged.putIfAbsent(c.id, () => c);
      }
    } catch (_) {
      // 已结课的课程是锦上添花，不能因此让整次刷新失败。
    }
    return merged.values.toList();
  }

  Future<List<CanvasAssignmentGroup>> getAssignmentGroups(int courseId) => getAllPages(
        '/api/v1/courses/$courseId/assignment_groups',
        {'per_page': 100},
        CanvasAssignmentGroup.fromJson,
      );

  /// 某门课的作业，每条都带上当前用户的提交记录。
  Future<List<CanvasAssignment>> getAssignments(int courseId) =>
      getAllPages(
        '/api/v1/courses/$courseId/assignments',
        {'include': ['submission'], 'per_page': 100, 'order_by': 'due_at'},
        CanvasAssignment.fromJson,
      );

  /// 单条作业，带完整 description。
  ///
  /// 列表接口也会返回 description，但那条数据不进本地缓存
  ///（单条常有几十 KB）。详情页按需拉一次。
  Future<CanvasAssignment> getAssignment(int courseId, int assignmentId) async {
    final data = await get(
      '/api/v1/courses/$courseId/assignments/$assignmentId',
      {'include': ['submission']},
    );
    if (data is! Map<String, dynamic>) {
      throw CanvasException(0, '/api/v1/courses/$courseId/assignments/$assignmentId', '作业详情返回了非预期的格式');
    }
    return CanvasAssignment.fromJson(data);
  }

  Future<List<CanvasTodoItem>> getTodo() async {
    final data = await get('/api/v1/users/self/todo');
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().map(CanvasTodoItem.fromJson).toList();
  }

  Future<List<CanvasNickname>> getCourseNicknames() => getAllPages(
        '/api/v1/users/self/course_nicknames',
        {'per_page': 100},
        CanvasNickname.fromJson,
      );

  /// 课程里的文件夹（扁平列表，用 parent_folder_id 表达层级）。
  Future<List<CanvasFolder>> getCourseFolders(int courseId) async {
    final rows = await getAllPages(
      '/api/v1/courses/$courseId/folders',
      {'per_page': 100},
        (m) => m,
    );
    return rows.map(CanvasFolder.fromJson).toList();
  }

  /// 课程里的文件（扁平列表，用 folder_id 归属到文件夹）。
  Future<List<CanvasFile>> getCourseFiles(int courseId) async {
    final rows = await getAllPages(
      '/api/v1/courses/$courseId/files',
      {'per_page': 100},
        (m) => m,
    );
    // 隐藏的、以及没有下载地址的（通常是锁定文件）直接丢掉，界面上点了也没用。
    return rows
        .map(CanvasFile.fromJson)
        .where((f) => !f.hidden && f.url.isNotEmpty)
        .toList();
  }
}
