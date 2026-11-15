import Foundation
import Security

struct NativeSessionVault {
    var read: () throws -> Data?
    var write: (Data) throws -> Void
    var remove: () throws -> Void
    static let live = NativeSessionVault(read: {
        var query = key
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw failure(status) }
        return result as? Data
    }, write: { data in
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(key.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure(status) }
    }, remove: {
        let status = SecItemDelete(key as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    })
    private static var key: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "elearning") + ".session", kSecAttrAccount as String: "native.cookies.v2"] }
    private static func failure(_ status: OSStatus) -> NativeError { .protocolFailure("系统安全存储暂不可用（\(status)），新登录信息仅保留到本次退出。") }
    func restore(from defaults: UserDefaults) throws -> [NativeCookie] {
        if defaults.bool(forKey: "native.session.revoked") { return [] }
        if let secure = try read() {
            let cookies = try JSONDecoder().decode([NativeCookie].self, from: secure)
            defaults.removeObject(forKey: "native.cookies.v1")
            return cookies
        }
        guard let legacy = defaults.data(forKey: "native.cookies.v1") else { return [] }
        let cookies = try JSONDecoder().decode([NativeCookie].self, from: legacy)
        try save(cookies, defaults: defaults)
        return cookies
    }
    func save(_ cookies: [NativeCookie], defaults: UserDefaults) throws {
        let data = try JSONEncoder().encode(cookies)
        try write(data)
        guard try read() == data else { throw NativeError.protocolFailure("登录信息回读验证失败，原数据已保留。") }
        defaults.removeObject(forKey: "native.cookies.v1")
        defaults.removeObject(forKey: "native.session.revoked")
    }
    func clear(defaults: UserDefaults) throws {
        // Tombstone prevents inaccessible keychain items from restoring an explicitly logged-out session.
        defaults.set(true, forKey: "native.session.revoked")
        defaults.removeObject(forKey: "native.cookies.v1")
        try remove()
    }
}
