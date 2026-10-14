import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show MaterialApp, AnimatedBuilder, TargetPlatform, ThemeMode;
import 'package:fudan_elearning/core/types.dart';
import 'package:fudan_elearning/theme.dart';
import 'package:fudan_elearning/ui/home_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fudan_elearning/core/clock.dart';
import 'package:fudan_elearning/ui/files_section.dart';
import 'package:fudan_elearning/ui/ios/assignment_page.dart';
import 'package:fudan_elearning/ui/ios/course_pages.dart';
import 'package:fudan_elearning/ui/ios/task_pages.dart';
import 'support/ios_fixture.dart';
import 'package:fudan_elearning/platform/calendar_service.dart';
import 'package:fudan_elearning/core/tasks.dart';
import 'package:fudan_elearning/ui/ios/components.dart';

class FakeCalendar implements CalendarService {
  CalendarResult result = CalendarResult.saved;
  int calls = 0;
  @override
  Future<CalendarResult> add(LearningTask task) async {
    calls++;
    return result;
  }
}

void main() {
  setUpAll(loadIosFonts);
  setUp(() => appNow = () => DateTime.utc(2026, 3, 15, 1));
  tearDown(() => appNow = DateTime.now);
  testWidgets('四个入口，首屏可见两项今日任务，点击直接查看详情', (tester) async {
    phoneViewport(tester);
    final state = await iosFixture();
    await tester.pumpWidget(iosTestApp(state));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoTabBar), findsOneWidget);
    for (final label in ['今日', '作业', '课程', '我的']) {
      expect(find.text(label), findsWidgets);
    }
    for (final title in [fixtureTitle1, fixtureTitle2]) {
      expect(find.text(title).hitTestable(), findsOneWidget);
      expect(tester.getRect(find.text(title)).bottom, lessThan(760));
    }
    await tester.tap(find.text(fixtureTitle1));
    await tester.pumpAndSettle();
    expect(find.byType(IosAssignmentPage), findsOneWidget);
    expect(
      tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar)).currentIndex,
      0,
    );
    expect(find.byType(IosCourseDetailPage), findsNothing);
    expect(find.text('前往 eLearning'), findsOneWidget);
  });
  testWidgets('搜索、已提交筛选与月历切换', (tester) async {
    phoneViewport(tester);
    final state = await iosFixture();
    await tester.pumpWidget(iosTestApp(state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作业').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoSearchTextField), '链表与队列');
    await tester.pumpAndSettle();
    expect(find.text(fixtureTitle2), findsOneWidget);
    expect(find.text(fixtureTitle1), findsNothing);
    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthCalendar), findsOneWidget);
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(find.text(fixtureTitle2), findsOneWidget);
    await state.setTaskFilter('submitted');
    await tester.pumpAndSettle();
    expect(find.text(fixtureTitle2), findsNothing);
  });
  testWidgets('通知日期跳转当天日历列表', (tester) async {
    phoneViewport(tester);
    final state = await iosFixture();
    await tester.pumpWidget(iosTestApp(state));
    await tester.pumpAndSettle();
    state.openReminderDay('2026-03-16');
    await tester.pumpAndSettle();
    expect(find.byType(MonthCalendar), findsOneWidget);
    expect(find.text('3月16日'), findsWidgets);
    expect(state.pendingReminderDay, isNull);
  });
  testWidgets('课程默认作业，文件进入选择模式才显示批量操作', (tester) async {
    phoneViewport(tester);
    final state = await iosFixture();
    await tester.pumpWidget(iosTestApp(state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .text(readableCourseName(state.snapshot!.courses.first.displayName))
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(IosCourseDetailPage), findsOneWidget);
    expect(find.byType(FilesSection), findsNothing);
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(find.byType(FilesSection), findsOneWidget);
    expect(find.text('下载选中'), findsNothing);
    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();
    expect(find.text('下载选中'), findsOneWidget);
    await tester.ensureVisible(find.text('课程大纲.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程大纲.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 个文件'), findsOneWidget);
  });
  testWidgets('日历保存后记录，重复添加可取消且不创建事件', (tester) async {
    phoneViewport(tester);
    final state = await iosFixture();
    final calendar = FakeCalendar();
    await tester.pumpWidget(iosTestApp(state, calendar: calendar));
    await tester.pumpAndSettle();
    await tester.tap(find.text(fixtureTitle1));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('添加到系统日历'));
    await tester.tap(find.text('添加到系统日历'));
    await tester.pumpAndSettle();
    expect(calendar.calls, 1);
    expect(state.prefs.calendarExports, hasLength(1));
    await tester.tap(find.text('好'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('已添加到系统日历'));
    await tester.tap(find.text('已添加到系统日历'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(calendar.calls, 1);
    calendar.result = CalendarResult.cancelled;
    await tester.tap(find.text('已添加到系统日历'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续添加'));
    await tester.pumpAndSettle();
    expect(calendar.calls, 2);
    expect(state.prefs.calendarExports, hasLength(1));
  });
  testWidgets('标记无需提交后返回首页不再显示该任务', (tester) async {
    phoneViewport(tester);
    final state = await iosFixture();
    await tester.pumpWidget(iosTestApp(state));
    await tester.pumpAndSettle();
    await tester.tap(find.text(fixtureTitle1));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('无需提交'));
    await tester.tap(find.byType(CupertinoSwitch).last);
    await tester.pumpAndSettle();
    expect(
      state.tasks.firstWhere((task) => task.title == fixtureTitle1).status,
      TaskStatus.ignored,
    );
    await tester.tap(find.byType(CupertinoNavigationBarBackButton));
    await tester.pumpAndSettle();
    expect(find.text(fixtureTitle1), findsNothing);
  });
  testWidgets('冷启动通知携带日期也能进入对应月历', (tester) async {
    phoneViewport(tester);
    final state = await iosFixture();
    state.openReminderDay('2026-03-16');
    await tester.pumpWidget(iosTestApp(state));
    await tester.pumpAndSettle();
    expect(find.byType(MonthCalendar), findsOneWidget);
    expect(find.text('3月16日'), findsWidgets);
  });
  testWidgets('通知等待首次数据加载时，导航重建仍保留目标日期', (tester) async {
    phoneViewport(tester);
    final state = await iosFixture();
    final data = state.snapshot!;
    state.snapshot = null;
    state.openReminderDay('2026-03-16');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(
          platform: TargetPlatform.iOS,
          fontFamily: 'IosTestCjk',
        ),
        home: AnimatedBuilder(
          animation: state,
          builder: (_, _) => HomeShell(state: state),
        ),
      ),
    );
    await tester.pumpAndSettle();
    state.snapshot = data;
    await state.setThemeMode(ThemeMode.system);
    await tester.pumpAndSettle();
    expect(find.byType(MonthCalendar), findsOneWidget);
    expect(find.text('3月16日'), findsWidgets);
  });
  testWidgets('账号变化后清除旧详情导航', (tester) async {
    phoneViewport(tester);
    final state = await iosFixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(
          platform: TargetPlatform.iOS,
          fontFamily: 'IosTestCjk',
        ),
        home: AnimatedBuilder(
          animation: state,
          builder: (_, _) => HomeShell(state: state),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(fixtureTitle1));
    await tester.pumpAndSettle();
    expect(find.byType(IosAssignmentPage), findsOneWidget);
    final data = state.snapshot!;
    state.snapshot = Snapshot(
      fetchedAt: data.fetchedAt,
      profile: const CanvasProfile(id: 777, name: '新账号'),
      courses: data.courses,
      terms: data.terms,
      assignments: data.assignments,
      todo: data.todo,
    );
    await state.setThemeMode(ThemeMode.system);
    await tester.pumpAndSettle();
    expect(find.byType(IosAssignmentPage), findsNothing);
    expect(
      tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar)).currentIndex,
      0,
    );
  });
  for (final dark in [false, true]) {
    testWidgets('两倍字号${dark ? '深色' : '浅色'}四页无溢出', (tester) async {
      phoneViewport(tester);
      final state = await iosFixture();
      await tester.pumpWidget(iosTestApp(state, dark: dark, scale: 2));
      await tester.pumpAndSettle();
      for (final label in ['作业', '课程', '我的', '今日']) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets('iPad 作业选择后在右侧显示完整详情', (tester) async {
    phoneViewport(tester, size: const Size(1194, 834));
    final state = await iosFixture();
    await tester.pumpWidget(iosTestApp(state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作业').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(fixtureTitle1));
    await tester.tap(find.text(fixtureTitle1));
    await tester.pumpAndSettle();
    expect(find.byType(IosAssignmentPage), findsOneWidget);
    expect(find.byType(TasksPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
