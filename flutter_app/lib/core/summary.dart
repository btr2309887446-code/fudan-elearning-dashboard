/// 作业简介。
///
/// 与桌面端 `src/core/summary.ts` 一一对应，行为必须一致
/// （`test/summary_test.dart` 与 `cli/test-summary.ts` 的用例逐条对应）。
///
/// 两层：
///  1. 纯函数：HTML 转纯文本、按句子边界截断；
///  2. 可选的大模型摘要：调用 OpenAI 兼容接口生成 100 字以内简介。
///     没配 key 就退化成「截取描述前 100 字」，功能不会不可用。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 摘要里存进快照的摘录长度。
const int excerptLength = 600;

/// 简介的目标长度。
const int summaryLength = 100;

const Map<String, String> _entities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'ldquo': '“',
  'rdquo': '”',
  'lsquo': '‘',
  'rsquo': '’',
  'hellip': '…',
  'mdash': '—',
  'ndash': '–',
  'middot': '·',
  'times': '×',
  'divide': '÷',
  'deg': '°',
  'plusmn': '±',
};

final RegExp _entityRe = RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);');
final RegExp _blockEnd = RegExp(
  r'<\s*\/\s*(p|div|li|tr|h[1-6]|section|article|blockquote|pre)\s*>',
  caseSensitive: false,
);
final RegExp _blockStart = RegExp(
  r'<\s*(p|div|section|article|blockquote|pre)\b[^>]*>',
  caseSensitive: false,
);
final RegExp _brTag = RegExp(r'<\s*br\s*\/?\s*>', caseSensitive: false);
final RegExp _liStart = RegExp(r'<\s*li\b[^>]*>', caseSensitive: false);
final RegExp _cellStart = RegExp(r'<\s*(td|th)\b[^>]*>', caseSensitive: false);
final RegExp _cellEnd = RegExp(r'<\s*\/\s*(td|th)\s*>', caseSensitive: false);
final RegExp _dropBlock = RegExp(
  r'<(script|style|head|noscript)[\s\S]*?<\/\1>',
  caseSensitive: false,
);
final RegExp _anyTag = RegExp(r'<[^>]*>');
final RegExp _zeroWidth = RegExp(r'[\u200b-\u200d\ufeff]');
final RegExp _spaces = RegExp(r'[ \t]+');
final RegExp _multiNewline = RegExp(r'\n{2,}');
final RegExp _trailingPipe = RegExp(r'\s*\|\s*$', multiLine: true);
final RegExp _anchorTag = RegExp(
  r"""<\s*a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\s*/\s*a\s*>""",
  caseSensitive: false,
);

/// 作业说明里的可点击链接。
///
/// 说明正文仍然用纯文本展示，避免把远端 HTML 直接交给 WebView；
/// 但把链接单独提出来，用户不必为了打开一个附件入口再跳整页浏览器。
List<({String label, String url})> extractHtmlLinks(String? html) {
  if (html == null || html.isEmpty) return const [];
  final out = <({String label, String url})>[];
  final seen = <String>{};
  for (final match in _anchorTag.allMatches(html)) {
    final url = decodeEntities(match.group(1) ?? '').trim();
    if (url.isEmpty || !seen.add(url)) continue;
    final label = htmlToPlainText(match.group(2)).trim();
    out.add((label: label.isEmpty ? url : label, url: url));
  }
  return out;
}

/// 解码常见的 HTML 实体（含数字实体）。
String decodeEntities(String input) {
  return input.replaceAllMapped(_entityRe, (m) {
    final body = m.group(1)!;
    if (body.startsWith('#')) {
      final isHex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
      final code = int.tryParse(isHex ? body.substring(2) : body.substring(1),
          radix: isHex ? 16 : 10);
      if (code == null || code <= 0 || code > 0x10ffff) return m.group(0)!;
      try {
        return String.fromCharCode(code);
      } catch (_) {
        return m.group(0)!;
      }
    }
    return _entities[body.toLowerCase()] ?? m.group(0)!;
  });
}

