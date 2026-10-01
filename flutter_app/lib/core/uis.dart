/// 复旦大学统一身份认证（id.fudan.edu.cn）→ Canvas 会话。
///
/// 整条链路是从认证服务器自己的前端代码
/// （`id.fudan.edu.cn/ac/js/chunk-71ba4ca7.*.js`）读出来后逐项实测验证的，
/// 请求体的字段与取值都与官方页面完全一致：
///
///   1. GET  elearning.fudan.edu.cn/login/cas
///        -> 302 id.fudan.edu.cn/idp/authCenter/authenticate?service=...
///        -> 302 id.fudan.edu.cn/ac/#/index?lck=...&entityId=...
///   2. POST id.fudan.edu.cn/idp/authn/getJsPublicKey   {} -> { data: <SPKI base64> }
///   3. POST id.fudan.edu.cn/idp/authn/queryAuthMethods {lck,entityId}
///        -> { data:[{moduleCode,moduleCodes,authChainCode,...}], requestType, second, code }
///   4. POST id.fudan.edu.cn/idp/authn/verifyCodeIsNeed
///        {lang,loginName,chainCode,authModuleCode} -> { pic, result }  （result=true 即需验证码）
///   5. POST id.fudan.edu.cn/idp/authn/authExecute
///        { authModuleCode, authChainCode, entityId, requestType, lck,
///          authPara:{ loginName, password:<RSA/PKCS#1 v1.5 base64>, verifyCode } }
///        -> { code:200, loginToken } | { code:40xx, message }
///   6. POST id.fudan.edu.cn/idp/authCenter/authnEngine?locale=zh-CN
///        表单 { loginToken } -> 含 #logon[action] 与 #ticket[value] 的 HTML
///   7. GET  <logon action>?ticket=...  -> Canvas 会话 Cookie
///
/// 第 4 步是纯粹的安全网：学校会因多次失败锁定账号，
/// 所以先问清楚要不要验证码，再决定是否消耗一次尝试。

library;

import 'dart:convert';

import 'cookies.dart';
import 'diag.dart';
import 'endpoints.dart';
import 'errors.dart';
import 'http.dart';

const String _locale = 'zh-CN';
const String _lang = 'zh_CN';

/// 密码加密函数：输入明文与 SPKI(base64) 公钥，输出 base64 密文。
///
/// 抽成函数类型是为了让 `core` 不绑定具体实现——
/// 移动端用纯 Dart，桌面端/测试可以用别的方式。
typedef PasswordEncryptor = String Function(String password, String spkiBase64);

class LoginResult {
  LoginResult({required this.jar, required this.finalUrl, required this.elapsedMs});

  final CookieJar jar;
  final String finalUrl;
  final int elapsedMs;
}

/// 提交密码之前就能获知的全部信息。
class LoginContext {
  LoginContext({
    required this.jar,
    required this.http,
    required this.spaUrl,
    required this.lck,
    required this.entityId,
    required this.chainCode,
    required this.authModuleCode,
    required this.requestType,
    required this.publicKey,
    required this.encryptor,
  });

  final CookieJar jar;
  final HttpClientLite http;
  final String spaUrl;
  final String lck;
  final String entityId;
  final String chainCode;
  final String authModuleCode;
  final String requestType;
  final String publicKey;
  final PasswordEncryptor encryptor;
}

class CaptchaState {
  const CaptchaState({required this.required, this.image});

  final bool required;

  /// 待填验证码的 data: URL。
  final String? image;
}

class Credentials {
  const Credentials({required this.username, required this.password, this.captchaCode});

  final String username;
  final String password;

  /// 仅当 [CaptchaState.required] 为 true 时才需要。
  final String? captchaCode;
}

// ---------------------------------------------------------------------------
// HTML 解析（只针对需要的那两个元素，写得防御一些）
// ---------------------------------------------------------------------------

const Map<String, String> _entities = {
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&apos;': "'",
  '&nbsp;': ' ',
};

String decodeEntities(String input) {
  var out = input.replaceAllMapped(
    RegExp(r'&(amp|lt|gt|quot|#39|apos|nbsp);'),
    (m) => _entities[m.group(0)] ?? m.group(0)!,
  );
  out = out.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (m) => String.fromCharCode(int.parse(m.group(1)!)),
  );
  return out;
}

/// 找到第一个带 `attr="value"` 的开始标签。
String? findTagWithAttr(String html, String attr, String value) {
  final tagRe = RegExp(r'<[a-zA-Z][\w:-]*\b[^>]*>');
  for (final m in tagRe.allMatches(html)) {
    final tag = m.group(0)!;
    final a = RegExp('\\b$attr\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))', caseSensitive: false)
        .firstMatch(tag);
    if (a == null) continue;
    final got = a.group(1) ?? a.group(2) ?? a.group(3) ?? '';
    if (got == value) return tag;
  }
  return null;
}

