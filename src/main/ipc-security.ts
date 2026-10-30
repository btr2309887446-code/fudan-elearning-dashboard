const noArgs = new Set(['prefs:get', 'auth:status', 'auth:remembered', 'auth:logout', 'data:cached', 'data:clear', 'app:version', 'llm:get', 'files:root', 'files:pickRoot', 'files:cancel']);
const object = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v);
const id = (v: unknown) => Number.isSafeInteger(v) && (v as number) >= 0;
const str = (v: unknown, max = 32768) => typeof v === 'string' && v.length <= max;
const optional = (v: unknown, test: (v: unknown) => boolean) => v === undefined || test(v);
export function validateIpc(channel: string, args: unknown[]): void {
  const reject = () => { throw Error('请求参数无效，请重新打开当前页面'); };
  if (args.length > 5 || JSON.stringify(args).length > 2 * 1024 * 1024) reject();
  if (noArgs.has(channel)) { if (args.length) reject(); return; }
  const [a,b,c,d] = args;
  if (channel.startsWith('lectures:') || channel.startsWith('workspace:') || channel === 'course:introduction') {
    if (!id(a)) reject();
    if (channel === 'workspace:mutate' && (!object(b) || !str(b.type, 80))) reject();
    if (channel === 'lectures:connect') {
      if (!object(b) || !['repository','branch','studentId','password'].every(k => str(b[k], 4096)) || !optional(b.token,v=>str(v,4096)) || !optional(b.remember,v=>typeof v==='boolean')) reject();
    }
    if (['lectures:detail','lectures:read'].includes(channel) && (!object(b) || !['sourceId','icourseCourseId','lectureId'].every(k=>str(b[k],500)))) reject();
    if (channel === 'lectures:bind' && (!str(b,2000) || (c !== null && !id(c)))) reject();
    if (channel === 'lectures:list' && (!id(b) || !optional(c,v=>str(v,500)) || !optional(d,id))) reject();
    if (channel === 'course:introduction' && (!id(b) || !optional(c,v=>typeof v==='boolean'))) reject();
    return;
  }
  if (['auth:prepare','auth:checkCaptcha','shell:open','files:reveal'].includes(channel)) { if (!str(a)) reject(); return; }
  if (!object(a) && !(channel === 'data:snapshot' && a === undefined)) reject();
  if (!object(a)) return;
  if (channel === 'auth:submit' && (!str(a.username,200) || !str(a.password,4096) || !optional(a.captchaCode,v=>str(v,200)) || !optional(a.remember,v=>typeof v==='boolean') || !optional(a.useRememberedPassword,v=>typeof v==='boolean'))) reject();
  if (channel === 'llm:set' && (!['baseUrl','model','apiKey'].every(k=>optional(a[k],v=>str(v,32768))) || !['enabled','clearApiKey'].every(k=>optional(a[k],v=>typeof v==='boolean')))) reject();
  if (channel.startsWith('files:') && !id(a.courseId)) reject();
  if (channel === 'files:download' && !optional(a.fileIds,v=>Array.isArray(v)&&v.every(id))) reject();
  if (channel.startsWith('assignment:') && (!id(a.courseId)||!id(a.assignmentId))) reject();
  if (channel === 'assignment:summarise' && (!str(a.name)||!str(a.description,1024*1024))) reject();
  if (channel === 'data:snapshot' && !['force','full'].every(k=>optional(a[k],v=>typeof v==='boolean'))) reject();
}

export function safeExternalUrl(value: string): string | undefined {
  try { const url = new URL(value); return url.protocol === 'https:' && !url.username && !url.password ? url.href : undefined; }
  catch { return undefined; }
}
