/**
 * Synthetic data for UI preview and screenshots.
 *
 * Enabled only when ELEARNING_DEMO is set; it never touches the network and is
 * never reachable in a normal run.
 */

import { buildTermGroups } from './scoring.ts';
import { buildFileTree, type CanvasFile, type CanvasFolder, type FileNode } from './files.ts';
import { makeExcerpt } from './summary.ts';
import type { AssignmentRow, CanvasProfile, CourseSummary, Snapshot, TermGroup } from './types.ts';

interface TermSeed {
  id: number;
  name: string;
  startOffsetDays: number;
  endOffsetDays: number;
}

/** Deliberately spans three semesters so term grouping is visible in previews. */
const TERMS: TermSeed[] = [
  { id: 101, name: '2026-2027 学年第一学期', startOffsetDays: -62, endOffsetDays: 62 },
  { id: 100, name: '2025-2026 学年第二学期', startOffsetDays: -245, endOffsetDays: -152 },
  { id: 99, name: '2025-2026 学年第一学期', startOffsetDays: -430, endOffsetDays: -337 },
];

interface Seed {
  id: number;
  termId: number;
  name: string;
  code: string;
  groups: { id: number; name: string; weight: number }[];
  assignments: {
    name: string;
    group: number;
    points: number;
    score: number | null;
    dueOffsetDays: number;
    late?: boolean;
    missing?: boolean;
    /** Handed in but not yet marked - the case that must never read as 逾期. */
    submitted?: boolean;
    /** 作业说明（HTML），用来验证详情页与简介。 */
    description?: string;
  }[];
}