String? getAttr(String tag, String attr) {
  final m = RegExp('\\b$attr\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))', caseSensitive: false)
      .firstMatch(tag);
  if (m == null) return null;
  return decodeEntities(m.group(1) ?? m.group(2) ?? m.group(3) ?? '');
}

/// 从 authnEngine 的响应里取出 `#logon[action]` 与 `#ticket[value]`。
({String action, String ticket})? extractTicketTarget(String html) {
  final logon = findTagWithAttr(html, 'id', 'logon');
  final ticket = findTagWithAttr(html, 'id', 'ticket');
  if (logon == null || ticket == null) return null;
  final action = getAttr(logon, 'action');
  final value = getAttr(ticket, 'value');
  if (action == null || value == null) return null;
  return (action: action, ticket: value);
}

({String lck, String entityId})? parseIdpSpaUrl(String url) {
  final hash = Uri.parse(url).fragment;
  if (hash.isEmpty) return null;
  try {
    final parsed = Uri.parse(idBase + (hash.startsWith('/') ? hash : '/$hash'));
    final lck = parsed.queryParameters['lck'];
    final entityId = parsed.queryParameters['entityId'];
    if (lck == null || entityId == null) return null;
    return (lck: lck, entityId: entityId);
  } catch (_) {
    return null;
  }
}

LoginException classifyAuthResult(Object? code, String? message) {
  final msg = (message ?? '').trim();
  if (msg.contains('用户名或密码错误') || msg.contains('密码有误')) {
    return LoginException(LoginFailureKind.credentialsInvalid, '学号或密码不正确。', msg);
  }
  if (msg.contains('验证码')) {
    return LoginException(
      LoginFailureKind.captchaRequired,
      '统一身份认证要求输入验证码。请按提示填写验证码后重试。',
      msg,
    );
  }
  if (msg.contains('锁定') || msg.contains('冻结')) {
    return LoginException(
      LoginFailureKind.accountLocked,
      '账号已被锁定，请等待自动解锁或联系信息办。',
      msg,
    );
  }
  if (msg.contains('维护')) {
    return LoginException(LoginFailureKind.maintenance, '统一身份认证正在维护，请稍后再试。', msg);
  }
  return LoginException(
    LoginFailureKind.protocol,
    '统一身份认证返回了未预期的结果${code != null ? '（code=$code）' : ''}。',
    msg.isEmpty ? '(无 message 字段)' : msg,
  );
}

// ---------------------------------------------------------------------------
// 对外接口
// ---------------------------------------------------------------------------

