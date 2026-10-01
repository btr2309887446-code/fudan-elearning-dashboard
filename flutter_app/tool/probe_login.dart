/// 在桌面 Dart VM 上对**真实服务器**跑一遍登录链的前半段。
///
/// `beginLogin()` 不需要学号密码，所以可以在没有凭据的情况下验证：
///   - `GET /login/cas` 的跳转链
///   - 每一跳的 Set-Cookie 有没有被 CookieJar 正确收集
///   - SPA 页面、公钥、认证方式查询是否都拿到了
///
/// 目的是和已经验证过的 TS 版（`cli/snapshot.ts`）逐步对照——
/// 如果 Dart 的 cookie 处理在真实响应上有偏差，这里就能看出来。
///
///   dart run tool/probe_login.dart            # 用 App 默认的 UA（iPhone Safari）
///   dart run tool/probe_login.dart desktop    # 用桌面 Chrome UA
///
/// 加 `desktop` 参数是为了验证一件事：服务器会不会因为 UA 不同而把登录链
/// 引到不同的 SPA（手机版 /ac-h5/ vs 桌面版 /ac/）。
///
/// **不会提交任何凭据，不会消耗登录尝试次数。**
library;

import 'dart:io';

import 'package:fudan_elearning/core/cookies.dart';
import 'package:fudan_elearning/core/http.dart';
import 'package:fudan_elearning/core/rsa.dart';
import 'package:fudan_elearning/core/uis.dart';

/// 与桌面端 TS 版一致：Chrome on Windows。
const String _desktopUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

Future<void> main(List<String> args) async {
  final useDesktop = args.contains('desktop');
  final ua = useDesktop ? _desktopUa : defaultUserAgent;

  stdout.writeln('=== Dart 登录链前半段对真实服务器 ===');
  stdout.writeln('UA: ${useDesktop ? '桌面 Chrome' : 'App 默认（iPhone Safari）'}');
  stdout.writeln('开始时间 ${DateTime.now().toIso8601String()}');
  stdout.writeln('');

  final jar = CookieJar();
  final http = HttpClientLite(jar: jar, userAgent: ua);

  try {
    final t0 = DateTime.now();
    final ctx = await beginLogin(
      jar: jar,
      http: http,
      encryptor: rsaPkcs1Encrypt,
      timeout: const Duration(seconds: 25),
    );
    final ms = DateTime.now().difference(t0).inMilliseconds;

    stdout.writeln('✓ beginLogin 成功（$ms ms）');
    stdout.writeln('');
    stdout.writeln('--- 解析出来的上下文 ---');
    stdout.writeln('  lck        = ${ctx.lck}');
    stdout.writeln('  entityId   = ${ctx.entityId}');
    stdout.writeln('  chainCode  = ${ctx.chainCode}');
    stdout.writeln('  moduleCode = ${ctx.authModuleCode}');
    stdout.writeln('  requestType= ${ctx.requestType}');
    stdout.writeln('  spaUrl     = ${ctx.spaUrl}');
    stdout.writeln('  公钥长度   = ${ctx.publicKey.length} 字符');
    stdout.writeln('');

    stdout.writeln('--- Cookie jar（域名:名字，不含值）---');
    final cookies = jar.all();
    if (cookies.isEmpty) {
      stdout.writeln('  （空！）');
    } else {
      for (final c in cookies) {
        stdout.writeln('  ${c.domain}  ${c.name}  '
            'path=${c.path} secure=${c.secure} hostOnly=${c.hostOnly} '
            'expires=${c.expires?.toIso8601String() ?? '会话'}');
      }
    }
    stdout.writeln('');

    stdout.writeln('--- 发给 id.fudan.edu.cn 的 Cookie 头会是什么 ---');
    final forId = jar.cookieHeader('https://id.fudan.edu.cn/idp/authn/queryAuthMethods');
    stdout.writeln('  ${forId == null ? '（无）' : forId.split('; ').map((p) => p.split('=').first).join(', ')}');
    stdout.writeln('');

    stdout.writeln('--- 发给 elearning.fudan.edu.cn 的 Cookie 头会是什么 ---');
    final forCanvas = jar.cookieHeader('https://elearning.fudan.edu.cn/api/v1/users/self');
    stdout.writeln('  ${forCanvas == null ? '（无）' : forCanvas.split('; ').map((p) => p.split('=').first).join(', ')}');
    stdout.writeln('');

    stdout.writeln('--- 完整请求轨迹 ---');
    for (final t in http.trace) {
      stdout.writeln('  ${t.method} ${t.url} → ${t.statusCode}'
          '${t.location != null ? ' → ${t.location}' : ''}'
          '${t.setCookies.isNotEmpty ? '  [set-cookie: ${t.setCookies.map((c) => c.split('=').first).join(',')}]' : ''}');
    }
  } catch (e, st) {
    stdout.writeln('✗ 失败：${e.runtimeType}: $e');
    stdout.writeln(st.toString().split('\n').take(6).join('\n'));
    stdout.writeln('');
    stdout.writeln('--- 失败前的请求轨迹 ---');
    for (final t in http.trace) {
      stdout.writeln('  ${t.method} ${t.url} → ${t.statusCode}'
          '${t.location != null ? ' → ${t.location}' : ''}'
          '${t.setCookies.isNotEmpty ? '  [set-cookie: ${t.setCookies.map((c) => c.split('=').first).join(',')}]' : ''}');
    }
    exitCode = 1;
  }
}
