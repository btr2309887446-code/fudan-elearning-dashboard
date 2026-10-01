/// 可翻译成用户可读中文的错误类型。
///
/// 复旦认证服务器几乎总是返回 HTTP 200 + 一段中文 `message`，
/// 所以判定依据是文本而不是状态码。

library;

import 'dart:convert';

enum LoginFailureKind {
  credentialsInvalid,
  captchaRequired,
  twoFactorRequired,
  accountLocked,
  maintenance,
  network,
  protocol,
  sessionExpired,
}

class LoginException implements Exception {
  LoginException(this.kind, this.message, [this.detail]);

  final LoginFailureKind kind;
  final String message;
  final String? detail;

  @override
  String toString() => message;
}

class CanvasException implements Exception {
  CanvasException(this.statusCode, this.url, this.body);

  final int statusCode;
  final String url;
  final String body;

  /// 会话失效，需要重新登录。
  bool get isAuthFailure => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'Canvas API $statusCode $url';
}

/// 把 Canvas 的错误响应变成一句人话。
String describeCanvasError(Object error) {
  if (error is CanvasException) {
    if (error.isAuthFailure) return '登录状态已失效，请重新登录。';
    try {
      final decoded = jsonDecode(error.body);
      if (decoded is Map) {
        final errors = decoded['errors'];
        if (errors is List && errors.isNotEmpty && errors.first is Map) {
          final msg = (errors.first as Map)['message'];
          if (msg is String && msg.isNotEmpty) {
            return 'Canvas 返回 ${error.statusCode}：$msg';
          }
        }
        final msg = decoded['message'];
        if (msg is String && msg.isNotEmpty) {
          return 'Canvas 返回 ${error.statusCode}：$msg';
        }
      }
    } on FormatException {
      // 响应体不是 JSON。
    }
    return 'Canvas 返回 ${error.statusCode}。';
  }
  if (error is LoginException) return error.message;
  return error.toString();
}
