/// 拉取并组装快照。
///
/// 成绩计算在 `scoring.dart`（纯函数，界面层可复用）；
/// 这里只负责和 Canvas 通信并把结果拼起来。

library;

import 'canvas.dart';
import 'errors.dart';
import 'refresh.dart';
import 'scoring.dart';
import 'types.dart';

/// 并发跑 [fn]，最多 [limit] 个同时在飞。
Future<List<R>> _mapPool<T, R>(
  List<T> items,
  int limit,
  Future<R> Function(T item, int index) fn,
) async {
  final out = List<R?>.filled(items.length, null);
  var cursor = 0;

  Future<void> worker() async {
    while (true) {
      final i = cursor++;
      if (i >= items.length) return;
      out[i] = await fn(items[i], i);
    }
  }

  final n = limit < items.length ? limit : items.length;
  await Future.wait(List.generate(n < 1 ? 1 : n, (_) => worker()));
  return out.cast<R>();
}

/// 401/403 到底是「会话失效」还是「这一门课没权限」？
///
/// **Canvas 对两者都返回 401**，只看状态码分不出来。所以用一个轻量请求探一下：
/// 探针还活着 → 是课程级权限问题；探针也挂了 → 会话真的失效了。
///
/// 为什么必须区分：不区分的话，一门访问不了的课会让整次刷新中断，
/// 界面报一句「登录状态已失效」——而用户其实是刚登录成功的。
/// 这个坑真实发生过（课程 94313 无权限，导致整个应用看起来登录不上）。
Future<bool> _sessionIsDead(CanvasClient client, Object error) async {
  if (error is! CanvasException || !error.isAuthFailure) return false;
  try {
    await client.getProfile();
    return false; // 探针成功，会话没问题
  } catch (_) {
    return true; // 探针也 401，会话确实失效了
  }
}

/// 课程级 401 的人话描述。
///
/// 不能直接走 [describeCanvasError]——它对 401 会返回
/// 「登录状态已失效，请重新登录。」，在这个语境下是误导。
String _authWarning(Object error) {
  final code = error is CanvasException ? error.statusCode : 0;
  return '无权访问（HTTP $code），已跳过这门课';
}

Future<List<AssignmentRow>> _fetchCourseAssignments(
  CanvasClient client,
  CanvasCourse course,
  String displayName,
  List<String> warnings,
) async {
  var groupById = <int, ({String name, double weight})>{};
  try {
    final groups = await client.getAssignmentGroups(course.id);
    groupById = {
      for (final g in groups) g.id: (name: g.name, weight: g.groupWeight),
    };
  } catch (e) {
    if (await _sessionIsDead(client, e)) rethrow;
    final msg = (e is CanvasException && e.isAuthFailure)
        ? '作业分组$_authWarning(e)'
        : '作业分组获取失败（${describeCanvasError(e)}）';
    warnings.add('$displayName：$msg');
  }

  try {
    final assignments = await client.getAssignments(course.id);
    return toAssignmentRows(course, displayName, assignments, groupById);
  } catch (e) {
    if (await _sessionIsDead(client, e)) rethrow;
    final msg = (e is CanvasException && e.isAuthFailure)
        ? _authWarning(e)
        : '作业列表获取失败（${describeCanvasError(e)}）';
    warnings.add('$displayName：$msg');
    return const [];
  }
}

class BuildSnapshotOptions {
  const BuildSnapshotOptions({
    this.enrollmentState = 'all',
    this.onProgress,
    this.previous,
    this.full = false,
  });

  final String enrollmentState;
  final void Function(int done, int total, String label)? onProgress;

  /// 上一次的快照。已结束学期的课程直接沿用它的汇总与作业行，不再发请求。
  final Snapshot? previous;

  /// 强制全量刷新，忽略 [previous] 里的历史学期数据。
  final bool full;
}

