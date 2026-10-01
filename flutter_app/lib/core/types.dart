/// 数据模型。
///
/// 与桌面端 `src/core/types.ts` 一一对应；字段名保持 identical，
/// 便于两边对照与排查。

library;

/// Canvas 的学期对象（`include[]=term` 返回）。
class CanvasTerm {
  const CanvasTerm({
    required this.id,
    required this.name,
    this.startAt,
    this.endAt,
  });

  final int id;
  final String name;
  final String? startAt;
  final String? endAt;

  factory CanvasTerm.fromJson(Map<String, dynamic> json) => CanvasTerm(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String?) ?? '',
        startAt: json['start_at'] as String?,
        endAt: json['end_at'] as String?,
      );
}

class CanvasProfile {
  const CanvasProfile({
    required this.id,
    required this.name,
    this.loginId,
    this.primaryEmail,
    this.avatarUrl,
    this.sisUserId,
  });

  final int id;
  final String name;
  final String? loginId;
  final String? primaryEmail;
  final String? avatarUrl;
  final String? sisUserId;

  factory CanvasProfile.fromJson(Map<String, dynamic> json) => CanvasProfile(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String?) ?? '未知用户',
        loginId: json['login_id'] as String?,
        primaryEmail: json['primary_email'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        sisUserId: json['sis_user_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (loginId != null) 'login_id': loginId,
        if (primaryEmail != null) 'primary_email': primaryEmail,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (sisUserId != null) 'sis_user_id': sisUserId,
      };
}

/// Canvas 的 enrollment（选课记录），学生的成绩挂在这里。
class CanvasEnrollment {
  const CanvasEnrollment({
    this.id,
    this.courseId,
    this.type,
    this.role,
    this.workflowState,
    this.computedCurrentScore,
    this.computedFinalScore,
    this.computedCurrentGrade,
    this.computedFinalGrade,
    this.grades,
  });

  final int? id;
  final int? courseId;
  final String? type;
  final String? role;
  final String? workflowState;
  final double? computedCurrentScore;
  final double? computedFinalScore;
  final String? computedCurrentGrade;
  final String? computedFinalGrade;
  final Map<String, dynamic>? grades;

  factory CanvasEnrollment.fromJson(Map<String, dynamic> json) => CanvasEnrollment(
        id: (json['id'] as num?)?.toInt(),
        courseId: (json['course_id'] as num?)?.toInt(),
        type: json['type'] as String?,
        role: json['role'] as String?,
        workflowState: json['enrollment_state'] as String?,
        computedCurrentScore: (json['computed_current_score'] as num?)?.toDouble(),
        computedFinalScore: (json['computed_final_score'] as num?)?.toDouble(),
        computedCurrentGrade: json['computed_current_grade'] as String?,
        computedFinalGrade: json['computed_final_grade'] as String?,
        grades: json['grades'] as Map<String, dynamic>?,
      );
}

class CanvasCourse {
  const CanvasCourse({
    required this.id,
    required this.name,
    required this.courseCode,
    required this.workflowState,
    this.enrollmentTermId,
    this.term,
    this.startAt,
    this.endAt,
    this.imageDownloadUrl,
    this.enrollments = const [],
  });

  final int id;
  final String name;
  final String courseCode;
  final String workflowState;
  final int? enrollmentTermId;
  final CanvasTerm? term;
  final String? startAt;
  final String? endAt;
  final String? imageDownloadUrl;
  final List<CanvasEnrollment> enrollments;

  factory CanvasCourse.fromJson(Map<String, dynamic> json) => CanvasCourse(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String?) ?? '',
        courseCode: (json['course_code'] as String?) ?? '',
        workflowState: (json['workflow_state'] as String?) ?? 'available',
        enrollmentTermId: (json['enrollment_term_id'] as num?)?.toInt(),
        term: json['term'] is Map<String, dynamic>
            ? CanvasTerm.fromJson(json['term'] as Map<String, dynamic>)
            : null,
        startAt: json['start_at'] as String?,
        endAt: json['end_at'] as String?,
        imageDownloadUrl: json['image_download_url'] as String?,
        enrollments: (json['enrollments'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(CanvasEnrollment.fromJson)
            .toList(),
      );
}

class CanvasSubmission {
  const CanvasSubmission({
    required this.id,
    required this.assignmentId,
    this.score,
    this.grade,
    this.submittedAt,
    this.gradedAt,
    this.workflowState = 'unsubmitted',
    this.late = false,
    this.missing = false,
    this.excused = false,
  });

