/// 拉取并组装快照。
///
/// 成绩计算在 `scoring.dart`（纯函数，界面层可复用）；
/// 这里只负责和 Canvas 通信并把结果拼起来。

library;

import 'canvas.dart';
import 'errors.dart';
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
    warnings.add('$displayName：作业分组获取失败（${describeCanvasError(e)}）');
  }

  try {
    final assignments = await client.getAssignments(course.id);
    return toAssignmentRows(course, displayName, assignments, groupById);
  } catch (e) {
    // 会话失效必须中断整次刷新，而不是悄悄降级。
    if (e is CanvasException && e.isAuthFailure) rethrow;
    warnings.add('$displayName：作业列表获取失败（${describeCanvasError(e)}）');
    return const [];
  }
}

class BuildSnapshotOptions {
  const BuildSnapshotOptions({
    this.enrollmentState = 'all',
    this.onProgress,
  });

  final String enrollmentState;
  final void Function(int done, int total, String label)? onProgress;
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
  var done = 0;

  final summaries = await _mapPool<CanvasCourse, CourseSummary>(courses, 4, (course, _) async {
    final nickname = nicknames[course.id];
    final displayName = (nickname != null && nickname.isNotEmpty) ? nickname : course.name;
    final term = resolveTerm(course, termInfo);
    final rows = await _fetchCourseAssignments(client, course, displayName, warnings);
    allRows.addAll(rows);
    done++;
    options.onProgress?.call(done, courses.length, displayName);
    return summariseCourse(course, displayName, nickname, rows, term);
  });

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
  );
}
