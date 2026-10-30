import XCTest
@testable import NativeRunner

final class StabilityTests: XCTestCase {
    func testSessionMigrationAndFailedWritesRetainOriginal() throws {
        let name = "stability-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let original = Data("[]".utf8)
        defaults.set(original, forKey: "native.cookies.v1")
        var data: Data?
        var fail = true
        let vault = NativeSessionVault(read: { data }, write: { value in
            if fail { throw NativeError.protocolFailure("synthetic failure") }; data = value
        }, remove: { data = nil })
        XCTAssertThrowsError(try vault.restore(from: defaults))
        XCTAssertEqual(defaults.data(forKey: "native.cookies.v1"), original)
        fail = false
        XCTAssertTrue(try vault.restore(from: defaults).isEmpty)
        XCTAssertNil(defaults.data(forKey: "native.cookies.v1"))
        XCTAssertEqual(data, original)
        try vault.clear(defaults: defaults)
        data = original // an inaccessible older item must not resurrect after logout
        XCTAssertTrue(try vault.restore(from: defaults).isEmpty)
        XCTAssertTrue(defaults.bool(forKey: "native.session.revoked"))
    }
    @MainActor func testClockCrossesBeijingMidnightWithoutNetwork() {
        var date = Beijing.parse("2026-10-27T23:59:59+08:00")!
        let clock = NativeClock(read: { date })
        XCTAssertEqual(Beijing.key(clock.now), "2026-10-27")
        date.addTimeInterval(2); clock.refresh()
        XCTAssertEqual(Beijing.key(clock.now), "2026-10-28")
        clock.setActive(false)
        date.addTimeInterval(86400); clock.setActive(true)
        XCTAssertEqual(Beijing.key(clock.now), "2026-10-29")
        clock.setActive(false)
    }
}

extension NativeSessionVault {
    static func testing() -> NativeSessionVault {
        var data: Data?
        return NativeSessionVault(read: { data }, write: { data = $0 }, remove: { data = nil })
    }
}
