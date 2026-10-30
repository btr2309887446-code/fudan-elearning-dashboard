import assert from 'node:assert/strict';
import { CanvasClient, CANVAS_BASE } from '../src/core/canvas.ts';
import type { HttpClient, HttpResponse } from '../src/core/http.ts';
import { CanvasError } from '../src/core/errors.ts';

let payload: unknown;
let status = 200;
let requestCount = 0;
let lastUrl = '';
let transportError: Error | null = null;
const client = new CanvasClient({
  async request(url: string): Promise<HttpResponse> {
    requestCount += 1;
    lastUrl = url;
    if (transportError) throw transportError;
    return { status, url, headers: new Headers(), body: JSON.stringify(payload) };
  },
} as unknown as HttpClient);

payload = {
  id: 42,
  syllabus_body: '<h1>课程目标</h1><p>理解极限 &amp; 连续。</p><script>alert("bad")</script><ul><li>每周阅读</li></ul>',
  teachers: [{ display_name: '张老师' }, { name: ' 李老师 ' }, { short_name: '王老师' }, { display_name: '张老师' }],
};
const start = Date.now();
const intro = await client.getCourseIntroduction(42);
assert.equal(intro.courseId, 42);
assert.equal(intro.description, '课程目标\n理解极限 & 连续。\n· 每周阅读');
assert.deepEqual(intro.teachers, ['张老师', '李老师', '王老师']);
assert(Date.parse(intro.fetchedAt) >= start);
assert(!intro.cached);
const requestUrl = new URL(lastUrl);
assert.equal(requestUrl.origin, CANVAS_BASE);
assert.equal(requestUrl.pathname, '/api/v1/courses/42');
assert.deepEqual(requestUrl.searchParams.getAll('include[]'), ['syllabus_body', 'teachers']);

// A course with no published syllabus or no visible teachers is a valid result.
for (const optional of [{}, { syllabus_body: null, teachers: null }, { syllabus_body: 7, teachers: [null, 4, {}, { name: '' }] }]) {
  payload = { id: 42, ...optional };
  const empty = await client.getCourseIntroduction(42);
  assert.equal(empty.description, '');
  assert.deepEqual(empty.teachers, []);
}
for (const malformed of [null, [], {}, { id: 43 }, { id: '42' }]) {
  payload = malformed;
  await assert.rejects(client.getCourseIntroduction(42), /响应格式异常/);
}
const beforeInvalid = requestCount;
for (const invalid of [-1, 0, 1.5, Number.NaN, Number.MAX_SAFE_INTEGER + 1]) {
  await assert.rejects(client.getCourseIntroduction(invalid), /课程编号无效/);
}
assert.equal(requestCount, beforeInvalid);

// Failures propagate to the separate introduction cache. They must never look
// like a successful empty syllabus that would replace the previous contents.
status = 401;
payload = { errors: [{ message: 'login expired' }] };
await assert.rejects(client.getCourseIntroduction(42), (error: unknown) => error instanceof CanvasError && error.status === 401);
status = 200;
transportError = new Error('network unavailable');
await assert.rejects(client.getCourseIntroduction(42), /network unavailable/);
console.log('Course introduction: optional metadata, HTML plain text, response identity, invalid IDs and failure propagation passed.');
