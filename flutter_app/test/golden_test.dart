/// 界面渲染成图片，用于人工核对视觉效果。
///
/// `flutter test` 默认用测试占位字体（所有字形都是方框），
/// 所以这里显式加载一份系统中文字体，否则截图里看不到任何汉字。
///
/// 生成/更新：
///   flutter test test/golden_test.dart --update-goldens
/// 产物在 test/goldens/ 下。
///
/// 打了 `golden` 标签，因为渲染结果依赖具体平台的字体与光栅化，
/// 跨机器必然有像素差异。CI 上用 `--exclude-tags golden` 跳过，
/// 这些图只用于本地人工核对视觉效果。

@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fudan_elearning/core/demo.dart';
import 'package:fudan_elearning/core/session.dart';
import 'package:fudan_elearning/state/app_state.dart';
import 'package:fudan_elearning/theme.dart';
import 'package:fudan_elearning/ui/course_detail_screen.dart';
import 'package:fudan_elearning/ui/home_shell.dart';
import 'package:fudan_elearning/ui/login_screen.dart';

const _fontFamily = 'Deng';

/// 依次尝试几个系统中文字体，取第一个能读到的。
const _fontCandidates = [
  r'C:\Windows\Fonts\Deng.ttf',
  r'C:\Windows\Fonts\simhei.ttf',
  r'C:\Windows\Fonts\simsunb.ttf',
];

Future<bool> loadCjkFont() async {
  for (final path in _fontCandidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final bytes = file.readAsBytesSync();
      final loader = FontLoader(_fontFamily)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      return true;
    } catch (_) {
      // 换下一个候选。
    }
  }
  return false;
}

Widget wrapGolden(Widget child, ThemeData theme) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: child,
    );

/// 统一用 iPhone 尺寸，截图才有代表性。
void usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
}

/// iPad 横屏：宽度过 760，应当切到左侧导航栏。
void useTabletViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(2388, 1668);
  tester.view.devicePixelRatio = 2.0;
}

/// Mac 窗口。
void useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
}