  final int id;
  final int assignmentId;
  final double? score;
  final String? grade;
  final String? submittedAt;
  final String? gradedAt;
  final String workflowState;
  final bool late;
  final bool missing;
  final bool excused;

  factory CanvasSubmission.fromJson(Map<String, dynamic> json) => CanvasSubmission(
        id: (json['id'] as num?)?.toInt() ?? 0,
        assignmentId: (json['assignment_id'] as num?)?.toInt() ?? 0,
        score: (json['score'] as num?)?.toDouble(),
        grade: json['grade'] as String?,
        submittedAt: json['submitted_at'] as String?,
        gradedAt: json['graded_at'] as String?,
        workflowState: (json['workflow_state'] as String?) ?? 'unsubmitted',
        late: json['late'] == true,
        missing: json['missing'] == true,
        excused: json['excused'] == true,
      );
}

class CanvasAssignment {
  const CanvasAssignment({
    required this.id,
    required this.courseId,
    required this.name,
    required this.assignmentGroupId,
    this.dueAt,
    this.pointsPossible,
    this.gradingType = 'points',
    this.published = true,
    this.htmlUrl,
    this.submission,
    this.omitFromFinalGrade = false,
  });

  final int id;
  final int courseId;
  final String name;
  final int assignmentGroupId;
  final String? dueAt;
  final double? pointsPossible;
  final String gradingType;
  final bool published;
  final String? htmlUrl;
  final CanvasSubmission? submission;
  final bool omitFromFinalGrade;

  factory CanvasAssignment.fromJson(Map<String, dynamic> json) => CanvasAssignment(
        id: (json['id'] as num?)?.toInt() ?? 0,
        courseId: (json['course_id'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String?) ?? '',
        assignmentGroupId: (json['assignment_group_id'] as num?)?.toInt() ?? 0,
        dueAt: json['due_at'] as String?,
        pointsPossible: (json['points_possible'] as num?)?.toDouble(),
        gradingType: (json['grading_type'] as String?) ?? 'points',
        published: json['published'] != false,
        htmlUrl: json['html_url'] as String?,
        omitFromFinalGrade: json['omit_from_final_grade'] == true,
        submission: json['submission'] is Map<String, dynamic>
            ? CanvasSubmission.fromJson(json['submission'] as Map<String, dynamic>)
            : null,
      );
}

class CanvasAssignmentGroup {
  const CanvasAssignmentGroup({
    required this.id,
    required this.name,
    this.position = 0,
    this.groupWeight = 0,
  });

  final int id;
  final String name;
  final int position;
  final double groupWeight;

  factory CanvasAssignmentGroup.fromJson(Map<String, dynamic> json) => CanvasAssignmentGroup(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String?) ?? '未分组',
        position: (json['position'] as num?)?.toInt() ?? 0,
        groupWeight: (json['group_weight'] as num?)?.toDouble() ?? 0,
      );
}

class CanvasTodoItem {
  const CanvasTodoItem({
    required this.type,
    this.assignment,
    this.quiz,
    this.courseId,
    this.htmlUrl,
  });

  final String type;
  final CanvasAssignment? assignment;
  final Map<String, dynamic>? quiz;
  final int? courseId;
  final String? htmlUrl;

  factory CanvasTodoItem.fromJson(Map<String, dynamic> json) => CanvasTodoItem(
        type: (json['type'] as String?) ?? '',
        assignment: json['assignment'] is Map<String, dynamic>
            ? CanvasAssignment.fromJson(json['assignment'] as Map<String, dynamic>)
            : null,
        quiz: json['quiz'] as Map<String, dynamic>?,
        courseId: (json['course_id'] as num?)?.toInt(),
        htmlUrl: json['html_url'] as String?,
      );
}

class CanvasNickname {
  const CanvasNickname({required this.courseId, required this.name, this.nickname});

  final int courseId;
  final String name;
  final String? nickname;

