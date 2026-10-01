/**
 * 作业简介。
 *
 * 分两层：
 *  1. 纯函数：把 Canvas 的 HTML 描述转成纯文本、截取前 N 字。
 *     这些不联网，能直接测。
 *  2. 可选的 LLM 摘要：调用任意 OpenAI 兼容接口生成 100 字以内的简介。
 *     没配 key 就退化成「直接截取描述前 100 字」，功能不会不可用。
 *
 * 为什么存「摘录」而不是完整描述：Canvas 的 description 是 HTML，
 * 单条常有几十 KB，143 条就能把本地缓存撑到好几 MB。
 * 列表和降级摘要只需要开头一段，完整描述在打开详情页时按需拉取。
 */

/** 摘录长度：够写一段像样的简介，又不至于把缓存撑大。 */
export const EXCERPT_LENGTH = 600;

/** 简介的目标长度。 */
export const SUMMARY_LENGTH = 100;

const ENTITIES: Record<string, string> = {
  amp: '&',
  lt: '<',
  gt: '>',
  quot: '"',
  apos: "'",
  nbsp: ' ',
  ldquo: '“',
  rdquo: '”',
  lsquo: '‘',
  rsquo: '’',
  hellip: '…',
  mdash: '—',
  ndash: '–',
  middot: '·',
  times: '×',
  divide: '÷',
  deg: '°',
  plusmn: '±',
};

/** 解码常见的 HTML 实体（含数字实体）。 */
export function decodeEntities(input: string): string {
  return input.replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g, (whole, body: string) => {
    if (body.startsWith('#')) {
      const isHex = body[1] === 'x' || body[1] === 'X';
      const code = Number.parseInt(isHex ? body.slice(2) : body.slice(1), isHex ? 16 : 10);
      if (!Number.isFinite(code) || code <= 0 || code > 0x10ffff) return whole;
      try {
        return String.fromCodePoint(code);
      } catch {
        return whole;
      }
    }
    return ENTITIES[body.toLowerCase()] ?? whole;
  });
}

/**
 * 把 Canvas 返回的 HTML 描述压成可读纯文本。
 *
 * 不是通用 HTML 解析器，只处理 Canvas 实际会产出的那几种结构：
 * 段落、换行、列表、标题、表格、代码块。目标是「读起来不别扭」。
 */
export function htmlToPlainText(html: string | null | undefined): string {
  if (!html) return '';

  let text = html;

  // 先干掉整块的非内容元素（含内容一起丢）。
  text = text.replace(/<(script|style|head|noscript)[\s\S]*?<\/\1>/gi, ' ');

  // 块级元素之间的边界换成换行，避免 "第一段第二段" 粘在一起。
  text = text.replace(/<\s*br\s*\/?\s*>/gi, '\n');
  text = text.replace(/<\s*\/\s*(p|div|li|tr|h[1-6]|section|article|blockquote|pre)\s*>/gi, '\n');
  text = text.replace(/<\s*(p|div|section|article|blockquote|pre)\b[^>]*>/gi, '\n');
  // 列表项给个记号，读起来像清单。
  text = text.replace(/<\s*li\b[^>]*>/gi, '\n· ');
  text = text.replace(/<\s*(td|th)\b[^>]*>/gi, ' ');
  text = text.replace(/<\s*\/\s*(td|th)\s*>/gi, ' | ');

  // 其余标签直接去掉。
  text = text.replace(/<[^>]*>/g, '');

  text = decodeEntities(text);

  // 全角空格、零宽字符统一处理。
  text = text.replace(/[\u200b-\u200d\ufeff]/g, '');
  text = text.replace(/\u00a0/g, ' ');

  // 行内多余空白压掉，行首尾修剪。
  text = text
    .split('\n')
    .map((line) => line.replace(/[ \t]+/g, ' ').trim())
    .join('\n');

  // 连续空行压成一个。
  text = text.replace(/\n{2,}/g, '\n').trim();

  // 表格留下的多余竖线。
  text = text.replace(/\s*\|\s*$/gm, '').trim();

  return text;
}

/** 按字符数截断，尽量在句子边界断开。 */
export function truncate(text: string, limit: number): string {
  const clean = text.replace(/\s+/g, ' ').trim();
  if (clean.length <= limit) return clean;

  // 给省略号留一位，否则追加 '…' 之后会超出上限一位。
  const window = clean.slice(0, Math.max(1, limit - 1));

  // 中文句读与英文句点都算边界，但不要切出一个太短的片段。
  const boundary = Math.max(
    window.lastIndexOf('。'),
    window.lastIndexOf('！'),
    window.lastIndexOf('？'),
    window.lastIndexOf('；'),
    window.lastIndexOf('. '),
    window.lastIndexOf('! '),
    window.lastIndexOf('? '),
    window.lastIndexOf('; '),
  );
  if (boundary >= limit * 0.6) return window.slice(0, boundary + 1).trim();

  return `${window.trimEnd()}…`;
}

/** 去掉 HTML 并截取一段，存进快照用。 */
export function makeExcerpt(html: string | null | undefined, limit = EXCERPT_LENGTH): string {
  return truncate(htmlToPlainText(html), limit);
}

/**
 * 去掉 HTML、压掉空白后的正文。判断「要不要精简」和喂给大模型都用它。
 */
