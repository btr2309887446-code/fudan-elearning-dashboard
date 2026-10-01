/// 各平台的存储实现。
///
/// `core` 只依赖 [KeyValueStore] 这个抽象，
/// 这样纯逻辑可以在测试里用内存实现跑，不需要任何平台通道。

library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/session.dart';

/// 基于 shared_preferences 的实现。
///
/// 只用来放会话 Cookie、缓存快照和界面偏好——**不放密码**。
class PrefsStore implements KeyValueStore {
  PrefsStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<PrefsStore> open() async =>
      PrefsStore(await SharedPreferences.getInstance());

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async => _prefs.setString(key, value);

  @override
  Future<void> delete(String key) async => _prefs.remove(key);
}

/// 密码走系统钥匙串（iOS Keychain / Android Keystore）。
///
/// 与桌面端一致：只有用户显式勾选「记住密码」时才写入。
class SecretStore implements SecretStoreLike {
  SecretStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _storage;

  static const _passwordKey = 'elearning.password';

  @override
  Future<String?> readPassword() async {
    try {
      return await _storage.read(key: _passwordKey);
    } catch (_) {
      // 钥匙串不可用（例如桌面调试环境）时按未保存处理。
      return null;
    }
  }

  @override
  Future<void> writePassword(String value) async {
    try {
      await _storage.write(key: _passwordKey, value: value);
    } catch (_) {
      // 写不进去也不该让登录失败。
    }
  }

  @override
  Future<void> deletePassword() async {
    try {
      await _storage.delete(key: _passwordKey);
    } catch (_) {
      // 忽略。
    }
  }
}
