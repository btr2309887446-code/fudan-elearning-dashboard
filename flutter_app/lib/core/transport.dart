/// 传输层的平台工厂。
///
/// 条件导入：有 dart:io 的平台（iOS/Android/桌面）用真实实现，
/// web 上退化成一个会提出明确错误的桩——界面验证只需要能编译能渲染。

library;

import 'http.dart';
import 'transport_stub.dart' if (dart.library.io) 'transport_io.dart' as impl;

HttpTransport createDefaultTransport() => impl.createTransport();