  factory CanvasNickname.fromJson(Map<String, dynamic> json) => CanvasNickname(
        courseId: (json['course_id'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String?) ?? '',
        nickname: json['nickname'] as String?,
      );
}

// ---------------------------------------------------------------------------
// 视图模型
// ---------------------------------------------------------------------------

/// 一个学期，界面按它给课程分组。
class TermGroup {
  const TermGroup({
    required this.id,
    required this.name,
    this.startAt,
    this.endAt,
    this.isCurrent = false,
    this.courseCount = 0,
  });

  /// null 表示 Canvas 没有给出学期的课程。
  final int? id;
  final String name;
  final String? startAt;
  final String? endAt;

  /// 当前日期落在其区间内的学期，否则是最近开始的那个。
  final bool isCurrent;
  final int courseCount;

  TermGroup copyWith({String? name, bool? isCurrent, int? courseCount}) => TermGroup(
        id: id,
        name: name ?? this.name,
        startAt: startAt,
        endAt: endAt,
        isCurrent: isCurrent ?? this.isCurrent,
        courseCount: courseCount ?? this.courseCount,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startAt': startAt,
        'endAt': endAt,
        'isCurrent': isCurrent,
        'courseCount': courseCount,
      };

  factory TermGroup.fromJson(Map<String, dynamic> json) => TermGroup(
        id: (json['id'] as num?)?.toInt(),
        name: (json['name'] as String?) ?? '未指定学期',
        startAt: json['startAt'] as String?,
        endAt: json['endAt'] as String?,
        isCurrent: json['isCurrent'] == true,
        courseCount: (json['courseCount'] as num?)?.toInt() ?? 0,
      );
}

class CourseSummary {
  const CourseSummary({
    required this.id,
    required this.name,
    required this.displayName,
    required this.courseCode,
    required this.termName,
    this.termId,
    this.termStartAt,
    this.termEndAt,
    this.nickname,
    this.startAt,
    this.endAt,
    this.imageUrl,
    this.currentScore,
    this.finalScore,
    this.currentGrade,
    this.finalGrade,
    this.earnedPoints,
    this.possiblePointsGraded,
    this.assignmentCount = 0,
    this.submittedCount = 0,
    this.gradedCount = 0,
    this.missingCount = 0,
    this.lateCount = 0,
    this.upcomingCount = 0,
  });

  final int id;
  final String name;
  final String displayName;
  final String courseCode;
  final String termName;
  final int? termId;
  final String? termStartAt;
  final String? termEndAt;
  final String? nickname;
  final String? startAt;
  final String? endAt;
  final String? imageUrl;
  final double? currentScore;
  final double? finalScore;
  final String? currentGrade;
  final String? finalGrade;
  final double? earnedPoints;
  final double? possiblePointsGraded;
  final int assignmentCount;
  final int submittedCount;
  final int gradedCount;
  final int missingCount;
  final int lateCount;
  final int upcomingCount;

  CourseSummary copyWith({String? termName, int? termId, String? termStartAt, String? termEndAt}) =>
      CourseSummary(
        id: id,
        name: name,
        displayName: displayName,
        courseCode: courseCode,
        termName: termName ?? this.termName,
        termId: termId ?? this.termId,
        termStartAt: termStartAt ?? this.termStartAt,
        termEndAt: termEndAt ?? this.termEndAt,
        nickname: nickname,
        startAt: startAt,
        endAt: endAt,
        imageUrl: imageUrl,
        currentScore: currentScore,
        finalScore: finalScore,
        currentGrade: currentGrade,
        finalGrade: finalGrade,
        earnedPoints: earnedPoints,
        possiblePointsGraded: possiblePointsGraded,
        assignmentCount: assignmentCount,
        submittedCount: submittedCount,
        gradedCount: gradedCount,
        missingCount: missingCount,
        lateCount: lateCount,
        upcomingCount: upcomingCount,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'displayName': displayName,
        'courseCode': courseCode,
        'termName': termName,
        'termId': termId,
        'termStartAt': termStartAt,
        'termEndAt': termEndAt,
        'nickname': nickname,
        'startAt': startAt,
        'endAt': endAt,
        'imageUrl': imageUrl,
        'currentScore': currentScore,
        'finalScore': finalScore,
        'currentGrade': currentGrade,
        'finalGrade': finalGrade,
        'earnedPoints': earnedPoints,
        'possiblePointsGraded': possiblePointsGraded,
        'assignmentCount': assignmentCount,
        'submittedCount': submittedCount,
        'gradedCount': gradedCount,
        'missingCount': missingCount,
        'lateCount': lateCount,
        'upcomingCount': upcomingCount,
      };

