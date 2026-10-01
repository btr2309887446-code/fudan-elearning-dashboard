/// 基于 `dart:io` 的传输层实现。
///
/// 用 `HttpClient` 而不是 `package:http`：后者把同名响应头合并成一个字符串，
/// `Set-Cookie` 会因此丢失边界，而整条登录链依赖逐跳精确收集 Cookie。

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'http.dart';

HttpTransport createTransport() => IoHttpTransport();

class IoHttpTransport implements HttpTransport {
  @override
  Future<RawResponse> send(
    String url, {
    required String method,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    final uri = Uri.parse(url);
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      // 手动跟随重定向：每一跳都要收集 Cookie。
      request.followRedirects = false;
      headers.forEach(request.headers.set);

      final bytes = body == null ? null : utf8.encode(body);
      if (bytes != null) {
        request.headers.contentLength = bytes.length;
        request.add(bytes);
      }

      final response = await request.close().timeout(timeout);

      // dart:io 把同名头存成 List，forEach 能原样拿到每一个 Set-Cookie。
      final setCookies = _headerValues(response.headers, HttpHeaders.setCookieHeader);

      final raw = <int>[];
      await for (final chunk in response) {
        raw.addAll(chunk);
      }

      final responseHeaders = <String, List<String>>{};
      response.headers.forEach((name, values) => responseHeaders[name] = values);

      return RawResponse(
        statusCode: response.statusCode,
        uri: uri,
        headers: responseHeaders,
        setCookies: setCookies,
        // Canvas 与认证服务器都是 UTF-8；容错解码避免个别坏字节让整次请求失败。
        body: utf8.decode(raw, allowMalformed: true),
      );
    } on TimeoutException {
      throw HttpError('请求超时：$method $url');
    } on SocketException catch (e) {
      throw HttpError('网络不可达：${e.message}（$url）');
    } on HandshakeException catch (e) {
      throw HttpError('TLS 握手失败：${e.message}（$url）');
    } finally {
      client.close(force: true);
    }
  }

  @override
  void close() {
    // 每次请求都自建并关闭客户端，这里无需额外清理。
  }

  static List<String> _headerValues(HttpHeaders headers, String name) {
    final wanted = name.toLowerCase();
    var found = const <String>[];
    headers.forEach((key, values) {
      if (key.toLowerCase() == wanted) found = values;
    });
    return found;
  }
}