const SEEDS: Seed[] = [
  {
    id: 21101,
    termId: 101,
    name: 'PHYS120012.01 大学物理实验 II',
    code: 'PHYS120012.01',
    groups: [
      { id: 1, name: '实验报告', weight: 60 },
      { id: 2, name: '预习与操作', weight: 25 },
      { id: 3, name: '期末考核', weight: 15 },
    ],
    assignments: [
      { name: '实验一 用示波器观测波形（报告）', group: 1, points: 100, score: 88, dueOffsetDays: -38 },
      { name: '实验二 用分光计测棱镜折射率（报告）', group: 1, points: 100, score: 92, dueOffsetDays: -31 },
      { name: '实验三 用惠斯通电桥测电阻（报告）', group: 1, points: 100, score: 85, dueOffsetDays: -24 },
      { name: '实验四 用牛顿环测曲率半径（报告）', group: 1, points: 100, score: 78, dueOffsetDays: -17 },
      {
        name: '实验五 用光电效应测普朗克常量（报告）',
        group: 1,
        points: 100,
        score: null,
        dueOffsetDays: -3,
        submitted: true,
        description: `<p>本次实验通过测量不同波长光照射下光电管的遏止电压，验证爱因斯坦光电效应方程并测定普朗克常量。</p>
<p><strong>实验内容：</strong></p>
<ul>
  <li>测量汞灯各谱线（365.0 / 404.7 / 435.8 / 546.1 / 577.0 nm）对应的遏止电压</li>
  <li>作 U<sub>c</sub>–ν 关系图，由斜率求普朗克常量 h</li>
  <li>由截距求逸出功，并与公认值比较</li>
</ul>
<p><strong>数据处理要求：</strong>用最小二乘法拟合直线，给出斜率的不确定度，计算 h 的相对误差并分析主要误差来源。</p>
<p><strong>报告需包含：</strong>实验目的、原理（附光电效应方程推导）、装置与步骤、原始数据表、数据处理过程、误差分析、结论、参考文献。<p>请于截止日期前上传 PDF 格式的实验报告，文件命名为「学号_姓名_实验五报告.pdf」。</p>`,
      },
      { name: '实验六 用迈克尔逊干涉仪测波长（预习）', group: 2, points: 20, score: 20, dueOffsetDays: -2 },
      {
        name: '实验六 用迈克尔逊干涉仪测波长（报告）',
        group: 1,
        points: 100,
        score: null,
        dueOffsetDays: 4,
        description: `<p>利用迈克尔逊干涉仪测量氦氖激光的波长，并观察等倾干涉与等厚干涉图样。</p>
<p>要求记录 M<sub>1</sub> 每移动 50 个条纹对应的读数，重复测量 6 次，用逐差法求平均值。报告需附干涉圆环的照片或手绘示意图，并讨论空程差对测量结果的影响。</p>`,
      },
      { name: '实验七 用弗兰克-赫兹实验测激发电位（预习）', group: 2, points: 20, score: null, dueOffsetDays: 9 },
      { name: '期末操作考核', group: 3, points: 100, score: null, dueOffsetDays: 32 },
    ],
  },
  {
    id: 21202,
    termId: 101,
    name: 'MATH120003.05 高等数学 A（下）',
    code: 'MATH120003.05',
    groups: [
      { id: 1, name: '平时作业', weight: 30 },
      { id: 2, name: '期中考试', weight: 20 },
      { id: 3, name: '期末考试', weight: 50 },
    ],
    assignments: [
      { name: '第 8 周作业（重积分）', group: 1, points: 50, score: 47, dueOffsetDays: -35 },
      { name: '第 9 周作业（曲线积分）', group: 1, points: 50, score: 44, dueOffsetDays: -28 },
      { name: '第 10 周作业（曲面积分）', group: 1, points: 50, score: 41, dueOffsetDays: -21 },
      {
        name: '第 11 周作业（级数）',
        group: 1,
        points: 50,
        score: null,
        missing: true,
        dueOffsetDays: -12,
        description: `<p>教材第 12 章习题：12.3、12.7、12.11、12.15、12.20。</p>
<p>其中 12.15 要求判断级数的敛散性并说明所用的判别法；12.20 要求求幂级数的收敛半径与收敛域，并写出和函数。</p>
<p>手写拍照或 LaTeX 排版均可，合并为一个 PDF 上传。</p>`,
      },
      { name: '第 12 周作业（幂级数）', group: 1, points: 50, score: 45, dueOffsetDays: -5 },
      { name: '期中考试', group: 2, points: 100, score: 82, dueOffsetDays: -26 },
      { name: '第 13 周作业（傅里叶级数）', group: 1, points: 50, score: null, dueOffsetDays: 2 },
      { name: '期末考试', group: 3, points: 100, score: null, dueOffsetDays: 45 },
    ],
  },
  {
    id: 21303,
    termId: 101,
    name: 'CS100113.02 程序设计基础',
    code: 'CS100113.02',
    groups: [
      { id: 1, name: '编程作业', weight: 45 },
      { id: 2, name: '上机实验', weight: 25 },
      { id: 3, name: '期末项目', weight: 30 },
    ],
    assignments: [
      { name: 'Lab 01 环境配置与 Hello World', group: 2, points: 10, score: 10, dueOffsetDays: -42 },
      { name: 'Lab 02 分支与循环', group: 2, points: 10, score: 10, dueOffsetDays: -35 },
      { name: 'Homework 01 基础语法练习', group: 1, points: 100, score: 96, dueOffsetDays: -33 },
      { name: 'Lab 03 数组与字符串', group: 2, points: 10, score: 9.5, dueOffsetDays: -28 },
      { name: 'Homework 02 函数与递归', group: 1, points: 100, score: 91, dueOffsetDays: -24 },
      { name: 'Lab 04 指针与内存', group: 2, points: 10, score: 9, dueOffsetDays: -18 },
      { name: 'Homework 03 结构体与文件', group: 1, points: 100, score: 88, late: true, dueOffsetDays: -12 },
      { name: 'Homework 04 简单数据结构实现', group: 1, points: 100, score: null, dueOffsetDays: 1 },
      { name: '期末项目 图书管理系统', group: 3, points: 100, score: null, dueOffsetDays: 28 },
    ],
  },
  {
    id: 21404,
    termId: 101,
    name: 'HIST120012.04 中国古代文明',
    code: 'HIST120012.04',
    groups: [
      { id: 1, name: '读书报告', weight: 40 },
      { id: 2, name: '课堂讨论', weight: 20 },
      { id: 3, name: '期末论文', weight: 40 },
    ],
    assignments: [
      { name: '读书报告一：《史记》选读', group: 1, points: 100, score: 90, dueOffsetDays: -30 },
      { name: '课堂讨论 第一讲 先秦文明', group: 2, points: 100, score: 88, dueOffsetDays: -29 },
      { name: '读书报告二：《汉书》选读', group: 1, points: 100, score: 93, dueOffsetDays: -16 },
      { name: '课堂讨论 第二讲 秦汉制度', group: 2, points: 100, score: 85, dueOffsetDays: -15 },
      { name: '期末论文选题与提纲', group: 3, points: 20, score: 18, dueOffsetDays: -4 },
      { name: '期末论文', group: 3, points: 100, score: null, dueOffsetDays: 21 },
    ],
  },
  {
    id: 21505,
    termId: 101,
    name: 'CS100211.01 数据结构',
    code: 'CS100211.01',
    groups: [
      { id: 1, name: '作业', weight: 40 },
      { id: 2, name: '实验', weight: 30 },
      { id: 3, name: '期末', weight: 30 },
    ],
    assignments: [
      { name: '作业一 线性表', group: 1, points: 100, score: 94, dueOffsetDays: -34 },
      { name: '实验一 顺序表与链表', group: 2, points: 100, score: 90, dueOffsetDays: -32 },
      { name: '作业二 栈与队列', group: 1, points: 100, score: 86, dueOffsetDays: -25 },
      { name: '实验二 表达式求值', group: 2, points: 100, score: null, missing: true, dueOffsetDays: -19 },
      { name: '作业三 树与二叉树', group: 1, points: 100, score: 79, dueOffsetDays: -11 },
      { name: '实验三 哈夫曼编码', group: 2, points: 100, score: null, dueOffsetDays: 0 },
      { name: '作业四 图与最短路径', group: 1, points: 100, score: null, dueOffsetDays: 5 },
      { name: '期末考试', group: 3, points: 100, score: null, dueOffsetDays: 40 },
    ],
  },
  {
    id: 21606,
    termId: 101,
    name: 'ENGL110022.07 大学英语 III',
    code: 'ENGL110022.07',
    groups: [
      { id: 1, name: '平时成绩', weight: 50 },
      { id: 2, name: '期中', weight: 20 },
      { id: 3, name: '期末', weight: 30 },
    ],
    assignments: [
      { name: 'Unit 1 Writing Task', group: 1, points: 100, score: 87, dueOffsetDays: -36 },
      { name: 'Unit 2 Group Presentation', group: 1, points: 100, score: 92, dueOffsetDays: -27 },
      { name: 'Midterm Listening Test', group: 2, points: 100, score: 84, dueOffsetDays: -20 },
      { name: 'Unit 3 Writing Task', group: 1, points: 100, score: 89, dueOffsetDays: -13 },
      { name: 'Unit 4 Reading Log', group: 1, points: 100, score: null, dueOffsetDays: 3 },
      { name: 'Final Oral Exam', group: 3, points: 100, score: null, dueOffsetDays: 38 },
    ],
  },

  // --- concluded semesters, so the term switch has something to show --------
  {
    id: 22107,
    termId: 100,
    name: 'MATH120002.03 高等数学 A（上）',
    code: 'MATH120002.03',
    groups: [
      { id: 1, name: '平时作业', weight: 40 },
      { id: 2, name: '期末考试', weight: 60 },
    ],
    assignments: [
      { name: '第 4 周作业（极限与连续）', group: 1, points: 50, score: 46, dueOffsetDays: -235 },
      { name: '第 6 周作业（导数与微分）', group: 1, points: 50, score: 43, dueOffsetDays: -225 },
      { name: '第 8 周作业（不定积分）', group: 1, points: 50, score: 48, dueOffsetDays: -215 },
      { name: '第 10 周作业（定积分）', group: 1, points: 50, score: 45, dueOffsetDays: -205 },
      { name: '期末考试', group: 2, points: 100, score: 88, dueOffsetDays: -158 },
    ],
  },
  {
    id: 22208,
    termId: 100,
    name: 'CS100114.01 计算机导论',
    code: 'CS100114.01',
    groups: [
      { id: 1, name: '平时成绩', weight: 50 },
      { id: 2, name: '期末项目', weight: 50 },
    ],
    assignments: [
      { name: '文献综述作业', group: 1, points: 100, score: 91, dueOffsetDays: -230 },
      { name: '课堂展示：图灵与计算', group: 1, points: 100, score: 94, dueOffsetDays: -200 },
      { name: '期末项目 个人网站', group: 2, points: 100, score: 89, dueOffsetDays: -156 },
    ],
  },
  {
    id: 22309,
    termId: 100,
    name: 'PHYS120011.02 大学物理 A（上）',
    code: 'PHYS120011.02',
    groups: [
      { id: 1, name: '平时作业', weight: 30 },
      { id: 2, name: '期中', weight: 20 },
      { id: 3, name: '期末', weight: 50 },
    ],
    assignments: [
      { name: '作业一 质点运动学', group: 1, points: 100, score: 85, dueOffsetDays: -240 },
      { name: '作业二 牛顿定律', group: 1, points: 100, score: 81, dueOffsetDays: -232 },
      { name: '期中考试', group: 2, points: 100, score: 76, dueOffsetDays: -210 },
      { name: '作业三 刚体转动', group: 1, points: 100, score: 88, dueOffsetDays: -190 },
      { name: '期末考试', group: 3, points: 100, score: 83, dueOffsetDays: -157 },
    ],
  },
  {
    id: 23110,
    termId: 99,
    name: 'CHIN110011.05 大学语文',
    code: 'CHIN110011.05',
    groups: [{ id: 1, name: '平时成绩', weight: 100 }],
    assignments: [
      { name: '古诗文默写测试', group: 1, points: 100, score: 92, dueOffsetDays: -425 },
      { name: '读书笔记：《论语》', group: 1, points: 100, score: 90, dueOffsetDays: -400 },
      { name: '期末小论文', group: 1, points: 100, score: 87, dueOffsetDays: -343 },
    ],
  },
  {
    id: 23211,
    termId: 99,
    name: 'PE100001.12 体育（一）',
    code: 'PE100001.12',
    groups: [{ id: 1, name: '平时成绩', weight: 100 }],
    assignments: [
      { name: '体质测试', group: 1, points: 100, score: 85, dueOffsetDays: -410 },
      { name: '太极拳考核', group: 1, points: 100, score: 88, dueOffsetDays: -350 },
    ],
  },
];

