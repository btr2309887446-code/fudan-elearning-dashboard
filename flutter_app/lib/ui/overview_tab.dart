import 'package:flutter/material.dart';

import '../core/types.dart';
import '../theme.dart';
import 'charts.dart';
import 'format.dart';
import 'widgets.dart';

class OverviewTab extends StatelessWidget {
  const OverviewTab({
    super.key,
    required this.courses,
    required this.assignments,
    required this.todo,
    required this.termName,
    required this.hideUnsubmitted,
    required this.onSelectCourse,
  });

  final List<CourseSummary> courses;
  final List<AssignmentRow> assignments;
  final List<TodoEntry> todo;
  final String termName;
  final bool hideUnsubmitted;
  final void Function(int courseId) onSelectCourse;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    if (courses.isEmpty) {
      return Center(child: Text('这个学期没有课程数据。', style: TextStyle(color: p.muted, fontSize: 13.5)));
    }

    final avg = averageScore(courses);
    // 未提交的作业正是「缺交」的来源，忽略它就得把这个数也归零。
    final missing = hideUnsubmitted ? 0 : courses.fold<int>(0, (s, c) => s + c.missingCount);
    final late = courses.fold<int>(0, (s, c) => s + c.lateCount);
    final graded = courses.where((c) => c.currentScore != null).length;
    final upcoming = hideUnsubmitted ? 0 : todo.length;

    final now = DateTime.now();
    final soon = hideUnsubmitted
        ? <AssignmentRow>[]
        : (assignments
            .where((a) => !isCompleted(a))
            .where((a) {
              final t = a.dueAt == null ? null : DateTime.tryParse(a.dueAt!);
              return t != null && t.isAfter(now) && t.difference(now).inDays < 3;
            })
            .toList()
          ..sort((a, b) => DateTime.parse(a.dueAt!).compareTo(DateTime.parse(b.dueAt!))));

    final ranked = [...courses]..sort(courseUrgency);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // --- 统计 ---
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.show_chart,
                label: '当前平均分',
                value: formatScore(avg),
                unit: '分',
                hint: '${hideUnsubmitted ? '' : '$termName · '}$graded 门已有得分',
                tone: avg == null ? null : p.forScore(avg),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                icon: Icons.menu_book_outlined,
                label: '课程',
                value: '${courses.length}',
                unit: '门',
                hint: '共 ${assignments.length} 项作业',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: missing > 0 ? Icons.error_outline : Icons.check_circle_outline,
                label: '缺交作业',
                value: hideUnsubmitted ? '—' : '$missing',
                unit: hideUnsubmitted ? null : '项',
                hint: hideUnsubmitted
                    ? '已忽略未提交的作业'
                    : missing > 0
                        ? (late > 0 ? '另有 $late 项迟交' : '建议优先处理')
                        : '保持得不错',
                tone: !hideUnsubmitted && missing > 0 ? p.bad : p.good,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                icon: Icons.schedule,
                label: '近期待办',
                value: hideUnsubmitted ? '—' : '$upcoming',
                hint: hideUnsubmitted
                    ? '已忽略未提交的作业'
                    : (soon.isNotEmpty ? '其中 ${soon.length} 项 3 天内截止' : '暂无紧迫任务'),
                tone: !hideUnsubmitted && upcoming > 0 ? p.warn : null,
              ),
            ),
          ],
        ),

        // --- 三天内截止 ---
        if (soon.isNotEmpty) ...[
          Gap.lg,
          SectionHeader('三天内截止', icon: Icons.schedule, iconColor: p.warn, trailing: _count(soon.length)),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < soon.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.border),
                  _DueRow(row: soon[i]),
                ],
              ],
            ),
          ),
        ],

        // --- 得分图 ---
        Gap.lg,
        const SectionHeader('各课程当前得分', icon: Icons.bar_chart, iconColor: null),
        AppCard(
          child: ScoreBars(courses: courses, onTap: onSelectCourse),
        ),

        // --- 需要关注 ---
        Gap.lg,
        SectionHeader('需要关注', icon: Icons.priority_high, iconColor: p.bad),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < (ranked.length > 4 ? 4 : ranked.length); i++) ...[
                if (i > 0) Divider(height: 1, color: p.border),
                InkWell(
                  onTap: () => onSelectCourse(ranked[i].id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(
                      children: [
                        ScoreRing(score: ranked[i].currentScore, size: 40, stroke: 4.5, showLabel: false),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ranked[i].displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (!hideUnsubmitted && ranked[i].missingCount > 0)
                                    '缺交 ${ranked[i].missingCount} 项',
                                  if (ranked[i].currentScore != null)
                                    AppPalette.labelForScore(ranked[i].currentScore),
                                  '共 ${ranked[i].assignmentCount} 项',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.muted, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 19, color: p.muted),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // --- 全部课程 ---
        Gap.lg,
        SectionHeader('课程', trailing: _count(courses.length)),
        for (final c in courses) ...[
          CourseCard(
            course: c,
            onTap: () => onSelectCourse(c.id),
            showTerm: true,
            hideUnsubmitted: hideUnsubmitted,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _count(int n) => Builder(
        builder: (context) => Text('$n', style: TextStyle(color: context.palette.muted, fontSize: 12.5)),
      );
}

class _DueRow extends StatelessWidget {
  const _DueRow({required this.row});

  final AssignmentRow row;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rel = dueRelative(row.dueAt, false);
    final color = rel.tone == DueTone.overdue ? p.bad : p.warn;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  '${row.courseName} · ${formatDate(row.dueAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(rel.text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
