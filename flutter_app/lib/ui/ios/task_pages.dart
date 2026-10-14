import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/clock.dart';
import '../../core/tasks.dart';
import '../../core/types.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import 'components.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({
    super.key,
    required this.state,
    required this.tasks,
    required this.termButton,
    this.termName,
    required this.onTask,
    required this.onAll,
  });
  final AppState state;
  final List<LearningTask> tasks;
  final Widget termButton;
  final String? termName;
  final ValueChanged<LearningTask> onTask;
  final ValueChanged<TaskBucket?> onAll;
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  bool _showOverdue = false;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final now = appNow();
    final open = widget.tasks
        .where((task) => task.status == TaskStatus.pending)
        .toList();
    List<LearningTask> bucket(TaskBucket value) =>
        open.where((task) => task.bucket(now) == value).toList();
    final overdue = bucket(TaskBucket.overdue);
    final today = bucket(TaskBucket.today);
    final week = bucket(TaskBucket.week);
    final date = beijingTime(now);
    final weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return IosScrollPage(
      title: '今日',
      scrollKey: const PageStorageKey('ios-today'),
      trailing: widget.termButton,
      onRefresh: () => widget.state.refresh(force: true),
      children: [
        Text(
          '${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}',
          style: TextStyle(fontSize: 15, color: p.textDim),
        ),
        if (widget.termName != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.termName!,
              style: TextStyle(fontSize: 13, color: p.textDim),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _count(context, '今天截止', today.length, p.accent),
            _count(context, '未来七天', week.length, p.text),
            _count(context, '待处理', open.length, p.text),
          ],
        ),
        if (overdue.isNotEmpty) ...[
          const SizedBox(height: 16),
          IosGroup(
            children: [
              CupertinoButton(
                padding: const EdgeInsets.all(14),
                onPressed: () => setState(() => _showOverdue = !_showOverdue),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.exclamationmark_circle,
                      color: p.bad,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${overdue.length} 项已逾期未交',
                        style: TextStyle(fontSize: 15, color: p.bad),
                      ),
                    ),
                    Icon(
                      _showOverdue
                          ? CupertinoIcons.chevron_up
                          : CupertinoIcons.chevron_down,
                      size: 14,
                      color: p.textDim,
                    ),
                  ],
                ),
              ),
              if (_showOverdue) ...[
                for (final task in overdue.take(3))
                  IosTaskRow(task: task, onTap: () => widget.onTask(task)),
                if (overdue.length > 3)
                  CupertinoButton(
                    onPressed: () => widget.onAll(TaskBucket.overdue),
                    child: const Text('查看全部逾期作业'),
                  ),
              ],
            ],
          ),
        ],
        IosSection(
          '今天截止',
          action: '查看全部',
          onAction: () => widget.onAll(TaskBucket.today),
        ),
        if (today.isEmpty)
          const IosEmpty('今天没有待交作业。看看接下来的一周。')
        else
          IosGroup(
            children: [
              for (final task in today.take(5))
                IosTaskRow(task: task, onTap: () => widget.onTask(task)),
            ],
          ),
        IosSection(
          '未来七天',
          action: '查看全部',
          onAction: () => widget.onAll(TaskBucket.week),
        ),
        if (week.isEmpty)
          const IosEmpty('未来七天没有待交作业。')
        else
          IosGroup(
            children: [
              for (final task in week.take(3))
                IosTaskRow(task: task, onTap: () => widget.onTask(task)),
            ],
          ),
        if (widget.state.error != null || widget.state.notice != null) ...[
          const SizedBox(height: 16),
          Text(
            widget.state.error ?? widget.state.notice!,
            style: TextStyle(fontSize: 15, color: p.textDim),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          '上次同步 ${_syncLabel(widget.state.snapshot?.fetchedAt)} · 北京时间',
          style: TextStyle(fontSize: 13, color: p.textDim),
        ),
        if (widget.state.busy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: CupertinoActivityIndicator(),
          ),
      ],
    );
  }

  Widget _count(BuildContext context, String label, int count, Color color) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: context.palette.textDim),
          ),
        ],
      );
}

String _syncLabel(String? iso) {
  final time = parseDeadline(iso);
  if (time == null) return '尚未同步';
  final wall = beijingTime(time);
  return '${wall.month}/${wall.day} ${wall.hour.toString().padLeft(2, '0')}:${wall.minute.toString().padLeft(2, '0')}';
}

