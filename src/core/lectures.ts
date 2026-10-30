/** Portable classroom-content contracts. Secrets never appear in returned state. */
export interface LectureRef {
  sourceId: string;
  icourseCourseId: string;
  lectureId: string;
}
export interface LectureCourse {
  id: string;
  title: string;
  teacher: string;
  terms: string[];
}
export interface LectureBinding {
  icourseCourseId: string;
  canvasCourseId: number;
}
export interface LectureConnection {
  configured: boolean;
  repository: string;
  branch: string;
  sourceId: string;
  locked: boolean;
  remembered: boolean;
  syncing: boolean;
  lastSynced?: string;
  error?: string;
  courses: LectureCourse[];
  bindings: LectureBinding[];
}
export interface LectureConnectInput {
  repository: string;
  branch: string;
  studentId: string;
  password: string;
  token?: string;
  remember: boolean;
}
export interface LectureItem extends LectureRef {
  title: string;
  date: string;
  courseTitle: string;
  teacher: string;
  summaryHash: string;
  hasSummary: boolean;
  hasTranscript: boolean;
  pptCount: number;
  read: boolean;
  updated: boolean;
  processedAt?: string;
  error?: string;
}
export interface LectureBody extends LectureItem {
  summary: string;
  transcript: string;
  pages: { page: number; seconds: number; text: string }[];
}
export interface LecturePage { items: LectureItem[]; total: number; offset: number }
export interface CourseIntroduction {
  courseId: number;
  description: string;
  teachers: string[];
  fetchedAt: string;
  cached?: boolean;
  warning?: string;
}
export const DEFAULT_LECTURE_REPOSITORY = 'btr2309887446-code/Fudan_iCourse_Subscriber';
export const lectureKey = (ref: LectureRef): string => JSON.stringify([ref.sourceId, ref.icourseCourseId, ref.lectureId]);
export function parseLectureKey(value: string): LectureRef | null {
  try {
    const a: unknown = JSON.parse(value);
    if (Array.isArray(a) && a.length === 3 && a.every(v => typeof v === 'string' && v.length > 0 && v.length < 300))
      return { sourceId: a[0], icourseCourseId: a[1], lectureId: a[2] };
  } catch { /* An older event or invalid target is not a lecture. */ }
  return null;
}
