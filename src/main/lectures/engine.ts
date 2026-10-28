import { createHash, createDecipheriv, createCipheriv, randomBytes, pbkdf2Sync } from 'node:crypto';
import { gunzipSync } from 'node:zlib';
import { readFileSync } from 'node:fs';
import { readFile, stat } from 'node:fs/promises';
import { atomicCache } from './cache.ts';
import initSqlJs, { type Database, type SqlJsStatic, type SqlValue } from 'sql.js';
import type { LectureBody, LectureCourse, LectureItem, LecturePage, LectureRef } from '../../core/lectures.ts';

export interface ShardEntry { name: string; sha256: string; size: number; course_ids?: string[]; bin?: string }
export interface LectureIndex { version: number; shards: ShardEntry[] }
export const digest = (value: string | Uint8Array) => createHash('sha256').update(value).digest('hex');
export const derivePassword = (studentId: string, password: string) => digest(`ICSv2:${studentId}:${password}`);
export function decrypt(data: Uint8Array, password: string): Buffer {
  const bytes = Buffer.from(data);
  if (bytes.length < 32 || bytes.subarray(0, 8).toString() !== 'Salted__') throw new Error('笔记文件格式无效');
  try {
    const material = pbkdf2Sync(password, bytes.subarray(8, 16), 100000, 48, 'sha256');
    const cipher = createDecipheriv('aes-256-cbc', material.subarray(0, 32), material.subarray(32));
    return Buffer.concat([cipher.update(bytes.subarray(16)), cipher.final()]);
  } catch { throw new Error('笔记解锁失败，请检查生成笔记时使用的学号和 UIS 密码'); }
}
export function decodeIndex(bytes: Uint8Array, password: string): LectureIndex {
  let value: LectureIndex;
  try { value = JSON.parse(decrypt(bytes, password).toString('utf8')) as LectureIndex; }
  catch { throw new Error('笔记索引无法解锁，请检查学号、密码或文件完整性'); }
  if (value.version !== 4 || !Array.isArray(value.shards) || value.shards.length > 2000)
    throw new Error('笔记索引版本暂不支持（需要版本 4），原有缓存已保留');
  const names = new Set<string>();
  for (const s of value.shards) {
    if (!/^[\w.-]+\.db\.gz\.enc$/.test(s.name) || names.has(s.name) || !/^[a-f0-9]{64}$/.test(s.sha256) ||
        !Number.isSafeInteger(s.size) || s.size < 32 || s.size > 128 * 1024 * 1024 ||
        (s.course_ids !== undefined && (!Array.isArray(s.course_ids) || s.course_ids.some(id => typeof id !== 'string' || id.length > 200))))
      throw new Error('笔记分片索引格式无效');
    names.add(s.name);
  }
  return value;
}
type IndexedItem = Omit<LectureItem, 'read' | 'updated'> & { shard: string };
const text = (value: SqlValue | undefined): string => value == null ? '' : String(value);
function query(db: Database, sql: string, args: SqlValue[] = []): Record<string, SqlValue>[] {
  const statement = db.prepare(sql);
  try { statement.bind(args); const rows: Record<string, SqlValue>[] = []; while (statement.step()) rows.push(statement.getAsObject()); return rows; }
  finally { statement.free(); }
}

