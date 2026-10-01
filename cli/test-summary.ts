/**
 * 作业简介相关的纯函数测试。
 *
 * 这些是「不接大模型也要能用」的底线：HTML 要能正确转成纯文本、
 * 截断不能把句子切得莫名其妙。大模型那条路只在有 key 时才走，
 * 这里用假的 fetch 验证解析与失败降级。
 *
 *   node cli/test-summary.ts
 */

import {
  decodeEntities,
  fallbackSummary,
  htmlToPlainText,
  llmReady,
  makeExcerpt,
  needsSummary,
  summarizeAssignment,
  summaryCacheKey,
  summarySourceText,
  truncate,
  DEFAULT_LLM,
  EXCERPT_LENGTH,
  SUMMARY_LENGTH,
  type LlmConfig,
} from '../src/core/summary.ts';

let passed = 0;
let failed = 0;

function check(name: string, ok: boolean, info = ''): void {
  if (ok) {
    passed += 1;
    console.log(`  OK   ${name}${info ? '  — ' + info : ''}`);
  } else {
    failed += 1;
    console.log(` FAIL  ${name}${info ? '  — ' + info : ''}`);
  }
}

function eq<T>(name: string, actual: T, expected: T): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  check(name, a === e, a === e ? '' : `得到 ${a}，期望 ${e}`);
}

console.log('=== 作业简介测试 ===\n');

// [1] HTML 实体 -------------------------------------------------------------
console.log('[1] decodeEntities');
{
  eq('命名实体', decodeEntities('a &amp; b &lt;c&gt; &quot;d&quot;'), 'a & b <c> "d"');
  eq('中文引号', decodeEntities('&ldquo;报告&rdquo;'), '“报告”');
  eq('nbsp 变空格', decodeEntities('a&nbsp;b'), 'a b');
  eq('十进制数字实体', decodeEntities('&#65;&#66;'), 'AB');
  eq('十六进制实体', decodeEntities('&#x4e2d;&#x6587;'), '中文');
  eq('未知实体原样保留', decodeEntities('&foo; &bar;'), '&foo; &bar;');
  eq('无实体时不变', decodeEntities('普通文本'), '普通文本');
}

// [2] HTML 转纯文本 ---------------------------------------------------------
console.log('\n[2] htmlToPlainText');
{
  eq('段落换行', htmlToPlainText('<p>第一段</p><p>第二段</p>'), '第一段\n第二段');
  eq('br 换行', htmlToPlainText('第一行<br>第二行'), '第一行\n第二行');
  eq('br 自闭合', htmlToPlainText('a<br/>b'), 'a\nb');
  eq('行内标签不换行', htmlToPlainText('<p>这是<strong>重点</strong>内容</p>'), '这是重点内容');
  eq('去掉链接标签保留文字', htmlToPlainText('<a href="x">点这里</a>'), '点这里');

  const list = htmlToPlainText('<ul><li>第一条</li><li>第二条</li></ul>');
  check('列表项带记号', list.includes('· 第一条') && list.includes('· 第二条'), JSON.stringify(list));

  const tbl = htmlToPlainText('<table><tr><td>姓名</td><td>分数</td></tr></table>');
  check('表格可读', tbl.includes('姓名') && tbl.includes('分数'), JSON.stringify(tbl));

  eq('script 整块丢掉', htmlToPlainText('<p>正文</p><script>alert(1)</script>'), '正文');
  eq('style 整块丢掉', htmlToPlainText('<style>p{color:red}</style><p>正文</p>'), '正文');
  eq('注释类噪声不留标签', htmlToPlainText('<div>a</div>'), 'a');

  eq('连续空行压成一个', htmlToPlainText('<p>a</p><p></p><p></p><p>b</p>'), 'a\nb');
  eq('零宽字符清掉', htmlToPlainText('a\u200bb\ufeffc'), 'abc');
  eq('nbsp 变普通空格', htmlToPlainText('a&nbsp;&nbsp;b'), 'a b');

  eq('空输入', htmlToPlainText(''), '');
  eq('null 输入', htmlToPlainText(null), '');
  eq('undefined 输入', htmlToPlainText(undefined), '');
  eq('只有标签', htmlToPlainText('<p></p><div></div>'), '');

  const long = htmlToPlainText('&lt;script&gt; 是要转义的');
  check('已转义的标签不会再被当标签删掉', long.includes('<script>'), long);
}

