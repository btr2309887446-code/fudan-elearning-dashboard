import 'package:flutter/material.dart';

import '../core/ignored.dart';
import '../core/types.dart';
import '../theme.dart';
import 'format.dart';
import 'widgets.dart';

enum OverviewDetailKind { scores, courses, missing, upcoming }

class OverviewDetailScreen extends StatelessWidget {
  const OverviewDetailScreen({
    super.key,
    required this.kind,
    required this.courses,
    required this.assignments,
    required this.todo,
    required this.ignoredSet,
    required this.onOpenCourse,
    required this.onOpenAssignment,
    required this.onOpenUrl,
  });

  final OverviewDetailKind kind;
  final List<CourseSummary> courses;
  final List<AssignmentRow> assignments;
  final List<TodoEntry> todo;
  final Set<String> ignoredSet;
  final ValueChanged<int> onOpenCourse;
  final ValueChanged<AssignmentRow> onOpenAssignment;
  final ValueChanged<String> onOpenUrl;

  String get _title => switch (kind) {
        OverviewDetailKind.scores => '课程成绩',
        OverviewDetailKind.courses => '全部课程',
        OverviewDetailKind.missing => '缺交作业',
        OverviewDetailKind.upcoming => '待办事项',
      };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rows = switch (kind) {
      OverviewDetailKind.scores => <AssignmentRow>[],
      OverviewDetailKind.courses => <AssignmentRow>[],
      OverviewDetailKind.missing => assignments
          .where((a) => a.missing && !isIgnored(ignoredSet, a.courseId, a.id))
          .toList()
        ..sort(_byDue),
      OverviewDetailKind.upcoming => <AssignmentRow>[],
    };
    final courseRows = [...courses];
    if (kind == OverviewDetailKind.scores) {
      courseRows.removeWhere((c) => c.currentScore == null);
      courseRows.sort((a, b) => a.currentScore!.compareTo(b.currentScore!));
    }

    final count = switch (kind) {
      OverviewDetailKind.scores ||
      OverviewDetailKind.courses =>
        courseRows.length,
      OverviewDetailKind.missing => rows.length,
      OverviewDetailKind.upcoming => todo.length,
    };

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
            child: Text(
              '$count 项',
              style: TextStyle(color: p.muted, fontSize: 12.5),
            ),
          ),
          if (kind == OverviewDetailKind.scores ||
              kind == OverviewDetailKind.courses) ...[
            for (final course in courseRows) ...[
              CourseCard(
                course: course,
                showTerm: true,
                onTap: () => onOpenCourse(course.id),
              ),
              const SizedBox(height: 10),
            ],
          ],
          if (kind == OverviewDetailKind.missing)
            for (final row in rows) ...[
              _AssignmentCard(
                row: row,
                onTap: () => onOpenAssignment(row),
              ),
              const SizedBox(height: 8),
            ],
          if (kind == OverviewDetailKind.upcoming)
            for (final entry in todo) ...[
              _TodoCard(
                entry: entry,
                assignment: _assignmentFor(entry),
                onOpenCourse: onOpenCourse,
                onOpenAssignment: onOpenAssignment,
                onOpenUrl: onOpenUrl,
              ),
              const SizedBox(height: 8),
            ],
          if (count == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text('目前没有相关内容。',
                    style: TextStyle(color: p.muted, fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }

  /// 把待办条目对回作业行。
  ///
  /// **优先按 id 匹配。** 待办列表（`/users/self/todo`）和作业列表
  /// （`/courses/:id/assignments`）是两套数据，之前只能按标题找，
  /// 而同一门课里出现同名作业（「实验报告」「期末考试」）就会匹配到错的那条——
  /// 点进去看到的是另一次作业的详情。
  ///
  /// 标题匹配只作为退路：老快照里没有 `assignmentId` 字段。
  AssignmentRow? _assignmentFor(TodoEntry entry) {
    if (entry.assignmentId != null) {
      for (final row in assignments) {
        if (row.id == entry.assignmentId) return row;
      }
      // id 对不上就不要退化成按标题猜——那正是要避免的事。
      return null;
    }
    for (final row in assignments) {
      if (row.name == entry.title &&
          (entry.courseId == null || row.courseId == entry.courseId)) {
        return row;
      }
    }
    return null;
  }

  /// 按截止时间排序。
  ///
  /// 用 [DateTime.tryParse] 而不是 `parse`：Canvas 偶尔会给出无法解析的
  /// 时间串，`parse` 会直接抛，把整个「缺交作业」页面弄崩。
  int _byDue(AssignmentRow a, AssignmentRow b) {
    final ta = a.dueAt == null ? null : DateTime.tryParse(a.dueAt!);
    final tb = b.dueAt == null ? null : DateTime.tryParse(b.dueAt!);
    // 两个都没有截止时间时返回 0——返回 1 会让排序结果不稳定，
    // 同一个列表每次重建顺序都可能不一样。
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return ta.compareTo(tb);
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({required this.row, required this.onTap});

  final AssignmentRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${row.courseName} · ${formatDate(row.dueAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const StatusTag(label: '缺交', tone: 'bad'),
          const SizedBox(width: 3),
          Icon(Icons.chevron_right, size: 18, color: p.muted),
        ],
      ),
    );
  }
}

class _TodoCard extends StatelessWidget {
  const _TodoCard({
    required this.entry,
    required this.assignment,
    required this.onOpenCourse,
    required this.onOpenAssignment,
    required this.onOpenUrl,
  });

  final TodoEntry entry;
  final AssignmentRow? assignment;
  final ValueChanged<int> onOpenCourse;
  final ValueChanged<AssignmentRow> onOpenAssignment;
  final ValueChanged<String> onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      onTap: _open,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${entry.courseName} · ${formatDate(entry.dueAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          InfoChip(entry.kind == 'quiz' ? '测验' : '待办'),
          const SizedBox(width: 3),
          Icon(Icons.chevron_right, size: 18, color: p.muted),
        ],
      ),
    );
  }

  void _open() {
    if (assignment != null) {
      onOpenAssignment(assignment!);
    } else if (entry.courseId != null) {
      onOpenCourse(entry.courseId!);
    } else if (entry.htmlUrl != null) {
      onOpenUrl(entry.htmlUrl!);
    }
  }
}
