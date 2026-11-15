const { ipcMain, app } = require('electron');
if (process.env.ELEARNING_DEMO !== '1' || !process.env.ELEARNING_DEMO_DIR) throw Error('Review test requires an isolated demo account');
let saves = 0, ref, generation = 0;
const handle = ipcMain.handle.bind(ipcMain);
ipcMain.handle = (channel, listener) => handle(channel, async (event, ...args) => {
  if (channel === 'workspace:mutate' && args[1]?.type === 'review' && args[1].action.kind === 'plan') {
    await new Promise(r => setTimeout(r, 200));
    if (++saves === 1) return { ok: false, error: { kind: 'test', message: '虚构测试：磁盘暂时不可写' } };
  }
  if (channel === 'review:prepare') { ref = args[2][0]; return { ok: true, data: { id: 'synthetic-job', model: '虚构测试模型', endpoint: 'https://example.invalid', batches: [{ index: 0, title: ref.title, characters: 100 }] } }; }
  if (channel === 'review:generate') {
    await new Promise(r => setTimeout(r, 250));
    if (++generation === 1) return { ok: false, error: { kind: 'test', message: '虚构测试：模型超时' } };
    return { ok: true, data: { rejected: 0, items: [{ id: 'synthetic-ai-item', title: '虚构 AI 知识点', notes: '通过自测解释展开式。', minutes: 20, extraMinutes: 0, mastery: 'unassessed', questions: [{ question: '解释 $x^2$ 的含义。', answer: '$x^2=x\\times x$' }], sources: [{ sourceId: ref.sourceId, icourseCourseId: ref.icourseCourseId, lectureId: ref.lectureId, title: ref.title, summaryHash: ref.summaryHash, quote: '理解概念、联系例子，再尝试独立推导。' }] }] } };
  }
  return listener(event, ...args);
});
if (process.env.ELEARNING_SMOKE_VIEW === 'reduced') app.commandLine.appendSwitch('force-prefers-reduced-motion');
require('../out/main/index.js');