/// 把 Canvas 返回的 HTML 描述压成可读纯文本。
///
/// 不是通用 HTML 解析器，只处理 Canvas 实际会产出的那几种结构。
String htmlToPlainText(String? html) {
  if (html == null || html.isEmpty) return '';

  var text = html;
  text = text.replaceAll(_dropBlock, ' ');
  text = text.replaceAll(_brTag, '\n');
  text = text.replaceAll(_blockEnd, '\n');
  text = text.replaceAll(_blockStart, '\n');
  text = text.replaceAll(_liStart, '\n· ');
  text = text.replaceAll(_cellStart, ' ');
  text = text.replaceAll(_cellEnd, ' | ');
  text = text.replaceAll(_anyTag, '');

  text = decodeEntities(text);

  text = text.replaceAll(_zeroWidth, '');
  text = text.replaceAll('\u00a0', ' ');

  text = text
      .split('\n')
      .map((line) => line.replaceAll(_spaces, ' ').trim())
      .join('\n');

  text = text.replaceAll(_multiNewline, '\n').trim();
  text = text.replaceAll(_trailingPipe, '').trim();

  return text;
}

/// 按字符数截断，尽量在句子边界断开。
String truncate(String text, int limit) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.length <= limit) return clean;

  // 给省略号留一位，否则追加 '…' 之后会超出上限一位。
  final window = clean.substring(0, limit - 1 > 0 ? limit - 1 : 1);

  const marks = ['。', '！', '？', '；', '. ', '! ', '? ', '; '];
  var boundary = -1;
  for (final m in marks) {
    final i = window.lastIndexOf(m);
    if (i > boundary) boundary = i;
  }
  if (boundary >= limit * 0.6) return window.substring(0, boundary + 1).trim();

  return '${window.trimRight()}…';
}

/// 去掉 HTML 并截取一段，存进快照用。
String makeExcerpt(String? html, [int limit = excerptLength]) =>
    truncate(htmlToPlainText(html), limit);

/// 去掉 HTML、压掉空白后的正文。判断「要不要精简」和喂给大模型都用它。
String summarySourceText(String? description) =>
    htmlToPlainText(description).trim();

/// 正文长到需要精简吗？
///
/// 门槛就是摘要长度本身：大部分作业的要求本来就不到 100 字，
/// 这时候「精简」出来的东西和原文信息量完全一样，纯属白调一次接口。
/// 所以短的直接显示原文，摘要栏整个不出现。
///
/// 与桌面端 `needsSummary()` 保持同一口径。
bool needsSummary(String? description) =>
    summarySourceText(description).length > summaryLength;

/// 降级简介：没接大模型时直接截取描述前 100 字。
String fallbackSummary(String? description) {
  final text = summarySourceText(description);
  if (text.isEmpty) return '';
  return truncate(text, summaryLength);
}

// ---------------------------------------------------------------------------
// 大模型摘要
// ---------------------------------------------------------------------------

class LlmConfig {
  const LlmConfig({
    this.baseUrl = 'https://api.deepseek.com/v1',
    this.apiKey = '',
    this.model = 'deepseek-chat',
    this.enabled = false,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final bool enabled;

  LlmConfig copyWith(
          {String? baseUrl, String? apiKey, String? model, bool? enabled}) =>
      LlmConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'enabled': enabled
      };

  factory LlmConfig.fromJson(Map<String, dynamic> json) => LlmConfig(
        baseUrl: (json['baseUrl'] as String?) ?? 'https://api.deepseek.com/v1',
        apiKey: (json['apiKey'] as String?) ?? '',
        model: (json['model'] as String?) ?? 'deepseek-chat',
        enabled: json['enabled'] == true,
      );
}

const LlmConfig defaultLlm = LlmConfig();

bool llmReady(LlmConfig? cfg) =>
    cfg != null &&
    cfg.enabled &&
    cfg.apiKey.trim().isNotEmpty &&
    cfg.baseUrl.trim().isNotEmpty &&
    cfg.model.trim().isNotEmpty;

const String _systemPrompt = '你是课程作业的摘要助手。把用户给出的作业说明压缩成一句话简介，'
    '不超过 $summaryLength 个汉字。要求：只陈述这项作业要做什么、要交什么；'
    '不要复述截止时间、分值、评分标准；不要加「这份作业」「本题」之类的开头；'
    '不要任何前后缀、引号或解释；直接输出简介正文。';

/// 一次大模型调用的结果。
class LlmHttpResponse {
  const LlmHttpResponse({required this.status, required this.body});