// [3] 截断 -------------------------------------------------------------------
console.log('\n[3] truncate');
{
  eq('短文本不动', truncate('短', 100), '短');
  eq('恰好等于上限', truncate('a'.repeat(100), 100), 'a'.repeat(100));
  eq('空白压缩', truncate('a   b\n\nc', 100), 'a b c');

  // 在句号处断开，且不早于 60%
  const s1 = `${'甲'.repeat(80)}。${'乙'.repeat(80)}`;
  const t1 = truncate(s1, 100);
  check('优先在句号处断开', t1.endsWith('。') && t1.length <= 100, `${t1.length} 字：…${t1.slice(-6)}`);

  // 句子边界太早时不硬切，改用省略号
  const s2 = `很短。${'丙'.repeat(300)}`;
  const t2 = truncate(s2, 100);
  check('边界过早时用省略号', t2.endsWith('…') && t2.length <= 100, `${t2.length} 字`);

  // 完全没有边界
  const t3 = truncate('丁'.repeat(300), 100);
  check('无边界仍不超长', t3.length <= 100, `${t3.length} 字`);

  eq('摘要长度常量可用', truncate('戊'.repeat(500), SUMMARY_LENGTH).length <= SUMMARY_LENGTH, true);
}

// [4] 摘录与降级简介 ---------------------------------------------------------
console.log('\n[4] makeExcerpt / fallbackSummary');
{
  const html = `<p>本次作业要求实现一个哈夫曼编码器。</p>
    <p>具体要求：</p><ul><li>统计字符频率</li><li>构建哈夫曼树</li><li>输出编码表</li></ul>
    <p>提交方式：上传源代码与实验报告。</p>`;

  const excerpt = makeExcerpt(html);
  check('摘录不含标签', !excerpt.includes('<'), excerpt.slice(0, 40));
  check('摘录含正文', excerpt.includes('哈夫曼编码器'));
  check('摘录不超长', excerpt.length <= EXCERPT_LENGTH, `${excerpt.length} 字`);

  const brief = fallbackSummary(html);
  check('降级简介不超 100 字', brief.length <= SUMMARY_LENGTH, `${brief.length} 字`);
  check('降级简介含关键内容', brief.includes('哈夫曼'), brief);

  eq('空描述降级为空串', fallbackSummary('<p></p>'), '');
  eq('null 降级为空串', fallbackSummary(null), '');
}

