/// 纯 Dart 的 RSA/ECB/PKCS#1 v1.5 加密。
///
/// 为什么不能用平台自带的加密 API：
///  - Web Crypto 只提供 RSA-OAEP，**没有** PKCS#1 v1.5 加密，服务器会拒绝；
///  - iOS 的 Security.framework 也不直接暴露 PKCS#1 v1.5 加密接口。
/// 所以用 pointycastle 在 Dart 层实现，跨平台一致。
///
/// 正确性由 `test/rsa_interop_test.dart` 交叉验证：
/// Dart 加密 → Node 的 node:crypto 解密（后者已被证明与学校服务器一致）。

library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/export.dart' show PublicKeyParameter;

/// 用 SPKI(base64) 公钥加密，返回 base64 密文。
String rsaPkcs1Encrypt(String password, String spkiBase64) {
  final publicKey = parseSpkiPublicKey(spkiBase64);

  // PKCS1Encoding 默认做 block type 2 的 PKCS#1 v1.5 填充，正是学校要的方式。
  final engine = PKCS1Encoding(RSAEngine())
    ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

  final input = Uint8List.fromList(utf8.encode(password));
  final output = engine.process(input);
  return base64.encode(output);
}

/// 解析 X.509 SubjectPublicKeyInfo（DER 的 base64）。
///
/// 结构：SEQUENCE { AlgorithmIdentifier, BIT STRING { SEQUENCE { n, e } } }
RSAPublicKey parseSpkiPublicKey(String spkiBase64) {
  final der = base64.decode(spkiBase64.replaceAll(RegExp(r'\s+'), ''));
  final top = ASN1Parser(Uint8List.fromList(der)).nextObject() as ASN1Sequence;
  final elements = top.elements;
  if (elements == null || elements.length < 2) {
    throw const FormatException('公钥结构异常：缺少 AlgorithmIdentifier 或 BIT STRING');
  }

  final bitString = elements[1];
  if (bitString is! ASN1BitString) {
    throw const FormatException('公钥结构异常：第二项不是 BIT STRING');
  }
  final innerBytes = bitString.stringValues;
  if (innerBytes == null) {
    throw const FormatException('公钥结构异常：BIT STRING 为空');
  }

  final inner = ASN1Parser(Uint8List.fromList(innerBytes)).nextObject() as ASN1Sequence;
  final parts = inner.elements;
  if (parts == null || parts.length < 2) {
    throw const FormatException('公钥结构异常：缺少模数或指数');
  }

  final modulus = (parts[0] as ASN1Integer).integer;
  final exponent = (parts[1] as ASN1Integer).integer;
  if (modulus == null || exponent == null) {
    throw const FormatException('公钥结构异常：模数或指数解析失败');
  }

  return RSAPublicKey(modulus, exponent);
}

/// 模数位数，便于自检时核对密文长度。
int rsaModulusBits(String spkiBase64) =>
    parseSpkiPublicKey(spkiBase64).modulus?.bitLength ?? 0;
