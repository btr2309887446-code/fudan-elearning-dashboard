/**
 * Canvas LMS REST client for elearning.fudan.edu.cn.
 *
 * Authentication is the browser session cookie produced by the UIS login, so
 * every call here is a plain authenticated GET. Canvas paginates with a
 * `Link: <...>; rel="next"` header; `getAllPages` walks it.
 */

import { fileFromJson, folderFromJson, type CanvasFile, type CanvasFolder } from './files.ts';
import { CanvasError } from './errors.ts';
import { HttpClient } from './http.ts';
import type {
  CanvasAssignment,
  CanvasAssignmentGroup,
  CanvasCourse,
  CanvasNickname,
  CanvasPlannerItem,
  CanvasProfile,
  CanvasTodoItem,
} from './types.ts';

export const CANVAS_BASE = 'https://elearning.fudan.edu.cn';

export type QueryValue = string | number | boolean | undefined | null | (string | number)[];

export function buildQuery(params?: Record<string, QueryValue>): string {
  if (!params) return '';
  const usp = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null) continue;
    if (Array.isArray(value)) {
      for (const v of value) usp.append(`${key}[]`, String(v));
    } else {
      usp.append(key, String(value));
    }
  }
  const s = usp.toString();
  return s ? `?${s}` : '';
}

/** Extract the `rel="next"` URL from a Canvas Link header. */
export function parseNextLink(linkHeader: string | null): string | null {
  if (!linkHeader) return null;
  for (const part of linkHeader.split(',')) {
    const m = /<([^>]+)>\s*;\s*rel\s*=\s*"?([^";]+)"?/.exec(part.trim());
    if (m && m[2].trim() === 'next') return m[1];
  }
  return null;
}

export class CanvasClient {
  readonly http: HttpClient;

  constructor(http: HttpClient) {
    this.http = http;
  }

  private async fetchJson<T>(url: string): Promise<{ data: T; link: string | null }> {
    const res = await this.http.request(url, {
      timeoutMs: 30_000,
      headers: { Accept: 'application/json' },
    });
    if (res.status < 200 || res.status >= 300) {
      throw new CanvasError(res.status, url, res.body);
    }
    let data: T;
    try {
      data = JSON.parse(res.body) as T;
    } catch {
      throw new CanvasError(res.status, url, `响应不是合法 JSON：${res.body.slice(0, 200)}`);
    }
    return { data, link: res.headers.get('link') };
  }

  async get<T>(path: string, params?: Record<string, QueryValue>): Promise<T> {
    const url = path.startsWith('http') ? path : CANVAS_BASE + path + buildQuery(params);
    const { data } = await this.fetchJson<T>(url);
    return data;
  }

  /** Follow Canvas pagination until exhausted (bounded, for safety). */
  async getAllPages<T>(path: string, params?: Record<string, QueryValue>, maxPages = 40): Promise<T[]> {
    let url: string | null = path.startsWith('http') ? path : CANVAS_BASE + path + buildQuery(params);
    const out: T[] = [];
    let pages = 0;
    while (url && pages < maxPages) {
      const { data, link } = await this.fetchJson<T[]>(url);
      if (Array.isArray(data)) out.push(...data);
      url = parseNextLink(link);
      pages += 1;
    }
    return out;
  }

  // --- endpoints -----------------------------------------------------------

  getProfile(): Promise<CanvasProfile> {
    return this.get<CanvasProfile>('/api/v1/users/self/profile');
  }

  /**
   * Courses the signed-in user is enrolled in, with the student's own
   * enrollment (and therefore grades) inlined, plus the enrollment term so the
   * UI can group by semester.
   *
   * `include[]=total_scores` only yields grades when an enrollment_state is
   * supplied, so 'active' is passed explicitly. For 'all' the plain list is
   * combined with the completed enrollments, because some deployments omit
   * concluded courses from the default listing.
   */
  async getCourses(
    opts: { enrollmentState?: 'active' | 'all'; includeTotalScores?: boolean } = {}
  ): Promise<CanvasCourse[]> {
    const includes: string[] = ['enrollments', 'term'];
    if (opts.includeTotalScores !== false) includes.push('total_scores');

    const base = await this.getAllPages<CanvasCourse>('/api/v1/courses', {
      include: includes,
      per_page: 100,
    });

    if (opts.enrollmentState === 'active') {
      // Filter locally rather than trusting enrollment_state, which also
      // honours section and course date overrides.
      const now = Date.now();
      return base.filter((c) => {
        const end = c.end_at ?? c.term?.end_at ?? null;
        return end === null || Date.parse(end) > now;
      });
    }

    const merged = new Map(base.map((c) => [c.id, c]));
    try {
      const completed = await this.getAllPages<CanvasCourse>('/api/v1/courses', {
        include: includes,
        per_page: 100,
        enrollment_state: 'completed',
      });
      for (const c of completed) if (!merged.has(c.id)) merged.set(c.id, c);
    } catch {
      // The concluded set is a bonus; never fail the whole refresh over it.
    }
    return [...merged.values()];
  }

  getAssignmentGroups(courseId: number): Promise<CanvasAssignmentGroup[]> {
    return this.getAllPages<CanvasAssignmentGroup>(`/api/v1/courses/${courseId}/assignment_groups`, {
      per_page: 100,
    });
  }

  /** Assignments for one course, each carrying the current user's submission. */
  getAssignments(courseId: number): Promise<CanvasAssignment[]> {
    return this.getAllPages<CanvasAssignment>(`/api/v1/courses/${courseId}/assignments`, {
      include: ['submission'],
      per_page: 100,
      order_by: 'due_at',
    });
  }

  getTodo(): Promise<CanvasTodoItem[]> {
    return this.get<CanvasTodoItem[]>('/api/v1/users/self/todo');
  }

  /**
   * 单条作业，带完整 description。
   *
   * 列表接口也会返回 description，但那条数据不进本地缓存（单条常有几十 KB）。
   * 详情页按需拉一次，只取自己需要的这一条。
   */
  getAssignment(courseId: number, assignmentId: number): Promise<CanvasAssignment> {
    return this.get<CanvasAssignment>(
      `/api/v1/courses/${courseId}/assignments/${assignmentId}`,
      { include: ['submission'] }
    );
  }

  getUpcomingEvents(): Promise<unknown[]> {
    return this.get<unknown[]>('/api/v1/users/self/upcoming_events');
  }

  getPlannerItems(startDate: string, endDate: string): Promise<CanvasPlannerItem[]> {
    return this.getAllPages<CanvasPlannerItem>('/api/v1/planner/items', {
      start_date: startDate,
      end_date: endDate,
      per_page: 100,
    });
  }

  getCourseNicknames(): Promise<CanvasNickname[]> {
    return this.getAllPages<CanvasNickname>('/api/v1/users/self/course_nicknames', { per_page: 100 });
  }

  /** 课程里的文件夹（扁平列表，用 parent_folder_id 表达层级）。 */
  async getCourseFolders(courseId: number): Promise<CanvasFolder[]> {
    const rows = await this.getAllPages<Record<string, unknown>>(
      `/api/v1/courses/${courseId}/folders`,
      { per_page: 100 }
    );
    return rows.map(folderFromJson);
  }

  /** 课程里的文件（扁平列表，用 folder_id 归属到文件夹）。 */
  async getCourseFiles(courseId: number): Promise<CanvasFile[]> {
    const rows = await this.getAllPages<Record<string, unknown>>(
      `/api/v1/courses/${courseId}/files`,
      { per_page: 100 }
    );
    return rows.map(fileFromJson).filter((f) => !f.hidden && f.url.length > 0);
  }
}