  factory CourseSummary.fromJson(Map<String, dynamic> json) => CourseSummary(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String?) ?? '',
        displayName: (json['displayName'] as String?) ?? '',
        courseCode: (json['courseCode'] as String?) ?? '',
        termName: (json['termName'] as String?) ?? '未指定学期',
        termId: (json['termId'] as num?)?.toInt(),
        termStartAt: json['termStartAt'] as String?,
        termEndAt: json['termEndAt'] as String?,
        nickname: json['nickname'] as String?,
        startAt: json['startAt'] as String?,
        endAt: json['endAt'] as String?,
        imageUrl: json['imageUrl'] as String?,
        currentScore: (json['currentScore'] as num?)?.toDouble(),
        finalScore: (json['finalScore'] as num?)?.toDouble(),
        currentGrade: json['currentGrade'] as String?,
        finalGrade: json['finalGrade'] as String?,
        earnedPoints: (json['earnedPoints'] as num?)?.toDouble(),
        possiblePointsGraded: (json['possiblePointsGraded'] as num?)?.toDouble(),
        assignmentCount: (json['assignmentCount'] as num?)?.toInt() ?? 0,
        submittedCount: (json['submittedCount'] as num?)?.toInt() ?? 0,
        gradedCount: (json['gradedCount'] as num?)?.toInt() ?? 0,
        missingCount: (json['missingCount'] as num?)?.toInt() ?? 0,
        lateCount: (json['lateCount'] as num?)?.toInt() ?? 0,
        upcomingCount: (json['upcomingCount'] as num?)?.toInt() ?? 0,
      );
}

class AssignmentRow {
  const AssignmentRow({
    required this.id,
    required this.courseId,
    required this.courseName,
    required this.name,
    required this.groupId,
    required this.groupName,
    this.dueAt,
    this.pointsPossible,
    this.groupWeight = 0,
    this.score,
    this.grade,
    this.submittedAt,
    this.gradedAt,
    this.workflowState = 'unsubmitted',
    this.late = false,
    this.missing = false,
    this.excused = false,
    this.omitFromFinalGrade = false,
    this.htmlUrl,
    this.percent,
    this.weightedContribution,
  });

  final int id;
  final int courseId;
  final String courseName;
  final String name;
  final int groupId;
  final String groupName;
  final String? dueAt;
  final double? pointsPossible;
  final double groupWeight;
  final double? score;
  final String? grade;
  final String? submittedAt;
  final String? gradedAt;
  final String workflowState;
  final bool late;
  final bool missing;
  final bool excused;
  final bool omitFromFinalGrade;
  final String? htmlUrl;

  /// score / pointsPossible，百分比。
  final double? percent;

  /// 加权计分下对课程分的贡献。
  final double? weightedContribution;

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'courseName': courseName,
        'name': name,
        'groupId': groupId,
        'groupName': groupName,
        'dueAt': dueAt,
        'pointsPossible': pointsPossible,
        'groupWeight': groupWeight,
        'score': score,
        'grade': grade,
        'submittedAt': submittedAt,
        'gradedAt': gradedAt,
        'workflowState': workflowState,
        'late': late,
        'missing': missing,
        'excused': excused,
        'omitFromFinalGrade': omitFromFinalGrade,
        'htmlUrl': htmlUrl,
        'percent': percent,
        'weightedContribution': weightedContribution,
      };