Future<Snapshot> buildSnapshot(CanvasClient client, [BuildSnapshotOptions options = const BuildSnapshotOptions()]) async {
  final warnings = <String>[];

  final profile = await client.getProfile();

  var courses = (await client.getCourses(enrollmentState: options.enrollmentState))
      .where((c) => c.workflowState == 'available')
      .toList();

  // 某些 Canvas 部署会拒绝更丰富的 include。与其显示空看板，
  // 不如退回最小请求——成绩本来就会在本地按作业重算。
  if (courses.isEmpty) {
    try {
      final basic = (await client.getCourses(includeTotalScores: false))
          .where((c) => c.workflowState == 'available')
          .toList();
      if (basic.isNotEmpty) {
        courses = basic;
        warnings.add('带成绩的课程列表请求被拒绝，已改用基础列表（得分由本地根据作业重新计算）。');
      }
    } catch (_) {
      // 保留原本的空结果。
    }
  }

  var nicknames = <int, String>{};
  try {
    final list = await client.getCourseNicknames();
    nicknames = {
      for (final n in list) n.courseId: (n.nickname?.isNotEmpty ?? false) ? n.nickname! : n.name,
    };
  } catch (e) {
    warnings.add('课程昵称获取失败：${describeCanvasError(e)}');
  }

  final allRows = <AssignmentRow>[];
  final termInfo = collectTermInfo(courses);

  // --- 刷新范围 -------------------------------------------------------------
  // 已结束学期的课不会再变，沿用上次的汇总与作业行，省下每门课两个请求。
  final prev = options.previous;
  final ids = cachedIds(
    prev?.courses.map((c) => c.id) ?? const <int>[],
    prev?.assignments.map((a) => a.courseId) ?? const <int>[],
  );
  final plan = planRefresh<CanvasCourse>(
    courses,
    (c) => c.id,
    (c) => resolveTerm(c, termInfo).endAt,
    RefreshInputs(
      full: options.full,
      now: DateTime.now().millisecondsSinceEpoch,
      cachedCourseIds: ids.courseIds,
      cachedRowCourseIds: ids.rowCourseIds,
    ),
  );

  final reused = <CourseSummary>[];
  if (plan.reuse.isNotEmpty && prev != null) {
    final wanted = plan.reuse.map((c) => c.id).toSet();
    reused.addAll(prev.courses.where((c) => wanted.contains(c.id)));
    allRows.addAll(prev.assignments.where((a) => wanted.contains(a.courseId)));
  }

  var done = 0;
  final fetched = await _mapPool<CanvasCourse, CourseSummary>(plan.fetch, 4, (course, _) async {
    final nickname = nicknames[course.id];
    final displayName = (nickname != null && nickname.isNotEmpty) ? nickname : course.name;
    final term = resolveTerm(course, termInfo);
    final rows = await _fetchCourseAssignments(client, course, displayName, warnings);
    allRows.addAll(rows);
    done++;
    options.onProgress?.call(done, plan.fetch.length, displayName);
    return summariseCourse(course, displayName, nickname, rows, term);
  });

  final summaries = [...reused, ...fetched];

  // 待办事项 --------------------------------------------------------------
  final todo = <TodoEntry>[];
  try {
    final items = await client.getTodo();
    String nameFor(int? id) {
      if (id == null) return '';
      for (final c in summaries) {
        if (c.id == id) return c.displayName;
      }
      return '课程 $id';
    }

    for (final item in items) {
      final a = item.assignment;
      if (a != null) {
        todo.add(TodoEntry(
          title: a.name,
          courseId: item.courseId ?? a.courseId,
          courseName: nameFor(item.courseId ?? a.courseId),
          dueAt: a.dueAt,
          pointsPossible: a.pointsPossible,
          htmlUrl: a.htmlUrl ?? item.htmlUrl,
          kind: 'assignment',
        ));
      } else if (item.quiz != null) {
        final q = item.quiz!;
        todo.add(TodoEntry(
          title: (q['title'] as String?) ?? '',
          courseId: item.courseId,
          courseName: nameFor(item.courseId),
          dueAt: q['due_at'] as String?,
          pointsPossible: (q['points_possible'] as num?)?.toDouble(),
          htmlUrl: q['html_url'] as String?,
          kind: 'quiz',
        ));
      }
    }
  } catch (e) {
    warnings.add('待办事项获取失败：${describeCanvasError(e)}');
  }

  todo.sort((a, b) {
    final ta = a.dueAt == null ? null : DateTime.tryParse(a.dueAt!);
    final tb = b.dueAt == null ? null : DateTime.tryParse(b.dueAt!);
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return ta.compareTo(tb);
  });

  summaries.sort((a, b) => a.displayName.compareTo(b.displayName));

  allRows.sort((a, b) {
    final ta = a.dueAt == null ? null : DateTime.tryParse(a.dueAt!);
    final tb = b.dueAt == null ? null : DateTime.tryParse(b.dueAt!);
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return tb.compareTo(ta);
  });

  return Snapshot(
    fetchedAt: DateTime.now().toIso8601String(),
    profile: profile,
    courses: summaries,
    terms: buildTermGroups(summaries),
    assignments: allRows,
    todo: todo,
    warnings: warnings,
    // 这次刷新沿用了多少门已结束学期的课（没有为它们发请求）。
    reusedCourseCount: reused.length,
  );
}
