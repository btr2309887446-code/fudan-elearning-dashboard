// Inspect the public course-search payload and the Canvas build/version markers.
const BASE = 'https://elearning.fudan.edu.cn';
const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

const res = await fetch(`${BASE}/api/v1/search/all_courses?per_page=3`, {
  headers: { 'User-Agent': UA, 'Accept-Language': 'zh-CN,zh;q=0.9', Accept: 'application/json' },
});
console.log('status', res.status, res.headers.get('content-type'));
const data = await res.json();
console.log('isArray', Array.isArray(data), 'len', data.length);
console.log(JSON.stringify(data.slice(0, 2), null, 2).slice(0, 3000));

// Look for a Canvas version string on the public page.
const home = await fetch(BASE + '/', { headers: { 'User-Agent': UA } });
const html = await home.text();
const m = html.match(/canvas[-_ ]?lms[^"',]*|"CANVAS_[A-Z_]+"\s*:\s*[^,}]+/gi) ?? [];
console.log('\nversion markers:', [...new Set(m)].slice(0, 10));
const rev = html.match(/"revision[^"]*"\s*:\s*"[^"]*"/i);
console.log('revision:', rev?.[0]);
const locale = html.match(/locale["']?\s*[:=]\s*["']([^"']+)/i);
console.log('locale:', locale?.[0]);
