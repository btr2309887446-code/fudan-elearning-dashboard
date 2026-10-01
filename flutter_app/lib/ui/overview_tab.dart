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
    required this.sections,
    required this.onToggleSection,
    required this.onOpenAssignment,
    required this.sectionOrder,
    required this.onMoveSection,
    required this.onResetOrder,
  });

  final List<CourseSummary> courses;
  final List<AssignmentRow> assignments;
  final List<TodoEntry> todo;
  final String termName;
  final bool hideUnsubmitted;
  final void Function(int courseId) onSelectCourse;

  /// 首页各板块的显示开关；缺省视为全开。
  final Map<String, bool> sections;
  final void Function(String key) onToggleSection;
  final void Function(AssignmentRow row) onOpenAssignment;

  /// 用户排定的板块顺序；空列表表示默认顺序。
  final List<String> sectionOrder;
  final void Function(String key, int direction) onMoveSection;
  final VoidCallback onResetOrder;

  bool _show(String key) => sections[key] != false;

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

    /// 所有还没交的作业，逾期的排前面。
    ///
    /// 这是「我想看有哪些作业没交」的直接答案：以前首页只有缺交总数，
    /// 看不出具体是哪些。
    final unsubmitted = hideUnsubmitted
        ? (overdue: <AssignmentRow>[], pending: <AssignmentRow>[])
        : () {
            final open = assignments.where((a) => !isCompleted(a)).toList();
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
    final orderedKeys = _orderedSectionKeys();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _SectionToggles(
          sections: sections,
          order: orderedKeys,
          onToggle: onToggleSection,
          onMove: onMoveSection,
          onReset: onResetOrder,
        ),
        const SizedBox(height: 14),
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

/// 首页板块开关。
///
/// 放在首页最上面而不是塞进设置里：这些开关调的就是当前这一页，
/// 就地能改比翻菜单直观。
class _SectionToggles extends StatelessWidget {
  const _SectionToggles({
    required this.sections,
    required this.order,
    required this.onToggle,
    required this.onMove,
    required this.onReset,
  });

  final Map<String, bool> sections;

  /// 已经算好的完整顺序（含默认补位）。
  final List<String> order;
  final void Function(String key) onToggle;
  final void Function(String key, int direction) onMove;
  final VoidCallback onReset;

  static const _items = <({String key, String label, IconData icon})>[
    (key: 'stats', label: '数据概览', icon: Icons.insights_outlined),
    (key: 'unsubmitted', label: '未提交作业', icon: Icons.inbox_outlined),
    (key: 'soon', label: '三天内截止', icon: Icons.schedule),
    (key: 'charts', label: '得分与关注', icon: Icons.bar_chart),
    (key: 'courses', label: '课程卡片', icon: Icons.menu_book_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // 胶囊也按用户排的顺序显示，和下面的板块一一对应。
    final byKey = {for (final it in _items) it.key: it};
    final ordered = [
      for (final k in order)
        if (byKey.containsKey(k)) byKey[k]!,
      for (final it in _items)
        if (!order.contains(it.key)) it,
    ];
    final canReset = order.length != _items.length ||
        !List.generate(_items.length, (i) => order[i] == _items[i].key).every((x) => x);

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (var i = 0; i < ordered.length; i++)
          Builder(builder: (context) {
            final it = ordered[i];
            final on = sections[it.key] != false;
            return Container(
              decoration: BoxDecoration(
                color: on ? p.accent.withValues(alpha: 0.12) : p.surface,
                border: Border.all(color: on ? p.accent : p.border),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => onToggle(it.key),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(11, 6, 4, 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(it.icon, size: 13, color: on ? p.accent : p.muted),
                          const SizedBox(width: 5),
                          Text(
                            it.label,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: on ? p.accent : p.textDim,
                              fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 排序：和桌面端的 ▲▼ 语义一致
                  _MoveButton(
                    label: '▲',
                    enabled: i > 0,
                    onTap: () => onMove(it.key, -1),
                    color: on ? p.accent : p.muted,
                  ),
                  _MoveButton(
                    label: '▼',
                    enabled: i < ordered.length - 1,
                    onTap: () => onMove(it.key, 1),
                    color: on ? p.accent : p.muted,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            );
          }),
        if (canReset)
          InkWell(
            onTap: onReset,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: p.surface,
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('恢复默认', style: TextStyle(fontSize: 12.5, color: p.textDim)),
            ),
          ),
      ],
    );
  }
}

/// 排序用的小三角。
class _MoveButton extends StatelessWidget {
  const _MoveButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.color,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: Text(
          label,
          style: TextStyle(fontSize: 8, height: 1, color: color.withValues(alpha: enabled ? 1 : 0.25)),
        ),
      ),
    );
  }
}