  final int status;
  final String body;
}

/// 调用大模型的方式，注入以便测试。
typedef LlmTransport = Future<LlmHttpResponse> Function(
  String url,
  String apiKey,
  String jsonBody,
);

/// 用 dart:io 真正发请求。失败时抛异常，由 [summarizeAssignment] 兜住。
Future<LlmHttpResponse> ioLlmTransport(
    String url, String apiKey, String jsonBody) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.postUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    req.add(utf8.encode(jsonBody));
    final res = await req.close().timeout(const Duration(seconds: 30));
    final body = await res.transform(utf8.decoder).join();
    return LlmHttpResponse(status: res.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}

class SummarizeResult {
  const SummarizeResult(
      {required this.summary, required this.source, this.error});

  final String summary;

  /// llm      = 走大模型精简
  /// fallback = 没接大模型，退回截取
  /// none     = 正文本来就不长，不需要精简（此时 summary 为空）
  final String source;
  final String? error;
}

/// 生成作业简介。
///
/// 失败时**不抛错**，而是退回截取结果——简介只是锦上添花，
/// 不该因为它把详情页弄崩。
///
/// 正文不超过 100 字时直接返回 `source: 'none'`，**一次接口都不调**。
Future<SummarizeResult> summarizeAssignment(
  String title,
  String? description,
  LlmConfig? cfg, {
  LlmTransport? transport,
}) async {
  final plain = summarySourceText(description);
  final fallback = fallbackSummary(description);

  // 没有正文，或者正文本来就够短——都不需要精简。
  if (plain.isEmpty || !needsSummary(description)) {
    return const SummarizeResult(summary: '', source: 'none');
  }
  if (!llmReady(cfg)) {
    return SummarizeResult(summary: fallback, source: 'fallback');
  }

  final base = cfg!.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final url = '$base/chat/completions';

  final body = jsonEncode({
    'model': cfg.model,
    'temperature': 0.2,
    'max_tokens': 200,
    'messages': [
      {'role': 'system', 'content': _systemPrompt},
      {
        'role': 'user',
        'content':
            '作业标题：$title\n\n作业说明：\n${plain.length > 4000 ? plain.substring(0, 4000) : plain}',
      },
    ],
  });

  try {
    final send = transport ?? ioLlmTransport;
    final res = await send(url, cfg.apiKey.trim(), body);

    if (res.status < 200 || res.status >= 300) {
      return SummarizeResult(
        summary: fallback,
        source: 'fallback',
        error: '大模型接口返回 ${res.status}'
            '${res.body.isNotEmpty ? '：${res.body.length > 160 ? res.body.substring(0, 160) : res.body}' : ''}',
      );
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    // 逐层判断而不是写成一长串 `.as Map?` 加空安全下标——
    // 那种写法既难读，Dart 的解析器也不喜欢。
    var raw = '';
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final message = first['message'];
        if (message is Map && message['content'] is String) {
          raw = message['content'] as String;
        }
      }
    }

    var cleaned = raw.trim();
    cleaned = cleaned
        .replaceAll(RegExp(r'^["「『]|["」』]$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.isEmpty) {
      return SummarizeResult(
          summary: fallback, source: 'fallback', error: '大模型返回了空内容');
    }

    return SummarizeResult(
        summary: truncate(cleaned, summaryLength), source: 'llm');
  } catch (e) {
    final msg = e.toString().replaceFirst('Exception: ', '');
    return SummarizeResult(
      summary: fallback,
      source: 'fallback',
      error: msg.contains('Timeout') || msg.contains('timed out')
          ? '大模型接口超时'
          : '调用大模型失败：$msg',
    );
  }
}

/// 简介缓存键：同一份描述才复用，描述改了就要重新生成。
String summaryCacheKey(int assignmentId, String? description) {
  final text = description ?? '';
  var checksum = 0;
  for (var i = 0; i < text.length; i++) {
    checksum = (checksum * 31 + text.codeUnitAt(i)) & 0xFFFFFFFF;
    // 保持 32 位有符号语义，与 TS 版一致
    if (checksum >= 0x80000000) checksum -= 0x100000000;
  }
  final unsigned = checksum < 0 ? checksum + 0x100000000 : checksum;
  return '$assignmentId:${text.length}:${unsigned.toRadixString(36)}';
}
