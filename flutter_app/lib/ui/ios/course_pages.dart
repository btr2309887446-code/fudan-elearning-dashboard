import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/scoring.dart';
import '../../core/tasks.dart';
import '../../core/types.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../charts.dart';
import '../files_section.dart';
import '../format.dart';
import 'components.dart';

class CoursesPage extends StatefulWidget {
  const CoursesPage({
    super.key,
    required this.state,
    required this.courses,
    required this.tasks,
    required this.termButton,
    required this.onCourse,
    required this.onTask,
    required this.onScores,
  });
  final AppState state;
  final List<CourseSummary> courses;
  final List<LearningTask> tasks;
  final Widget termButton;
  final ValueChanged<int> onCourse;
  final ValueChanged<LearningTask> onTask;
  final VoidCallback onScores;
  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  String _query = '';
  int? _selected;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final wide = MediaQuery.sizeOf(context).width >= 768;
    final courses = widget.courses
        .where(
          (course) => '${course.displayName} ${course.courseCode}'
              .toLowerCase()
              .contains(_query.toLowerCase()),
        )
        .toList();
    final page = IosScrollPage(
      title: '课程',
      trailing: widget.termButton,
      scrollKey: const PageStorageKey('ios-courses'),
      onRefresh: () => widget.state.refresh(force: true),
      children: [
        CupertinoSearchTextField(
          placeholder: '搜索课程',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 12),
        IosGroup(
          children: [
            CupertinoListTile(
              title: const Text('成绩概览'),
              subtitle: const Text('查看当前学期的得分与趋势'),
              leading: Icon(CupertinoIcons.chart_bar, color: p.accent),
              trailing: const CupertinoListTileChevron(),
              onTap: widget.onScores,
            ),
          ],
        ),
        const IosSection('我的课程'),
        if (courses.isEmpty)
          const IosEmpty('没有找到课程。试试切换学期或清除搜索。', icon: CupertinoIcons.book)
        else
          IosGroup(
            children: [
              for (final course in courses)
                CupertinoButton(
                  padding: const EdgeInsets.all(16),
                  onPressed: () {
                    if (wide) {
                      setState(() => _selected = course.id);
                    } else {
                      widget.onCourse(course.id);
                    }
                  },
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(CupertinoIcons.book, color: p.accent, size: 23),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              readableCourseName(course.displayName),
                              style: TextStyle(
                                fontSize: 17,
                                color: p.text,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${course.courseCode}\n${course.termName}',
                              style: TextStyle(fontSize: 13, color: p.textDim),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${widget.tasks.where((task) => task.courseId == course.id && task.status == TaskStatus.pending).length} 项待交',
                              style: TextStyle(fontSize: 15, color: p.textDim),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        CupertinoIcons.chevron_forward,
                        size: 14,
                        color: p.textDim,
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
    if (!wide) return page;
    final selected = widget.courses.any((course) => course.id == _selected)
        ? _selected
        : null;
    return Row(
      children: [
        SizedBox(width: 360, child: page),
        VerticalDivider(width: 1, color: p.border),
        Expanded(
          child: selected == null
              ? const IosEmpty('选择一门课程查看作业、成绩与文件。', icon: CupertinoIcons.book)
              : IosCourseDetailPage(
                  key: ValueKey(selected),
                  state: widget.state,
                  courseId: selected,
                  onTask: widget.onTask,
                  embedded: true,
                ),
        ),
      ],
    );
  }
}

class IosCourseDetailPage extends StatefulWidget {
  const IosCourseDetailPage({
    super.key,
    required this.state,
    required this.courseId,
    required this.onTask,
    this.embedded = false,
  });
  final AppState state;
  final int courseId;
  final ValueChanged<LearningTask> onTask;
  final bool embedded;
  @override
  State<IosCourseDetailPage> createState() => _IosCourseDetailPageState();
}

class _IosCourseDetailPageState extends State<IosCourseDetailPage> {
  int _segment = 0;
  TaskStatus? _filter = TaskStatus.pending;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final p = context.palette;
      final snapshot = widget.state.snapshot;
      final detail = snapshot == null
          ? null
          : buildCourseDetail(snapshot, widget.courseId);
      if (detail == null) return const IosEmpty('找不到这门课程。');
      final course = detail.course;
      final tasks = widget.state.tasks
          .where(
            (task) =>
                task.courseId == widget.courseId &&
                (_filter == null || task.status == _filter),
          )
          .toList();
      return CupertinoPageScaffold(
        backgroundColor: p.background,
        navigationBar: CupertinoNavigationBar(
          middle: const Text('课程详情'),
          automaticallyImplyLeading: !widget.embedded,
          backgroundColor: p.background,
          border: null,
        ),
        child: SafeArea(
          child: CustomScrollView(
            key: PageStorageKey('course:${widget.courseId}:$_segment'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(
                      readableCourseName(course.displayName),
                      style: TextStyle(
                        fontSize: 24,
                        color: p.text,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${course.courseCode}\n${course.termName}',
                      style: TextStyle(
                        fontSize: 13,
                        color: p.textDim,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoSlidingSegmentedControl<int>(
                        groupValue: _segment,
                        children: const {
                          0: Text('作业'),
                          1: Text('成绩'),
                          2: Text('文件'),
                        },
                        onValueChanged: (value) {
                          if (value != null) setState(() => _segment = value);
                        },
                      ),
                    ),
                    if (_segment == 0) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () async {
                            final value = await iosChoice(
                              context,
                              '作业状态',
                              const {0: '未提交', 1: '已提交', 2: '无需提交', 3: '全部作业'},
                            );
                            if (value != null && mounted) {
                              setState(
                                () => _filter = value == 3
                                    ? null
                                    : TaskStatus.values[value],
                              );
                            }
                          },
                          child: IosMenuLabel(
                            _filter == null
                                ? '全部作业'
                                : switch (_filter!) {
                                    TaskStatus.pending => '未提交',
                                    TaskStatus.submitted => '已提交',
                                    TaskStatus.ignored => '无需提交',
                                  },
                          ),
                        ),
                      ),
                      if (tasks.isEmpty)
                        const IosEmpty('这个范围内没有作业。')
                      else
                        IosGroup(
                          children: [
                            for (final task in tasks)
                              IosTaskRow(
                                task: task,
                                onTap: () => widget.onTask(task),
                              ),
                          ],
                        ),
                    ] else if (_segment == 1) ...[
                      const IosSection('eLearning 当前得分'),
                      _panel(
                        context,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatScoreCompact(course.currentScore),
                              style: TextStyle(
                                fontSize: 36,
                                color: p.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${course.gradedCount} / ${course.assignmentCount} 项已评分',
                              style: TextStyle(color: p.textDim, fontSize: 15),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${detail.gradingScheme == 'weighted' ? '按作业分组权重计算' : '按已评分总分计算'}，不代表教务处正式成绩。',
                              style: TextStyle(
                                color: p.textDim,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                            if (course.finalScore != null)
                              Text(
                                '最终得分 ${formatScoreCompact(course.finalScore)}',
                                style: TextStyle(fontSize: 15, color: p.text),
                              ),
                          ],
                        ),
                      ),
                      const IosSection('得分趋势'),
                      _panel(context, TrendChart(rows: detail.assignments)),
                      const IosSection('作业分组'),
                      IosGroup(
                        children: [
                          for (final group in detail.groups)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${group.name}${group.weight > 0 ? ' · 权重 ${group.weight.round()}%' : ''}',
                                    style: TextStyle(
                                      fontSize: 17,
                                      color: p.text,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    group.percent == null
                                        ? '尚未评分'
                                        : '${formatScoreCompact(group.percent)}% · ${formatScoreCompact(group.earned)} / ${formatScoreCompact(group.possible)} 分',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: p.textDim,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  ThinBarProxy(
                                    percent: group.percent,
                                    color: p.accent,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 20),
                      FilesSection(
                        state: widget.state,
                        courseId: widget.courseId,
                        ios: true,
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _panel(BuildContext context, Widget child) => Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: context.palette.surface,
    borderRadius: BorderRadius.circular(14),
  ),
  child: child,
);

class IosScoresPage extends StatelessWidget {
  const IosScoresPage({
    super.key,
    required this.courses,
    required this.onCourse,
  });
  final List<CourseSummary> courses;
  final ValueChanged<int> onCourse;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scored = courses
        .where((course) => course.currentScore != null)
        .toList();
    return IosScrollPage(
      title: '成绩概览',
      children: [
        Text(
          '平均得分 ${formatScoreCompact(averageScore(courses))}',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: p.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${scored.length} 门课程已有得分 · 仅为 eLearning 教学数据',
          style: TextStyle(fontSize: 13, color: p.textDim),
        ),
        const IosSection('各课程得分'),
        IosGroup(
          children: [
            for (final course in courses)
              CupertinoButton(
                padding: const EdgeInsets.all(16),
                onPressed: () => onCourse(course.id),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      readableCourseName(course.displayName),
                      style: TextStyle(fontSize: 17, color: p.text),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      course.currentScore == null
                          ? '暂无已评分作业'
                          : '${formatScoreCompact(course.currentScore)} 分',
                      style: TextStyle(fontSize: 15, color: p.textDim),
                    ),
                    const SizedBox(height: 10),
                    ThinBarProxy(percent: course.currentScore, color: p.accent),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
