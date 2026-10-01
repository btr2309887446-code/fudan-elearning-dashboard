import 'package:flutter_test/flutter_test.dart';
import 'package:fudan_elearning/core/ignored.dart';

/// 「无需提交」标记的纯函数测试。
///
/// 与桌面端 `cli/test-ignored.ts` 覆盖同一组行为，两边的键与语义必须一致。
void main() {
  group('assignmentKey', () {
    test('基本形式', () {
      expect(assignmentKey(12, 34), '12:34');
    });

    test('不同课程同 id 不撞', () {
      expect(assignmentKey(1, 7) == assignmentKey(2, 7), isFalse);
    });

    test('同课程不同 id 不撞', () {
      expect(assignmentKey(1, 7) == assignmentKey(1, 8), isFalse);
    });
  });

  group('isIgnored / toIgnoredSet', () {
    test('空集合', () {
      final empty = toIgnoredSet(null);
      expect(empty, isEmpty);
      expect(isIgnored(empty, 1, 2), isFalse);
    });

    test('命中与不命中', () {
      final set = toIgnoredSet(['1:2', '3:4']);
      expect(isIgnored(set, 1, 2), isTrue);
      expect(isIgnored(set, 3, 4), isTrue);
      expect(isIgnored(set, 1, 3), isFalse);
      expect(isIgnored(set, 1, 9), isFalse);
      expect(isIgnored(set, 9, 2), isFalse);
    });
  });

  group('toggleIgnored', () {
    test('从空列表打标记', () {
      expect(toggleIgnored([], 1, 2), ['1:2']);
    });

    test('追加到后面', () {
      expect(toggleIgnored(['1:2'], 3, 4), ['1:2', '3:4']);
    });

    test('再点一次取消', () {
      expect(toggleIgnored(['1:2', '3:4'], 1, 2), ['3:4']);
    });

    test('取消中间一条后顺序不变', () {
      expect(toggleIgnored(['1:1', '2:2', '3:3'], 2, 2), ['1:1', '3:3']);
    });

    test('不改动入参', () {
      final orig = ['1:2'];
      toggleIgnored(orig, 3, 4);
      expect(orig, ['1:2']);
    });

    test('点偶数次等于没点', () {
      var keys = <String>[];
      for (var i = 0; i < 6; i++) {
        keys = toggleIgnored(keys, 5, 6);
      }
      expect(keys, isEmpty);
    });
  });

  group('filterIgnored', () {
    final rows = [
      (courseId: 1, id: 10, name: 'a'),
      (courseId: 1, id: 11, name: 'b'),
      (courseId: 2, id: 10, name: 'c'),
    ];
    int cid(({int courseId, int id, String name}) r) => r.courseId;
    int rid(({int courseId, int id, String name}) r) => r.id;

    test('空集合原样返回', () {
      expect(filterIgnored(rows, toIgnoredSet(null), cid, rid).length, 3);
    });

    test('滤掉一条', () {
      final one = filterIgnored(rows, toIgnoredSet(['1:10']), cid, rid);
      expect(one.map((r) => r.name), ['b', 'c']);
    });

    test('跨课程不误伤', () {
      // 课程 2 的 10 号不该被课程 1 的标记影响
      final cross = filterIgnored(rows, toIgnoredSet(['2:10']), cid, rid);
      expect(cross.map((r) => r.name), ['a', 'b']);
    });

    test('全标记就没有了', () {
      final all = filterIgnored(rows, toIgnoredSet(['1:10', '1:11', '2:10']), cid, rid);
      expect(all, isEmpty);
    });
  });
}
