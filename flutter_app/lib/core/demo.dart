/// 界面预览与截图用的演示数据。
///
/// 不联网、不需要账号；只在 DEMO 模式下使用。
/// 刻意铺了两个学期，让学期切换有东西可看。

library;

import 'files.dart';
import 'scoring.dart';
import 'types.dart';

/// 演示用的课程文件树。
///
/// 刻意包含几种真实场景：多级文件夹、中文与特殊字符文件名、
/// 大文件（视频），以及根目录直接放文件。
/// 文件夹带 position，用来验证「第一章」排在「第二章」之前。
FileNode buildDemoFileTree(int courseId) {
  final folders = <CanvasFolder>[
    const CanvasFolder(id: 1001, name: '课件', position: 1),
    const CanvasFolder(id: 1002, name: '第一章 绪论', parentFolderId: 1001, position: 1),
    const CanvasFolder(id: 1003, name: '第二章 线性表', parentFolderId: 1001, position: 2),
    const CanvasFolder(id: 1004, name: '作业', position: 2),
    const CanvasFolder(id: 1005, name: '实验材料', position: 3),
  ];

  CanvasFile mk(int id, int? folderId, String name, int size, String type) => CanvasFile(
        id: id + courseId * 1000,
        folderId: folderId,
        displayName: name,
        filename: name,
        contentType: type,
        url: 'https://elearning.fudan.edu.cn/files/$id/download?verifier=demo',
        size: size,
      );

  final files = <CanvasFile>[
    mk(1, 1002, '第1章 绪论.pdf', 2480000, 'application/pdf'),
    mk(2, 1002, '第1章 习题解答.pdf', 890000, 'application/pdf'),
    mk(3, 1003, '第2章 线性表.pdf', 3150000, 'application/pdf'),
    mk(4, 1004, '作业一：复杂度分析.docx', 128000,
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
    mk(5, 1004, '作业二：链表实现.zip', 1020000, 'application/zip'),
    mk(6, 1005, '实验指导书.pdf', 5600000, 'application/pdf'),
    // 特殊字符 + 大文件，用来验证净化与进度显示。
    mk(7, 1005, '实验数据：第1组 / 原始记录.xlsx', 76000,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
    mk(8, null, '课程大纲.pdf', 420000, 'application/pdf'),
    mk(9, null, '教学视频 第1讲.mp4', 268000000, 'video/mp4'),
  ];

  return buildFileTree(folders, files);
}

class _AssignmentSeed {
  const _AssignmentSeed(
    this.name,
    this.group,
    this.points,
    this.score,
    this.dueOffsetDays, {
    this.late = false,
    this.missing = false,
    this.submitted = false,
  });

  final String name;
  final int group;
  final double points;
  final double? score;
  final int dueOffsetDays;
  final bool late;
  final bool missing;

  /// 已交但未批改——这种记录绝不能被标成「逾期」。
  final bool submitted;
}

class _CourseSeed {
  const _CourseSeed({
    required this.id,
    required this.termId,
    required this.name,
    required this.code,
    required this.groups,
    required this.assignments,
  });

  final int id;
  final int termId;
  final String name;
  final String code;
  final List<({int id, String name, double weight})> groups;
  final List<_AssignmentSeed> assignments;
}

class _TermSeed {
  const _TermSeed(this.id, this.name, this.startOffsetDays, this.endOffsetDays);
  final int id;
  final String name;
  final int startOffsetDays;
  final int endOffsetDays;
}

const _terms = <_TermSeed>[
  _TermSeed(101, '2026-2027 学年第一学期', -62, 62),
  _TermSeed(100, '2025-2026 学年第二学期', -245, -152),
];

const _courses = <_CourseSeed>[
  _CourseSeed(
    id: 21101,
    termId: 101,
    name: 'PHYS120012.01 大学物理实验 II',
    code: 'PHYS120012.01',
    groups: [
      (id: 1, name: '实验报告', weight: 60),
      (id: 2, name: '预习与操作', weight: 25),
      (id: 3, name: '期末考核', weight: 15),
    ],
    assignments: [
      _AssignmentSeed('实验一 用示波器观测波形（报告）', 1, 100, 88, -38),
      _AssignmentSeed('实验二 用分光计测棱镜折射率（报告）', 1, 100, 92, -31),
      _AssignmentSeed('实验三 用惠斯通电桥测电阻（报告）', 1, 100, 85, -24),
      _AssignmentSeed('实验四 用牛顿环测曲率半径（报告）', 1, 100, 78, -17),
      // 已交、未批改、已过截止时间——旧的判定会把它误标成逾期。
      _AssignmentSeed('实验五 用光电效应测普朗克常量（报告）', 1, 100, null, -3, submitted: true),
      _AssignmentSeed('实验六 用迈克尔逊干涉仪测波长（预习）', 2, 20, 20, -2),
      _AssignmentSeed('实验六 用迈克尔逊干涉仪测波长（报告）', 1, 100, null, 4),
      _AssignmentSeed('期末操作考核', 3, 100, null, 32),
    ],
  ),
  _CourseSeed(
    id: 21202,
    termId: 101,
    name: 'MATH120003.05 高等数学 A（下）',
    code: 'MATH120003.05',
    groups: [
      (id: 1, name: '平时作业', weight: 30),
      (id: 2, name: '期中考试', weight: 20),
      (id: 3, name: '期末考试', weight: 50),
    ],
    assignments: [
      _AssignmentSeed('第 8 周作业（重积分）', 1, 50, 47, -35),
      _AssignmentSeed('第 9 周作业（曲线积分）', 1, 50, 44, -28),
      _AssignmentSeed('第 10 周作业（曲面积分）', 1, 50, 41, -21),
      _AssignmentSeed('第 11 周作业（级数）', 1, 50, null, -12, missing: true),
      _AssignmentSeed('第 12 周作业（幂级数）', 1, 50, 45, -5),
      _AssignmentSeed('期中考试', 2, 100, 82, -26),
      _AssignmentSeed('第 13 周作业（傅里叶级数）', 1, 50, null, 2),
      _AssignmentSeed('期末考试', 3, 100, null, 45),
    ],
  ),
  _CourseSeed(
    id: 21303,
    termId: 101,
    name: 'CS100113.02 程序设计基础',
    code: 'CS100113.02',
    groups: [
      (id: 1, name: '编程作业', weight: 45),
      (id: 2, name: '上机实验', weight: 25),
      (id: 3, name: '期末项目', weight: 30),
    ],
    assignments: [
      _AssignmentSeed('Lab 01 环境配置与 Hello World', 2, 10, 10, -42),
      _AssignmentSeed('Homework 01 基础语法练习', 1, 100, 96, -33),
      _AssignmentSeed('Lab 02 分支与循环', 2, 10, 10, -35),
      _AssignmentSeed('Homework 02 函数与递归', 1, 100, 91, -24),
      _AssignmentSeed('Homework 03 结构体与文件', 1, 100, 88, -12, late: true),
      _AssignmentSeed('Homework 04 简单数据结构实现', 1, 100, null, 1),
      _AssignmentSeed('期末项目 图书管理系统', 3, 100, null, 28),
    ],
  ),
  _CourseSeed(
    id: 21505,
    termId: 101,
    name: 'CS100211.01 数据结构',
    code: 'CS100211.01',
    groups: [
      (id: 1, name: '作业', weight: 40),
      (id: 2, name: '实验', weight: 30),
      (id: 3, name: '期末', weight: 30),
    ],
    assignments: [
      _AssignmentSeed('作业一 线性表', 1, 100, 94, -34),
      _AssignmentSeed('实验一 顺序表与链表', 2, 100, 90, -32),
      _AssignmentSeed('作业二 栈与队列', 1, 100, 86, -25),
      _AssignmentSeed('实验二 表达式求值', 2, 100, null, -19, missing: true),
      _AssignmentSeed('作业三 树与二叉树', 1, 100, 79, -11),
      _AssignmentSeed('实验三 哈夫曼编码', 2, 100, null, 0),
      _AssignmentSeed('期末考试', 3, 100, null, 40),
    ],
  ),
  _CourseSeed(
    id: 22107,
    termId: 100,
    name: 'MATH120002.03 高等数学 A（上）',
    code: 'MATH120002.03',
    groups: [
      (id: 1, name: '平时作业', weight: 40),
      (id: 2, name: '期末考试', weight: 60),
    ],
    assignments: [
      _AssignmentSeed('第 4 周作业（极限与连续）', 1, 50, 46, -235),
      _AssignmentSeed('第 8 周作业（不定积分）', 1, 50, 48, -215),
      _AssignmentSeed('期末考试', 2, 100, 88, -158),
    ],
  ),
  _CourseSeed(
    id: 22208,
    termId: 100,
    name: 'CS100114.01 计算机导论',
    code: 'CS100114.01',
    groups: [
      (id: 1, name: '平时成绩', weight: 50),
      (id: 2, name: '期末项目', weight: 50),
    ],
    assignments: [
      _AssignmentSeed('文献综述作业', 1, 100, 91, -230),
      _AssignmentSeed('课堂展示：图灵与计算', 1, 100, 94, -200),
      _AssignmentSeed('期末项目 个人网站', 2, 100, 89, -156),
    ],
  ),
];

String _iso(int daysFromNow, [int hour = 23, int minute = 59]) {
  final d = DateTime.now().add(Duration(days: daysFromNow));
  return DateTime(d.year, d.month, d.day, hour, minute).toIso8601String();
}

Snapshot buildDemoSnapshot() {
  const profile = CanvasProfile(id: 90210, name: '示例同学', loginId: '20302010001');

  final courses = <CourseSummary>[];
  final assignments = <AssignmentRow>[];

  for (final seed in _courses) {
    final term = _terms.firstWhere((t) => t.id == seed.termId);
    final termStart = _iso(term.startOffsetDays, 0, 0);
    final termEnd = _iso(term.endOffsetDays);

    final rows = <AssignmentRow>[];
    for (var i = 0; i < seed.assignments.length; i++) {
      final a = seed.assignments[i];
      final group = seed.groups.firstWhere((g) => g.id == a.group);
      final score = a.score;
      final percent = score == null ? null : (score / a.points) * 100;
      final done = score != null || a.late || a.submitted;

      rows.add(AssignmentRow(
        id: seed.id * 100 + i,
        courseId: seed.id,
        courseName: seed.name,
        name: a.name,
        dueAt: _iso(a.dueOffsetDays),
        pointsPossible: a.points,
        groupId: a.group,
        groupName: group.name,
        groupWeight: group.weight,
        score: score,
        grade: score?.toString(),
        submittedAt: done ? _iso(a.dueOffsetDays - 1) : null,
        gradedAt: score == null ? null : _iso(a.dueOffsetDays - 1, 10, 0),
        workflowState: score != null ? 'graded' : (done ? 'submitted' : 'unsubmitted'),
        late: a.late,
        missing: a.missing,
        htmlUrl: 'https://elearning.fudan.edu.cn/courses/${seed.id}/assignments/${seed.id * 100 + i}',
        percent: percent,
        weightedContribution: percent == null || group.weight == 0 ? null : (percent / 100) * group.weight,
      ));
    }

    // 加权分：只算已评分的分组，权重重新归一化。
    final totals = <int, ({double weight, double earned, double possible})>{};
    for (final r in rows) {
      final g = totals[r.groupId] ?? (weight: r.groupWeight, earned: 0.0, possible: 0.0);
      if (r.score != null && r.pointsPossible != null && r.pointsPossible! > 0) {
        totals[r.groupId] = (
          weight: g.weight,
          earned: g.earned + r.score!,
          possible: g.possible + r.pointsPossible!,
        );
      } else {
        totals[r.groupId] = g;
      }
    }
    final currentScore = computeWeightedPercent(totals.values.toList());
    final earned = totals.values.fold<double>(0, (s, g) => s + g.earned);
    final possible = totals.values.fold<double>(0, (s, g) => s + g.possible);
    final now = DateTime.now();

    courses.add(CourseSummary(
      id: seed.id,
      name: seed.name,
      displayName: seed.name,
      courseCode: seed.code,
      termId: term.id,
      termName: term.name,
      termStartAt: termStart,
      termEndAt: termEnd,
      startAt: termStart,
      endAt: termEnd,
      currentScore: currentScore,
      earnedPoints: possible > 0 ? earned : null,
      possiblePointsGraded: possible > 0 ? possible : null,
      assignmentCount: rows.length,
      submittedCount: rows.where((r) => r.workflowState != 'unsubmitted').length,
      gradedCount: rows.where((r) => r.score != null).length,
      missingCount: rows.where((r) => r.missing).length,
      lateCount: rows.where((r) => r.late).length,
      upcomingCount: rows
          .where((r) => r.dueAt != null && DateTime.parse(r.dueAt!).isAfter(now))
          .length,
    ));

    assignments.addAll(rows);
  }

  courses.sort((a, b) => a.displayName.compareTo(b.displayName));
  assignments.sort((a, b) {
    final ta = a.dueAt == null ? null : DateTime.parse(a.dueAt!);
    final tb = b.dueAt == null ? null : DateTime.parse(b.dueAt!);
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return tb.compareTo(ta);
  });

  final now = DateTime.now();
  final todo = assignments
      .where((r) => r.score == null && r.dueAt != null && DateTime.parse(r.dueAt!).isAfter(now))
      .map((r) => TodoEntry(
            title: r.name,
            courseId: r.courseId,
            courseName: r.courseName,
            dueAt: r.dueAt,
            pointsPossible: r.pointsPossible,
            htmlUrl: r.htmlUrl,
            kind: 'assignment',
          ))
      .toList()
    ..sort((a, b) => DateTime.parse(a.dueAt!).compareTo(DateTime.parse(b.dueAt!)));

  return Snapshot(
    fetchedAt: DateTime.now().toIso8601String(),
    profile: profile,
    courses: courses,
    terms: buildTermGroups(courses),
    assignments: assignments,
    todo: todo,
  );
}
