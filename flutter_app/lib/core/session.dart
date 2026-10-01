/// 存放会话与偏好的抽象。
///
/// `core` 不直接碰文件系统或 shared_preferences——
/// 那样会让纯逻辑无法在测试里跑，也把移动端和桌面的差异渗进来。
/// 各平台提供自己的实现（见 lib/platform/）。

library;

abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// 放在内存里的实现，测试用。
class MemoryStore implements KeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

/// 密码存储的抽象（真机上是系统钥匙串）。
///
/// 放在 core 里而不是 platform 里，是为了让状态层不必依赖具体平台实现。
abstract class SecretStoreLike {
  Future<String?> readPassword();
  Future<void> writePassword(String value);
  Future<void> deletePassword();
}

/// 会话与偏好的读写封装。
///
/// 只存 Cookie，**从不存密码**——密码由平台的安全存储单独负责。
class SessionRepository {
  SessionRepository(this.store);

  final KeyValueStore store;

  static const _sessionKey = 'elearning.session';
  static const _snapshotKey = 'elearning.snapshot';
  static const _prefsKey = 'elearning.prefs';

  Future<String?> readSession() => store.read(_sessionKey);
  Future<void> writeSession(String json) => store.write(_sessionKey, json);
  Future<void> clearSession() => store.delete(_sessionKey);

  Future<String?> readSnapshot() => store.read(_snapshotKey);
  Future<void> writeSnapshot(String json) => store.write(_snapshotKey, json);
  Future<void> clearSnapshot() => store.delete(_snapshotKey);

  Future<String?> readPrefs() => store.read(_prefsKey);
  Future<void> writePrefs(String json) => store.write(_prefsKey, json);

  /// 出错恢复用：把会话和缓存一并清掉。
  Future<void> clearAll() async {
    await clearSession();
    await clearSnapshot();
  }
}
