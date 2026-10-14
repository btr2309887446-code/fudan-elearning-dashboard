@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fudan_elearning/core/clock.dart';
import 'package:fudan_elearning/ui/ios/home_shell.dart';
import 'support/ios_fixture.dart';

void main() {
  setUpAll(loadIosFonts);
  setUp(() => appNow = () => DateTime.utc(2026, 3, 15, 1));
  tearDown(() => appNow = DateTime.now);
  for (final dark in [false, true]) {
    testWidgets('今日${dark ? '深色' : '浅色'}', (tester) async {
      phoneViewport(tester);
      final state = await iosFixture();
      await tester.pumpWidget(iosTestApp(state, dark: dark));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(IosHomeShell),
        matchesGoldenFile('goldens/ios_today_${dark ? 'dark' : 'light'}.png'),
      );
    });
  }
  for (final label in ['作业', '课程', '我的', '日历', '作业详情']) {
    testWidgets('$label浅色', (tester) async {
      phoneViewport(tester);
      final state = await iosFixture();
      await tester.pumpWidget(iosTestApp(state));
      await tester.pumpAndSettle();
      if (label == '作业详情') {
        await tester.tap(find.text(fixtureTitle1));
      } else {
        await tester.tap(find.text(label == '日历' ? '作业' : label).last);
        await tester.pumpAndSettle();
        if (label == '日历') {
          await tester.tap(find.text('日历'));
        }
      }
      await tester.pumpAndSettle();
      final name = {
        '作业': 'tasks',
        '课程': 'courses',
        '我的': 'profile',
        '日历': 'calendar',
        '作业详情': 'assignment',
      }[label]!;
      await expectLater(
        find.byType(IosHomeShell),
        matchesGoldenFile('goldens/ios_${name}_light.png'),
      );
    });
  }
  for (final segment in ['作业', '成绩', '文件']) {
    testWidgets('课程详情$segment浅色', (tester) async {
      phoneViewport(tester);
      final state = await iosFixture();
      await tester.pumpWidget(iosTestApp(state));
      await tester.pumpAndSettle();
      await tester.tap(find.text('课程').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('程序设计基础').first);
      await tester.pumpAndSettle();
      if (segment != '作业') {
        await tester.tap(find.text(segment));
        await tester.pumpAndSettle();
      }
      final name = {'作业': 'tasks', '成绩': 'grades', '文件': 'files'}[segment]!;
      await expectLater(
        find.byType(IosHomeShell),
        matchesGoldenFile('goldens/ios_course_${name}_light.png'),
      );
    });
  }
}