class TasksPage extends StatefulWidget {
  const TasksPage({
    super.key,
    required this.state,
    required this.tasks,
    required this.courses,
    required this.termButton,
    required this.onTask,
    this.bucket,
    this.requestedDay,
    this.requestSerial = 0,
    this.onClearBucket,
    this.detailBuilder,
  });
  final AppState state;
  final List<LearningTask> tasks;
  final List<CourseSummary> courses;
  final Widget termButton;
  final ValueChanged<LearningTask> onTask;
  final TaskBucket? bucket;
  final DateTime? requestedDay;
  final int requestSerial;
  final VoidCallback? onClearBucket;
  final Widget Function(LearningTask)? detailBuilder;
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  bool _calendar = false;
  String _query = '';
  int? _course;
  LearningTask? _selected;
  final _search = TextEditingController();
  late DateTime _day = beijingDay(appNow());
  late DateTime _month = DateTime.utc(_day.year, _day.month);
  @override
  void initState() {
    super.initState();
    final requested = widget.requestedDay;
    if (requested != null) {
      _day = requested;
      _month = DateTime.utc(requested.year, requested.month);
      _calendar = true;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TasksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestSerial != widget.requestSerial) {
      _query = '';
      _search.clear();
      _course = null;
      _selected = null;
      if (widget.requestedDay != null) {
        _day = widget.requestedDay!;
        _month = DateTime.utc(_day.year, _day.month);
        _calendar = true;
      } else {
        _calendar = false;
        _day = beijingDay(appNow());
        _month = DateTime.utc(_day.year, _day.month);
      }
    }
    if (_course != null &&
        !widget.courses.any((course) => course.id == _course)) {
      _course = null;
    }
    if (_selected != null &&
        !widget.tasks.any((task) => task.key == _selected!.key)) {
      _selected = null;
    }
  }

  TaskStatus get _status => TaskStatus.values.firstWhere(
    (value) => value.name == widget.state.prefs.taskFilter,
    orElse: () => TaskStatus.pending,
  );
  List<LearningTask> get _filtered => widget.tasks
      .where(
        (task) =>
            task.status == _status &&
            (_course == null || task.courseId == _course) &&
            '${task.title} ${task.courseName}'.toLowerCase().contains(
              _query.toLowerCase(),
            ) &&
            (widget.bucket == null || task.bucket(appNow()) == widget.bucket),
      )
      .toList();

