/// 纯成绩计算。
///
/// 刻意不依赖任何网络或平台 API，方便直接单元测试，
/// 也让界面层可以复用同一套口径。
///
/// 关于分数的说明：Canvas 会返回一个 `computed_current_score`，
/// 但作业未批改时它是空的，而且不一定反映作业分组的权重。
/// 所以这里**根据每次提交的得分与满分重新计算**；
/// 服务器值存在时优先展示服务器值，分组明细则一律用本地重算结果。

library;

import 'summary.dart';
import 'types.dart';

double? _num(Object? v) {
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : null;
  }
  return null;
}

/// 从课程里挑出当前用户自己的选课记录。
CanvasEnrollment? pickOwnEnrollment(CanvasCourse course) {
  if (course.enrollments.isEmpty) return null;
  for (final e in course.enrollments) {
    if (e.type == 'StudentEnrollment' || e.role == 'StudentEnrollment') return e;
  }
  return course.enrollments.first;
}

class ExtractedScores {
  const ExtractedScores({
    this.currentScore,
    this.finalScore,
    this.currentGrade,
    this.finalGrade,
  });

  final double? currentScore;
  final double? finalScore;
  final String? currentGrade;
  final String? finalGrade;
}

ExtractedScores extractScores(CanvasEnrollment? enrollment) {
  if (enrollment == null) return const ExtractedScores();
  final g = enrollment.grades ?? const {};

  // computed_* 是学生在网页上看到的值；grades.* 是同一份数据的嵌套写法；
  // 最后再兜底到扁平的老字段名。
  return ExtractedScores(
    currentScore: enrollment.computedCurrentScore ?? _num(g['current_score']),
    finalScore: enrollment.computedFinalScore ?? _num(g['final_score']),
    currentGrade: enrollment.computedCurrentGrade ?? g['current_grade'] as String?,
    finalGrade: enrollment.computedFinalGrade ?? g['final_grade'] as String?,
  );
}

/// 一条作业是否计入课程分（按 Canvas 的规则）。
bool countsTowardScore(double? score, double? pointsPossible, bool excused, bool omit) {
  return !excused && !omit && pointsPossible != null && pointsPossible > 0 && score != null;
}

/// 作业分组的加权百分比。
///
/// 尚无评分的分组会被剔除，剩余权重重新归一化——
/// 这正是学期中途 Canvas 显示的口径。
double? computeWeightedPercent(List<({double weight, double earned, double possible})> groups) {
  final graded = groups.where((g) => g.possible > 0).toList();
  if (graded.isEmpty) return null;

  final totalWeight = graded.fold<double>(0, (s, g) => s + (g.weight > 0 ? g.weight : 0));
  if (totalWeight > 0) {
    final sum = graded.fold<double>(0, (s, g) => s + (g.earned / g.possible) * g.weight);
    return (sum / totalWeight) * 100;
  }

  final earned = graded.fold<double>(0, (s, g) => s + g.earned);
  final possible = graded.fold<double>(0, (s, g) => s + g.possible);
  return possible > 0 ? (earned / possible) * 100 : null;
}

List<AssignmentRow> toAssignmentRows(
  CanvasCourse course,
  String courseName,
  List<CanvasAssignment> assignments,
  Map<int, ({String name, double weight})> groupById,
) {
  return assignments.map((a) {
    final sub = a.submission;
    final score = (sub != null && !sub.excused) ? sub.score : null;
    final points = a.pointsPossible;
    final group = groupById[a.assignmentGroupId];
    final percent = (score != null && points != null && points > 0) ? (score / points) * 100 : null;
    final weight = group?.weight ?? 0;

    return AssignmentRow(
      id: a.id,
      courseId: course.id,
      courseName: courseName,
      name: a.name,
      dueAt: a.dueAt,
      pointsPossible: points,
      groupId: a.assignmentGroupId,
      groupName: group?.name ?? '未分组',
      groupWeight: weight,
      score: score,
      grade: sub?.grade,
      submittedAt: sub?.submittedAt,
      gradedAt: sub?.gradedAt,
      workflowState: sub?.workflowState ?? 'unsubmitted',
      late: sub?.late ?? false,
      missing: sub?.missing ?? false,
      excused: sub?.excused ?? false,
      omitFromFinalGrade: a.omitFromFinalGrade,
      htmlUrl: a.htmlUrl,
      descriptionExcerpt: makeExcerpt(a.description),
      percent: percent,
      weightedContribution: (percent != null && weight > 0) ? (percent / 100) * weight : null,
    );
  }).toList();
}