// [5] 大模型调用 -------------------------------------------------------------
console.log('\n[5] summarizeAssignment');
{
  // 夹具必须超过 100 字，否则会被摘要门槛挡下、根本走不到大模型那条路。
  // 门槛本身在 [6] 里单独测。
  const html =
    '<p>写一份关于二叉搜索树的实验报告，包含插入、删除、查找三种操作的复杂度分析。' +
    '要求给出每种操作的平均情况与最坏情况时间复杂度推导过程，画出至少三种不同形态的树' +
    '（平衡、退化成链、随机插入）并对比它们的查找效率，最后总结在什么情况下会退化以及' +
    '如何用平衡树避免。</p>';

  // 未配置 → 直接降级
  eq('未配置时走降级', (await summarizeAssignment('实验五', html, DEFAULT_LLM)).source, 'fallback');
  eq('null 配置也走降级', (await summarizeAssignment('实验五', html, null)).source, 'fallback');
  eq('enabled 为 false 不算就绪', llmReady({ ...DEFAULT_LLM, apiKey: 'sk-x', enabled: false }), false);
  eq('有 key 且 enabled 才算就绪', llmReady({ ...DEFAULT_LLM, apiKey: 'sk-x', enabled: true }), true);
  eq('key 是空白不算就绪', llmReady({ ...DEFAULT_LLM, apiKey: '   ', enabled: true }), false);

  // 正常返回
  const okCfg: LlmConfig = { baseUrl: 'https://api.example.com/v1', apiKey: 'sk-test', model: 'm', enabled: true };
  let capturedUrl = '';
  let capturedBody = '';
  const okFetch = (async (url: string, init: RequestInit) => {
    capturedUrl = String(url);
    capturedBody = String(init.body);
    return new Response(
      JSON.stringify({ choices: [{ message: { content: '「实现二叉搜索树并分析三种操作的复杂度。」' } }] }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }) as unknown as typeof fetch;

  const okRes = await summarizeAssignment('实验五', html, okCfg, okFetch);
  eq('成功时来源是 llm', okRes.source, 'llm');
  eq('去掉了包裹的引号', okRes.summary, '实现二叉搜索树并分析三种操作的复杂度。');
  eq('请求地址正确', capturedUrl, 'https://api.example.com/v1/chat/completions');
  check('请求体带上了标题与描述', capturedBody.includes('实验五') && capturedBody.includes('二叉搜索树'));
  check('请求体带上了模型名', capturedBody.includes('"model":"m"'));

  // baseUrl 结尾多斜杠也能拼对
  let url2 = '';
  const slashFetch = (async (url: string) => {
    url2 = String(url);
    return new Response(JSON.stringify({ choices: [{ message: { content: '简短。' } }] }), { status: 200 });
  }) as unknown as typeof fetch;
  await summarizeAssignment('t', html, { ...okCfg, baseUrl: 'https://api.example.com/v1///' }, slashFetch);
  eq('多余斜杠被规整', url2, 'https://api.example.com/v1/chat/completions');

  // HTTP 错误 → 降级且带原因
  const errFetch = (async () =>
    new Response('unauthorized', { status: 401 })) as unknown as typeof fetch;
  const errRes = await summarizeAssignment('实验五', html, okCfg, errFetch);
  eq('401 时降级', errRes.source, 'fallback');
  check('错误里带状态码', (errRes.error ?? '').includes('401'), errRes.error);
  check('降级仍有内容', errRes.summary.length > 0, errRes.summary);

  // 返回空内容 → 降级
  const emptyFetch = (async () =>
    new Response(JSON.stringify({ choices: [{ message: { content: '   ' } }] }), { status: 200 })) as unknown as typeof fetch;
  const emptyRes = await summarizeAssignment('实验五', html, okCfg, emptyFetch);
  eq('空内容降级', emptyRes.source, 'fallback');

  // 网络异常 → 降级，不抛
  const throwFetch = (async () => {
    throw new Error('ECONNREFUSED');
  }) as unknown as typeof fetch;
  const throwRes = await summarizeAssignment('实验五', html, okCfg, throwFetch);
  eq('网络异常降级', throwRes.source, 'fallback');
  check('错误里带原因', (throwRes.error ?? '').includes('ECONNREFUSED'), throwRes.error);

  // 超长返回值也会被截到 100 字内
  const longFetch = (async () =>
    new Response(JSON.stringify({ choices: [{ message: { content: '己'.repeat(400) } }] }), { status: 200 })) as unknown as typeof fetch;
  const longRes = await summarizeAssignment('实验五', html, okCfg, longFetch);
  check('超长简介被截断', longRes.summary.length <= SUMMARY_LENGTH, `${longRes.summary.length} 字`);

  // 没有描述时不该去调接口
  let called = false;
  const spyFetch = (async () => {
    called = true;
    return new Response('{}', { status: 200 });
  }) as unknown as typeof fetch;
  await summarizeAssignment('空作业', '', okCfg, spyFetch);
  eq('无描述时不调用接口', called, false);
}

// [6] 缓存键 -----------------------------------------------------------------
console.log('\n[6] summaryCacheKey');
{
  const a = summaryCacheKey(1, '<p>abc</p>');
  eq('同输入同键', a, summaryCacheKey(1, '<p>abc</p>'));
  check('不同 id 不同键', a !== summaryCacheKey(2, '<p>abc</p>'));
  check('描述变了键也变', a !== summaryCacheKey(1, '<p>abcd</p>'));
  check('null 描述可用', summaryCacheKey(1, null).startsWith('1:0:'), summaryCacheKey(1, null));

  // 内容不同但长度相同——校验和必须能区分开
  const x = summaryCacheKey(5, 'abcdefghij');
  const y = summaryCacheKey(5, 'abcdefghij'.split('').reverse().join(''));
  check('等长不同内容能区分', x !== y, `${x} vs ${y}`);
}

// [7] 摘要门槛 ---------------------------------------------------------------
console.log('\n[7] needsSummary');
{
  // 大部分作业的要求本来就不到 100 字，这时候「精简」出来的东西
  // 和原文信息量完全一样，白白调一次接口。所以短的直接不做摘要。
  check('短正文不需要精简', !needsSummary('<p>交一份实验报告。</p>'));
  check('刚好 100 字不需要精简', !needsSummary('字'.repeat(SUMMARY_LENGTH)));
  check('101 字需要精简', needsSummary('字'.repeat(SUMMARY_LENGTH + 1)));
  check('空正文不需要精简', !needsSummary('') && !needsSummary(null) && !needsSummary(undefined));
  check('纯标签不算正文', !needsSummary('<p></p><div>   </div>'));
  // HTML 标签本身不该被算进长度
  check('标签不计入长度', !needsSummary(`<p>${'字'.repeat(SUMMARY_LENGTH)}</p>`));
  check('首尾空白不计入长度', !needsSummary(`  ${'字'.repeat(SUMMARY_LENGTH)}  `));

  eq('summarySourceText 去标签并 trim', summarySourceText('  <p>你好</p>  '), '你好');

  // 短正文一次接口都不该调
  {
    let called = false;
    const spy = (async () => {
      called = true;
      return new Response('{}', { status: 200 });
    }) as unknown as typeof fetch;
    const cfg: LlmConfig = {
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-test',
      model: 'm',
      enabled: true,
    };
    const shortRes = await summarizeAssignment('短作业', '<p>交一份报告。</p>', cfg, spy);
    eq('短正文不调用接口', called, false);
    eq('短正文来源是 none', shortRes.source, 'none');
    eq('短正文不给摘要', shortRes.summary, '');

    // 长正文才真的发请求
    called = false;
    await summarizeAssignment('长作业', '字'.repeat(SUMMARY_LENGTH + 1), cfg, spy);
    eq('长正文会调用接口', called, true);
  }
}

console.log(`\n=== 结果：${passed}/${passed + failed} 项通过 ===`);
if (failed > 0) process.exit(1);
