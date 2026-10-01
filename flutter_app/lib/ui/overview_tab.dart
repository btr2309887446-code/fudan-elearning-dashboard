import '../core/clock.dart';
import 'package:flutter/material.dart';

import '../core/ignored.dart';
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
    required this.sections,
    required this.onOpenAssignment,
    required this.sectionOrder,
    this.ignoredSet = const {},
  });

  final List<CourseSummary> courses;
  final List<AssignmentRow> assignments;
  final List<TodoEntry> todo;
  final String termName;
  final bool hideUnsubmitted;
  final void Function(int courseId) onSelectCourse;

  /// 首页各板块的显示开关；缺省视为全开。
  final Map<String, bool> sections;
  final void Function(AssignmentRow row) onOpenAssignment;

  /// 被标记为「无需提交」的作业键；这些不计入缺交、也不出现在未交清单。
  final Set<String> ignoredSet;

  /// 用户排定的板块顺序；空列表表示默认顺序。
  final List<String> sectionOrder;
  bool _show(String key) => sections[key] != false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    if (courses.isEmpty) {
      return Center(child: Text('这个学期没有课程数据。', style: TextStyle(color: p.muted, fontSize: 13.5)));
    }

    final avg = averageScore(courses);

    // 被标记为「无需提交」的不计入任何一处。
    // 缺交数从作业行现算，而不是用 course.missingCount——后者是聚合阶段
    // 算好的，不知道用户在本机标了什么。
    final notIgnored = filterIgnored(
      assignments,
      ignoredSet,
      (AssignmentRow a) => a.courseId,
      (AssignmentRow a) => a.id,
    );
    final missingRows = notIgnored.where((a) => a.missing).toList();
    final missingByCourse = <int, int>{};
    for (final a in missingRows) {
      missingByCourse[a.courseId] = (missingByCourse[a.courseId] ?? 0) + 1;
    }
    int missingOf(int courseId) => missingByCourse[courseId] ?? 0;

    // 未提交的作业正是「缺交」的来源，忽略它就得把这个数也归零。
    final missing = hideUnsubmitted ? 0 : missingRows.length;
    final late = courses.fold<int>(0, (s, c) => s + c.lateCount);
    final graded = courses.where((c) => c.currentScore != null).length;
    final upcoming = hideUnsubmitted ? 0 : todo.length;

    final now = appNow();
    final soon = hideUnsubmitted
        ? <AssignmentRow>[]
        : (notIgnored
            .where((a) => !isCompleted(a))
            .where((a) {
              final t = a.dueAt == null ? null : DateTime.tryParse(a.dueAt!);
              return t != null && t.isAfter(now) && t.difference(now).inDays < 3;
            })
            .toList()
          ..sort((a, b) => DateTime.parse(a.dueAt!).compareTo(DateTime.parse(b.dueAt!))));

    final ranked = [...courses]..sort(courseUrgency);

    /// 所有还没交的作业，逾期的排前面。
    ///
    /// 这是「我想看有哪些作业没交」的直接答案：以前首页只有缺交总数，
    /// 看不出具体是哪些。
    final unsubmitted = hideUnsubmitted
        ? (overdue: <AssignmentRow>[], pending: <AssignmentRow>[])
        : () {
            final open = notIgnored.where((a) => !isCompleted(a)).toList();
            final od = <AssignmentRow>[];
            final pd = <AssignmentRow>[];
            for (final a in open) {
              final t = a.dueAt == null ? null : DateTime.tryParse(a.dueAt!);
              if (t != null && t.isBefore(now)) {
                od.add(a);
              } else {
                pd.add(a);
              }
            }
            int byDue(AssignmentRow x, AssignmentRow y) {
              if (x.dueAt == null) return 1;
              if (y.dueAt == null) return -1;
              return DateTime.parse(x.dueAt!).compareTo(DateTime.parse(y.dueAt!));
            }

            od.sort(byDue);
            pd.sort(byDue);
            return (overdue: od, pending: pd);
          }();

    final totalOpen = unsubmitted.overdue.length + unsubmitted.pending.length;

    // 各板块的 Widget 列表。用 Map 存起来再按用户排的顺序拼，
    // 而不是把整段拆成回调——板块内容长且各带条件渲染，拆开只会更难读。
    // 每个板块自带前导 Gap.lg，换顺序时间距依然对。
    final blocks = <String, List<Widget>>{
      // --- 统计 ---
      'stats': [
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
                hint: '共{assignments.length} 项作业',
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
      ],

      // --- 未提交的作业 ---
      // 与「三天内截止」各自独立：关掉一个不该连带关掉另一个。
      'unsubmitted': [
        if (_show('unsubmitted') && !hideUnsubmitted && totalOpen > 0) ...[
            Gap.lg,
            SectionHeader(
              '未提交的作业',
              icon: Icons.inbox_outlined,
              iconColor: p.warn,
              trailing: _count(totalOpen),
            ),
            if (unsubmitted.overdue.isNotEmpty) ...[
              _TodoGroupTitle(
                label: '已逾期 ${unsubmitted.overdue.length} 项',
                color: p.bad,
                icon: Icons.priority_high,
              ),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < unsubmitted.overdue.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: p.border),
                      _DueRow(row: unsubmitted.overdue[i], onTap: onOpenAssignment),
                    ],
                  ],
                ),
              ),
            ],
            if (unsubmitted.pending.isNotEmpty) ...[
              _TodoGroupTitle(
                label: '尚未到期 ${unsubmitted.pending.length} 项',
                color: p.textDim,
                icon: Icons.schedule,
              ),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < unsubmitted.pending.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: p.border),
                      _DueRow(row: unsubmitted.pending[i], onTap: onOpenAssignment),
                    ],
                  ],
                ),
              ),
            ],
        ],
      ],

      // --- 三天内截止 ---
      // 与「未提交的作业」各自独立：关掉一个不该连带关掉另一个。
      'soon': [
        if (_show('soon') && soon.isNotEmpty) ...[
          Gap.lg,
          SectionHeader('三天内截止', icon: Icons.schedule, iconColor: p.warn, trailing: _count(soon.length)),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < soon.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: p.border),
                    _DueRow(row: soon[i], onTap: onOpenAssignment),
                  ],
                ],
              ),
            ),
          ],
      ],

      // --- 得分图 ---
      'charts': [
        if (_show('charts')) ...[
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
                                  if (!hideUnsubmitted && missingOf(ranked[i].id) > 0)
                                    '缺交 ${missingOf(ranked[i].id)} 项',
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
        ],
      ],

      // --- 全部课程 ---
      'courses': [
        if (_show('courses')) ...[
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
      ],
    };

    // 按用户排的顺序拼；顺序表里没提到的按默认顺序补在后面，
    // 所以以后新增板块时老用户也不会漏看。
    //
    // 开关与排序的界面在设置页里，这里只负责按顺序渲染。
    final orderedKeys = _orderedSectionKeys();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        for (final k in orderedKeys) ...(blocks[k] ?? const <Widget>[]),
      ],
    );
  }

  /// 默认的板块顺序。
  static const List<String> _defaultSectionOrder = [
    'stats',
    'unsubmitted',
    'soon',
    'charts',
    'courses',
  ];

  List<String> _orderedSectionKeys() {
    final out = <String>[];
    for (final k in sectionOrder) {
      if (_defaultSectionOrder.contains(k) && !out.contains(k)) out.add(k);
    }
    for (final k in _defaultSectionOrder) {
      if (!out.contains(k)) out.add(k);
    }
    return out;
  }

  Widget _count(int n) => Builder(
        builder: (context) => Text('$n', style: TextStyle(color: context.palette.muted, fontSize: 12.5)),
      );
}

class _DueRow extends StatelessWidget {
  const _DueRow({required this.row, this.onTap});

  final AssignmentRow row;

  /// 点击打开作业详情；不传就只是展示。
  final void Function(AssignmentRow row)? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rel = dueRelative(row.dueAt, false);
    final color = rel.tone == DueTone.overdue ? p.bad : p.warn;

    final body = Padding(
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

    if (onTap == null) return body;
    return InkWell(onTap: () => onTap!(row), child: body);
  }
}

/// 「已逾期 N 项」这类分组小标题。
class _TodoGroupTitle extends StatelessWidget {
  const _TodoGroupTitle({required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