CourseSummary summariseCourse(
  CanvasCourse course,
  String displayName,
  String? nickname,
  List<AssignmentRow> rows,
  ({int? id, String name, String? startAt, String? endAt}) term,
) {
  final scores = extractScores(pickOwnEnrollment(course));

  final groups = <int, ({double weight, double earned, double possible})>{};
  for (final r in rows) {
    final g = groups[r.groupId] ?? (weight: r.groupWeight, earned: 0.0, possible: 0.0);
    if (countsTowardScore(r.score, r.pointsPossible, r.excused, r.omitFromFinalGrade)) {
      groups[r.groupId] = (
        weight: g.weight,
        earned: g.earned + r.score!,
        possible: g.possible + r.pointsPossible!,
      );
    } else {
      groups[r.groupId] = g;
    }
  }

  final weighted = computeWeightedPercent(groups.values.toList());
  final earnedPoints = groups.values.fold<double>(0, (s, g) => s + g.earned);
  final possiblePoints = groups.values.fold<double>(0, (s, g) => s + g.possible);
  final now = DateTime.now();

  int dueInFuture(AssignmentRow r) {
    final t = r.dueAt == null ? null : DateTime.tryParse(r.dueAt!);
    return (t != null && t.isAfter(now)) ? 1 : 0;
  }

  return CourseSummary(
    id: course.id,
    name: course.name,
    displayName: displayName,
    courseCode: course.courseCode,
    nickname: nickname,
    termId: term.id,
    termName: term.name,
    termStartAt: term.startAt,
    termEndAt: term.endAt,
    startAt: course.startAt,
    endAt: course.endAt,
    imageUrl: course.imageDownloadUrl,
    currentScore: scores.currentScore ?? weighted,
    finalScore: scores.finalScore,
    currentGrade: scores.currentGrade,
    finalGrade: scores.finalGrade,
    earnedPoints: possiblePoints > 0 ? earnedPoints : null,
    possiblePointsGraded: possiblePoints > 0 ? possiblePoints : null,
    assignmentCount: rows.length,
    submittedCount: rows.where((r) => r.workflowState != 'unsubmitted').length,
    gradedCount: rows.where((r) => r.score != null).length,
    missingCount: rows.where((r) => r.missing).length,
    lateCount: rows.where((r) => r.late).length,
    upcomingCount: rows.fold<int>(0, (s, r) => s + dueInFuture(r)),
  );
}

/// 判断课程属于哪个学期。
///
/// `include[]=term` 会给出 id、名称和日期；拿不到时（老部署、或该 include 被拒）
/// 仍有 `enrollment_term_id`，所以分组永远是对的，只是名称会退化成占位标签。
({int? id, String name, String? startAt, String? endAt}) resolveTerm(
  CanvasCourse course,
  Map<int, CanvasTerm> termInfo,
) {
  final id = course.term?.id ?? course.enrollmentTermId;
  if (id == null) {
    return (id: null, name: '未指定学期', startAt: null, endAt: null);
  }
  final info = course.term ?? termInfo[id];
  final name = (info?.name ?? '').trim();
  return (
    id: id,
    name: name.isEmpty ? '学期 #$id' : name,
    startAt: info?.startAt,
    endAt: info?.endAt,
  );
}

/// 收集响应里出现过的全部学期对象。
Map<int, CanvasTerm> collectTermInfo(List<CanvasCourse> courses) {
  final map = <int, CanvasTerm>{};
  for (final c in courses) {
    final t = c.term;
    if (t != null) map[t.id] = t;
  }
  return map;
}