function termOf(termId: number): TermSeed {
  return TERMS.find((t) => t.id === termId) ?? TERMS[0];
}

function iso(daysFromNow: number, hour = 23, minute = 59): string {
  const d = new Date();
  d.setDate(d.getDate() + daysFromNow);
  d.setHours(hour, minute, 0, 0);
  return d.toISOString();
}

export function buildDemoSnapshot(): Snapshot {
  const profile: CanvasProfile = {
    id: 90210,
    name: '示例同学',
    login_id: '20302010001',
    primary_email: '20302010001@fudan.edu.cn',
    sis_user_id: '20302010001',
  };

  const now = Date.now();
  const courses: CourseSummary[] = [];
  const all: AssignmentRow[] = [];

  for (const seed of SEEDS) {
    const rows: AssignmentRow[] = seed.assignments.map((a, index) => {
      const group = seed.groups.find((g) => g.id === a.group);
      const score = a.score;
      const percent = score === null ? null : (score / a.points) * 100;
      const weight = group?.weight ?? 0;
      const due = iso(a.dueOffsetDays);
      // A submission only exists once something was handed in: either it was
      // graded, explicitly marked late, or declared as awaiting marking.
      const submitted = score !== null || a.late === true || a.submitted === true;
      return {
        id: seed.id * 100 + index,
        courseId: seed.id,
        courseName: seed.name,
        name: a.name,
        dueAt: due,
        pointsPossible: a.points,
        groupId: a.group,
        groupName: group?.name ?? '未分组',
        groupWeight: weight,
        score,
        grade: score === null ? null : String(score),
        submittedAt: submitted ? iso(a.dueOffsetDays - 1) : null,
        gradedAt: score === null ? null : iso(a.dueOffsetDays - 1, 10, 0),
        workflowState: score === null ? (submitted ? 'submitted' : 'unsubmitted') : 'graded',        late: a.late === true,
        missing: a.missing === true,
        excused: false,
        omitFromFinalGrade: false,
        htmlUrl: `https://elearning.fudan.edu.cn/courses/${seed.id}/assignments/${seed.id * 100 + index}`,
        descriptionExcerpt: makeExcerpt(a.description),
        percent,
        weightedContribution: percent !== null && weight > 0 ? (percent / 100) * weight : null,
      };
    });

    // Weighted score over groups that have graded work, weights renormalised.
    const groupTotals = new Map<number, { weight: number; earned: number; possible: number }>();
    for (const r of rows) {
      const g = groupTotals.get(r.groupId) ?? { weight: r.groupWeight, earned: 0, possible: 0 };
      if (r.score !== null && r.pointsPossible) {
        g.earned += r.score;
        g.possible += r.pointsPossible;
      }
      groupTotals.set(r.groupId, g);
    }
    const gradedGroups = [...groupTotals.values()].filter((g) => g.possible > 0);
    const totalWeight = gradedGroups.reduce((s, g) => s + g.weight, 0);
    const currentScore =
      totalWeight > 0
        ? gradedGroups.reduce((s, g) => s + (g.earned / g.possible) * g.weight, 0) / totalWeight * 100
        : gradedGroups.length > 0
          ? (gradedGroups.reduce((s, g) => s + g.earned, 0) / gradedGroups.reduce((s, g) => s + g.possible, 0)) * 100
          : null;

    const term = termOf(seed.termId);
    const termStart = iso(term.startOffsetDays, 0, 0);
    const termEnd = iso(term.endOffsetDays, 23, 59);

    courses.push({
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
      imageUrl: null,
      currentScore,
      finalScore: null,
      currentGrade: null,
      finalGrade: null,
      earnedPoints: gradedGroups.reduce((s, g) => s + g.earned, 0),
      possiblePointsGraded: gradedGroups.reduce((s, g) => s + g.possible, 0),
      assignmentCount: rows.length,
      submittedCount: rows.filter((r) => r.workflowState !== 'unsubmitted').length,
      gradedCount: rows.filter((r) => r.score !== null).length,
      missingCount: rows.filter((r) => r.missing).length,
      lateCount: rows.filter((r) => r.late).length,
      upcomingCount: rows.filter((r) => r.dueAt && Date.parse(r.dueAt) > now).length,
    });

    all.push(...rows);
  }

  const todo = all
    .filter((r) => r.score === null && r.dueAt && Date.parse(r.dueAt) > now)
    .sort((a, b) => Date.parse(a.dueAt as string) - Date.parse(b.dueAt as string))
    .map((r) => ({
      title: r.name,
      courseId: r.courseId,
      courseName: r.courseName,
      dueAt: r.dueAt,
      pointsPossible: r.pointsPossible,
      htmlUrl: r.htmlUrl,
      kind: 'assignment',
    }));

  return {
    fetchedAt: new Date().toISOString(),
    profile,
    courses: courses.sort((a, b) => a.displayName.localeCompare(b.displayName, 'zh-Hans-CN')),
    terms: buildTermGroups(courses),
    assignments: all.sort((a, b) => {
      if (!a.dueAt) return 1;
      if (!b.dueAt) return -1;
      return Date.parse(b.dueAt) - Date.parse(a.dueAt);
    }),
    todo,
    warnings: [],
  };
}

