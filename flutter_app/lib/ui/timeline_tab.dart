import '../core/clock.dart';
import 'package:flutter/material.dart';

import '../core/types.dart';
import '../theme.dart';
import 'format.dart';
import 'widgets.dart';

/// 时间线上的一个条目。
class _Item {
  _Item({
    required this.title,
    required this.courseName,
    required this.kind,
    required this.done,
    required this.state,
    this.courseId,
    this.dueAt,
    this.pointsPossible,
  });

  final String title;
  final String courseName;
  final String kind;
  final int? courseId;
  final String? dueAt;
  final double? pointsPossible;

  /// 已交（无论是否已批改）。
  final bool done;

  /// graded / submitted / missing / open
  final String state;
}

class TimelineTab extends StatefulWidget {
  const TimelineTab({
    super.key,
    required this.courses,
    required this.assignments,
    required this.todo,
    required this.hideUnsubmitted,
    required this.onSelectCourse,
  });

  final List<CourseSummary> courses;
  final List<AssignmentRow> assignments;
  final List<TodoEntry> todo;
  final bool hideUnsubmitted;
  final void Function(int courseId) onSelectCourse;

  @override
  State<TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends State<TimelineTab> {
  bool _showCompleted = false;

  List<_Item> get _items {
    final items = <int, _Item>{};

    for (final a in widget.assignments) {
      final done = isCompleted(a);
      final state = a.score != null
          ? 'graded'
          : done
              ? 'submitted'
              : a.missing
                  ? 'missing'
                  : 'open';
      items[a.id] = _Item(
        title: a.name,
        courseName: a.courseName,
        kind: a.groupName,
        courseId: a.courseId,
        dueAt: a.dueAt,
        pointsPossible: a.pointsPossible,
        done: done,
        state: state,
      );
    }

    // Canvas 自己的待办列表是权威的，用它补齐作业列表里没有的条目。
    final courseIds = widget.courses.map((c) => c.id).toSet();
    for (final t in widget.todo) {
      if (t.courseId != null && !courseIds.contains(t.courseId)) continue;
      final exists = items.values.any(
        (i) => i.title == t.title && (t.courseId == null || i.courseId == t.courseId),
      );
      if (exists) continue;
      items[-(t.title.length + (t.courseId ?? 0))] = _Item(
        title: t.title,
        courseName: t.courseName,
        kind: t.kind == 'quiz' ? '测验' : '待办',
        courseId: t.courseId,
        dueAt: t.dueAt,
        pointsPossible: t.pointsPossible,
        done: false,
        state: 'open',
      );
    }

    final list = items.values.toList()
      ..sort((a, b) {
        final ta = a.dueAt == null ? null : DateTime.tryParse(a.dueAt!);
        final tb = b.dueAt == null ? null : DateTime.tryParse(b.dueAt!);
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return ta.compareTo(tb);
      });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final all = _items;
    final now = appNow();

    // 忽略未提交时，已完成条目正是列表的全部意义，所以「显示已完成」不再生效。
    final withCompleted = _showCompleted || widget.hideUnsubmitted;
    final pool = widget.hideUnsubmitted ? all.where((i) => i.done).toList() : all;
    final open = pool.where((i) => !i.done).toList();

    bool before(_Item i, Duration d) {
      final t = i.dueAt == null ? null : DateTime.tryParse(i.dueAt!);
      return t != null && t.isBefore(now.add(d));
    }

    bool after(_Item i, Duration d) {
      final t = i.dueAt == null ? null : DateTime.tryParse(i.dueAt!);
      return t != null && !t.isBefore(now.add(d));
    }

    final buckets = <({String title, List<_Item> items})>[
      (title: '已逾期未交', items: open.where((i) => before(i, Duration.zero)).toList()),
      (
        title: '三天内截止',
        items: open
            .where((i) => !before(i, Duration.zero) && before(i, const Duration(days: 3)))
            .toList()
      ),
      (title: '之后', items: open.where((i) => after(i, const Duration(days: 3))).toList()),
      (title: '无截止时间', items: open.where((i) => i.dueAt == null).toList()),
      (title: '已完成', items: withCompleted ? pool.where((i) => i.done).toList() : <_Item>[]),
    ].where((b) => b.items.isNotEmpty).toList();

    final totalOpen = all.where((i) => !i.done).length;
    final totalDone = all.length - totalOpen;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.hideUnsubmitted
                    ? '已忽略未提交 · 显示 $totalDone 项已完成'
                    : '待处理 $totalOpen 项 · 已完成 $totalDone 项',
                style: TextStyle(color: p.muted, fontSize: 12.5),
              ),
            ),
            if (!widget.hideUnsubmitted)
              Row(
                children: [
                  Checkbox(
                    value: _showCompleted,
                    onChanged: (v) => setState(() => _showCompleted = v ?? false),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  Text('显示已完成', style: TextStyle(color: p.textDim, fontSize: 12.5)),
                ],
              ),
          ],
        ),
        Gap.sm,

        if (buckets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                widget.hideUnsubmitted ? '这个范围内没有已提交的作业。' : '没有待办事项，暂时轻松。',
                style: TextStyle(color: p.muted, fontSize: 13.5),
              ),
            ),
          ),

        for (final bucket in buckets) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Row(
              children: [
                Text(
                  bucket.title,
                  style: TextStyle(color: p.textDim, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Text('${bucket.items.length} 项', style: TextStyle(color: p.muted, fontSize: 12)),
              ],
            ),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              children: [
                for (var i = 0; i < bucket.items.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.border),
                  _TimelineRow(
                    item: bucket.items[i],
                    onTap: bucket.items[i].courseId == null
                        ? null
                        : () => widget.onSelectCourse(bucket.items[i].courseId!),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.item, this.onTap});

  final _Item item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rel = dueRelative(item.dueAt, item.done);

    final barColor = switch (rel.tone) {
      DueTone.overdue => p.bad,
      DueTone.soon => p.warn,
      DueTone.later => p.good,
      DueTone.none => p.border,
    };

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 40,
              decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      item.courseName,
                      if (item.pointsPossible != null) '满分 ${item.pointsPossible!.toStringAsFixed(0)}',
                      if (item.kind.isNotEmpty) item.kind,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 11.5),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    formatDate(item.dueAt),
                    style: TextStyle(color: p.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (item.state == 'graded')
                  const StatusTag(label: '已评分', tone: 'good')
                else if (item.state == 'submitted')
                  const StatusTag(label: '已提交待评分', tone: 'info')
                else if (item.state == 'missing')
                  const StatusTag(label: '未提交', tone: 'bad')
                else
                  StatusTag(label: rel.text, tone: rel.tone == DueTone.overdue ? 'bad' : 'neutral'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
