import 'package:flutter/material.dart';

import '../core/scoring.dart';
import '../core/types.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'charts.dart';
import 'files_section.dart';
import 'format.dart';
import 'widgets.dart';

class CourseDetailScreen extends StatefulWidget {
  const CourseDetailScreen({
    super.key,
    required this.state,
    required this.snapshot,
    required this.courseId,
    required this.hideUnsubmitted,
    this.onOpenAssignment,
  });

  /// 课程文件那一节需要它来取数、下载。
  final AppState state;
  final Snapshot snapshot;
  final int courseId;
  final bool hideUnsubmitted;
  final void Function(AssignmentRow row)? onOpenAssignment;

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

enum _Sort { due, score, group }

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  _Sort _sort = _Sort.due;
  bool _onlyUnfinished = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final detail = buildCourseDetail(widget.snapshot, widget.courseId);

    if (detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('课程详情')),
        body: Center(child: Text('找不到该课程。', style: TextStyle(color: p.muted))),
      );
    }

    final course = detail.course;
    final rows = <AssignmentRow>[...detail.assignments];
    final ignoredCount = detail.assignments
        .where((r) => widget.state.ignoredSet.contains('${r.courseId}:${r.id}'))
        .length;
    if (widget.hideUnsubmitted) rows.removeWhere((r) => !isCompleted(r));
    if (_onlyUnfinished) rows.removeWhere((r) => r.score != null || r.excused);

    rows.sort((a, b) {
      switch (_sort) {
        case _Sort.score:
          return (a.percent ?? -1).compareTo(b.percent ?? -1);
        case _Sort.group:
          final g = a.groupName.compareTo(b.groupName);
          return g != 0 ? g : a.name.compareTo(b.name);
        case _Sort.due:
          final ta = a.dueAt == null ? null : DateTime.tryParse(a.dueAt!);
          final tb = b.dueAt == null ? null : DateTime.tryParse(b.dueAt!);
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return ta.compareTo(tb);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(course.displayName,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
        children: [
          // --- 概览 ---
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(course.courseCode,
                    style: TextStyle(color: p.muted, fontSize: 12)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ScoreRing(
                        score: course.currentScore, size: 92, stroke: 8.5),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              InfoChip(course.termName),
                              InfoChip(
                                AppPalette.labelForScore(course.currentScore),
                                tone: p.forScore(course.currentScore),
                              ),
                              InfoChip(detail.gradingScheme == 'weighted'
                                  ? '按权重计分'
                                  : '按总分计分'),
                              if (course.currentGrade != null)
                                InfoChip('等级 ${course.currentGrade}'),
                              if (course.finalScore != null)
                                InfoChip(
                                    '最终分 ${formatScoreCompact(course.finalScore)}'),
                              if (course.finalGrade != null)
                                InfoChip('最终等级 ${course.finalGrade}'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ThinBarProxy(
                  percent: course.assignmentCount == 0
                      ? 0
                      : course.gradedCount / course.assignmentCount * 100,
                  color: p.accent,
                  height: 5,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 128,
                      child: _MiniStat(
                        label: '已得 / 已评总分',
                        value: course.earnedPoints != null &&
                                course.possiblePointsGraded != null
                            ? '${course.earnedPoints!.toStringAsFixed(1)} / ${course.possiblePointsGraded!.toStringAsFixed(0)}'
                            : '—',
                      ),
                    ),
                    SizedBox(
                      width: 92,
                      child: _MiniStat(
                        label: '已评分项',
                        value:
                            '${course.gradedCount} / ${course.assignmentCount}',
                      ),
                    ),
                    if (!widget.hideUnsubmitted)
                      SizedBox(
                        width: 70,
                        child: _MiniStat(
                          label: '缺交',
                          value: '${course.missingCount}',
                          color: course.missingCount > 0 ? p.bad : null,
                        ),
                      ),
                    if (course.lateCount > 0)
                      SizedBox(
                        width: 70,
                        child: _MiniStat(
                          label: '迟交',
                          value: '${course.lateCount}',
                          color: p.warn,
                        ),
                      ),
                    if (ignoredCount > 0)
                      SizedBox(
                        width: 88,
                        child: _MiniStat(
                          label: '无需提交',
                          value: '$ignoredCount',
                          color: p.accent,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // --- 趋势 ---
          Gap.lg,
          const SectionHeader('得分趋势', icon: Icons.timeline),
          AppCard(child: TrendChart(rows: detail.assignments)),

          // --- 分组 ---
          Gap.lg,
          SectionHeader('作业分组达成度',
              icon: Icons.pie_chart_outline, iconColor: p.good),
          AppCard(
            child: Column(
              children: [
                GroupBars(groups: detail.groups),
                if (detail.groups.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final g in detail.groups) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            g.weight > 0
                                ? '${g.name}（${g.weight.toStringAsFixed(0)}%）'
                                : g.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.text, fontSize: 12.5),
                          ),
                        ),
                        Text(
                          g.percent != null
                              ? '${g.percent!.toStringAsFixed(1)}% · ${g.earned.toStringAsFixed(1)}/${g.possible.toStringAsFixed(0)}'
                              : '未评分',
                          style: TextStyle(color: p.muted, fontSize: 11.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ThinBarProxy(
                        percent: g.percent, color: p.forScore(g.percent)),
                    const SizedBox(height: 11),
                  ],
                ],
              ],
            ),
          ),

          // --- 明细 ---
          Gap.lg,
          SectionHeader(
            '作业明细',
            trailing: Text(
              '${rows.length} / ${detail.assignments.length} 项',
              style: TextStyle(color: p.muted, fontSize: 11.5),
            ),
          ),
          Row(
            children: [
              if (!widget.hideUnsubmitted)
                Expanded(
                  child: Row(
                    children: [
                      Checkbox(
                        value: _onlyUnfinished,
                        onChanged: (v) =>
                            setState(() => _onlyUnfinished = v ?? false),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      Text('只看未完成',
                          style: TextStyle(color: p.textDim, fontSize: 12.5)),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Text('已忽略未提交的作业',
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ),
              PopupMenuButton<_Sort>(
                initialValue: _sort,
                onSelected: (v) => setState(() => _sort = v),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: p.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        switch (_sort) {
                          _Sort.due => '按截止时间',
                          _Sort.score => '按得分率',
                          _Sort.group => '按作业分组',
                        },
                        style: TextStyle(color: p.textDim, fontSize: 12.5),
                      ),
                      Icon(Icons.expand_more, size: 17, color: p.muted),
                    ],
                  ),
                ),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: _Sort.due, child: Text('按截止时间')),
                  PopupMenuItem(value: _Sort.score, child: Text('按得分率（低→高）')),
                  PopupMenuItem(value: _Sort.group, child: Text('按作业分组')),
                ],
              ),
            ],
          ),
          Gap.sm,
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.border),
                  _AssignmentRowTile(
                    row: rows[i],
                    onTap: widget.onOpenAssignment == null
                        ? null
                        : () => widget.onOpenAssignment!(rows[i]),
                  ),
                ],
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Text('没有符合条件的作业。',
                        style: TextStyle(color: p.muted, fontSize: 13)),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // --- 课程文件 ---
          FilesSection(state: widget.state, courseId: widget.courseId),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: p.muted, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color ?? p.text,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _AssignmentRowTile extends StatelessWidget {
  const _AssignmentRowTile({required this.row, this.onTap});

  final AssignmentRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = submissionState(row);
    final done = isCompleted(row);
    final rel = dueRelative(row.dueAt, done);

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          height: 1.35),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      row.groupName +
                          (row.omitFromFinalGrade ? ' · 不计入总评' : ''),
                      style: TextStyle(color: p.muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              StatusTag(label: state.label, tone: state.tone),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                row.score != null ? formatScoreCompact(row.score) : '—',
                style: TextStyle(
                  color: p.forScore(row.percent),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                ' / ${row.pointsPossible?.toStringAsFixed(0) ?? '—'}',
                style: TextStyle(color: p.muted, fontSize: 11.5),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: ThinBarProxy(
                      percent: row.percent,
                      color: p.forScore(row.percent),
                      height: 5)),
              const SizedBox(width: 8),
              Text(
                row.percent != null
                    ? '${row.percent!.toStringAsFixed(0)}%'
                    : '',
                style: TextStyle(color: p.muted, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Text(formatDate(row.dueAt),
                  style: TextStyle(color: p.muted, fontSize: 11)),
              const Spacer(),
              if (rel.tone == DueTone.overdue)
                Text(rel.text,
                    style: TextStyle(
                        color: p.bad,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      ),
    );
  }
}