/// 缓存里缺 `terms` 时，用课程日期推一个学期名。
///
/// 老的缓存仍有真实的 `enrollment_term_id`，分组是对的，
/// 但每个学期都会叫「未指定学期」而无法区分。
/// 开课日期是足够可靠的线索：2-7 月开始的是春季，否则是秋季。
String _guessTermName(String? startAt, int? termId) {
  if (startAt != null) {
    final d = DateTime.tryParse(startAt);
    if (d != null) {
      final season = (d.month >= 2 && d.month <= 7) ? '春季' : '秋季';
      return '${d.year} 年$season学期';
    }
  }
  return termId == null ? '未指定学期' : '学期 #$termId';
}

/// 把课程按学期归组，最新的在前，并标出当前学期。
///
/// 「当前」指日期落在其区间内的学期；日期缺失或都不在学期内时，
/// 取最近开始的那个。
List<TermGroup> buildTermGroups(List<CourseSummary> courses) {
  final map = <int?, TermGroup>{};

  for (final c in courses) {
    final key = c.termId;
    final existing = map[key];
    if (existing != null) {
      var startAt = existing.startAt;
      var endAt = existing.endAt;
      // 同一学期内课程日期可能略有出入，取并集。
      if (c.termStartAt != null &&
          (startAt == null || DateTime.parse(c.termStartAt!).isBefore(DateTime.parse(startAt)))) {
        startAt = c.termStartAt;
      }
      if (c.termEndAt != null &&
          (endAt == null || DateTime.parse(c.termEndAt!).isAfter(DateTime.parse(endAt)))) {
        endAt = c.termEndAt;
      }
      map[key] = TermGroup(
        id: key,
        name: existing.name,
        startAt: startAt,
        endAt: endAt,
        isCurrent: existing.isCurrent,
        courseCount: existing.courseCount + 1,
      );
    } else {
      map[key] = TermGroup(
        id: key,
        name: c.termName,
        startAt: c.termStartAt,
        endAt: c.termEndAt,
        courseCount: 1,
      );
    }
  }

  final groups = map.values.toList()
    ..sort((a, b) {
      final ta = a.startAt == null ? null : DateTime.tryParse(a.startAt!);
      final tb = b.startAt == null ? null : DateTime.tryParse(b.startAt!);
      if (ta == null && tb == null) return (b.id ?? -1).compareTo(a.id ?? -1);
      if (ta == null) return 1; // 没有日期的学期沉到底部
      if (tb == null) return -1;
      final cmp = tb.compareTo(ta);
      return cmp != 0 ? cmp : (b.id ?? -1).compareTo(a.id ?? -1);
    });

  if (groups.isNotEmpty) {
    final now = DateTime.now();
    TermGroup? current;
    for (final g in groups) {
      final s = g.startAt == null ? null : DateTime.tryParse(g.startAt!);
      final e = g.endAt == null ? null : DateTime.tryParse(g.endAt!);
      if (s != null && e != null && !s.isAfter(now) && !now.isAfter(e)) {
        current = g;
        break;
      }
    }
    current ??= groups.firstWhere(
      (g) {
        final s = g.startAt == null ? null : DateTime.tryParse(g.startAt!);
        return s != null && !s.isAfter(now);
      },
      orElse: () => groups.first,
    );

    for (var i = 0; i < groups.length; i++) {
      groups[i] = groups[i].copyWith(isCurrent: identical(groups[i], current));
    }
  }

  // Canvas 有时把同一学期拆成多个 term，推导出的名字也可能撞车。
  // 两个同名标签无法区分，所以重名时补上 term id。
  final nameCounts = <String, int>{};
  for (final g in groups) {
    nameCounts[g.name] = (nameCounts[g.name] ?? 0) + 1;
  }
  for (var i = 0; i < groups.length; i++) {
    if ((nameCounts[groups[i].name] ?? 0) > 1) {
      groups[i] = groups[i].copyWith(name: '${groups[i].name}（#${groups[i].id ?? '无'}）');
    }
  }

  return groups;
}

