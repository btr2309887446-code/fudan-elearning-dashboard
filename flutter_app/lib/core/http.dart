/// HTTP 的类型与协议逻辑（**纯 Dart，不含 dart:io**）。
///
/// 分成两层：
///  - [HttpTransport]：只负责把字节发出去，各平台各自实现；
///  - [HttpClientLite]：Cookie 与重定向逻辑，纯 Dart，可注入假传输层来测试。
///
/// 这样既能用假传输层完整测试登录链，也让界面层可以在 web 上编译
/// （web 没有 dart:io，但界面验证只需要能跑起来）。

library;

import 'dart:async';
import 'dart:convert';

import 'cookies.dart';
import 'transport.dart';

const String defaultUserAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

/// 传输层返回的原始响应。
class RawResponse {
  const RawResponse({
    required this.statusCode,
    required this.uri,
    required this.headers,
    required this.setCookies,
    required this.body,
  });

  final int statusCode;
  final Uri uri;
  final Map<String, List<String>> headers;

  /// 逐个 Set-Cookie 的值，**不合并**——Cookie 值里可能含逗号。
  final List<String> setCookies;
  final String body;
}

/// 只发字节，不管 Cookie 与重定向。
abstract class HttpTransport {
  Future<RawResponse> send(
    String url, {
    required String method,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  });

  void close();
}

class HttpResponseData {
  HttpResponseData({
    required this.statusCode,
    required this.uri,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Uri uri;
  final Map<String, List<String>> headers;
  final String body;

  String? header(String name) {
    final key = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == key && entry.value.isNotEmpty) {
        return entry.value.first;
      }
    }
    return null;
  }

  List<String> headerValues(String name) {
    final key = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == key) return entry.value;
    }
    return const [];
  }
}

class HttpTrace {
  HttpTrace(this.method, this.url, this.statusCode, this.location, this.setCookies);

  final String method;
  final String url;
  final int statusCode;
  final String? location;
  final List<String> setCookies;

  @override
  String toString() {
    final loc = location == null ? '' : ' -> $location';
    return '$method $url [$statusCode]$loc';
  }
}

class HttpRequestOptions {
  const HttpRequestOptions({
    this.method = 'GET',
    this.headers = const {},
    this.body,
    this.follow = true,
    this.maxRedirects = 12,
    this.timeout = const Duration(seconds: 20),
  });

  final String method;
  final Map<String, String> headers;
  final String? body;
  final bool follow;
  final int maxRedirects;
  final Duration timeout;

  HttpRequestOptions copyWith({String? method, String? body}) => HttpRequestOptions(
        method: method ?? this.method,
        headers: headers,
        body: body,
        follow: follow,
        maxRedirects: maxRedirects,
        timeout: timeout,
      );
}

class HttpClientLite {
  HttpClientLite({CookieJar? jar, HttpTransport? transport, this.userAgent = defaultUserAgent})
      : jar = jar ?? CookieJar(),
        _transport = transport;

  final CookieJar jar;
  final String userAgent;
  final List<HttpTrace> trace = [];

  HttpTransport? _transport;

  /// 传输层按需创建，便于在 web 上把错误推迟到真正发起请求时。
  HttpTransport get transport => _transport ??= createDefaultTransport();

  static const _redirectCodes = {301, 302, 303, 307, 308};

  void close() {
    _transport?.close();
    _transport = null;
  }

  /// 单次请求，不跟随重定向。
  Future<HttpResponseData> raw(String url, [HttpRequestOptions options = const HttpRequestOptions()]) async {
    final method = options.method.toUpperCase();
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      ...options.headers,
    };
    final cookie = jar.cookieHeader(url);
    if (cookie != null) headers['Cookie'] = cookie;

    final response = await transport.send(
      url,
      method: method,
      headers: headers,
      body: options.body,
      timeout: options.timeout,
    );

    if (response.setCookies.isNotEmpty) {
      jar.setFromResponse(response.uri.toString(), response.setCookies);
    }

    trace.add(HttpTrace(
      method,
      url,
      response.statusCode,
      response.headers.entries
          .where((e) => e.key.toLowerCase() == 'location')
          .expand((e) => e.value)
          .firstOrNull,
      response.setCookies,
    ));

    return HttpResponseData(
      statusCode: response.statusCode,
      uri: response.uri,
      headers: response.headers,
      body: response.body,
    );
  }

  /// 请求并跟随重定向。303（以及 POST 后的 301/302）会退回 GET。
  Future<HttpResponseData> request(String url, [HttpRequestOptions options = const HttpRequestOptions()]) async {
    var currentUrl = url;
    var method = options.method.toUpperCase();
    String? body = options.body;

    var response = await raw(currentUrl, options.copyWith(method: method, body: body));

    var hops = 0;
    while (_redirectCodes.contains(response.statusCode) && options.follow && hops < options.maxRedirects) {
      final location = response.header('location');
      if (location == null) break;

      final next = Uri.parse(currentUrl).resolve(location).toString();

      // 只有 307/308 保留方法与请求体，其余按浏览器行为降级为 GET。
      if (response.statusCode != 307 && response.statusCode != 308) {
        if (method != 'GET' && method != 'HEAD') {
          method = 'GET';
          body = null;
        }
      }

      currentUrl = next;
      hops++;
      response = await raw(currentUrl, options.copyWith(method: method, body: body));
    }
    return response;
  }

  /// POST 一个 JSON 请求体。
  Future<HttpResponseData> postJson(String url, Object payload,
          [HttpRequestOptions options = const HttpRequestOptions()]) =>
      request(
        url,
        HttpRequestOptions(
          method: 'POST',
          body: jsonEncode(payload),
          headers: {
            'Content-Type': 'application/json;charset=UTF-8',
            'Accept': 'application/json, text/plain, */*',
            ...options.headers,
          },
          follow: options.follow,
          maxRedirects: options.maxRedirects,
          timeout: options.timeout,
        ),
      );

  /// POST 一个 application/x-www-form-urlencoded 请求体。
  Future<HttpResponseData> postForm(String url, Map<String, String> fields,
      [HttpRequestOptions options = const HttpRequestOptions()]) {
    final origin = Uri.parse(url).origin;
    return request(
      url,
      HttpRequestOptions(
        method: 'POST',
        body: fields.entries
            .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
            .join('&'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Origin': origin,
          'Referer': '$origin/',
          ...options.headers,
        },
        follow: options.follow,
        maxRedirects: options.maxRedirects,
        timeout: options.timeout,
      ),
    );
  }
}

class HttpError implements Exception {
  HttpError(this.message);
  final String message;

  @override
  String toString() => message;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
