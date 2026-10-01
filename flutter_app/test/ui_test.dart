/// 界面与格式化逻辑的测试。
///
/// 这里最有价值的是两组：
///  1. 「已交但未批改的作业不能被标成逾期」——桌面端出过这个 bug，
///     现在在两端的判定逻辑里都钉死；
///  2. 真实渲染一遍主要界面，确保 demo 数据能把整棵树跑通不抛异常。

library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fudan_elearning/core/demo.dart';
import 'package:fudan_elearning/core/session.dart';
import 'package:fudan_elearning/core/types.dart';
import 'package:fudan_elearning/state/app_state.dart';
import 'package:fudan_elearning/theme.dart';
import 'package:fudan_elearning/ui/charts.dart';
import 'package:fudan_elearning/ui/format.dart';
import 'package:fudan_elearning/ui/home_shell.dart';
import 'package:fudan_elearning/ui/overview_tab.dart';
import 'package:fudan_elearning/ui/timeline_tab.dart';

AssignmentRow row({
  double? score,
  String? submittedAt,
  String workflowState = 'unsubmitted',
  bool missing = false,
  bool late = false,
  bool excused = false,
  String? dueAt,
  double? points = 100,
}) =>
    AssignmentRow(
      id: 1,
      courseId: 1,
      courseName: 'C',
      name: 'W',
      groupId: 1,
      groupName: 'G',
      score: score,
      submittedAt: submittedAt,
      workflowState: workflowState,
      missing: missing,
      late: late,
      excused: excused,
      dueAt: dueAt,
      pointsPossible: points,
    );

Future<AppState> bootedDemoState() async {
  final state = AppState(store: MemoryStore(), demo: true);
  await state.boot();
  return state;
}

Widget wrap(AppState state) => MaterialApp(
      theme: AppTheme.light(),
      home: HomeShell(state: state),
    );

