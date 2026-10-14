import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fudan_elearning/core/clock.dart';
import 'package:fudan_elearning/core/session.dart';
import 'package:fudan_elearning/core/tasks.dart';
import 'package:fudan_elearning/core/types.dart';
import 'package:fudan_elearning/platform/calendar_service.dart';
import 'package:fudan_elearning/state/app_state.dart';
import 'package:fudan_elearning/theme.dart';
import 'package:fudan_elearning/ui/ios/home_shell.dart';

const fixtureTitle1 = '实验报告：测量数据与误差分析';
const fixtureTitle2 = '程序设计作业：链表与队列';
Future<void> loadIosFonts() async {
  for (final path in [
    '/System/Library/Fonts/STHeiti Medium.ttc',
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    '/System/Library/Fonts/STHeiti Medium.ttc',
    r'C:\Windows\Fonts\Deng.ttf',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  ]) {
    if (!File(path).existsSync()) continue;
    await (FontLoader('IosTestCjk')..addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
        ))
        .load();
    break;
  }
  await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      ))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

Future<AppState> iosFixture() async {
  final state = AppState(store: MemoryStore(), demo: true);
  await state.boot();
  final data = state.snapshot!;
  final course = data.courses.firstWhere(
    (course) => course.termId == defaultTermId(data),
  );
  AssignmentRow make(int id, String name, int hour) => AssignmentRow(
    id: id,
    courseId: course.id,
    courseName: course.displayName,
    name: name,
    groupId: 1,
    groupName: '课程作业',
    pointsPossible: 100,
    dueAt: beijingInstant(DateTime.utc(2026, 3, 15, hour)).toIso8601String(),
    descriptionExcerpt: '请整理实验数据，完成分析并上传 PDF 报告。',
    htmlUrl:
        'https://elearning.fudan.edu.cn/courses/${course.id}/assignments/$id',
  );
  state.snapshot = Snapshot(
    fetchedAt: appNow().toUtc().toIso8601String(),
    profile: data.profile,
    courses: [
      for (final item in data.courses)
        if (item.id == course.id)
          CourseSummary.fromJson({
            ...item.toJson(),
            'assignmentCount': item.assignmentCount + 2,
            'upcomingCount': item.upcomingCount + 2,
          })
        else
          item,
    ],
    terms: data.terms,
    assignments: [
      ...data.assignments,
      make(90001, fixtureTitle1, 20),
      make(90002, fixtureTitle2, 23),
    ],
    todo: data.todo,
  );
  return state;
}

Widget iosTestApp(
  AppState state, {
  bool dark = false,
  double scale = 1,
  CalendarService calendar = const DemoCalendarService(),
}) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  theme: dark
      ? AppTheme.dark(fontFamily: 'IosTestCjk', platform: TargetPlatform.iOS)
      : AppTheme.light(fontFamily: 'IosTestCjk', platform: TargetPlatform.iOS),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: IosHomeShell(state: state, calendar: calendar),
);
void phoneViewport(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.reset);
  addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
}
