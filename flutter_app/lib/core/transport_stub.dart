/// web 上的传输层桩。
///
/// 本项目面向 iOS/Android/桌面，web 只用来做界面渲染验证，
/// 因此这里不做真实网络请求，但会给出明确的错误而不是静默失败。

library;

import 'http.dart';

HttpTransport createTransport() => WebStubTransport();

class WebStubTransport implements HttpTransport {
  @override
  Future<RawResponse> send(
    String url, {
    required String method,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    throw HttpError(
      '当前运行环境（web）不支持直接访问校园网络接口。'
      '请在 iOS / Android / 桌面上运行本应用。',
    );
  }

  @override
  void close() {}
}