export function summarySourceText(description: string | null | undefined): string {
  return htmlToPlainText(description).trim();
}

/**
 * 正文长到需要精简吗？
 *
 * 门槛就是摘要长度本身：大部分作业的要求本来就不到 100 字，
 * 这时候「精简」出来的东西和原文信息量完全一样，纯属白调一次接口。
 * 所以短的直接显示原文，摘要栏整个不出现。
 */
export function needsSummary(description: string | null | undefined): boolean {
  return summarySourceText(description).length > SUMMARY_LENGTH;
}

/**
 * 降级简介：没接大模型时直接截取描述前 100 字。
 *
 * 之所以不走 [makeExcerpt] 的截断结果，是因为摘录可能被截到 600 字，
 * 这里要的是「前 100 字」，两者长度不同。
 */
export function fallbackSummary(description: string | null | undefined): string {
  const text = summarySourceText(description);
  if (!text) return '';
  return truncate(text, SUMMARY_LENGTH);
}

// ---------------------------------------------------------------------------
// 大模型摘要
// ---------------------------------------------------------------------------

export interface LlmConfig {
  /** OpenAI 兼容的 base URL，例如 https://api.deepseek.com/v1 */
  baseUrl: string;
  apiKey: string;
  model: string;
  /** 关掉时完全不调用，只用截取。 */
  enabled: boolean;
}

export const DEFAULT_LLM: LlmConfig = {
  baseUrl: 'https://api.deepseek.com/v1',
  apiKey: '',
  model: 'deepseek-chat',
  enabled: false,
};

export function llmReady(cfg: LlmConfig | null | undefined): boolean {
  return Boolean(cfg && cfg.enabled && cfg.apiKey.trim() && cfg.baseUrl.trim() && cfg.model.trim());
}

const SYSTEM_PROMPT =
  '你是课程作业的摘要助手。把用户给出的作业说明压缩成一句话简介，' +
  `不超过 ${SUMMARY_LENGTH} 个汉字。要求：只陈述这项作业要做什么、要交什么；` +
  '不要复述截止时间、分值、评分标准；不要加「这份作业」「本题」之类的开头；' +
  '不要任何前后缀、引号或解释；直接输出简介正文。';

export interface SummarizeResult {
  summary: string;
  /**
   * llm      = 走大模型精简
   * fallback = 没接大模型，退回截取
   * none     = 正文本来就不长，不需要精简（此时 summary 为空）
   */
  source: 'llm' | 'fallback' | 'none';
  error?: string;
}

/**
 * 生成作业简介。
 *
 * 调用方传进来完整描述；失败时**不会抛错**，而是退回截取结果——
 * 简介只是锦上添花，不该因为它把详情页弄崩。
 *
 * 正文不超过 100 字时直接返回 `source: 'none'`，**一次接口都不调**。
 */
export async function summarizeAssignment(
  title: string,
  description: string | null | undefined,
  cfg: LlmConfig | null | undefined,
  fetchImpl: typeof fetch = fetch
): Promise<SummarizeResult> {
  const plain = summarySourceText(description);
  const fallback = fallbackSummary(description);

  // 没有正文，或者正文本来就够短——都不需要精简。
  if (!plain || !needsSummary(description)) return { summary: '', source: 'none' };
  if (!llmReady(cfg)) return { summary: fallback, source: 'fallback' };

  const base = cfg!.baseUrl.replace(/\/+$/, '');
  const url = `${base}/chat/completions`;

  // 描述可能很长，只截一段喂进去，省 token 也够判断作业要做什么。
  const body = {
    model: cfg!.model,
    temperature: 0.2,
    max_tokens: 200,
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: `作业标题：${title}\n\n作业说明：\n${plain.slice(0, 4000)}` },
    ],
  };

  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 30_000);
    const res = await fetchImpl(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${cfg!.apiKey.trim()}`,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    clearTimeout(timer);

    if (!res.ok) {
      const detail = await res.text().catch(() => '');
      return {
        summary: fallback,
        source: 'fallback',
        error: `大模型接口返回 ${res.status}${detail ? `：${detail.slice(0, 160)}` : ''}`,
      };
    }

    const json = (await res.json()) as {
      choices?: { message?: { content?: string } }[];
    };
    const raw = json.choices?.[0]?.message?.content ?? '';
    const cleaned = raw
      .trim()
      .replace(/^["「『]|["」』]$/g, '')
      .replace(/\s+/g, ' ')
      .trim();

    if (!cleaned) return { summary: fallback, source: 'fallback', error: '大模型返回了空内容' };

    return { summary: truncate(cleaned, SUMMARY_LENGTH), source: 'llm' };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return {
      summary: fallback,
      source: 'fallback',
      error: msg.includes('abort') ? '大模型接口超时' : `调用大模型失败：${msg}`,
    };
  }
}

/**
 * 简介缓存键：同一份描述才复用，描述改了就要重新生成。
 *
 * 不引入哈希库——用长度加简单校验和就够了，这里只是防串号，不是安全用途。
 */
export function summaryCacheKey(assignmentId: number, description: string | null | undefined): string {
  const text = description ?? '';
  let checksum = 0;
  for (let i = 0; i < text.length; i += 1) {
    checksum = (checksum * 31 + text.charCodeAt(i)) | 0;
  }
  return `${assignmentId}:${text.length}:${(checksum >>> 0).toString(36)}`;
}
