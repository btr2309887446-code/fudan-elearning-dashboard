import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/clock.dart';
import '../../core/tasks.dart';
import '../../theme.dart';

String readableCourseName(String name) =>
    name.replaceFirst(RegExp(r'^[A-Z]{2,}\d{4,}(?:\.\d+)?\s+'), '');

String deadlineLabel(LearningTask task, {bool absolute = false}) {
  final due = task.dueAt;
  if (due == null) return '无截止时间';
  final wall = beijingTime(due);
  final time =
      '${wall.hour.toString().padLeft(2, '0')}:${wall.minute.toString().padLeft(2, '0')}';
  final today = beijingDay(appNow());
  final day = beijingDay(due);
  final date = absolute
      ? '${wall.year}/${wall.month}/${wall.day}'
      : day == today
      ? '今天'
      : day == today.add(const Duration(days: 1))
      ? '明天'
      : '${wall.month}月${wall.day}日';
  return '$date $time 截止';
}

class IosTaskRow extends StatelessWidget {
  const IosTaskRow({
    super.key,
    required this.task,
    this.onTap,
    this.selected = false,
  });
  final LearningTask task;
  final VoidCallback? onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final overdue = task.bucket(appNow()) == TaskBucket.overdue;
    final row = task.assignment;
    final status = task.status == TaskStatus.ignored
        ? '无需提交'
        : task.status == TaskStatus.submitted
        ? (row?.excused == true
              ? '已免除'
              : row?.score != null
              ? '已评分'
              : '已提交待评分')
        : overdue
        ? '已逾期未交'
        : null;
    final color = overdue
        ? p.bad
        : task.bucket(appNow()) == TaskBucket.today
        ? p.accent
        : p.textDim;
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Container(
          width: double.infinity,
          color: selected ? p.accent.withValues(alpha: 0.08) : p.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: Icon(
                  task.status == TaskStatus.submitted
                      ? CupertinoIcons.checkmark_circle_fill
                      : task.status == TaskStatus.ignored
                      ? CupertinoIcons.minus_circle
                      : overdue
                      ? CupertinoIcons.exclamationmark_circle
                      : CupertinoIcons.circle,
                  size: 21,
                  color: overdue
                      ? p.bad
                      : task.status == TaskStatus.submitted
                      ? p.good
                      : p.textDim,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        color: p.text,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      readableCourseName(task.courseName),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: p.textDim,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      deadlineLabel(task),
                      style: TextStyle(
                        fontSize: 13,
                        color: task.status == TaskStatus.pending
                            ? color
                            : p.textDim,
                        fontWeight: task.status == TaskStatus.pending
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                    if (status != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          status,
                          style: TextStyle(
                            fontSize: 13,
                            color: overdue ? p.bad : p.textDim,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 8),
                child: Icon(
                  CupertinoIcons.chevron_forward,
                  color: p.textDim,
                  size: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class IosGroup extends StatelessWidget {
  const IosGroup({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: ColoredBox(
      color: context.palette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Divider(height: 1, color: context.palette.border),
              ),
            children[i],
          ],
        ],
      ),
    ),
  );
}

class IosSection extends StatelessWidget {
  const IosSection(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: context.palette.text,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (action != null)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            onPressed: onAction,
            child: Text(action!, style: const TextStyle(fontSize: 15)),
          ),
      ],
    ),
  );
}

class IosEmpty extends StatelessWidget {
  const IosEmpty(
    this.message, {
    super.key,
    this.icon = CupertinoIcons.checkmark_circle,
    this.action,
    this.onAction,
  });
  final String message;
  final IconData icon;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 12),
    child: Column(
      children: [
        Icon(icon, color: context.palette.textDim, size: 30),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: context.palette.textDim,
            height: 1.5,
          ),
        ),
        if (action != null)
          CupertinoButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

class IosScrollPage extends StatelessWidget {
  const IosScrollPage({
    super.key,
    required this.title,
    required this.children,
    this.onRefresh,
    this.trailing,
    this.scrollKey,
  });
  final String title;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final Widget? trailing;
  final Key? scrollKey;
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: context.palette.background,
    child: CustomScrollView(
      key: scrollKey,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        CupertinoSliverNavigationBar(
          largeTitle: Text(title),
          trailing: trailing,
          backgroundColor: context.palette.background,
          border: null,
        ),
        if (onRefresh != null)
          CupertinoSliverRefreshControl(onRefresh: onRefresh),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverList(delegate: SliverChildListDelegate(children)),
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
        ),
      ],
    ),
  );
}

Future<T?> iosChoice<T>(
  BuildContext context,
  String title,
  Map<T, String> choices, {
  T? selected,
}) => showCupertinoModalPopup<T>(
  context: context,
  builder: (ctx) => CupertinoActionSheet(
    title: Text(title),
    actions: [
      for (final choice in choices.entries)
        CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx, choice.key),
          child: Text('${choice.value}${choice.key == selected ? ' ✓' : ''}'),
        ),
    ],
    cancelButton: CupertinoActionSheetAction(
      onPressed: () => Navigator.pop(ctx),
      child: const Text('取消'),
    ),
  ),
);

Future<bool> iosConfirm(
  BuildContext context,
  String title,
  String message, {
  String confirm = '确定',
  bool destructive = false,
}) async =>
    await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirm),
          ),
        ],
      ),
    ) ??
    false;

Future<void> iosMessage(BuildContext context, String message) =>
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好'),
          ),
        ],
      ),
    );

class IosMenuLabel extends StatelessWidget {
  const IosMenuLabel(this.label, {super.key, this.fontSize = 15});
  final String label;
  final double fontSize;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: fontSize),
        ),
      ),
      const SizedBox(width: 4),
      const Icon(CupertinoIcons.chevron_down, size: 12),
    ],
  );
}