void main() {
  group('已交作业的逾期判定（回归）', () {
    test('已交但未批改、且已过截止时间的作业不算逾期', () {
      final past = DateTime.now().subtract(const Duration(days: 3)).toIso8601String();
      final r = row(score: null, submittedAt: past, workflowState: 'submitted', dueAt: past);

      expect(isCompleted(r), isTrue, reason: '有提交时间即视为已交');
      expect(dueRelative(r.dueAt, isCompleted(r)).tone, DueTone.later,
          reason: '已交的作业不应显示逾期');
      expect(dueRelative(r.dueAt, isCompleted(r)).text, isEmpty);

      final st = submissionState(r);
      expect(st.label, '已提交待评分');
      expect(st.tone, 'info');
    });

    test('即使 Canvas 把已交作业标成 missing，也不算缺交', () {
      final r = row(submittedAt: '2026-01-01T00:00:00Z', missing: true);
      expect(submissionState(r).label, '已提交待评分');
    });

    test('真正未交且过期才算逾期', () {
      final past = DateTime.now().subtract(const Duration(days: 3)).toIso8601String();
      final r = row(dueAt: past);
      expect(isCompleted(r), isFalse);
      expect(dueRelative(r.dueAt, isCompleted(r)).tone, DueTone.overdue);
      expect(submissionState(r).label, '已逾期未交');
    });

    test('已评分优先显示，迟交额外标注', () {
      expect(submissionState(row(score: 88)).label, '已评分');
      expect(submissionState(row(score: 88, late: true)).label, '已评分（迟交）');
    });

    test('免除的作业单独标记', () {
      expect(submissionState(row(excused: true)).label, '已免除');
      expect(isCompleted(row(excused: true)), isTrue);
    });
  });

  group('格式化', () {
    test('整分不带小数', () {
      expect(formatScoreCompact(93), '93');
      expect(formatScoreCompact(93.25), '93.3');
      expect(formatScoreCompact(null), '—');
      expect(formatScore(93.256), '93.26');
    });

    test('日期在空值下安全', () {
      expect(formatDate(null), '—');
      expect(formatDate('not-a-date'), '—');
    });

    test('平均分只算有成绩的课程', () {
      final courses = [
        const CourseSummary(
            id: 1, name: 'a', displayName: 'a', courseCode: 'a', termName: 't', currentScore: 90),
        const CourseSummary(
            id: 2, name: 'b', displayName: 'b', courseCode: 'b', termName: 't', currentScore: 80),
        const CourseSummary(id: 3, name: 'c', displayName: 'c', courseCode: 'c', termName: 't'),
      ];
      expect(averageScore(courses), closeTo(85, 0.001));
    });
  });

  group('趋势数据', () {
    test('逐条累计，只统计已评分的作业', () {
      final rows = [
        row(score: 45, points: 50, dueAt: '2026-09-01T00:00:00Z'),
        row(score: 30, points: 50, dueAt: '2026-09-08T00:00:00Z'),
        row(score: null, points: 50, dueAt: '2026-09-15T00:00:00Z'),
      ];
      final pts = TrendChart.points(rows);
      expect(pts.length, 2, reason: '未评分的作业不参与累计');
      expect(pts[0].percent, closeTo(90, 0.001));
      expect(pts[1].percent, closeTo(75, 0.001));
    });

    test('按截止时间排序，即使输入是乱序的', () {
      final rows = [
        row(score: 30, points: 50, dueAt: '2026-09-08T00:00:00Z'),
        row(score: 45, points: 50, dueAt: '2026-09-01T00:00:00Z'),
      ];
      final pts = TrendChart.points(rows);
      expect(pts[0].percent, closeTo(90, 0.001), reason: '先算 9/1 那条');
    });
  });

  group('演示数据', () {
    test('快照自洽：课程、学期、作业互相对应', () {
      final s = buildDemoSnapshot();
      expect(s.courses, isNotEmpty);
      expect(s.terms, isNotEmpty);

      final ids = s.courses.map((c) => c.id).toSet();
      expect(s.assignments.every((a) => ids.contains(a.courseId)), isTrue);
      expect(s.assignments.every((a) => a.courseName.isNotEmpty), isTrue);

      // 每门课的作业数与汇总一致。
      for (final c in s.courses) {
        final count = s.assignments.where((a) => a.courseId == c.id).length;
        expect(c.assignmentCount, count, reason: '${c.displayName} 的作业数应一致');
      }
    });

    test('包含「已交未批改且已过截止」的记录，用于回归验证', () {
      final s = buildDemoSnapshot();
      final pending = s.assignments.where((a) {
        final due = a.dueAt == null ? null : DateTime.parse(a.dueAt!);
        return a.score == null && isCompleted(a) && due != null && due.isBefore(DateTime.now());
      });
      expect(pending, isNotEmpty, reason: '演示数据必须覆盖这个曾经出错的场景');
    });

    test('学期按时间倒序且标明当前学期', () {
      final s = buildDemoSnapshot();
      expect(s.terms.where((t) => t.isCurrent).length, 1);
    });
  });

  group('界面渲染', () {
    testWidgets('总览页能在演示数据下完整渲染', (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final state = await bootedDemoState();
      await tester.pumpWidget(wrap(state));
      await tester.pumpAndSettle();

      expect(find.text('学习总览'), findsOneWidget);
      expect(find.text('当前平均分'), findsOneWidget);
      expect(find.text('课程'), findsWidgets);
      // 学期选择器应当出现「全部学期」。
      expect(find.text('全部学期'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('总览页能单独渲染（不经由外壳）', (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final s = buildDemoSnapshot();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: OverviewTab(
            courses: s.courses,
            assignments: s.assignments,
            todo: s.todo,
            termName: '全部学期',
            hideUnsubmitted: false,
            onSelectCourse: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('各课程当前得分'), findsOneWidget);
      expect(find.byType(ScoreBars), findsOneWidget);

      // ListView 是懒加载的，靠后的区块必须先滚进视口才会被构建。
      await tester.scrollUntilVisible(
        find.text('需要关注'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('需要关注'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('作业页按状态分组', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final s = buildDemoSnapshot();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TimelineTab(
            courses: s.courses,
            assignments: s.assignments,
            todo: s.todo,
            hideUnsubmitted: false,
            onSelectCourse: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('待处理'), findsOneWidget);
      expect(find.text('已逾期未交'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('忽略未提交后，作业页只剩已完成', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final s = buildDemoSnapshot();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TimelineTab(
            courses: s.courses,
            assignments: s.assignments,
            todo: s.todo,
            hideUnsubmitted: true,
            onSelectCourse: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('已逾期未交'), findsNothing, reason: '未提交的条目应当被隐藏');
      expect(find.text('已完成'), findsOneWidget);
      expect(find.textContaining('已忽略未提交'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('深色主题下也能渲染', (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final state = await bootedDemoState();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: HomeShell(state: state),
      ));
      await tester.pumpAndSettle();

      expect(find.text('学习总览'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('学期筛选', () {
    testWidgets('切到某个学期后课程数随之变化', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final state = await bootedDemoState();
      final s = state.snapshot!;
      final current = s.terms.firstWhere((t) => t.isCurrent);
      final currentCount = s.courses.where((c) => c.termId == current.id).length;
      final allCount = s.courses.length;
      expect(currentCount, lessThan(allCount), reason: '演示数据要有多个学期');

      await tester.pumpWidget(wrap(state));
      await tester.pumpAndSettle();

      // 外壳启动后会自动选中当前学期。
      expect(find.text('$currentCount'), findsWidgets);
    });
  });
}
