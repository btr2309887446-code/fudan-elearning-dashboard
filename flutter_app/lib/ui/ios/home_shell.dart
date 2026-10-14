import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/clock.dart';
import '../../core/tasks.dart';
import '../../core/types.dart';
import '../../platform/calendar_service.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import 'assignment_page.dart';
import 'components.dart';
import 'course_pages.dart';
import 'profile_page.dart';
import 'task_pages.dart';

class IosHomeShell extends StatefulWidget {
  const IosHomeShell({super.key, required this.state, required this.calendar});
  final AppState state;
  final CalendarService calendar;
  @override
  State<IosHomeShell> createState() => _IosHomeShellState();
}

class _IosHomeShellState extends State<IosHomeShell>
    with WidgetsBindingObserver {
  final _tabs = CupertinoTabController();
  final _navigators = List.generate(4, (_) => GlobalKey<NavigatorState>());
  String _term = 'default';
  TaskBucket? _bucket;
  DateTime? _requestedDay;
  int _requestSerial = 0;
  Timer? _timer;
  late String _today = dayKey(beijingDay(appNow()));
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_onState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onState());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final day = dayKey(beijingDay(appNow()));
      setState(() {});
      if (day != _today) {
        _today = day;
        unawaited(widget.state.reconcileReminders());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.state.removeListener(_onState);
    WidgetsBinding.instance.removeObserver(this);
    _tabs.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.state.refreshIfStale());
    }
  }

  void _onState() {
    final day = widget.state.pendingReminderDay;
    if (day == null || widget.state.snapshot == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.state.pendingReminderDay != day) return;
      widget.state.pendingReminderDay = null;
      _navigators[1].currentState?.popUntil((route) => route.isFirst);
      setState(() {
        _term = 'default';
        _bucket = null;
        _requestedDay = parseDayKey(day);
        _requestSerial++;
      });
      unawaited(widget.state.setTaskFilter('pending'));
      _tabs.index = 1;
    });
  }

  String _termKey(int? id) => 'term:${id ?? 'none'}';
  int? _activeTerm(Snapshot snapshot) {
    final selected = _term == 'default'
        ? defaultTermId(snapshot)
        : _term == 'term:none'
        ? null
        : int.tryParse(_term.replaceFirst('term:', ''));
    return snapshot.terms.any((term) => term.id == selected)
        ? selected
        : defaultTermId(snapshot);
  }

  List<CourseSummary> _courses(Snapshot snapshot) => _term == 'all'
      ? snapshot.courses
      : snapshot.courses
            .where((course) => course.termId == _activeTerm(snapshot))
            .toList();
  Future<void> _all(TaskBucket? bucket) async {
    await widget.state.setTaskFilter('pending');
    if (!mounted) return;
    _navigators[1].currentState?.popUntil((route) => route.isFirst);
    setState(() {
      _bucket = bucket;
      _requestedDay = null;
      _requestSerial++;
    });
    _tabs.index = 1;
  }

  Widget _termButton(BuildContext context, Snapshot snapshot) {
    final selected = _term == 'all' ? 'all' : _termKey(_activeTerm(snapshot));
    final choices = {
      'all': '全部学期',
      for (final term in snapshot.terms) _termKey(term.id): term.name,
    };
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () async {
        final value = await iosChoice(
          context,
          '选择学期',
          choices,
          selected: selected,
        );
        if (value != null && mounted) {
          setState(() {
            _term = value;
            _bucket = null;
          });
        }
      },
      child: SizedBox(
        width: 140,
        child: IosMenuLabel(
          selected == _termKey(defaultTermId(snapshot))
              ? '当前学期'
              : selected == 'all'
              ? '全部学期'
              : RegExp(
                      r'\d{4}-\d{4}',
                    ).firstMatch(choices[selected] ?? '')?.group(0) ??
                    '选择学期',
          fontSize: 13,
        ),
      ),
    );
  }

  void _task(BuildContext context, LearningTask task) {
    if (task.assignment == null) {
      if (task.url != null) {
        unawaited(widget.state.openUrl(task.url!));
      } else {
        unawaited(iosMessage(context, '这项待办暂时没有可打开的链接。'));
      }
      return;
    }
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => IosAssignmentPage(
          state: widget.state,
          task: task,
          calendar: widget.calendar,
        ),
      ),
    );
  }

  void _course(BuildContext context, int id) => Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (ctx) => IosCourseDetailPage(
        state: widget.state,
        courseId: id,
        onTask: (task) => _task(ctx, task),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CupertinoTheme(
      data: CupertinoThemeData(
        brightness: Theme.of(context).brightness,
        primaryColor: p.accent,
        scaffoldBackgroundColor: p.background,
        barBackgroundColor: p.surface,
        textTheme: CupertinoTextThemeData(
          navActionTextStyle: TextStyle(
            inherit: false,
            fontSize: 17,
            color: p.accent,
            fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
          ),
          navTitleTextStyle: TextStyle(
            inherit: false,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: p.text,
            fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
          ),
          navLargeTitleTextStyle: TextStyle(
            inherit: false,
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: p.text,
            fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
          ),
          actionTextStyle: TextStyle(
            inherit: false,
            fontSize: 17,
            color: p.accent,
            fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
          ),
          tabLabelTextStyle: TextStyle(
            inherit: false,
            fontSize: 13,
            color: p.textDim,
            fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
          ),
          textStyle: TextStyle(
            inherit: false,
            fontSize: 17,
            color: p.text,
            fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
          ),
        ),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          inherit: false,
          fontSize: 17,
          color: p.text,
          decoration: TextDecoration.none,
          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
        ),
        child: CupertinoTabScaffold(
          controller: _tabs,
          backgroundColor: p.background,
          tabBar: CupertinoTabBar(
            backgroundColor: p.surface,
            activeColor: p.accent,
            inactiveColor: p.textDim,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.sun_max),
                activeIcon: Icon(CupertinoIcons.sun_max_fill),
                label: '今日',
              ),
              BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.check_mark_circled),
                activeIcon: Icon(CupertinoIcons.check_mark_circled_solid),
                label: '作业',
              ),
              BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.book),
                activeIcon: Icon(CupertinoIcons.book_fill),
                label: '课程',
              ),
              BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.person_crop_circle),
                activeIcon: Icon(CupertinoIcons.person_crop_circle_fill),
                label: '我的',
              ),
            ],
          ),
          tabBuilder: (context, index) => CupertinoTabView(
            navigatorKey: _navigators[index],
            builder: (ctx) => AnimatedBuilder(
              animation: widget.state,
              builder: (context, _) {
                final snapshot = widget.state.snapshot;
                if (index == 3) return ProfilePage(state: widget.state);
                if (snapshot == null) {
                  return IosScrollPage(
                    title: ['今日', '作业', '课程'][index],
                    onRefresh: () => widget.state.refresh(force: true),
                    children: [
                      IosEmpty(
                        widget.state.busy ? '正在同步学习数据…' : '还没有同步的数据。',
                        action: '立即同步',
                        onAction: () => widget.state.refresh(force: true),
                      ),
                      if (widget.state.error != null)
                        Text(
                          widget.state.error!,
                          style: TextStyle(color: p.textDim, fontSize: 15),
                        ),
                    ],
                  );
                }
                final courses = _courses(snapshot);
                final tasks = buildTasks(
                  snapshot,
                  ignored: widget.state.ignoredSet,
                  courseIds: courses.map((course) => course.id).toSet(),
                );
                final term = _termButton(ctx, snapshot);
                return switch (index) {
                  0 => TodayPage(
                    state: widget.state,
                    tasks: tasks,
                    termButton: term,
                    termName: snapshot.terms.isEmpty
                        ? '未指定学期'
                        : _term == 'all'
                        ? '全部学期'
                        : snapshot.terms
                              .firstWhere(
                                (value) => value.id == _activeTerm(snapshot),
                                orElse: () => snapshot.terms.first,
                              )
                              .name,
                    onTask: (task) => _task(ctx, task),
                    onAll: _all,
                  ),
                  1 => TasksPage(
                    state: widget.state,
                    tasks: tasks,
                    courses: courses,
                    termButton: term,
                    onTask: (task) => _task(ctx, task),
                    bucket: _bucket,
                    requestedDay: _requestedDay,
                    requestSerial: _requestSerial,
                    detailBuilder: (task) => task.assignment == null
                        ? IosEmpty(
                            '此待办需在 eLearning 中查看。',
                            action: '前往 eLearning',
                            onAction: () => _task(ctx, task),
                          )
                        : IosAssignmentPage(
                            key: ValueKey(task.key),
                            state: widget.state,
                            task: task,
                            calendar: widget.calendar,
                            embedded: true,
                          ),
                    onClearBucket: () => setState(() => _bucket = null),
                  ),
                  _ => CoursesPage(
                    state: widget.state,
                    courses: courses,
                    tasks: tasks,
                    termButton: term,
                    onTask: (task) => _task(ctx, task),
                    onCourse: (id) => _course(ctx, id),
                    onScores: () => Navigator.of(ctx).push(
                      CupertinoPageRoute<void>(
                        builder: (scoresCtx) => IosScoresPage(
                          courses: courses,
                          onCourse: (id) => _course(scoresCtx, id),
                        ),
                      ),
                    ),
                  ),
                };
              },
            ),
          ),
        ),
      ),
    );
  }
}
