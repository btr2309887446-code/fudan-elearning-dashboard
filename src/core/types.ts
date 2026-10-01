/** Shared data shapes for the Canvas payloads this app consumes. */

export interface CanvasProfile {
  id: number;
  name: string;
  login_id?: string;
  primary_email?: string;
  avatar_url?: string;
  sis_user_id?: string;
}

export interface CanvasGrades {
  current_score: number | null;
  final_score: number | null;
  current_grade: string | null;
  final_grade: string | null;
  unposted_current_score?: number | null;
  unposted_final_score?: number | null;
}

export interface CanvasEnrollment {
  id: number;
  course_id: number;
  user_id: number;
  type: string;
  role: string;
  enrollment_state: string;
  computed_current_score?: number | null;
  computed_final_score?: number | null;
  computed_current_grade?: string | null;
  computed_final_grade?: string | null;
  current_score?: number | null;
  current_grade?: string | null;
  final_score?: number | null;
  final_grade?: string | null;
  grades?: CanvasGrades;
}

export interface CanvasTerm {
  id: number;
  name: string;
  start_at?: string | null;
  end_at?: string | null;
}

export interface CanvasCourse {
  id: number;
  name: string;
  course_code: string;
  workflow_state: string;
  enrollment_term_id?: number;
  /** Present only when the request asks for include[]=term. */
  term?: CanvasTerm | null;
  start_at?: string | null;
  end_at?: string | null;
  created_at?: string;
  time_zone?: string;
  image_download_url?: string | null;
  enrollments?: CanvasEnrollment[];
  total_scores?: unknown;
}

export interface CanvasSubmission {
  id: number;
  assignment_id: number;
  user_id: number;
  score: number | null;
  grade: string | null;
  submitted_at: string | null;
  graded_at: string | null;
  workflow_state: string;
  attempt?: number | null;
  late?: boolean;
  missing?: boolean;
  excused?: boolean;
  points_deducted?: number | null;
  seconds_late?: number | null;
  html_url?: string;
  preview_url?: string;
}

export interface CanvasAssignment {
  id: number;
  course_id: number;
  name: string;
  description?: string | null;
  due_at: string | null;
  unlock_at: string | null;
  lock_at: string | null;
  points_possible: number | null;
  grading_type: string;
  assignment_group_id: number;
  published: boolean;
  muted?: boolean;
  html_url?: string;
  submission_types?: string[];
  submission?: CanvasSubmission | null;
  has_submitted_submissions?: boolean;
  quiz_id?: number;
  omit_from_final_grade?: boolean;
}

export interface CanvasAssignmentGroup {
  id: number;
  name: string;
  position: number;
  group_weight: number;
  assignments?: CanvasAssignment[];
  rules?: Record<string, unknown>;
}

export interface CanvasTodoItem {
  type: string;
  assignment?: CanvasAssignment;
  quiz?: { id: number; title: string; due_at: string | null; points_possible: number | null; html_url?: string };
  context_type?: string;
  course_id?: number;
  html_url?: string;
  ignore?: string;
  ignore_permanently?: string;
}

export interface CanvasPlannerItem {
  type: string;
  title?: string;
  course_id?: number;
  plannable_id: number;
  plannable_type: string;
  plannable_date: string | null;
  plannable?: {
    id: number;
    title?: string;
    name?: string;
    due_at?: string | null;
    points_possible?: number | null;
  };
  html_url?: string;
  submissions?: unknown;
}

export interface CanvasNickname {
  course_id: number;
  name: string;
  nickname?: string;
}

/** One semester, as the UI groups courses by it. */
export interface TermGroup {
  /** null groups courses Canvas gave no term for. */
  id: number | null;
  name: string;
  startAt: string | null;
  endAt: string | null;
  /** The term the current date falls inside, else the most recent one. */
  isCurrent: boolean;
  courseCount: number;
}

/** Fully assembled per-course view model handed to the renderer. */
export interface CourseSummary {
  id: number;
  name: string;
  displayName: string;
  courseCode: string;
  nickname?: string;
  termId: number | null;
  termName: string;
  /** The term's own date range, which the UI shows as the semester heading. */
  termStartAt: string | null;
  termEndAt: string | null;
  startAt: string | null;
  endAt: string | null;
  imageUrl?: string | null;
  currentScore: number | null;
  finalScore: number | null;
  currentGrade: string | null;
  finalGrade: string | null;
  /** Points the student has earned so far, when derivable. */
  earnedPoints: number | null;
  possiblePointsGraded: number | null;
  assignmentCount: number;
  submittedCount: number;
  gradedCount: number;
  missingCount: number;
  lateCount: number;
  upcomingCount: number;
}

export interface AssignmentRow {
  id: number;
  courseId: number;
  courseName: string;
  name: string;
  dueAt: string | null;
  pointsPossible: number | null;
  groupId: number;
  groupName: string;
  groupWeight: number;
  score: number | null;
  grade: string | null;
  submittedAt: string | null;
  gradedAt: string | null;
  workflowState: string;
  late: boolean;
  missing: boolean;
  excused: boolean;
  omitFromFinalGrade: boolean;
  htmlUrl?: string;
  /**
   * 作业描述的纯文本摘录（已去 HTML、截到 600 字左右）。
   *
   * 存摘录而不是完整 HTML：Canvas 单条描述常有几十 KB，
   * 全部塞进本地缓存会膨胀到好几 MB。完整描述在打开详情页时按需拉。
   */
  descriptionExcerpt?: string;
  /** score / points_possible, as a percentage. */
  percent: number | null;
  /** Contribution to the course score under weighted grading, when available. */
  weightedContribution: number | null;
}

export interface CourseDetail {
  course: CourseSummary;
  groups: { id: number; name: string; weight: number; earned: number; possible: number; percent: number | null }[];
  assignments: AssignmentRow[];
  gradingScheme: 'weighted' | 'points';
}

export interface Snapshot {
  fetchedAt: string;
  profile: CanvasProfile;
  courses: CourseSummary[];
  /** Semesters present in `courses`, newest first. */
  terms: TermGroup[];
  assignments: AssignmentRow[];
  todo: {
    title: string;
    courseId: number | null;
    courseName: string;
    dueAt: string | null;
    pointsPossible: number | null;
    htmlUrl?: string;
    kind: string;
  }[];
  /** Non-fatal problems encountered while assembling the snapshot. */
  warnings: string[];
  /**
   * 这次刷新沿用了多少门已结束学期的课（没有为它们发请求）。
   *
   * 老快照里没有这个字段，读缓存时要按 0 处理。
   */
  reusedCourseCount?: number;
}