/**
 * 演示用的课程文件树。
 *
 * 刻意包含几种真实场景：多级文件夹、中文与特殊字符文件名、
 * 大文件（视频）、以及根目录直接放文件。
 */
export function buildDemoFileTree(courseId: number): FileNode {
  const folders: CanvasFolder[] = [
    { id: 1001, name: '课件', fullName: 'course files/课件', parentFolderId: null, filesCount: 0, foldersCount: 1, position: 1 },
    { id: 1002, name: '第一章 绪论', fullName: 'course files/课件/第一章 绪论', parentFolderId: 1001, filesCount: 2, foldersCount: 0, position: 1 },
    { id: 1003, name: '第二章 线性表', fullName: 'course files/课件/第二章 线性表', parentFolderId: 1001, filesCount: 1, foldersCount: 0, position: 2 },
    { id: 1004, name: '作业', fullName: 'course files/作业', parentFolderId: null, filesCount: 2, foldersCount: 0, position: 2 },
    { id: 1005, name: '实验材料', fullName: 'course files/实验材料', parentFolderId: null, filesCount: 2, foldersCount: 0, position: 3 },
  ];

  const mk = (id: number, folderId: number | null, name: string, size: number, type: string): CanvasFile => ({
    id: id + courseId * 1000,
    folderId,
    displayName: name,
    filename: name,
    contentType: type,
    url: `https://elearning.fudan.edu.cn/files/${id}/download?verifier=demo`,
    size,
    createdAt: iso(-30),
    updatedAt: iso(-3),
    locked: false,
    hidden: false,
  });

  const files: CanvasFile[] = [
    mk(1, 1002, '第1章 绪论.pdf', 2_480_000, 'application/pdf'),
    mk(2, 1002, '第1章 习题解答.pdf', 890_000, 'application/pdf'),
    mk(3, 1003, '第2章 线性表.pdf', 3_150_000, 'application/pdf'),
    mk(4, 1004, '作业一：复杂度分析.docx', 128_000, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
    mk(5, 1004, '作业二：链表实现.zip', 1_020_000, 'application/zip'),
    mk(6, 1005, '实验指导书.pdf', 5_600_000, 'application/pdf'),
    // 特殊字符 + 大文件，用来验证净化与进度显示。
    mk(7, 1005, '实验数据：第1组 / 原始记录.xlsx', 76_000, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
    mk(8, null, '课程大纲.pdf', 420_000, 'application/pdf'),
    mk(9, null, '教学视频 第1讲.mp4', 268_000_000, 'video/mp4'),
  ];

  return buildFileTree(folders, files);
}