  factory AssignmentRow.fromJson(Map<String, dynamic> json) => AssignmentRow(
        id: (json['id'] as num?)?.toInt() ?? 0,
        courseId: (json['courseId'] as num?)?.toInt() ?? 0,
        courseName: (json['courseName'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        groupId: (json['groupId'] as num?)?.toInt() ?? 0,
        groupName: (json['groupName'] as String?) ?? '未分组',
        dueAt: json['dueAt'] as String?,
        pointsPossible: (json['pointsPossible'] as num?)?.toDouble(),
        groupWeight: (json['groupWeight'] as num?)?.toDouble() ?? 0,
        score: (json['score'] as num?)?.toDouble(),
        grade: json['grade'] as String?,
        submittedAt: json['submittedAt'] as String?,
        gradedAt: json['gradedAt'] as String?,
        workflowState: (json['workflowState'] as String?) ?? 'unsubmitted',
        late: json['late'] == true,
        missing: json['missing'] == true,
        excused: json['excused'] == true,
        omitFromFinalGrade: json['omitFromFinalGrade'] == true,
        htmlUrl: json['htmlUrl'] as String?,
        percent: (json['percent'] as num?)?.toDouble(),
        weightedContribution: (json['weightedContribution'] as num?)?.toDouble(),
      );
}

class TodoEntry {
  const TodoEntry({
    required this.title,
    required this.courseName,
    required this.kind,
    this.courseId,
    this.dueAt,
    this.pointsPossible,
    this.htmlUrl,
  });

  final String title;
  final String courseName;
  final String kind;
  final int? courseId;
  final String? dueAt;
  final double? pointsPossible;
  final String? htmlUrl;

  Map<String, dynamic> toJson() => {
        'title': title,
        'courseName': courseName,
        'kind': kind,
        'courseId': courseId,
        'dueAt': dueAt,
        'pointsPossible': pointsPossible,
        'htmlUrl': htmlUrl,
      };

  factory TodoEntry.fromJson(Map<String, dynamic> json) => TodoEntry(
        title: (json['title'] as String?) ?? '',
        courseName: (json['courseName'] as String?) ?? '',
        kind: (json['kind'] as String?) ?? 'assignment',
        courseId: (json['courseId'] as num?)?.toInt(),
        dueAt: json['dueAt'] as String?,
        pointsPossible: (json['pointsPossible'] as num?)?.toDouble(),
        htmlUrl: json['htmlUrl'] as String?,
      );
}

/// 一次同步的完整结果，也是本地缓存的形态。
class Snapshot {
  const Snapshot({
    required this.fetchedAt,
    required this.profile,
    required this.courses,
    required this.terms,
    required this.assignments,
    this.todo = const [],
    this.warnings = const [],
  });

  final String fetchedAt;
  final CanvasProfile profile;
  final List<CourseSummary> courses;
  final List<TermGroup> terms;
  final List<AssignmentRow> assignments;
  final List<TodoEntry> todo;

  /// 组装过程中遇到的非致命问题。
  final List<String> warnings;

  Map<String, dynamic> toJson() => {
        'fetchedAt': fetchedAt,
        'profile': profile.toJson(),
        'courses': courses.map((c) => c.toJson()).toList(),
        'terms': terms.map((t) => t.toJson()).toList(),
        'assignments': assignments.map((a) => a.toJson()).toList(),
        'todo': todo.map((t) => t.toJson()).toList(),
        'warnings': warnings,
      };

  factory Snapshot.fromJson(Map<String, dynamic> json) => Snapshot(
        fetchedAt: (json['fetchedAt'] as String?) ?? DateTime.now().toIso8601String(),
        profile: CanvasProfile.fromJson(
            (json['profile'] as Map<String, dynamic>?) ?? const {'id': 0, 'name': '未知用户'}),
        courses: (json['courses'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(CourseSummary.fromJson)
            .toList(),
        terms: (json['terms'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(TermGroup.fromJson)
            .toList(),
        assignments: (json['assignments'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(AssignmentRow.fromJson)
            .toList(),
        todo: (json['todo'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(TodoEntry.fromJson)
            .toList(),
        warnings: (json['warnings'] as List<dynamic>? ?? []).whereType<String>().toList(),
      );
}

/// 课程详情页的聚合结果。
class CourseDetail {
  const CourseDetail({
    required this.course,
    required this.groups,
    required this.assignments,
    required this.gradingScheme,
  });

  final CourseSummary course;
  final List<AssignmentGroupDetail> groups;
  final List<AssignmentRow> assignments;

  /// 'weighted' 或 'points'。
  final String gradingScheme;
}

class AssignmentGroupDetail {
  const AssignmentGroupDetail({
    required this.id,
    required this.name,
    required this.weight,
    required this.earned,
    required this.possible,
    this.percent,
  });

  final int id;
  final String name;
  final double weight;
  final double earned;
  final double possible;
  final double? percent;
}
