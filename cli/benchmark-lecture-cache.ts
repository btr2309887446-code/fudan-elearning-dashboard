import assert from 'node:assert/strict';
import { createCipheriv, pbkdf2Sync } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire } from 'node:module';
import initSqlJs from 'sql.js';
import { LectureEngine, digest, derivePassword } from '../src/main/lectures/engine.ts';

const require = createRequire(import.meta.url), wasm = require.resolve('sql.js/dist/sql-wasm.wasm');
const SQL = await initSqlJs({ wasmBinary: Uint8Array.from(readFileSync(wasm)).buffer });
const folder = mkdtempSync(join(tmpdir(), 'lecture-budget-'));
const password = derivePassword('synthetic', 'benchmark-only');
const engine = new LectureEngine(wasm, 'benchmark');
const results: Record<string, unknown>[] = [];
let peakSampledRSS = 0;
const sample = () => { peakSampledRSS = Math.max(peakSampledRSS, process.memoryUsage().rss); };
const locations: { name: string; path: string; hash: string }[] = [];
try {
  for (let n = 0; n < 3; n++) {
    const db = new SQL.Database(), id = `course-${n}`;
    db.run('CREATE TABLE courses(course_id TEXT,title TEXT,teacher TEXT); CREATE TABLE lectures(sub_id TEXT,course_id TEXT,sub_title TEXT,date TEXT,summary TEXT,transcript TEXT);');
    db.run('INSERT INTO courses VALUES(?,?,?)', [id,'Synthetic course','Example']);
    const transcript = 'Synthetic transcript. '.repeat(50000);
    for(let row=0;row<48;row++) db.run('INSERT INTO lectures VALUES(?,?,?,?,?,?)',[`${row}`,id,`Lecture ${row}`,'2026-10-01','Example summary',transcript]);
    const raw=db.export(); db.close(); sample();
    const salt=Buffer.from('12345678'), key=pbkdf2Sync(password,salt,100000,48,'sha256');
    const cipher=createCipheriv('aes-256-cbc',key.subarray(0,32),key.subarray(32));
    const bytes=Buffer.concat([Buffer.from('Salted__'),salt,cipher.update(gzipSync(raw)),cipher.final()]);
    const path=join(folder,`${n}.enc`), name=`${n}.db.gz.enc`; writeFileSync(path,bytes);
    locations.push({name,path,hash:digest(bytes)});
    const start=performance.now(); await engine.loadFile(name,path,password,digest(bytes)); sample();
    results.push({operation:'index', shard:n, decodedBytes:raw.length, ms:performance.now()-start, ...engine.stats()});
  }
  engine.close();
  for(const item of locations) await engine.loadFile(item.name,item.path,password,item.hash);
  assert.equal(engine.stats().databases,0,'encrypted lightweight indexes must reopen without body databases');
  for(const n of [0,1,2,0]) {
    const start=performance.now();
    const body=await engine.body({sourceId:'benchmark',icourseCourseId:`course-${n}`,lectureId:'0'}); sample();
    assert(body.transcript.length>1000000);
    assert(engine.stats().residentBytes<=128*1024*1024);
    assert(engine.stats().databases<=2,'third large shard evicts the least recently used database');
    results.push({operation:'body',shard:n,ms:performance.now()-start,...engine.stats()});
  }
  const tiny=new LectureEngine(wasm,'benchmark',1024);
  const item=locations[0]; await tiny.loadFile(item.name,item.path,password,item.hash);
  await tiny.body({sourceId:'benchmark',icourseCourseId:'course-0',lectureId:'0'});
  assert.equal(tiny.stats().databases,0,'a single oversized database is released after the query'); tiny.close();
  mkdirSync('artifacts/benchmarks',{recursive:true});
  writeFileSync('artifacts/benchmarks/lecture-cache.json',JSON.stringify({budgetBytes:128*1024*1024,peakSampledRSS,notes:'RSS includes fixture creation, WASM capacity and transient buffers; database residency is not a process memory cap.',results},null,2));
  console.log(JSON.stringify({checks:'passed',peakSampledRSS,results}));
} finally { engine.close(); rmSync(folder,{recursive:true,force:true}); }
