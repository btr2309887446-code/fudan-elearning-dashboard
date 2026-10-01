/// 刷新范围：哪些课程必须重新请求，哪些可以沿用上次的数据。
///
/// 已结束的学期里成绩和作业不会再变，每次刷新都去拉一遍纯属浪费——
/// 一个用了两年的账号里往往只有几门课是当学期，其余全是历史。
/// 每门课要发两个请求（作业分组 + 作业列表），省下的就是这么多。
///
/// 与桌面端 `src/core/refresh.ts` 同一套判定，改动要同步。
library;

/// 一门课在这次刷新里该怎么处理。
enum RefreshAction { fetch, reuse }

class RefreshInputs {
  const RefreshInputs({
    required this.full,
    required this.now,
    required this.cachedCourseIds,
    required this.cachedRowCourseIds,
  });

  /// 强制全量刷新（忽略缓存）。
  final bool full;

  /// 当前时间戳。做成入参是为了测试能注入。
  final int now;

  /// 上次快照里有课程汇总的课程 id。
  final Set<int> cachedCourseIds;

  /// 上次快照里有作业行的课程 id。
  final Set<int> cachedRowCourseIds;
}

/// 这个学期是否已经结束。
///
/// 没有结束时间时返回 false——宁可真去请求一次，也好过把一门还在上的课
/// 当成历史冻住。
bool isTermOver(String? termEndAt, int now) {
  if (termEndAt == null || termEndAt.isEmpty) return false;
  final end = DateTime.tryParse(termEndAt);
  if (end == null) return false;
  return end.millisecondsSinceEpoch < now;
}

RefreshAction decideRefresh(int courseId, String? termEndAt, RefreshInputs inputs) {
  if (inputs.full) return RefreshAction.fetch;
  // 缓存里缺任何一半都不能沿用：只有课程汇总没有作业行，
  // 课程详情页的表格会空掉；反过来未交清单会漏。
  if (!inputs.cachedCourseIds.contains(courseId)) return RefreshAction.fetch;
  if (!inputs.cachedRowCourseIds.contains(courseId)) return RefreshAction.fetch;
  return isTermOver(termEndAt, inputs.now) ? RefreshAction.reuse : RefreshAction.fetch;
}

/// 把一批课分成「要请求」与「沿用」两组，各自保持原顺序。
///
/// [idOf] 显式传进来，而不是靠泛型反射——Dart 没有结构化类型，
/// 与其搞一个全局注入，不如多写一个参数。
({List<T> fetch, List<T> reuse}) planRefresh<T>(
  List<T> courses,
  int Function(T) idOf,
  String? Function(T) termEndOf,
  RefreshInputs inputs,
) {
  final fetch = <T>[];
  final reuse = <T>[];
  for (final c in courses) {
    if (decideRefresh(idOf(c), termEndOf(c), inputs) == RefreshAction.reuse) {
      reuse.add(c);
    } else {
      fetch.add(c);
    }
  }
  return (fetch: fetch, reuse: reuse);
}

/// 从上次快照的两组 id 建出 [RefreshInputs] 需要的形式。
({Set<int> courseIds, Set<int> rowCourseIds}) cachedIds(
  Iterable<int> courseIds,
  Iterable<int> rowCourseIds,
) =>
    (courseIds: courseIds.toSet(), rowCourseIds: rowCourseIds.toSet());