/// 把缓存的快照升级到当前结构。
///
/// 旧版本写下的缓存缺少新版本依赖的字段——0.1.0 的缓存没有 `terms`，
/// 直接读取会让整个界面在首帧崩溃。所以每次读缓存都过这里：
/// 缺的补上，无法挽救的返回 null，由调用方改为重新拉取。
Snapshot? normaliseSnapshot(Map<String, dynamic>? raw) {
  if (raw == null) return null;
  final coursesRaw = raw['courses'];
  final assignmentsRaw = raw['assignments'];
  if (coursesRaw is! List || assignmentsRaw is! List) return null;

  final assignments = assignmentsRaw
      .whereType<Map<String, dynamic>>()
      .map(AssignmentRow.fromJson)
      .toList();

  // 很多 Canvas 课程根本没有开课日期，于是用该课最早的作业截止时间兜底——
  // 真正把课程定位在时间轴上的就是它。
  final earliestByCourse = <int, DateTime>{};
  for (final a in assignments) {
    if (a.dueAt == null) continue;
    final t = DateTime.tryParse(a.dueAt!);
    if (t == null) continue;
    final prev = earliestByCourse[a.courseId];
    if (prev == null || t.isBefore(prev)) earliestByCourse[a.courseId] = t;
  }

  final courses = <CourseSummary>[];
  for (final c in coursesRaw.whereType<Map<String, dynamic>>()) {
    final base = CourseSummary.fromJson(c);
    var startAt = base.termStartAt ?? base.startAt;
    startAt ??= earliestByCourse[base.id]?.toIso8601String();

    final hasRealName = base.termName.isNotEmpty && base.termName != '未指定学期';
    courses.add(base.copyWith(
      termName: hasRealName ? base.termName : _guessTermName(startAt, base.termId),
      termStartAt: startAt,
      termEndAt: base.termEndAt ?? base.endAt,
    ));
  }

  final termsRaw = raw['terms'];
  final terms = (termsRaw is List && termsRaw.isNotEmpty)
      ? termsRaw.whereType<Map<String, dynamic>>().map(TermGroup.fromJson).toList()
      : buildTermGroups(courses);

  return Snapshot(
    fetchedAt: (raw['fetchedAt'] as String?) ?? DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
    profile: CanvasProfile.fromJson(
        (raw['profile'] as Map<String, dynamic>?) ?? const {'id': 0, 'name': '未知用户'}),
    courses: courses,
    terms: terms,
    assignments: assignments,
    todo: (raw['todo'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(TodoEntry.fromJson)
        .toList(),
    warnings: (raw['warnings'] as List<dynamic>? ?? []).whereType<String>().toList(),
  );
}

CourseDetail? buildCourseDetail(Snapshot snapshot, int courseId) {
  CourseSummary? course;
  for (final c in snapshot.courses) {
    if (c.id == courseId) {
      course = c;
      break;
    }
  }
  if (course == null) return null;

  final rows = snapshot.assignments.where((a) => a.courseId == courseId).toList();

  final byGroup = <int, ({String name, double weight, double earned, double possible})>{};
  for (final r in rows) {
    final g = byGroup[r.groupId] ?? (name: r.groupName, weight: r.groupWeight, earned: 0.0, possible: 0.0);
    if (countsTowardScore(r.score, r.pointsPossible, r.excused, r.omitFromFinalGrade)) {
      byGroup[r.groupId] = (
        name: g.name,
        weight: g.weight,
        earned: g.earned + r.score!,
        possible: g.possible + r.pointsPossible!,
      );
    } else {
      byGroup[r.groupId] = g;
    }
  }

  final groups = byGroup.entries
      .map((e) => AssignmentGroupDetail(
            id: e.key,
            name: e.value.name,
            weight: e.value.weight,
            earned: e.value.earned,
            possible: e.value.possible,
            percent: e.value.possible > 0 ? (e.value.earned / e.value.possible) * 100 : null,
          ))
      .toList()
    ..sort((a, b) {
      final cmp = b.weight.compareTo(a.weight);
      return cmp != 0 ? cmp : a.name.compareTo(b.name);
    });

  return CourseDetail(
    course: course,
    groups: groups,
    assignments: rows,
    gradingScheme: groups.any((g) => g.weight > 0) ? 'weighted' : 'points',
  );
}