void main() {
  setUpAll(() async {
    final ok = await loadCjkFont();
    if (!ok) {
      // ignore: avoid_print
      print('警告：没有找到可用中文字体，截图中的文字会是占位方框。');
    }
  });

  testWidgets('总览页（浅色）', (tester) async {
    usePhoneViewport(tester);
    addTearDown(tester.view.reset);

    final state = AppState(store: MemoryStore(), demo: true);
    await state.boot();

    await tester.pumpWidget(
      wrapGolden(HomeShell(state: state), AppTheme.light(fontFamily: _fontFamily)),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(HomeShell),
      matchesGoldenFile('goldens/overview_light.png'),
    );
  });

  testWidgets('总览页（深色）', (tester) async {
    usePhoneViewport(tester);
    addTearDown(tester.view.reset);

    final state = AppState(store: MemoryStore(), demo: true);
    await state.boot();

    await tester.pumpWidget(
      wrapGolden(HomeShell(state: state), AppTheme.dark(fontFamily: _fontFamily)),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(HomeShell),
      matchesGoldenFile('goldens/overview_dark.png'),
    );
  });

  testWidgets('作业与截止页（浅色）', (tester) async {
    usePhoneViewport(tester);
    addTearDown(tester.view.reset);

    final state = AppState(store: MemoryStore(), demo: true);
    await state.boot();

    await tester.pumpWidget(
      wrapGolden(HomeShell(state: state), AppTheme.light(fontFamily: _fontFamily)),
    );
    await tester.pumpAndSettle();

    // 底部导航切到第二个标签。
    await tester.tap(find.text('作业与截止').last);
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(HomeShell),
      matchesGoldenFile('goldens/timeline_light.png'),
    );
  });

  testWidgets('课程详情页（浅色）', (tester) async {
    usePhoneViewport(tester);
    addTearDown(tester.view.reset);

    final snapshot = buildDemoSnapshot();
    // 挑一门作业多的课，能把分组柱状图和明细列表都显示出来。
    final course = snapshot.courses.firstWhere((c) => c.assignmentCount >= 6);

    final state = AppState(store: MemoryStore(), demo: true);
    await state.boot();

    await tester.pumpWidget(
      wrapGolden(
        CourseDetailScreen(
          state: state,
          snapshot: snapshot,
          courseId: course.id,
          hideUnsubmitted: false,
        ),
        AppTheme.light(fontFamily: _fontFamily),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(CourseDetailScreen),
      matchesGoldenFile('goldens/course_detail_light.png'),
    );
  });

  testWidgets('iPad 横屏（自适应：左侧导航栏）', (tester) async {
    useTabletViewport(tester);
    addTearDown(tester.view.reset);

    final state = AppState(store: MemoryStore(), demo: true);
    await state.boot();

    await tester.pumpWidget(
      wrapGolden(HomeShell(state: state), AppTheme.light(fontFamily: _fontFamily)),
    );
    await tester.pumpAndSettle();

    // 宽屏应当用 NavigationRail 而不是底部导航。
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await expectLater(
      find.byType(HomeShell),
      matchesGoldenFile('goldens/overview_ipad.png'),
    );
  });

  testWidgets('Mac 窗口（自适应：左侧导航栏）', (tester) async {    useDesktopViewport(tester);
    addTearDown(tester.view.reset);

    final state = AppState(store: MemoryStore(), demo: true);
    await state.boot();

    await tester.pumpWidget(
      wrapGolden(HomeShell(state: state), AppTheme.dark(fontFamily: _fontFamily)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);

    await expectLater(
      find.byType(HomeShell),
      matchesGoldenFile('goldens/overview_macos_dark.png'),
    );
  });

  testWidgets('课程文件（浅色）', (tester) async {
    // 文件区在课程详情页最下面，手机高度下要先滚下去才会被构建。
    usePhoneViewport(tester);
    addTearDown(tester.view.reset);

    final snapshot = buildDemoSnapshot();
    final course = snapshot.courses.firstWhere((c) => c.assignmentCount >= 6);
    final state = AppState(store: MemoryStore(), demo: true);
    await state.boot();

    await tester.pumpWidget(
      wrapGolden(
        CourseDetailScreen(
          state: state,
          snapshot: snapshot,
          courseId: course.id,
          hideUnsubmitted: false,
        ),
        AppTheme.light(fontFamily: _fontFamily),
      ),
    );
    await tester.pumpAndSettle();

    // 一路滚到底，让文件区完整渲染。
    for (var i = 0; i < 8; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
    }

    expect(find.text('课程文件'), findsOneWidget);
    expect(find.text('下载本课全部'), findsOneWidget);
    // 默认展开第一层，应当能看到「课件」文件夹。
    expect(find.text('课件'), findsOneWidget);

    await expectLater(
      find.byType(CourseDetailScreen),
      matchesGoldenFile('goldens/course_files_light.png'),
    );
  });

  testWidgets('登录页（浅色）', (tester) async {
    // 验证品牌标识：这里用的是纯图形版 logo，
    // 完整版（含「复旦 eLearning」文字）在 42 像素下会糊成一团。
    usePhoneViewport(tester);
    addTearDown(tester.view.reset);

    final state = AppState(store: MemoryStore());
    await state.boot();

    await tester.pumpWidget(
      wrapGolden(LoginScreen(state: state), AppTheme.light(fontFamily: _fontFamily)),
    );
    await tester.pumpAndSettle();

    // Image.asset 的解码是真实异步 I/O，pumpAndSettle 不会等它——
    // 不跑一段 runAsync 的话，截图里的 Logo 会是一个空白方块。
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();

    expect(find.text('eLearning 学习看板'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);

    await expectLater(
      find.byType(LoginScreen),
      matchesGoldenFile('goldens/login_light.png'),
    );
  });

  testWidgets('课程文件：勾选后出现「下载选中」（浅色）', (tester) async {
    usePhoneViewport(tester);
    addTearDown(tester.view.reset);

    final snapshot = buildDemoSnapshot();
    final course = snapshot.courses.firstWhere((c) => c.assignmentCount >= 6);
    final state = AppState(store: MemoryStore(), demo: true);
    await state.boot();

    await tester.pumpWidget(
      wrapGolden(
        CourseDetailScreen(
          state: state,
          snapshot: snapshot,
          courseId: course.id,
          hideUnsubmitted: false,
        ),
        AppTheme.light(fontFamily: _fontFamily),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 8; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
    }

    // 勾选前两个文件（复选框按树的顺序出现）。
    final boxes = find.byType(Checkbox);
    final n = tester.widgetList(boxes).length;
    expect(n, greaterThan(2), reason: '文件区应当有若干复选框');
    await tester.tap(boxes.at(n - 2));
    await tester.pumpAndSettle();
    await tester.tap(boxes.at(n - 1));
    await tester.pumpAndSettle();

    expect(find.text('下载选中'), findsOneWidget);
    expect(find.textContaining('已选'), findsOneWidget);

    await expectLater(
      find.byType(CourseDetailScreen),
      matchesGoldenFile('goldens/course_files_selected.png'),
    );
  });
}