/// 第 1-3 步：抵达认证服务器、取公钥、问清楚认证方式。
Future<LoginContext> beginLogin({
  CookieJar? jar,
  PasswordEncryptor? encryptor,
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (encryptor == null) {
    throw LoginException(
      LoginFailureKind.protocol,
      '未提供密码加密实现。',
      '调用方需要注入一个 PasswordEncryptor（例如 lib/core/rsa.dart 中的 rsaPkcs1Encrypt）。',
    );
  }

  final theJar = jar ?? CookieJar();
  // 强制走一次真实认证，而不是复用残留的 CAS 票据。
  theJar.deleteByName('CASTGC');
  final http = HttpClientLite(jar: theJar);

  final entry = await http.request(loginEntry, HttpRequestOptions(timeout: timeout));

  if (!entry.uri.host.contains(idHost)) {
    throw LoginException(
      LoginFailureKind.protocol,
      entry.uri.host.contains(canvasHost)
          ? '当前会话似乎已经登录，无需重新认证。'
          : '未跳转到统一身份认证（落点：${entry.uri}）。',
      entry.uri.toString(),
    );
  }

  final idp = parseIdpSpaUrl(entry.uri.toString());
  if (idp == null) {
    throw LoginException(
      LoginFailureKind.protocol,
      '未能从统一身份认证页面解析出登录参数（lck / entityId）。',
      '落点: ${entry.uri}',
    );
  }

  final pkRes = await http.postJson(
    '$idBase/idp/authn/getJsPublicKey',
    const <String, dynamic>{},
    HttpRequestOptions(
      timeout: timeout,
      headers: {'Origin': idBase, 'Referer': entry.uri.toString()},
    ),
  );

  String? publicKey;
  try {
    final parsed = jsonDecode(pkRes.body);
    if (parsed is Map && parsed['data'] is String) publicKey = parsed['data'] as String;
  } catch (_) {
    // 下面统一报错。
  }
  if (publicKey == null || publicKey.isEmpty) {
    throw LoginException(
      LoginFailureKind.protocol,
      '无法获取统一身份认证的加密公钥。',
      pkRes.body.length > 300 ? pkRes.body.substring(0, 300) : pkRes.body,
    );
  }

  final qRes = await http.postJson(
    '$idBase/idp/authn/queryAuthMethods',
    {'lck': idp.lck, 'entityId': idp.entityId},
    HttpRequestOptions(
      timeout: timeout,
      headers: {'Origin': idBase, 'Referer': entry.uri.toString()},
    ),
  );

  Map<String, dynamic> payload;
  try {
    payload = jsonDecode(qRes.body) as Map<String, dynamic>;
  } catch (_) {
    throw LoginException(
      LoginFailureKind.protocol,
      '统一身份认证返回了无法解析的认证方式列表。',
      qRes.body.length > 300 ? qRes.body.substring(0, 300) : qRes.body,
    );
  }

  final methods = (payload['data'] as List<dynamic>? ?? [])
      .whereType<Map<String, dynamic>>()
      .toList();

  if (methods.isEmpty) {
    throw classifyAuthResult(payload['code'], payload['message'] as String?);
  }
  if (payload['second'] == true) {
    throw LoginException(
      LoginFailureKind.twoFactorRequired,
      '该账号启用了二次验证，本应用暂不支持。请先在浏览器完成一次登录。',
    );
  }

  Map<String, dynamic>? pwdMethod;
  for (final m in methods) {
    final codes = (m['moduleCodes'] as List<dynamic>? ?? []).whereType<String>().toList();
    if (codes.contains('userAndPwd') || m['moduleCode'] == 'userAndPwd') {
      pwdMethod = m;
      break;
    }
  }
  if (pwdMethod == null || pwdMethod['authChainCode'] is! String) {
    final codes = methods.map((m) => m['moduleCode']).join(', ');
    throw LoginException(
      LoginFailureKind.protocol,
      '该账号没有开放「用户名密码」认证方式（可用方式：${codes.isEmpty ? '(空)' : codes}）。',
    );
  }

  final moduleCodes = (pwdMethod['moduleCodes'] as List<dynamic>? ?? []).whereType<String>().toList();

  return LoginContext(
    jar: theJar,
    http: http,
    spaUrl: entry.uri.toString(),
    lck: idp.lck,
    entityId: idp.entityId,
    chainCode: pwdMethod['authChainCode'] as String,
    // 官方页面取的是选中方式的 moduleCodes[0]。
    authModuleCode: moduleCodes.isNotEmpty ? moduleCodes.first : (pwdMethod['moduleCode'] as String? ?? 'userAndPwd'),
    requestType: (payload['requestType'] as String?) ?? 'chain_type',
    publicKey: publicKey,
    encryptor: encryptor,
  );
}

/// 第 4 步：问一下这次会不会要验证码。绝不抛异常，失败就当不需要。
Future<CaptchaState> checkCaptcha(LoginContext ctx, String username) async {
  try {
    final res = await ctx.http.postJson(
      '$idBase/idp/authn/verifyCodeIsNeed',
      {
        'lang': _lang,
        'loginName': username,
        'chainCode': ctx.chainCode,
        'authModuleCode': ctx.authModuleCode,
      },
      HttpRequestOptions(
        timeout: const Duration(seconds: 15),
        headers: {'Origin': idBase, 'Referer': ctx.spaUrl},
      ),
    );
    final parsed = jsonDecode(res.body);
    if (parsed is Map) {
      return CaptchaState(
        required: parsed['result'] == true,
        image: parsed['pic'] as String?,
      );
    }
  } catch (_) {
    // 预检失败不应阻断登录。
  }
  return const CaptchaState(required: false);
}

/// 第 5-7 步：消耗一次认证尝试，并落回 Canvas。
Future<LoginResult> completeLogin(
  LoginContext ctx,
  Credentials credentials, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final started = DateTime.now();

  final encrypted = ctx.encryptor(credentials.password, ctx.publicKey);

  final execRes = await ctx.http.postJson(
    '$idBase/idp/authn/authExecute',
    {
      'authModuleCode': ctx.authModuleCode,
      'authChainCode': ctx.chainCode,
      'entityId': ctx.entityId,
      'requestType': ctx.requestType,
      'lck': ctx.lck,
      'authPara': {
        'loginName': credentials.username,
        'password': encrypted,
        'verifyCode': credentials.captchaCode ?? '',
      },
    },
    HttpRequestOptions(
      timeout: timeout,
      headers: {'Origin': idBase, 'Referer': ctx.spaUrl},
    ),
  );

  Map<String, dynamic> body;
  try {
    body = jsonDecode(execRes.body) as Map<String, dynamic>;
  } catch (_) {
    throw LoginException(
      LoginFailureKind.protocol,
      '统一身份认证返回了无法解析的登录结果。',
      execRes.body.length > 300 ? execRes.body.substring(0, 300) : execRes.body,
    );
  }

  final codeStr = '${body['code']}';
  if (body['second'] == true) {
    throw LoginException(LoginFailureKind.twoFactorRequired, '该账号需要二次验证，本应用暂不支持。');
  }

  final loginToken = body['loginToken'] as String?;
  if (codeStr != '200' || loginToken == null || loginToken.isEmpty) {
    diag('uis', 'authExecute 失败 code=$codeStr message=${body['message']}');
    if (codeStr == '4340' && body['data'] is String) {
      throw LoginException(
        LoginFailureKind.protocol,
        '账号需要在统一身份认证页面完成额外设置，请先用浏览器登录一次。',
        body['data'] as String,
      );
    }
    throw classifyAuthResult(body['code'], body['message'] as String?);
  }
  diag('uis', 'authExecute 成功，拿到 loginToken ${redact(loginToken, keep: 6)}');

  // 用 loginToken 换 CAS 服务票据，再去 Canvas 兑换会话。
  final engineRes = await ctx.http.postForm(
    '$idBase/idp/authCenter/authnEngine?locale=$_locale',
    {'loginToken': loginToken},
    HttpRequestOptions(timeout: timeout, headers: {'Referer': ctx.spaUrl}),
  );

  final target = extractTicketTarget(engineRes.body);
  if (target == null) {
    diag('uis', '✗ authnEngine 页面里找不到 #logon/#ticket（HTTP ${engineRes.statusCode}）');
    throw LoginException(
      LoginFailureKind.protocol,
      '登录成功，但从认证服务器返回的页面里找不到服务票据。',
      engineRes.body.replaceAll(RegExp(r'\s+'), ' ').substring(
            0,
            engineRes.body.length > 400 ? 400 : engineRes.body.length,
          ),
    );
  }
  diag('uis', '拿到服务票据 action=${target.action} ticket=${redact(target.ticket, keep: 10)}');

  final ticketUrl = Uri.parse(target.action).replace(
    queryParameters: {
      ...Uri.parse(target.action).queryParameters,
      'ticket': target.ticket,
    },
  );

  final finalRes = await ctx.http.request(ticketUrl.toString(), HttpRequestOptions(timeout: timeout));

  if (!finalRes.uri.host.contains(canvasHost)) {
    diag('uis', '✗ 票据校验后没回到 eLearning，落点是 ${finalRes.uri}');
    throw LoginException(
      LoginFailureKind.protocol,
      '票据校验后未回到 eLearning（落点：${finalRes.uri}）。',
    );
  }

  // 登录链结束后 jar 里应当有 Canvas 域的会话 cookie。
  // 只记名字与域名，不记值——这条日志是给用户复制发出来的。
  final jarSummary = ctx.jar
      .all()
      .map((c) => '${c.domain}:${c.name}')
      .take(12)
      .join(', ');
  diag('uis', '票据校验完成，落点 ${finalRes.uri}；'
      'jar 里共 ${ctx.jar.all().length} 条 cookie'
      '${jarSummary.isNotEmpty ? ' [$jarSummary]' : '（空！）'}');

  return LoginResult(
    jar: ctx.jar,
    finalUrl: finalRes.uri.toString(),
    elapsedMs: DateTime.now().difference(started).inMilliseconds,
  );
}

/// 便捷封装：begin -> （可选）验证码预检 -> complete。
Future<LoginResult> loginFudanUis({
  required String username,
  required String password,
  String? captchaCode,
  CookieJar? jar,
  PasswordEncryptor? encryptor,
  bool skipCaptchaCheck = false,
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (username.isEmpty || password.isEmpty) {
    throw LoginException(LoginFailureKind.protocol, '学号和密码不能为空。');
  }

  final ctx = await beginLogin(jar: jar, encryptor: encryptor, timeout: timeout);

  if (!skipCaptchaCheck && captchaCode == null) {
    final captcha = await checkCaptcha(ctx, username);
    if (captcha.required) {
      // 明知会失败，就不要浪费一次尝试。
      throw LoginException(
        LoginFailureKind.captchaRequired,
        '统一身份认证要求输入验证码，已中止以避免浪费登录次数。请重新登录并在提示时填写验证码。',
        captcha.image,
      );
    }
  }

  return completeLogin(
    ctx,
    Credentials(username: username, password: password, captchaCode: captchaCode),
    timeout: timeout,
  );
}
