/// 「无需提交」标记。
///
/// 有些作业本质上不用交——课堂签到、可选的练习、老师明说不用交的——
/// 但 Canvas 仍然把它们算作 unsubmitted，于是永远挂在未交清单里，
/// 把真正要交的东西淹掉。这个标记由用户手动打。
///
/// 口径与「忽略未提交的作业」一致：**只影响显示，不影响得分**。
/// 未提交且未批改的作业本来就不计入 Canvas 的当前分数，这里也不动它。
///
/// 与桌面端 `src/core/ignored.ts` 保持同一套键与语义。
library;

/// 偏好里存的是 `courseId:assignmentId`。
///
/// 单用作业 id 理论上也唯一，但 Canvas 不保证跨课程唯一，带上课程更保险。
String assignmentKey(int courseId, int id) => '$courseId:$id';

Set<String> toIgnoredSet(List<String>? keys) => {...?keys};

bool isIgnored(Set<String> set, int courseId, int id) =>
    set.contains(assignmentKey(courseId, id));

/// 打上或取消标记，返回新的键列表（保持原有顺序）。
List<String> toggleIgnored(List<String> keys, int courseId, int id) {
  final key = assignmentKey(courseId, id);
  return keys.contains(key)
      ? (List<String>.from(keys)..remove(key))
      : [...keys, key];
}

/// 从一批「带 courseId 与 id 的东西」里滤掉被标记的。
List<T> filterIgnored<T>(
  Iterable<T> rows,
  Set<String> set,
  int Function(T) courseIdOf,
  int Function(T) idOf,
) {
  if (set.isEmpty) return rows.toList();
  return rows.where((r) => !isIgnored(set, courseIdOf(r), idOf(r))).toList();
}
