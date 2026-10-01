/// 核心逻辑的单元测试。
///
/// 对应桌面端的 `cli/doctor.ts`（协议与解析）和 `cli/test-cache.ts`（缓存兼容性），
/// 保证 Dart 移植版在行为上与已验证的 TypeScript 版一致。

library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fudan_elearning/core/canvas.dart';
import 'package:fudan_elearning/core/cookies.dart';
import 'package:fudan_elearning/core/http.dart';
import 'package:fudan_elearning/core/scoring.dart';
import 'package:fudan_elearning/core/types.dart';
import 'package:fudan_elearning/core/uis.dart';

void main() {
  group('Cookie 容器', () {
    test('域内匹配发送，跨域不发送', () {
      final jar = CookieJar()
        ..setFromResponse('https://id.fudan.edu.cn/idp/x', ['REQID=abc; Path=/; Secure; HttpOnly']);

      expect(jar.cookieHeader('https://id.fudan.edu.cn/other'), contains('REQID=abc'));
      expect(jar.cookieHeader('https://elearning.fudan.edu.cn/'), isNull);
    });

    test('多个域互不干扰', () {
      final jar = CookieJar()
        ..setFromResponse('https://id.fudan.edu.cn/idp/x', ['REQID=abc; Path=/'])
        ..setFromResponse('https://elearning.fudan.edu.cn/login', [
          '_normandy_session=xyz; path=/; secure; HttpOnly',
        ]);

      final canvas = jar.cookieHeader('https://elearning.fudan.edu.cn/courses');
      expect(canvas, contains('_normandy_session=xyz'));
      expect(canvas, isNot(contains('REQID')));
    });

    test('Max-Age=0 删除 Cookie', () {
      final jar = CookieJar()
        ..setFromResponse('https://id.fudan.edu.cn/', ['REQID=abc; Path=/'])
        ..setFromResponse('https://id.fudan.edu.cn/', ['REQID=gone; Path=/; Max-Age=0']);

      expect(jar.cookieHeader('https://id.fudan.edu.cn/'), isNull);
    });

    test('嵌套路径只发送给匹配的路径', () {
      final jar = CookieJar()
        ..setFromResponse('https://x.edu.cn/a/b', ['p=1; Path=/a']);

      expect(jar.cookieHeader('https://x.edu.cn/a/c'), isNotNull);
      expect(jar.cookieHeader('https://x.edu.cn/other'), isNull);
    });

    test('Domain 属性让 Cookie 覆盖子域', () {
      final jar = CookieJar()
        ..setFromResponse('https://fudan.edu.cn/', ['d=1; Domain=.fudan.edu.cn; Path=/']);

      expect(jar.cookieHeader('https://elearning.fudan.edu.cn/'), contains('d=1'));
      expect(jar.cookieHeader('https://other.edu.cn/'), isNull);
    });

    test('过期时间解析（RFC 1123）', () {
      final jar = CookieJar()
        ..setFromResponse('https://x.edu.cn/', ['e=1; Path=/; Expires=Wed, 09 Jun 2021 10:18:14 GMT']);
      // 早已过期，应当被丢弃。
      expect(jar.cookieHeader('https://x.edu.cn/'), isNull);
    });

    test('JSON 往返', () {
      final jar = CookieJar()
        ..setFromResponse('https://x.edu.cn/', ['a=1; Path=/'])
        ..setFromResponse('https://x.edu.cn/', ['b=2; Path=/']);
      final restored = CookieJar.fromJsonString(jar.toJsonString());
      expect(restored.cookieHeader('https://x.edu.cn/'), contains('a=1'));
      expect(restored.cookieHeader('https://x.edu.cn/'), contains('b=2'));
    });

    test('损坏的 JSON 退化为空容器而不是抛错', () {
      expect(CookieJar.fromJsonString('{not json').all(), isEmpty);
    });
  });

  group('dart:io 的多 Set-Cookie 处理', () {
    test('多个 Set-Cookie 能逐条拿到（不丢失边界）', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response.headers.add('Set-Cookie', 'a=1; Path=/');
        req.response.headers.add('Set-Cookie', 'b=2; Path=/');
        req.response.write('ok');
        req.response.close();
      });

      try {
        final url = 'http://127.0.0.1:${server.port}/';
        final http = HttpClientLite();
        await http.raw(url);

        final header = http.jar.cookieHeader(url);
        expect(header, contains('a=1'), reason: '第一个 Set-Cookie 应当被保留');
        expect(header, contains('b=2'), reason: '第二个 Set-Cookie 应当被保留');
      } finally {
        await server.close(force: true);
      }
    });
  });

  group('HTML 解析（认证服务器返回的票据页面）', () {
    test('解析 #logon[action] 与 #ticket[value]', () {
      const html =
          '<form id="logon" method="post" action="https://elearning.fudan.edu.cn/login/cas?service=abc&amp;x=1">'
          '<input type="hidden" id="ticket" value="ST-123-xyz"></form>';
      final t = extractTicketTarget(html);
      expect(t, isNotNull);
      expect(t!.action, 'https://elearning.fudan.edu.cn/login/cas?service=abc&x=1');
      expect(t.ticket, 'ST-123-xyz');
    });

    test('兼容属性顺序、单引号与自闭合标签', () {
      const html = "<input value='T-9' id='ticket'/><form action='/a?b=1' id='logon'></form>";
      final t = extractTicketTarget(html);
      expect(t, isNotNull);
      expect(t!.action, '/a?b=1');
      expect(t.ticket, 'T-9');
    });

    test('找不到元素时返回 null', () {
      expect(extractTicketTarget('<html>nope</html>'), isNull);
    });
  });

  group('IdP 地址解析', () {
    test('从 SPA 地址里取出 lck 与 entityId', () {
      final parsed = parseIdpSpaUrl(
        'https://id.fudan.edu.cn/ac/#/index'
        '?lck=context_CAS_abc&entityId=https://elearning.fudan.edu.cn&theme=xyz',
      );
      expect(parsed, isNotNull);
      expect(parsed!.lck, 'context_CAS_abc');
      expect(parsed.entityId, 'https://elearning.fudan.edu.cn');
    });

    test('缺少参数时返回 null', () {
      expect(parseIdpSpaUrl('https://id.fudan.edu.cn/ac/#/index'), isNull);
      expect(parseIdpSpaUrl('https://id.fudan.edu.cn/'), isNull);
    });
  });

  group('成绩计算', () {
    test('未评分的分组被剔除，剩余权重重新归一化', () {
      final percent = computeWeightedPercent([
        (weight: 60, earned: 300, possible: 400), // 75%
        (weight: 40, earned: 0, possible: 0), // 尚无评分
      ]);
      // 只有第一组有效，权重归一化后就是它本身的百分比。
      expect(percent, closeTo(75, 0.001));
    });

    test('两组都有评分时按权重加权', () {
      final percent = computeWeightedPercent([
        (weight: 50, earned: 90, possible: 100), // 90%
        (weight: 50, earned: 60, possible: 100), // 60%
      ]);
      expect(percent, closeTo(75, 0.001));
    });

    test('全部未评分时返回 null', () {
      expect(computeWeightedPercent([(weight: 100, earned: 0, possible: 0)]), isNull);
    });

    test('无权重时退化为总分制', () {
      final percent = computeWeightedPercent([
        (weight: 0, earned: 45, possible: 50),
        (weight: 0, earned: 30, possible: 50),
      ]);
      expect(percent, closeTo(75, 0.001));
    });

    test('免除与不计入总评的作业被排除', () {
      expect(countsTowardScore(10, 100, true, false), isFalse, reason: '免除');
      expect(countsTowardScore(10, 100, false, true), isFalse, reason: '不计入总评');
      expect(countsTowardScore(null, 100, false, false), isFalse, reason: '未评分');
      expect(countsTowardScore(10, 0, false, false), isFalse, reason: '满分为 0');
      expect(countsTowardScore(10, 100, false, false), isTrue);
    });
  });

  group('学期归组', () {
    CourseSummary course({
      required int id,
      required int? termId,
      required String termName,
      String? termStartAt,
      String? termEndAt,
      double? score,
    }) =>
        CourseSummary(
          id: id,
          name: 'C$id',
          displayName: 'C$id',
          courseCode: 'C$id',
          termId: termId,
          termName: termName,
          termStartAt: termStartAt,
          termEndAt: termEndAt,
          currentScore: score,
        );

    test('按学期分组并按开始时间倒序', () {
      final groups = buildTermGroups([
        course(id: 1, termId: 1, termName: '旧学期', termStartAt: '2024-09-01T00:00:00Z'),
        course(id: 2, termId: 2, termName: '新学期', termStartAt: '2026-09-01T00:00:00Z'),
        course(id: 3, termId: 2, termName: '新学期', termStartAt: '2026-09-01T00:00:00Z'),
      ]);

      expect(groups.length, 2);
      expect(groups.first.name, '新学期');
      expect(groups.first.courseCount, 2);
      expect(groups.last.name, '旧学期');
    });

    test('区间包含今天的学期被标记为当前', () {
      final groups = buildTermGroups([
        course(id: 1, termId: 1, termName: '过去', termStartAt: '2020-09-01T00:00:00Z', termEndAt: '2021-01-01T00:00:00Z'),
        course(id: 2, termId: 2, termName: '进行中', termStartAt: '2020-01-01T00:00:00Z', termEndAt: '2099-01-01T00:00:00Z'),
      ]);
      final current = groups.firstWhere((g) => g.isCurrent);
      expect(current.name, '进行中');
    });

    test('同名学期自动加 term id 区分', () {
      final groups = buildTermGroups([
        course(id: 1, termId: 28, termName: '2026 年春季学期', termStartAt: '2026-03-01T00:00:00Z'),
        course(id: 2, termId: 29, termName: '2026 年春季学期', termStartAt: '2026-03-01T00:00:00Z'),
      ]);
      final names = groups.map((g) => g.name).toSet();
      expect(names.length, 2, reason: '两个学期不能同名');
      expect(names.any((n) => n.contains('#28')), isTrue);
      expect(names.any((n) => n.contains('#29')), isTrue);
    });
  });

  group('缓存兼容性', () {
    test('0.1.0 风格的缓存（无 terms）能被安全升级', () {
      final legacy = {
        'fetchedAt': '2026-09-30T05:11:32.000Z',
        'profile': {'id': 1, 'name': '测试同学'},
        'courses': [
          {
            'id': 101,
            'name': 'A 课程',
            'displayName': 'A 课程',
            'courseCode': 'A.01',
            'termId': 7,
            'currentScore': 88,
          },
          {
            'id': 102,
            'name': 'B 课程',
            'displayName': 'B 课程',
            'courseCode': 'B.01',
            'termId': 7,
            'currentScore': 91,
          },
        ],
        'assignments': [
          {'id': 1, 'courseId': 101, 'name': '作业一', 'dueAt': '2026-09-01T00:00:00Z'},
        ],
        'todo': <dynamic>[],
        'warnings': <dynamic>[],
      };

      final snapshot = normaliseSnapshot(legacy);
      expect(snapshot, isNotNull);
      expect(snapshot!.terms, isNotEmpty, reason: '应当派生出 terms');
      expect(snapshot.courses.every((c) => c.termName.isNotEmpty), isTrue);
      expect(snapshot.assignments.length, 1);
    });

    test('用作业截止时间反推学期名', () {
      final legacy = {
        'profile': {'id': 1, 'name': 'x'},
        'courses': [
          {'id': 5, 'name': 'C', 'displayName': 'C', 'courseCode': 'C', 'termId': 3},
        ],
        'assignments': [
          {'id': 1, 'courseId': 5, 'name': 'w', 'dueAt': '2026-03-15T00:00:00Z'},
        ],
      };
      final snapshot = normaliseSnapshot(legacy);
      expect(snapshot!.courses.first.termName, contains('春季'));
      expect(snapshot.terms.first.name, contains('春季'));
    });

    test('损坏或残缺的缓存被拒绝', () {
      expect(normaliseSnapshot(null), isNull);
      expect(normaliseSnapshot({'assignments': <dynamic>[]}), isNull, reason: '缺 courses');
      expect(normaliseSnapshot({'courses': <dynamic>[]}), isNull, reason: '缺 assignments');
    });

    test('结构正确但为空的缓存可接受', () {
      final snapshot = normaliseSnapshot({'courses': <dynamic>[], 'assignments': <dynamic>[]});
      expect(snapshot, isNotNull);
      expect(snapshot!.terms, isEmpty);
    });

    test('当前版本的缓存往返不变（不含 terms 时补上，含则不覆盖）', () {
      final courses = [
        const CourseSummary(
          id: 1,
          name: 'C',
          displayName: 'C',
          courseCode: 'C',
          termId: 9,
          termName: '2026-2027 学年第一学期',
          termStartAt: '2026-09-01T00:00:00Z',
          termEndAt: '2027-01-15T00:00:00Z',
        ),
      ];
      final snapshot = Snapshot(
        fetchedAt: '2026-09-30T05:11:32.000Z',
        profile: const CanvasProfile(id: 1, name: '测试'),
        courses: courses,
        terms: buildTermGroups(courses),
        assignments: const [],
        warnings: const ['w'],
      );

      final back = normaliseSnapshot(jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>);
      expect(back!.terms.first.name, '2026-2027 学年第一学期');
      expect(back.warnings.length, 1);
      expect(back.courses.first.currentScore, isNull);
    });
  });

  group('Canvas 客户端工具', () {
    test('查询串把数组展开为 key[]', () {
      expect(
        CanvasClient.buildQuery({'include': ['submission', 'term'], 'per_page': 100}),
        '?include%5B%5D=submission&include%5B%5D=term&per_page=100',
      );
    });

    test('null 值被跳过', () {
      expect(CanvasClient.buildQuery({'a': null, 'b': 'x'}), '?b=x');
      expect(CanvasClient.buildQuery(null), '');
    });

    test('解析 Link 头里的 next', () {
      const link = '<https://e.fudan.edu.cn/api/v1/courses?page=2>; rel="next", '
          '<https://e.fudan.edu.cn/api/v1/courses?page=5>; rel="last"';
      expect(CanvasClient.parseNextLink(link), 'https://e.fudan.edu.cn/api/v1/courses?page=2');
    });

    test('没有 next 时返回 null', () {
      expect(CanvasClient.parseNextLink('<https://x/?page=1>; rel="last"'), isNull);
      expect(CanvasClient.parseNextLink(null), isNull);
      expect(CanvasClient.parseNextLink(''), isNull);
    });
  });
}
