import 'package:flutter_test/flutter_test.dart';
import 'package:fudan_elearning/core/refresh.dart';

/// 刷新范围的纯函数测试。
///
/// 规则很简单，但错一处就会「历史学期被冻住不再更新」或者
/// 「省了请求却把课程详情搞空」，所以逐条钉住。
///
/// 与桌面端 `cli/test-refresh.ts` 覆盖同一组行为。
void main() {
  /// 2026-06-01T00:00:00Z
  final now = DateTime.utc(2026, 6, 1).millisecondsSinceEpoch;

  RefreshInputs inputs({
    bool full = false,
    Set<int>? cachedCourseIds,
    Set<int>? cachedRowCourseIds,
  }) =>
      RefreshInputs(
        full: full,
        now: now,
        cachedCourseIds: cachedCourseIds ?? {1, 2, 3},
        cachedRowCourseIds: cachedRowCourseIds ?? {1, 2, 3},
      );

  group('isTermOver', () {
    test('结束时间在过去 → 已结束', () {
      expect(isTermOver('2026-01-15T00:00:00Z', now), isTrue);
    });

    test('结束时间在未来 → 未结束', () {
      expect(isTermOver('2026-09-15T00:00:00Z', now), isFalse);
    });

    test('没有结束时间 → 当作未结束', () {
      expect(isTermOver(null, now), isFalse);
      expect(isTermOver('', now), isFalse);
    });

    test('无法解析 → 当作未结束', () {
      expect(isTermOver('不是日期', now), isFalse);
    });

    test('结束时刻正好等于现在 → 仍未结束（宁多拉一次）', () {
      // 严格小于。这是更安全的一侧——宁可多请求一次，
      // 也别把可能还有末次更新的课冻住。
      expect(isTermOver('2026-06-01T00:00:00Z', now), isFalse);
      expect(isTermOver('2026-05-31T23:59:59.999Z', now), isTrue);
    });
  });

  group('decideRefresh', () {
    const over = '2026-01-15T00:00:00Z';
    const current = '2026-09-15T00:00:00Z';

    test('已结束 + 有缓存 → 沿用', () {
      expect(decideRefresh(1, over, inputs()), RefreshAction.reuse);
    });

    test('未结束 → 请求', () {
      expect(decideRefresh(1, current, inputs()), RefreshAction.fetch);
    });

    test('没有结束时间 → 请求', () {
      expect(decideRefresh(1, null, inputs()), RefreshAction.fetch);
    });

    test('全量刷新 → 一律请求', () {
      expect(decideRefresh(1, over, inputs(full: true)), RefreshAction.fetch);
    });

    test('缓存缺课程汇总 → 请求', () {
      expect(decideRefresh(9, over, inputs()), RefreshAction.fetch);
    });

    test('缓存缺作业行 → 请求', () {
      expect(
        decideRefresh(1, over, inputs(cachedRowCourseIds: <int>{})),
        RefreshAction.fetch,
      );
    });
  });

  group('planRefresh', () {
    const over = '2026-01-15T00:00:00Z';
    const current = '2026-09-15T00:00:00Z';

    final courses = [
      (id: 1, end: over), // 历史，有缓存
      (id: 2, end: current), // 当学期
      (id: 3, end: over), // 历史，有缓存
      (id: 4, end: over), // 历史，但缓存里没有
    ];
    int idOf(({int id, String? end}) c) => c.id;
    String? endOf(({int id, String? end}) c) => c.end;

    test('历史学期沿用、其余请求', () {
      final p = planRefresh(courses, idOf, endOf, inputs());
      expect(p.fetch.map((c) => c.id), [2, 4]);
      expect(p.reuse.map((c) => c.id), [1, 3]);
    });

    test('两组加起来等于全部', () {
      final p = planRefresh(courses, idOf, endOf, inputs());
      expect(p.fetch.length + p.reuse.length, courses.length);
    });

    test('沿用组保持原顺序', () {
      final p = planRefresh(courses, idOf, endOf, inputs());
      expect(p.reuse.map((c) => c.id), [1, 3]);
    });

    test('全量刷新时全都要请求', () {
      final p = planRefresh(courses, idOf, endOf, inputs(full: true));
      expect(p.fetch.map((c) => c.id), [1, 2, 3, 4]);
      expect(p.reuse, isEmpty);
    });

    test('没有缓存时全部请求', () {
      final p = planRefresh(
        courses,
        idOf,
        endOf,
        inputs(cachedCourseIds: <int>{}, cachedRowCourseIds: <int>{}),
      );
      expect(p.fetch.length, 4);
    });

    test('空课程列表', () {
      final p = planRefresh(<({int id, String? end})>[], idOf, endOf, inputs());
      expect(p.fetch, isEmpty);
      expect(p.reuse, isEmpty);
    });
  });

  group('cachedIds', () {
    test('去重', () {
      final ids = cachedIds([1, 2, 2], [1, 1, 1, 3]);
      expect(ids.courseIds, {1, 2});
      expect(ids.rowCourseIds, {1, 3});
    });

    test('空输入', () {
      final ids = cachedIds(const [], const []);
      expect(ids.courseIds, isEmpty);
      expect(ids.rowCourseIds, isEmpty);
    });

    test('只有汇总的课程不算齐全', () {
      final ids = cachedIds([2], [1, 3]);
      expect(ids.rowCourseIds.contains(2), isFalse);
      expect(ids.courseIds.contains(3), isFalse);
    });
  });
}
