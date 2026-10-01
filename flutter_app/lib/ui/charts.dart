/// 图表。
///
/// 刻意不引入图表库：这里只需要横向得分条、分组柱状图和一条趋势折线，
/// 用 CustomPainter 画出来既轻量又没有版本兼容风险。
/// 桌面端用 ECharts，这里手工实现等价的视觉效果。

library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/types.dart';
import '../theme.dart';
import 'format.dart';

/// 各课程当前得分（横向条，手机上比柱状图更易读）。
class ScoreBars extends StatelessWidget {
  const ScoreBars({super.key, required this.courses, this.onTap});

  final List<CourseSummary> courses;
  final void Function(int courseId)? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scored = courses.where((c) => c.currentScore != null).toList()
      ..sort((a, b) => a.currentScore!.compareTo(b.currentScore!));

    if (scored.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('暂无已评分课程', style: TextStyle(color: p.muted, fontSize: 13.5))),
      );
    }

    return Column(
      children: [
        for (final c in scored) ...[
          InkWell(
            onTap: onTap == null ? null : () => onTap!(c.id),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.textDim, fontSize: 12.5),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        formatScoreCompact(c.currentScore),
                        style: TextStyle(
                          color: p.forScore(c.currentScore),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ThinBarProxy(percent: c.currentScore, color: p.forScore(c.currentScore)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 单独抽出来，避免 charts.dart 反向依赖 widgets.dart。
class ThinBarProxy extends StatelessWidget {
  const ThinBarProxy({super.key, required this.percent, required this.color, this.height = 6});

  final double? percent;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final v = (percent ?? 0).clamp(0, 100).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: height,
        color: p.surfaceAlt,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: v / 100,
          child: Container(color: color),
        ),
      ),
    );
  }
}

/// 作业分组达成度（竖向柱）。
class GroupBars extends StatelessWidget {
  const GroupBars({super.key, required this.groups});

  final List<AssignmentGroupDetail> groups;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final usable = groups.where((g) => g.percent != null).toList();
    if (usable.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('暂无已评分的作业分组', style: TextStyle(color: p.muted, fontSize: 13.5))),
      );
    }

    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final g in usable)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      g.percent!.toStringAsFixed(1),
                      style: TextStyle(
                        color: p.forScore(g.percent),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            height: math.max(3, box.maxHeight * (g.percent! / 100).clamp(0, 1)),
                            decoration: BoxDecoration(
                              color: p.forScore(g.percent),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      g.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 10.5, height: 1.2),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 按截止时间累计的课程百分比折线。
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.rows});

  final List<AssignmentRow> rows;

  /// 只统计已评分且满分为正的作业，按截止时间排序后累计。
  static List<({DateTime at, double percent})> points(List<AssignmentRow> rows) {
    final graded = rows
        .where((r) => r.score != null && r.pointsPossible != null && r.pointsPossible! > 0 && !r.excused)
        .toList()
      ..sort((a, b) {
        final ta = DateTime.tryParse(a.dueAt ?? a.gradedAt ?? '') ?? DateTime(2000);
        final tb = DateTime.tryParse(b.dueAt ?? b.gradedAt ?? '') ?? DateTime(2000);
        return ta.compareTo(tb);
      });

    var earned = 0.0;
    var possible = 0.0;
    final out = <({DateTime at, double percent})>[];
    for (final r in graded) {
      earned += r.score!;
      possible += r.pointsPossible!;
      final at = DateTime.tryParse(r.dueAt ?? r.gradedAt ?? '') ?? DateTime(2000);
      out.add((at: at, percent: (earned / possible) * 100));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pts = points(rows);

    if (pts.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('已评分的作业不足，暂无法绘制趋势', style: TextStyle(color: p.muted, fontSize: 13.5)),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 150,
          child: CustomPaint(
            // CustomPainter 里的 TextPainter **不会**继承主题字体，
            // 必须把当前字族显式传进去，否则刻度会退回默认字体。
            painter: _TrendPainter(
              pts,
              p.accent,
              p.border,
              p.muted,
              p.surface,
              DefaultTextStyle.of(context).style.fontFamily,
            ),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${pts.first.at.month}/${pts.first.at.day}',
              style: TextStyle(color: p.muted, fontSize: 10.5),
            ),
            Text(
              '${pts.last.at.month}/${pts.last.at.day}',
              style: TextStyle(color: p.muted, fontSize: 10.5),
            ),
          ],
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.points, this.accent, this.grid, this.label, this.surface, this.fontFamily);

  final List<({DateTime at, double percent})> points;
  final Color accent;
  final Color grid;
  final Color label;
  final Color surface;
  final String? fontFamily;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 30.0;
    const rightPad = 6.0;
    const topPad = 8.0;
    const bottomPad = 4.0;

    final plotW = size.width - leftPad - rightPad;
    final plotH = size.height - topPad - bottomPad;
    if (plotW <= 0 || plotH <= 0) return;

    // 纵轴范围：把数据包住，但至少给 10 个百分点的高度。
    var minV = points.map((p) => p.percent).reduce(math.min);
    var maxV = points.map((p) => p.percent).reduce(math.max);
    if (maxV - minV < 10) {
      final mid = (maxV + minV) / 2;
      minV = (mid - 5).clamp(0, 100);
      maxV = (mid + 5).clamp(0, 100);
    }
    final span = math.max(1.0, maxV - minV);

    double xAt(int i) => leftPad + (points.length == 1 ? plotW / 2 : plotW * i / (points.length - 1));
    double yAt(double v) => topPad + plotH * (1 - (v - minV) / span);

    // 网格线与刻度
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final textStyle = TextStyle(color: label, fontSize: 9.5, fontFamily: fontFamily);
    for (var i = 0; i <= 3; i++) {
      final v = minV + span * i / 3;
      final y = yAt(v);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: '${v.round()}%', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 5, y - tp.height / 2));
    }

    // 折线
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = Offset(xAt(i), yAt(points[i].percent));
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }

    // 面积填充
    final area = Path.from(path)
      ..lineTo(xAt(points.length - 1), topPad + plotH)
      ..lineTo(xAt(0), topPad + plotH)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent.withValues(alpha: 0.26), accent.withValues(alpha: 0.01)],
        ).createShader(Rect.fromLTWH(0, topPad, size.width, plotH)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 数据点
    for (var i = 0; i < points.length; i++) {
      final o = Offset(xAt(i), yAt(points[i].percent));
      canvas.drawCircle(o, 4.0, Paint()..color = surface);
      canvas.drawCircle(o, 2.6, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points || old.accent != accent || old.fontFamily != fontFamily;
}
