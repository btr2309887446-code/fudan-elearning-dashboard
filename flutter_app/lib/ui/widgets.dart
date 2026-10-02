/// 共享组件。

library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/types.dart';
import '../theme.dart';
import 'format.dart';

/// 环形得分指示器（纯 CustomPainter，不依赖图表库）。
class ScoreRing extends StatelessWidget {
  const ScoreRing(
      {super.key,
      required this.score,
      this.size = 64,
      this.stroke = 6,
      this.showLabel = true});

  final double? score;
  final double size;
  final double stroke;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final has = score != null && !score!.isNaN;
    final color = p.forScore(score);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(
                begin: 0, end: has ? (score! / 100).clamp(0.0, 1.0) : 0.0),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => CustomPaint(
              size: Size(size, size),
              painter: _RingPainter(value, color, p.ringTrack, stroke),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                has ? formatScoreCompact(score) : '—',
                style: TextStyle(
                  color: color,
                  fontSize: size * 0.30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  height: 1.1,
                ),
              ),
              if (showLabel && size >= 56)
                Text(
                  AppPalette.labelForScore(score),
                  style: TextStyle(
                      color: p.muted, fontSize: size * 0.15, height: 1.2),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color, this.track, this.stroke);

  final double progress;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);
    if (progress > 0) {
      canvas.drawArc(
          rect, -math.pi / 2, math.pi * 2 * progress, false, valuePaint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

/// 统计卡。
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.unit,
    this.hint,
    this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? unit;
  final String? hint;

  /// null 表示用主色；否则用 good / bad / warn。
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = tone ?? p.accent;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 27,
                height: 27,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              Gap.hSm,
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: p.muted, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          // 用 Text.rich 而不是 RichText：后者不会继承 DefaultTextStyle，
          // 主题里的字体设置会失效。
          //
          // 数字本身带功能色——这是整张卡片的视觉重心，
          // 只给小图标上色的话整屏还是白花花一片，分不出哪张卡在说什么。
          Text.rich(
            TextSpan(
              text: value,
              style: TextStyle(
                color: color,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                height: 1.1,
              ),
              children: [
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                        color: p.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 3),
            Text(
              hint!,
              style: TextStyle(color: p.muted, fontSize: 11.5),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// 状态小标签。
class StatusTag extends StatelessWidget {
  const StatusTag({super.key, required this.label, required this.tone});

  final String label;
  final String tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (bg, fg, border) = switch (tone) {
      'good' => (p.good, p.good, p.good),
      'info' => (p.accent, p.accent, p.accent),
      'warn' => (p.warn, p.warn, p.warn),
      'bad' => (p.bad, p.bad, p.bad),
      _ => (p.muted, p.muted, p.muted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// 中性信息片。
class InfoChip extends StatelessWidget {
  const InfoChip(this.text, {super.key, this.tone});

  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = tone;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c == null ? p.surfaceAlt : c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border:
            Border.all(color: c == null ? p.border : c.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: c ?? p.textDim, fontSize: 11.5),
      ),
    );
  }
}

/// 小节标题。
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title,
      {super.key, this.trailing, this.icon, this.iconColor});

  final String title;
  final Widget? trailing;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: iconColor ?? p.accent),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: p.text,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// 卡片外壳，统一圆角与描边。
///
/// 描边用 [AppPalette.cardBorder] 而不是 `border`：
/// 深色下前者几乎看不见，卡片靠灰阶差从纯黑背景里浮出来——
/// 这才是「深灰圆角块」该有的样子；画一圈看得见的线会变成 Material 味。
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final content = Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.cardBorder),
      ),
      child: child,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: content,
      ),
    );
  }
}

/// 细进度条。
class ThinBar extends StatelessWidget {
  const ThinBar(
      {super.key, required this.percent, this.color, this.height = 6});

  final double? percent;
  final Color? color;
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
          child: Container(color: color ?? p.forScore(percent)),
        ),
      ),
    );
  }
}

/// 课程卡片（列表形态，适合手机）。
class CourseCard extends StatelessWidget {
  const CourseCard({
    super.key,
    required this.course,
    required this.onTap,
    this.showTerm = false,
    this.hideUnsubmitted = false,
  });

  final CourseSummary course;
  final VoidCallback onTap;
  final bool showTerm;
  final bool hideUnsubmitted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScoreRing(score: course.currentScore, size: 62, stroke: 6),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      course.courseCode,
                      style: TextStyle(color: p.muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: p.muted),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Text('得分构成', style: TextStyle(color: p.muted, fontSize: 11.5)),
              const Spacer(),
              Text(
                course.earnedPoints != null &&
                        course.possiblePointsGraded != null
                    ? '${course.earnedPoints!.toStringAsFixed(1)} / ${course.possiblePointsGraded!.toStringAsFixed(0)} 分'
                    : '尚无评分',
                style: TextStyle(color: p.muted, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ThinBar(
              percent: course.currentScore,
              color: p.forScore(course.currentScore)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (showTerm) InfoChip(course.termName),
              InfoChip('${course.assignmentCount} 项作业'),
              if (course.gradedCount > 0) InfoChip('已评分 ${course.gradedCount}'),
              if (!hideUnsubmitted && course.missingCount > 0)
                InfoChip('缺交 ${course.missingCount}', tone: p.bad),
              if (!hideUnsubmitted && course.lateCount > 0)
                InfoChip('迟交 ${course.lateCount}', tone: p.warn),
            ],
          ),
        ],
      ),
    );
  }
}
