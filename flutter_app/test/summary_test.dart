/// 作业简介测试。
///
/// 用例与桌面端 `cli/test-summary.ts` 逐条对应。
///
/// 关键的一类断言是「与桌面端输出逐字节相同」：缓存键、HTML 转文本、
/// 截断结果都写死了 TS 版实测出来的精确值。两端只要有一边改跑偏，
/// 这里就会红——这比各自断言「长度不超过 100」有意义得多。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fudan_elearning/core/summary.dart';

/// 假的传输层，记录请求内容。
class FakeTransport {
  FakeTransport(this.status, this.body);

  int status;
  String body;
  int calls = 0;
  String? lastUrl;
  String? lastKey;
  String? lastBody;

  Future<LlmHttpResponse> call(String url, String apiKey, String jsonBody) async {
    calls += 1;
    lastUrl = url;
    lastKey = apiKey;
    lastBody = jsonBody;
    return LlmHttpResponse(status: status, body: body);
  }
}

void main() {
  group('decodeEntities 与桌面端一致', () {
    test('命名实体', () {
      expect(decodeEntities('a &amp; b &lt;c&gt; &quot;d&quot;'), 'a & b <c> "d"');
    });
    test('中文引号', () => expect(decodeEntities('&ldquo;报告&rdquo;'), '“报告”'));
    test('nbsp 变空格', () => expect(decodeEntities('a&nbsp;b'), 'a b'));
    test('十进制数字实体', () => expect(decodeEntities('&#65;&#66;'), 'AB'));
    test('十六进制实体', () => expect(decodeEntities('&#x4e2d;&#x6587;'), '中文'));
    test('未知实体原样保留', () => expect(decodeEntities('&foo; &bar;'), '&foo; &bar;'));
  });

  group('htmlToPlainText 与桌面端逐字节一致', () {
    test('段落换行', () => expect(htmlToPlainText('<p>第一段</p><p>第二段</p>'), '第一段\n第二段'));
    test('br 换行', () => expect(htmlToPlainText('第一行<br>第二行'), '第一行\n第二行'));
    test('br 自闭合', () => expect(htmlToPlainText('a<br/>b'), 'a\nb'));
    test('行内标签不换行', () => expect(htmlToPlainText('<p>这是<strong>重点</strong>内容</p>'), '这是重点内容'));
    test('链接只留文字', () => expect(htmlToPlainText('<a href="x">点这里</a>'), '点这里'));

    // 这三条是写死的 TS 实测输出
    test('列表记号与桌面端一致', () => expect(htmlToPlainText('<ul><li>甲</li><li>乙</li></ul>'), '· 甲\n· 乙'));
    test('表格与桌面端一致', () => expect(htmlToPlainText('<table><tr><td>姓名</td><td>分数</td></tr></table>'), '姓名 | 分数'));
    test('实体与空白与桌面端一致', () => expect(htmlToPlainText('a&nbsp;&nbsp;b'), 'a b'));
    test('混合实体与桌面端一致', () => expect(htmlToPlainText('&ldquo;报告&rdquo; &#x4e2d;'), '“报告” 中'));

    test('script 整块丢掉', () => expect(htmlToPlainText('<p>正文</p><script>alert(1)</script>'), '正文'));
    test('style 整块丢掉', () => expect(htmlToPlainText('<style>p{color:red}</style><p>正文</p>'), '正文'));
    test('连续空行压成一个', () => expect(htmlToPlainText('<p>a</p><p></p><p></p><p>b</p>'), 'a\nb'));
    test('零宽字符清掉', () => expect(htmlToPlainText('a\u200bb\ufeffc'), 'abc'));
    test('空输入', () => expect(htmlToPlainText(''), ''));
    test('null 输入', () => expect(htmlToPlainText(null), ''));
    test('只有标签', () => expect(htmlToPlainText('<p></p><div></div>'), ''));
    test('已转义的标签不会被删掉', () => expect(htmlToPlainText('&lt;script&gt; 是要转义的'), '<script> 是要转义的'));
  });

  group('truncate 与桌面端逐字节一致', () {
    test('短文本不动', () => expect(truncate('短', 100), '短'));
    test('恰好等于上限', () => expect(truncate('a' * 100, 100), 'a' * 100));
    test('空白压缩', () => expect(truncate('a   b\n\nc', 100), 'a b c'));

    test('优先在句号处断开', () {
      final t = truncate('${'甲' * 80}。${'乙' * 80}', 100);
      expect(t, '${'甲' * 80}。');
      expect(t.length, 81);
    });

    // 边界早于 60% 时不硬切，改用省略号
    test('边界过早时用省略号', () {
      final t = truncate('很短。${'丙' * 300}', 100);
      expect(t.length, 100);
      expect(t.endsWith('丙…'), isTrue);
    });

    test('无边界时用省略号且不超长', () {
      final t = truncate('丁' * 300, 100);
      expect(t.length, 100);
      expect(t.endsWith('丁…'), isTrue);
    });
  });

  group('摘录与降级简介', () {
    const html = '<p>本次作业要求实现一个哈夫曼编码器。</p>'
        '<p>具体要求：</p><ul><li>统计字符频率</li><li>构建哈夫曼树</li><li>输出编码表</li></ul>'
        '<p>提交方式：上传源代码与实验报告。</p>';

    test('摘录不含标签且不超长', () {
      final e = makeExcerpt(html);
      expect(e.contains('<'), isFalse);
      expect(e.contains('哈夫曼编码器'), isTrue);
      expect(e.length, lessThanOrEqualTo(excerptLength));
    });

    test('降级简介不超 100 字且含关键内容', () {
      final b = fallbackSummary(html);
      expect(b.length, lessThanOrEqualTo(summaryLength));
      expect(b.contains('哈夫曼'), isTrue);
    });

    test('空描述降级为空串', () => expect(fallbackSummary('<p></p>'), ''));
    test('null 降级为空串', () => expect(fallbackSummary(null), ''));
  });

  group('摘要门槛', () {
    // 大部分作业的要求本来就不到 100 字，这时候「精简」出来的东西
    // 和原文信息量完全一样，白白调一次接口。所以短的直接不做摘要。
    test('短正文不需要精简', () {
      expect(needsSummary('<p>交一份实验报告。</p>'), isFalse);
    });

    test('刚好 100 字不需要精简，101 字需要', () {
      expect(needsSummary('字' * summaryLength), isFalse);
      expect(needsSummary('字' * (summaryLength + 1)), isTrue);
    });

    test('空正文不需要精简', () {
      expect(needsSummary(''), isFalse);
      expect(needsSummary(null), isFalse);
    });

    test('纯标签不算正文', () {
      expect(needsSummary('<p></p><div>   </div>'), isFalse);
    });

    test('HTML 标签不计入长度', () {
      expect(needsSummary('<p>${'字' * summaryLength}</p>'), isFalse);
    });

    test('首尾空白不计入长度', () {
      expect(needsSummary('  ${'字' * summaryLength}  '), isFalse);
    });

    test('summarySourceText 去标签并 trim', () {
      expect(summarySourceText('  <p>你好</p>  '), '你好');
    });

    test('短正文一次接口都不调，长正文才调', () async {
      const cfg = LlmConfig(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-test',
        model: 'm',
        enabled: true,
      );

      var called = false;
      Future<LlmHttpResponse> spy(String url, String apiKey, String body) async {
        called = true;
        return const LlmHttpResponse(
          status: 200,
          body: '{"choices":[{"message":{"content":"摘要"}}]}',
        );
      }

      final short = await summarizeAssignment('短作业', '<p>交一份报告。</p>', cfg, transport: spy);
      expect(called, isFalse, reason: '短正文不该发请求');
      expect(short.source, 'none');
      expect(short.summary, isEmpty);

      called = false;
      await summarizeAssignment('长作业', '字' * (summaryLength + 1), cfg, transport: spy);
      expect(called, isTrue, reason: '长正文应当发请求');
    });
  });

  group('大模型调用', () {
    // 夹具必须超过 100 字，否则会被摘要门槛挡下、根本走不到大模型那条路。
    // 门槛本身在「摘要门槛」那组里单独测。
    const html = '<p>写一份关于二叉搜索树的实验报告，包含插入、删除、查找三种操作的复杂度分析。'
        '要求给出每种操作的平均情况与最坏情况时间复杂度推导过程，画出至少三种不同形态的树'
        '（平衡、退化成链、随机插入）并对比它们的查找效率，最后总结在什么情况下会退化以及'
        '如何用平衡树避免。</p>';
    const cfg = LlmConfig(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-test',
      model: 'm',
      enabled: true,
    );

    test('未配置时走降级', () async {
      final r = await summarizeAssignment('实验五', html, defaultLlm);
      expect(r.source, 'fallback');
    });

    test('null 配置也走降级', () async {
      final r = await summarizeAssignment('实验五', html, null);
      expect(r.source, 'fallback');
    });

    test('llmReady 判定', () {
      expect(llmReady(const LlmConfig(apiKey: 'sk-x', enabled: false)), isFalse);
      expect(llmReady(const LlmConfig(apiKey: 'sk-x', enabled: true)), isTrue);
      expect(llmReady(const LlmConfig(apiKey: '   ', enabled: true)), isFalse);
      expect(llmReady(null), isFalse);
    });

    test('成功时解析内容并去掉包裹引号', () async {
      final t = FakeTransport(200, '{"choices":[{"message":{"content":"「实现二叉搜索树并分析三种操作的复杂度。」"}}]}');
      final r = await summarizeAssignment('实验五', html, cfg, transport: t.call);
      expect(r.source, 'llm');
      expect(r.summary, '实现二叉搜索树并分析三种操作的复杂度。');
      expect(t.lastUrl, 'https://api.example.com/v1/chat/completions');
      expect(t.lastKey, 'sk-test');
      expect(t.lastBody!.contains('实验五'), isTrue);
      expect(t.lastBody!.contains('二叉搜索树'), isTrue);
      expect(t.lastBody!.contains('"model":"m"'), isTrue);
    });

    test('baseUrl 结尾多余斜杠被规整', () async {
      final t = FakeTransport(200, '{"choices":[{"message":{"content":"简短。"}}]}');
      await summarizeAssignment(
        't',
        html,
        cfg.copyWith(baseUrl: 'https://api.example.com/v1///'),
        transport: t.call,
      );
      expect(t.lastUrl, 'https://api.example.com/v1/chat/completions');
    });

    test('401 时降级且带状态码', () async {
      final t = FakeTransport(401, 'unauthorized');
      final r = await summarizeAssignment('实验五', html, cfg, transport: t.call);
      expect(r.source, 'fallback');
      expect(r.error, contains('401'));
      expect(r.summary.isNotEmpty, isTrue);
    });

    test('返回空内容时降级', () async {
      final t = FakeTransport(200, '{"choices":[{"message":{"content":"   "}}]}');
      final r = await summarizeAssignment('实验五', html, cfg, transport: t.call);
      expect(r.source, 'fallback');
    });

    test('网络异常时降级且不抛', () async {
      Future<LlmHttpResponse> boom(String u, String k, String b) async =>
          throw Exception('ECONNREFUSED');
      final r = await summarizeAssignment('实验五', html, cfg, transport: boom);
      expect(r.source, 'fallback');
      expect(r.error, contains('ECONNREFUSED'));
    });

    test('JSON 解析失败也降级', () async {
      final t = FakeTransport(200, 'not json at all');
      final r = await summarizeAssignment('实验五', html, cfg, transport: t.call);
      expect(r.source, 'fallback');
    });

    test('超长返回值被截到 100 字内', () async {
      final t = FakeTransport(200, '{"choices":[{"message":{"content":"${'己' * 400}"}}]}');
      final r = await summarizeAssignment('实验五', html, cfg, transport: t.call);
      expect(r.summary.length, lessThanOrEqualTo(summaryLength));
    });

    test('没有描述时不调用接口', () async {
      final t = FakeTransport(200, '{}');
      await summarizeAssignment('空作业', '', cfg, transport: t.call);
      expect(t.calls, 0);
    });
  });

  group('summaryCacheKey 与桌面端完全一致', () {
    // 这些期望值是从 `cli/test-summary.ts` 实测出来的，
    // 两端算法只要有一边跑偏就会在这里暴露。
    test('空描述', () {
      expect(summaryCacheKey(1, null), '1:0:0');
      expect(summaryCacheKey(1, ''), '1:0:0');
    });

    test('普通 HTML', () => expect(summaryCacheKey(1, '<p>abc</p>'), '1:10:1yy8pll'));

    test('等长不同内容能区分', () {
      expect(summaryCacheKey(5, 'abcdefghij'), '5:10:1ojgfc5');
      expect(summaryCacheKey(5, 'jihgfedcba'), '5:10:anflmj');
    });

    test('中文长描述', () {
      expect(
        summaryCacheKey(2120203, '教材第 12 章习题：12.3、12.7、12.11、12.15、12.20。'),
        '2120203:39:1llb99p',
      );
    });

    test('同输入同键、不同 id 不同键', () {
      expect(summaryCacheKey(7, 'x'), summaryCacheKey(7, 'x'));
      expect(summaryCacheKey(7, 'x') == summaryCacheKey(8, 'x'), isFalse);
    });
  });

  group('LlmConfig 序列化', () {
    test('往返', () {
      const c = LlmConfig(baseUrl: 'https://x/v1', apiKey: 'sk-1', model: 'm', enabled: true);
      final back = LlmConfig.fromJson(c.toJson());
      expect(back.baseUrl, c.baseUrl);
      expect(back.apiKey, c.apiKey);
      expect(back.model, c.model);
      expect(back.enabled, isTrue);
    });

    test('缺字段时用默认值', () {
      final c = LlmConfig.fromJson(const {});
      expect(c.baseUrl, defaultLlm.baseUrl);
      expect(c.enabled, isFalse);
    });
  });
}