/** All expensive decryption, decompression and SQLite work runs in a worker. */
export class LectureEngine {
  private sql: Promise<SqlJsStatic>;
  private dbs = new Map<string, Database>();
  private sizes = new Map<string, number>();
  private locations = new Map<string, { path?: string; bytes?: Uint8Array; password: string; hash: string }>();
  private sorted: IndexedItem[] = [];
  private budget: number;
  private items = new Map<string, IndexedItem>();
  private courseRows = new Map<string, LectureCourse>();
  private catalog = new Map<string, { terms: string[]; teacher: string; title: string }>();
  private demoBodies = new Map<string, LectureBody>();
  private sourceId: string;
  private loaded = new Map<string, { hash: string; courses: string[] }>();
  constructor(wasmPath: string, sourceId: string, budget = 128 * 1024 * 1024) {
    this.budget = budget;
    this.sourceId = sourceId;
    const bytes = readFileSync(wasmPath);
    this.sql = initSqlJs({ wasmBinary: Uint8Array.from(bytes).buffer });
  }
  private rebuild() { this.sorted = [...this.items.values()].sort((a,b)=>b.date.localeCompare(a.date)||a.lectureId.localeCompare(b.lectureId)); }
  private remember(name: string, db: Database, size: number) {
    this.dbs.get(name)?.close(); this.dbs.delete(name); this.sizes.delete(name);
    if (size > this.budget) return;
    while ([...this.sizes.values()].reduce((a,b)=>a+b,0) + size > this.budget && this.dbs.size) {
      const oldest = this.dbs.keys().next().value!;
      this.dbs.get(oldest)!.close(); this.dbs.delete(oldest); this.sizes.delete(oldest);
    }
    this.dbs.set(name,db); this.sizes.set(name,size);
  }
  stats() { return { residentBytes:[...this.sizes.values()].reduce((a,b)=>a+b,0), databases:this.dbs.size, items:this.items.size }; }
  async loadFile(name: string, path: string, password: string, expectedHash: string, validate = false): Promise<string[]> {
    if (!validate && this.loaded.get(name)?.hash === expectedHash && (await stat(path)).isFile()) return this.loaded.get(name)!.courses;
    const encrypted = await readFile(path);
    if (digest(encrypted) !== expectedHash) throw Error("笔记缓存校验失败，请重试同步");
    if (!validate && this.loaded.get(name)?.hash === expectedHash) return this.loaded.get(name)!.courses;
    try {
      const cached = await readFile(`${path}.index`);
      const key = createHash('sha256').update(password).digest();
      const decipher = createDecipheriv('aes-256-gcm',key,cached.subarray(0,12)); decipher.setAuthTag(cached.subarray(12,28));
      const meta = JSON.parse(Buffer.concat([decipher.update(cached.subarray(28)),decipher.final()]).toString('utf8'));
      if (meta.version !== 1 || meta.hash !== expectedHash || meta.source !== this.sourceId || !Array.isArray(meta.items) || !Array.isArray(meta.courses) || !Array.isArray(meta.catalog)) throw Error('index');
      this.dbs.get(name)?.close(); this.dbs.delete(name); this.sizes.delete(name);
      const incoming = new Set<string>(meta.courses.map((c: LectureCourse)=>c.id));
      for (const [id,item] of this.items) if (item.shard === name || incoming.has(item.icourseCourseId)) this.items.delete(id);
      for (const item of meta.items as IndexedItem[]) this.items.set(JSON.stringify([item.icourseCourseId,item.lectureId]),{...item,shard:name});
      for (const course of meta.courses as LectureCourse[]) this.courseRows.set(course.id,course);
      for (const [id,row] of meta.catalog) this.catalog.set(id,row);
      this.loaded.set(name,{hash:expectedHash,courses:[...incoming]});
      this.locations.set(name,{path,password,hash:expectedHash}); this.rebuild();
      return [...incoming];
    } catch { /* Missing/old/invalid local indexes are rebuilt from the encrypted shard. */ }
    const courses = await this.load(name,encrypted,password,expectedHash,path);
    const meta = JSON.stringify({version:1,hash:expectedHash,source:this.sourceId,items:[...this.items.values()].filter(i=>i.shard===name),courses:courses.map(id=>this.courseRows.get(id)),catalog:[...this.catalog]});
    const nonce=randomBytes(12), cipher=createCipheriv('aes-256-gcm',createHash('sha256').update(password).digest(),nonce);
    const body=Buffer.concat([cipher.update(meta,'utf8'),cipher.final()]);
    await atomicCache(`${path}.index`,Buffer.concat([nonce,cipher.getAuthTag(),body]),()=>{}).catch(()=>{});
    return courses;
  }
  async load(name: string, encrypted: Uint8Array, password: string, expectedHash: string, path?: string): Promise<string[]> {
    if (digest(encrypted) !== expectedHash) throw new Error('笔记分片校验失败，已保留旧内容');
    if (this.loaded.get(name)?.hash === expectedHash) return this.loaded.get(name)!.courses;
    const compressed = decrypt(encrypted, password);
    if (compressed[0] !== 0x1f || compressed[1] !== 0x8b) throw new Error('笔记解密结果无效');
    const raw = gunzipSync(compressed, { maxOutputLength: 256 * 1024 * 1024 });
    if (raw.subarray(0, 16).toString() !== 'SQLite format 3\0') throw new Error('笔记数据库格式无效');
    const db = new (await this.sql).Database(raw);
    try {
      db.run('PRAGMA query_only=ON');
      const courseRows = query(db, 'SELECT course_id, title, teacher FROM courses');
      const hasPpt = query(db, "SELECT name FROM sqlite_master WHERE type='table' AND name='ppt_pages'").length > 0;
      const columns = new Set(query(db, "PRAGMA table_info('lectures')").map(c => text(c.name)));
      for (const required of ['sub_id', 'course_id', 'sub_title', 'date', 'summary', 'transcript'])
        if (!columns.has(required)) throw new Error('笔记数据库字段不兼容');
      const statement = db.prepare( `SELECT sub_id, course_id, sub_title, date, summary, length(transcript) AS transcript_length,
        ${columns.has('processed_at') ? 'processed_at' : "'' AS processed_at"},
        ${columns.has('error_msg') ? 'error_msg' : "'' AS error_msg"} FROM lectures`);
      const counts = new Map(hasPpt ? query(db, 'SELECT sub_id, count(*) AS n FROM ppt_pages GROUP BY sub_id').map(p => [text(p.sub_id), Number(p.n)]) : []);
      const courses = new Map(courseRows.map(c => [text(c.course_id), c]));
      const indexed: IndexedItem[] = [];
      try { while (statement.step()) { const row = statement.getAsObject();
        const courseId = text(row.course_id), summary = text(row.summary).trim(), course = courses.get(courseId);
        indexed.push({ sourceId: this.sourceId, icourseCourseId: courseId, lectureId: text(row.sub_id), title: text(row.sub_title) || '未命名课次',
          date: text(row.date), courseTitle: text(course?.title), teacher: text(course?.teacher), summaryHash: summary ? digest(summary) : '',
          hasSummary: !!summary, hasTranscript: Number(row.transcript_length) > 0, pptCount: counts.get(text(row.sub_id)) ?? 0,
          processedAt: text(row.processed_at) || undefined, error: text(row.error_msg) ? '上游处理尚未完成，请稍后同步' : undefined, shard: name });
      } } finally { statement.free(); }
      const catalogRows = query(db, "SELECT name FROM sqlite_master WHERE type='table' AND name='all_courses'").length
        ? query(db, 'SELECT course_id, term, title, teacher FROM all_courses') : [];
      // Publish only after the complete shard has validated, never partially replace a working DB.
      const incoming = new Set(courseRows.map(c => text(c.course_id)));
      for (const [id, item] of this.items) if (item.shard === name || incoming.has(item.icourseCourseId)) this.items.delete(id);
      for (const item of indexed) this.items.set(JSON.stringify([item.icourseCourseId, item.lectureId]), item);
      for (const course of courseRows) this.courseRows.set(text(course.course_id), {
        id: text(course.course_id), title: text(course.title), teacher: text(course.teacher), terms: [] });
      for (const row of catalogRows) {
        const id = text(row.course_id), old = this.catalog.get(id);
        this.catalog.set(id, { title: text(row.title), teacher: text(row.teacher), terms: [...new Set([...(old?.terms ?? []), text(row.term)].filter(Boolean))] });
      }
      this.dbs.get(name)?.close(); this.dbs.delete(name); this.sizes.delete(name); db.close();
      this.locations.set(name,{path,bytes:path?undefined:Uint8Array.from(encrypted),password,hash:expectedHash});
      this.rebuild();
      this.loaded.set(name, { hash: expectedHash, courses: [...incoming] });
      return [...incoming];
    } catch (error) { db.close(); throw error; }
  }
  retain(names: string[]): void {
    const keep = new Set(names);
    for (const [name, db] of this.dbs) if (!keep.has(name)) { db.close(); this.dbs.delete(name); this.sizes.delete(name); }
    for (const [key, item] of this.items) if (!keep.has(item.shard)) this.items.delete(key);
    for (const name of this.loaded.keys()) if (!keep.has(name)) { this.loaded.delete(name); this.locations.delete(name); this.sizes.delete(name); }
    this.rebuild();
    const courses = new Set([...this.loaded.values()].flatMap(s => s.courses));
    for (const id of this.courseRows.keys()) if (!courses.has(id)) this.courseRows.delete(id);
  }
  courses(): LectureCourse[] {
    return [...this.courseRows.values()].map(c => ({ ...c, teacher: c.teacher || this.catalog.get(c.id)?.teacher || '', terms: this.catalog.get(c.id)?.terms ?? [] }));
  }
  list(courseIds: string[], search = '', offset = 0): LecturePage {
    const ids = new Set(courseIds), normalized = search.trim().toLocaleLowerCase();
    const all = this.sorted.filter(i => ids.has(i.icourseCourseId) && (!normalized || `${i.title} ${i.date} ${i.courseTitle} ${i.teacher}`.toLocaleLowerCase().includes(normalized)))
      ;
    return { total: all.length, offset, items: all.slice(offset, offset + 50).map(({ shard: _shard, ...item }) => ({ ...item, read: false, updated: false })) };
  }
  async body(ref: LectureRef): Promise<LectureBody> {
    const item = this.items.get(JSON.stringify([ref.icourseCourseId, ref.lectureId]));
    if (!item || ref.sourceId !== this.sourceId) throw new Error('这条课堂笔记不可用，请刷新课程');
    if (this.demoBodies.has(ref.lectureId)) return this.demoBodies.get(ref.lectureId)!;
    let db = this.dbs.get(item.shard);
    if (db) { this.dbs.delete(item.shard); this.dbs.set(item.shard,db); }
    else {
      const location=this.locations.get(item.shard);
      if (!location) throw Error('笔记正文缓存缺失，请同步重试');
      const bytes=location.path ? await readFile(location.path) : location.bytes!;
      if(digest(bytes)!==location.hash) throw Error('笔记缓存损坏，请同步重试');
      const raw=gunzipSync(decrypt(bytes,location.password),{maxOutputLength:256*1024*1024});
      db=new (await this.sql).Database(raw); db.run('PRAGMA query_only=ON'); this.remember(item.shard,db,raw.length);
    }
    try {
    const row = query(db, 'SELECT summary, transcript FROM lectures WHERE course_id=? AND sub_id=?', [ref.icourseCourseId, ref.lectureId])[0];
    if (!row) throw new Error('课堂笔记不存在');
    const pages = query(db, "SELECT name FROM sqlite_master WHERE type='table' AND name='ppt_pages'").length
      ? query(db, 'SELECT page_num, created_sec, text FROM ppt_pages WHERE sub_id=? ORDER BY page_num', [ref.lectureId]) : [];
    const { shard: _shard, ...metadata } = item;
    if (text(row.summary).length + text(row.transcript).length + pages.reduce((n, p) => n + text(p.text).length, 0) > 8 * 1024 * 1024)
      throw new Error('本课次正文过大，请在 iCourse 订阅网页中查看');
    return { ...metadata, read: false, updated: false, summary: text(row.summary), transcript: text(row.transcript),
      pages: pages.map(p => ({ page: Number(p.page_num), seconds: Number(p.created_sec), text: text(p.text) })) };
    } finally { if (!this.dbs.has(item.shard)) db.close(); }
  }
  resources(courseIds: string[]): { ref: LectureRef; title: string; hash: string }[] {
    const ids = new Set(courseIds);
    return [...this.items.values()].filter(i => ids.has(i.icourseCourseId) && i.hasSummary).map(i => ({
      ref: { sourceId: i.sourceId, icourseCourseId: i.icourseCourseId, lectureId: i.lectureId }, title: i.title, hash: i.summaryHash }));
  }
  demo(courses: { id: number; displayName: string }[]): void {
    courses.slice(0, 4).forEach((course, ci) => {
      const id = `demo-${course.id}`;
      this.courseRows.set(id, { id, title: course.displayName, teacher: '示例教师', terms: ['2026-2027 第一学期'] });
      for (let n = 0; n < 4; n++) {
        const lectureId = `${id}-${n}`, summary = `## 课程事项提醒\n\n- 阅读本章并整理三个疑问，下次课讨论。\n- 完成课堂练习，具体提交日期以老师通知为准。\n\n## 本节重点\n\n理解概念、联系例子，再尝试独立推导。\n\n$$f(x)=\\sum_{k=0}^{n}a_kx^k$$\n\n| 内容 | 复习建议 |\n| --- | --- |\n| 核心概念 | 用自己的话解释 |\n| 课堂例题 | 独立重做一次 |\n\n## 课后复习\n\n将例题与定义对照，记录尚未掌握的步骤。`;
        const body: LectureBody = { sourceId: this.sourceId, icourseCourseId: id, lectureId, title: `第 ${n + 1} 讲 · 核心概念与应用`,
          date: `2026-10-${String(8 + n * 3 + ci).padStart(2, '0')}`, courseTitle: course.displayName, teacher: '示例教师', summaryHash: digest(summary), hasSummary: true,
          hasTranscript: true, pptCount: 2, read: false, updated: false, summary, transcript: '（虚构演示转写）\n今天我们从一个例子开始，理解定义与推导的联系。请在下次课前整理三个疑问。',
          pages: [{ page: 1, seconds: 0, text: '第一部分：核心定义与直观解释' }, { page: 2, seconds: 180, text: '第二部分：课堂练习与讨论' }] };
        const { summary: _s, transcript: _t, pages: _p, ...meta } = body;
        this.items.set(JSON.stringify([id, lectureId]), { ...meta, shard: 'demo' }); this.demoBodies.set(lectureId, body);
      }
    });
    this.rebuild();
  }
  close(): void { for (const db of this.dbs.values()) db.close(); this.dbs.clear(); this.locations.clear(); this.sizes.clear(); this.sorted=[]; this.loaded.clear(); this.items.clear(); this.courseRows.clear(); this.catalog.clear(); this.demoBodies.clear(); }
}
