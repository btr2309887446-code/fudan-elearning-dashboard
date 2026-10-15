import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fudan_elearning/core/cookies.dart';
import 'package:fudan_elearning/core/errors.dart';
import 'package:fudan_elearning/core/http.dart';
import 'package:fudan_elearning/core/rsa.dart';
import 'package:fudan_elearning/core/uis.dart';

String _safeUrl(String value) {
  try {
    final uri = Uri.parse(value);
    return uri.replace(query: null, fragment: null).toString();
  } catch (_) {
    return '<invalid-url>';
  }
}

String _phase(HttpTrace trace, {required bool engineSeen}) {
  if (trace.phase != null) return trace.phase!;
  final path = Uri.tryParse(trace.url)?.path ?? '';
  if (path == '/login/cas') return engineSeen ? 'ticket' : 'canvas-entry';
  if (path.contains('/verifyCodeIsNeed')) return 'captcha-precheck';
  if (path.contains('/authExecute')) return 'authExecute';
  if (path.contains('/authnEngine')) return 'authnEngine';
  if (path.contains('/getJsPublicKey') || path.contains('/queryAuthMethods')) return 'auth-setup';
  if (path.contains('/users/self/profile')) return 'canvas-profile';
  return 'other';
}

List<Map<String, Object?>> _safeTrace(List<HttpTrace> trace) {
  var engineSeen = false;
  return trace.map((item) {
    final phase = _phase(item, engineSeen: engineSeen);
    if (phase == 'authnEngine') engineSeen = true;
    return <String, Object?>{
      'phase': phase,
      'method': item.method,
      'url': _safeUrl(item.url),
      'status': item.statusCode,
      if (item.location != null) 'location': _safeUrl(Uri.parse(item.url).resolve(item.location!).toString()),
      'setCookieNames': item.setCookieNames,
      'sentCookieNames': item.sentCookieNames,
      if (item.requestOrigin != null) 'origin': item.requestOrigin,
      if (item.requestReferer != null) 'referer': item.requestReferer,
      'bodyShape': item.bodyShape,
      if (item.authCode != null) 'authCode': item.authCode,
      if (item.loginTokenPresent != null) 'loginTokenPresent': item.loginTokenPresent,
      if (item.secondFactorRequired != null) 'secondFactorRequired': item.secondFactorRequired,
      if (item.ticketFound != null) 'ticketFound': item.ticketFound,
      if (item.ticketHost != null) 'ticketHost': item.ticketHost,
      if (item.captchaCheckVerified != null) 'captchaCheckVerified': item.captchaCheckVerified,
      if (item.captchaRequired != null) 'captchaRequired': item.captchaRequired,
    };
  }).toList();
}

String _failureCategory(Object error) {
  if (error is LoginException) return error.kind.name;
  if (error is CanvasException) return 'http_${error.statusCode}';
  if (error is HttpError) {
    if (error.message.contains('重定向循环')) return 'redirect_loop';
    if (error.message.contains('重定向次数')) return 'redirect_limit';
  }
  if (error is SocketException || error is HandshakeException || error is TimeoutException) return 'network';
  return 'protocol';
}

Map<String, Object?> _result({
  required String status,
  required List<HttpTrace> trace,
  String? stage,
  String? errorCategory,
  int? profileStatus,
  List<String> cookieNames = const [],
  int? cookieCount,
}) => {
      'platform': 'flutter',
      'status': status,
      if (stage != null) 'stage': stage,
      if (errorCategory != null) 'errorCategory': errorCategory,
      if (profileStatus != null) 'profileStatus': profileStatus,
      if (cookieCount != null) 'cookieCount': cookieCount,
      if (cookieNames.isNotEmpty) 'cookieNames': cookieNames,
      'trace': _safeTrace(trace),
    };

Future<void> main() async {
  final env = Platform.environment;
  final username = env['FUDAN_TEST_USERNAME']?.trim() ?? '';
  final password = env['FUDAN_TEST_PASSWORD'] ?? '';
  if (username.isEmpty || password.isEmpty) {
    stdout.writeln(jsonEncode(_result(status: 'skipped', trace: const [], errorCategory: 'credentials_missing')));
    return;
  }

  final jar = CookieJar();
  final http = HttpClientLite(jar: jar);
  var stage = 'canvas-entry';
  try {
    final context = await beginLogin(
      jar: jar,
      http: http,
      encryptor: rsaPkcs1Encrypt,
      timeout: const Duration(seconds: 30),
    );
    stage = 'captcha-precheck';
    final captcha = await checkCaptcha(context, username);
    final precheck = http.trace.isEmpty ? null : http.trace.last;
    if (!captcha.verified || precheck?.captchaCheckVerified != true) {
      stdout.writeln(jsonEncode(_result(
        status: 'stopped', trace: http.trace, stage: stage,
        errorCategory: 'captcha_precheck_unverified',
      )));
      return;
    }
    if (captcha.required) {
      stdout.writeln(jsonEncode(_result(
        status: 'stopped', trace: http.trace, stage: stage,
        errorCategory: 'captcha_required',
      )));
      return;
    }

    stage = 'authExecute';
    await completeLogin(context, Credentials(username: username, password: password), timeout: const Duration(seconds: 30));
    stage = 'canvas-profile';
    final profileStart = http.trace.length;
    final profile = await http.request(
      'https://elearning.fudan.edu.cn/api/v1/users/self/profile',
      const HttpRequestOptions(
        headers: {'Accept': 'application/json', 'Referer': 'https://elearning.fudan.edu.cn/'},
        timeout: Duration(seconds: 30),
      ),
    );
    for (final item in http.trace.skip(profileStart)) {
      item.phase = 'canvas-profile';
    }
    stdout.writeln(jsonEncode(_result(
      status: profile.statusCode == 200 ? 'passed' : 'failed',
      trace: http.trace,
      stage: stage,
      profileStatus: profile.statusCode,
      cookieCount: jar.all().length,
      cookieNames: jar.all().map((cookie) => cookie.name).toSet().toList()..sort(),
    )));
  } catch (error) {
    final last = http.trace.isEmpty ? null : http.trace.last;
    final failedStage = last?.phase ?? stage;
    stdout.writeln(jsonEncode(_result(
      status: 'failed', trace: http.trace, stage: failedStage,
      errorCategory: _failureCategory(error),
      cookieCount: jar.all().length,
      cookieNames: jar.all().map((cookie) => cookie.name).toSet().toList()..sort(),
    )));
  } finally {
    http.close();
  }
}
