/// 交叉验证用的小工具：读取公钥文件，加密给定的口令，输出 base64 密文。
///
/// 由 recon/test-dart-rsa-interop.mjs 驱动：
/// Node 生成密钥对 → Dart 加密 → Node 解密，以此证明 Dart 的
/// RSA/PKCS#1 v1.5 实现与服务器期望的方式完全一致。
///
///   dart run tool/rsa_probe.dart <公钥文件> <待加密文本>

library;

import 'dart:io';

import 'package:fudan_elearning/core/rsa.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('用法: dart run tool/rsa_probe.dart <公钥文件> <待加密文本>');
    exit(2);
  }

  final publicKeyBase64 = File(args[0]).readAsStringSync().trim();
  final plaintext = args[1];

  final bits = rsaModulusBits(publicKeyBase64);
  final cipher = rsaPkcs1Encrypt(plaintext, publicKeyBase64);

  stdout.writeln('BITS=$bits');
  stdout.writeln('CIPHER=$cipher');
}