  void _select(LearningTask task, bool wide) {
    if (wide) {
      setState(() => _selected = task);
    } else {
      widget.onTask(task);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 768;
    final page = IosScrollPage(
      title: '作业',
      trailing: widget.termButton,
      scrollKey: const PageStorageKey('ios-tasks'),
      onRefresh: () => widget.state.refresh(force: true),
      children: [
        CupertinoSearchTextField(
          controller: _search,
          placeholder: '搜索作业或课程',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<bool>(
            groupValue: _calendar,
            children: const {false: Text('列表'), true: Text('日历')},
            onValueChanged: (value) {
              FocusManager.instance.primaryFocus?.unfocus();
              if (value != null) setState(() => _calendar = value);
            },
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              onPressed: () async {
                final status = await iosChoice(context, '作业状态', const {
                  TaskStatus.pending: '未提交',
                  TaskStatus.submitted: '已提交',
                  TaskStatus.ignored: '无需提交',
                }, selected: _status);
                if (status != null) {
                  await widget.state.setTaskFilter(status.name);
                }
              },
              child: IosMenuLabel(switch (_status) {
                TaskStatus.pending => '未提交',
                TaskStatus.submitted => '已提交',
                TaskStatus.ignored => '无需提交',
              }),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              onPressed: () async {
                final choices = <int, String>{
                  -1: '全部课程',
                  for (final course in widget.courses)
                    course.id: course.displayName,
                };
                final value = await iosChoice(
                  context,
                  '课程',
                  choices,
                  selected: _course ?? -1,
                );
                if (value != null && mounted) {
                  setState(() => _course = value == -1 ? null : value);
                }
              },
              child: IosMenuLabel(_course == null ? '全部课程' : '已选课程'),
            ),
            if (widget.bucket != null)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onPressed: widget.onClearBucket,
                child: Text(
                  '${_bucketName(widget.bucket!)} ×',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
          ],
        ),
        if (_calendar) ...[
          MonthCalendar(
            month: _month,
            day: _day,
            tasks: _filtered,
            onMonth: (value) => setState(() {
              _month = value;
              final lastDay = DateTime.utc(value.year, value.month + 1, 0).day;
              _day = DateTime.utc(
                value.year,
                value.month,
                _day.day.clamp(1, lastDay),
              );
            }),
            onDay: (value) => setState(() => _day = value),
          ),
          IosSection('${_day.month}月${_day.day}日'),
          _rows(
            _filtered
                .where(
                  (task) =>
                      task.dueAt != null && beijingDay(task.dueAt!) == _day,
                )
                .toList(),
            wide,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              '北京时间 · 无截止时间的作业请在列表中查看',
              style: TextStyle(color: context.palette.textDim, fontSize: 13),
            ),
          ),
        ] else if (_filtered.isEmpty)
          const IosEmpty('没有符合条件的作业。试试其他状态或课程。', icon: CupertinoIcons.search)
        else ...[
          for (final bucket in TaskBucket.values)
            if (_filtered.any((task) => task.bucket(appNow()) == bucket)) ...[
              IosSection(_bucketName(bucket)),
              _rows(
                _filtered
                    .where((task) => task.bucket(appNow()) == bucket)
                    .toList(),
                wide,
              ),
            ],
        ],
      ],
    );
    if (!wide) return page;
    final selected = _selected;
    return Row(
      children: [
        SizedBox(width: 380, child: page),
        VerticalDivider(width: 1, color: context.palette.border),
        Expanded(
          child: selected == null
              ? const IosEmpty('选择一项作业查看详情。', icon: CupertinoIcons.doc_text)
              : widget.detailBuilder?.call(selected) ??
                    IosScrollPage(
                      title: '作业概况',
                      children: [
                        IosGroup(children: [IosTaskRow(task: selected)]),
                        const SizedBox(height: 20),
                        CupertinoButton.filled(
                          onPressed: () => widget.onTask(selected),
                          child: const Text('查看作业详情'),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _rows(List<LearningTask> tasks, bool wide) => tasks.isEmpty
      ? const IosEmpty('这一天没有符合条件的作业。')
      : IosGroup(
          children: [
            for (final task in tasks)
              IosTaskRow(
                task: task,
                selected: task.key == _selected?.key,
                onTap: () => _select(task, wide),
              ),
          ],
        );
}

String _bucketName(TaskBucket bucket) => switch (bucket) {
  TaskBucket.overdue => '已逾期未交',
  TaskBucket.today => '今天截止',
  TaskBucket.week => '未来七天',
  TaskBucket.later => '其他日期',
  TaskBucket.undated => '无截止时间',
};

class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.day,
    required this.tasks,
    required this.onMonth,
    required this.onDay,
  });
  final DateTime month;
  final DateTime day;
  final List<LearningTask> tasks;
  final ValueChanged<DateTime> onMonth;
  final ValueChanged<DateTime> onDay;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final counts = <String, int>{};
    for (final task in tasks) {
      if (task.dueAt != null) {
        counts.update(
          dayKey(beijingDay(task.dueAt!)),
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final start = DateTime.utc(month.year, month.month);
    final days = DateTime.utc(month.year, month.month + 1, 0).day;
    final offset = start.weekday - 1;
    final weeks = ((days + offset) / 7).ceil();
    final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
    final cellHeight = 52.0 * scale.clamp(1.0, 2.5);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CupertinoButton(
                padding: const EdgeInsets.all(10),
                onPressed: () =>
                    onMonth(DateTime.utc(month.year, month.month - 1)),
                child: const Icon(CupertinoIcons.chevron_back, size: 20),
              ),
              Expanded(
                child: Text(
                  '${month.year}年${month.month}月',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    color: p.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.all(10),
                onPressed: () =>
                    onMonth(DateTime.utc(month.year, month.month + 1)),
                child: const Icon(CupertinoIcons.chevron_forward, size: 20),
              ),
            ],
          ),
          Row(
            children: [
              for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.textDim, fontSize: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var week = 0; week < weeks; week++)
            Row(
              children: [
                for (var weekday = 0; weekday < 7; weekday++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final number = week * 7 + weekday - offset + 1;
                        if (number < 1 || number > days) {
                          return SizedBox(height: cellHeight);
                        }
                        final value = DateTime.utc(
                          month.year,
                          month.month,
                          number,
                        );
                        final count = counts[dayKey(value)] ?? 0;
                        final selected = value == day;
                        final today = value == beijingDay(appNow());
                        return Semantics(
                          label: '${month.month}月$number日，$count 项作业',
                          selected: selected,
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => onDay(value),
                            child: Container(
                              height: cellHeight,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected ? p.accent : null,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$number',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: today
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: selected
                                          ? Colors.white
                                          : today
                                          ? p.accent
                                          : p.text,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    count == 0 ? '' : '$count',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: selected
                                          ? Colors.white
                                          : p.textDim,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
