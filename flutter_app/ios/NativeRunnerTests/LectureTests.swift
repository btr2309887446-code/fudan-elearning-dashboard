import XCTest
import Darwin
@testable import NativeRunner

private final class LectureFixtureProtocol: URLProtocol {
    static var responses: [String: Data] = [:]
    static var offline = false
    static var calls: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls.append(request.url!.path)
        guard !Self.offline, let data = Self.responses[request.url!.path] else { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
final class LectureTests: XCTestCase {
    struct Fixture: Decodable {
        struct LargeShard: Decodable { var bytes: Data; var hash: String; var decodedBytes: Int }
        var password: String; var index: Data; var shard: Data; var hash: String; var largeShards: [LargeShard]
    }
    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "lecture-fixture", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
    func testEncryptedContractAndLargeIndex() throws {
        let f = try fixture()
        XCTAssertEqual(LectureCrypto.derive(student: "fictional-student", password: "fictional-password"), f.password)
        XCTAssertEqual(try LectureManifest.decode(f.index, password: f.password).shards.first?.sha256, f.hash)
        XCTAssertThrowsError(try LectureManifest.decode(f.index, password: "incorrect"))
        let engine = LectureEngine(source: "source")
        try engine.load("fixture", data: f.shard, password: f.password, hash: f.hash)
        XCTAssertEqual(engine.items.count, 5000)
        XCTAssertEqual(engine.courses.first?.terms, ["2026秋"])
        let reference = LectureReference(sourceID: "source", courseID: "101", lectureID: "lecture-0")
        let body = try engine.body(reference)
        XCTAssertTrue(body.summary.contains("$$x^2$$")); XCTAssertEqual(body.transcript, "虚构转写")
        XCTAssertTrue(body.pages.first?.contains("虚构 PPT") == true)
        var corrupt = f.shard; corrupt[30] ^= 1
        XCTAssertThrowsError(try engine.load("fixture", data: corrupt, password: f.password, hash: f.hash))
        XCTAssertEqual(engine.items.count, 5000)
        XCTAssertEqual(LectureReference.parse(reference.key), reference)
        XCTAssertNil(LectureReference.parse("[\"a\"]"))
        XCTAssertEqual(LectureActions.extract(body.summary), ["阅读教材并整理问题。"])
        XCTAssertTrue(LectureActions.extract("```\n- 作业是假代码\n```").isEmpty)
        XCTAssertNotNil(Bundle.main.url(forResource: "lecture-reader", withExtension: "html"))
    }
    func testLazyIndexBudgetAndOfflineBody() throws {
        let f = try fixture(), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent(f.hash + ".enc"); try f.shard.write(to: url)
        let build = LectureEngine(source: "source", budget: 1024)
        try build.loadFile("fixture", url: url, password: f.password, hash: f.hash)
        XCTAssertEqual(build.residentBytes, 0)
        let restored = LectureEngine(source: "source", budget: 1024)
        try restored.loadFile("fixture", url: url, password: f.password, hash: f.hash)
        XCTAssertEqual(restored.items.count, 5000); XCTAssertEqual(restored.residentDatabases, 0)
        let body = try restored.body(restored.items[0].reference)
        XCTAssertFalse(body.summary.isEmpty); XCTAssertEqual(restored.residentDatabases, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("index").path))
    }
    func testMultipleLargeShardsEvictWithinDefaultBudget() throws {
        let f = try fixture(), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = LectureEngine(source: "large")
        for (n, shard) in f.largeShards.enumerated() {
            let url = folder.appendingPathComponent("\(n).enc"); try shard.bytes.write(to: url)
            try engine.loadFile("\(n)", url: url, password: f.password, hash: shard.hash)
            XCTAssertEqual(engine.residentDatabases, 0)
        }
        var metrics: [[String: Any]] = []
        for n in [0, 1, 2, 0] {
            let start = Date()
            let body = try engine.body(LectureReference(sourceID: "large", courseID: "large-\(n)", lectureID: "0"))
            XCTAssertGreaterThan(body.transcript.count, 1_000_000)
            XCTAssertLessThanOrEqual(engine.residentBytes, 64 * 1024 * 1024)
            XCTAssertEqual(engine.residentDatabases, 1)
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            metrics.append(["shard": n, "milliseconds": Date().timeIntervalSince(start) * 1000,
                            "residentDatabaseBytes": engine.residentBytes, "processMaxRSSBytes": usage.ru_maxrss])
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: metrics, options: .prettyPrinted), uniformTypeIdentifier: "public.json")
        attachment.name = "lecture-cache-budget-and-timings"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testSourceValidationAndLegacyTasks() throws {
        XCTAssertEqual(try LectureService.source(repository: "https://github.com/Owner/Repo.git/", branch: "data").0, "Owner/Repo")
        XCTAssertThrowsError(try LectureService.source(repository: "../Repo", branch: "data"))
        XCTAssertThrowsError(try LectureService.source(repository: "Owner/Repo", branch: "../main"))
        var task = PersonalTaskSeries(title: "阅读", notes: "原文")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any])
        object.removeValue(forKey: "lectureSource")
        XCTAssertNil(try JSONDecoder().decode(PersonalTaskSeries.self, from: JSONSerialization.data(withJSONObject: object)).lectureSource)
        task.lectureSource = LectureTaskSource(reference: LectureReference(sourceID: "s", courseID: "c", lectureID: "l"), title: "第一讲")
        let restored = try JSONDecoder().decode(PersonalTaskSeries.self, from: JSONEncoder().encode(task))
        XCTAssertEqual(restored.lectureSource, task.lectureSource); XCTAssertNil(restored.dueAt)
    }
    func testServiceOfflineIsolationReadAndFailedWrite() async throws {
        let f = try fixture(), prefix = "/repos/Owner/Repo/", hash = String(repeating: "a", count: 40), tree = String(repeating: "b", count: 40), index = String(repeating: "c", count: 40), shard = String(repeating: "d", count: 40)
        LectureFixtureProtocol.offline = false
        LectureFixtureProtocol.responses = [
            prefix + "git/ref/heads/data": Data("{\"object\":{\"sha\":\"\(hash)\"}}".utf8),
            prefix + "git/commits/\(hash)": Data("{\"tree\":{\"sha\":\"\(tree)\"}}".utf8),
            prefix + "git/trees/\(tree)": try JSONSerialization.data(withJSONObject: ["tree": [["path":"data/icourse-index.enc","sha":index,"type":"blob"],["path":"data/shards/shard-hot-0000.db.gz.enc","sha":shard,"type":"blob"]]]),
            prefix + "git/blobs/\(index)": f.index, prefix + "git/blobs/\(shard)": f.shard]
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [LectureFixtureProtocol.self]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); LectureFixtureProtocol.offline = false }
        let service = LectureService(account: 1, root: root, configuration: config)
        _ = try await service.restore()
        let input = LectureCredentials(repository: "Owner/Repo", branch: "data", student: "fictional-student", password: "fictional-password", token: "", remember: false)
        let connected = try await service.connect(input)
        XCTAssertFalse(connected.locked); XCTAssertTrue(connected.bindings.isEmpty)
        _ = try await service.bind("101", to: 4)
        let page = try await service.page(course: 4)
        XCTAssertEqual(page.total, 5000); XCTAssertEqual(page.items.count, 50)
        let exact = try await service.page(course: 4, search: "课次 4999"); XCTAssertEqual(exact.items.count, 1)
        let body = try await service.body(page.items[0].reference, course: 4)
        try await service.read(body.item.reference, course: 4, hash: body.item.summaryHash)
        let read = try await service.page(course: 4); XCTAssertTrue(read.items[0].read)
        LectureFixtureProtocol.calls = []
        let healthy = try await service.sync(); XCTAssertNil(healthy.error)
        XCTAssertEqual(LectureFixtureProtocol.calls, [prefix + "git/ref/heads/data"])
        LectureFixtureProtocol.offline = true
        let failed = try await service.sync(); XCTAssertNotNil(failed.error)
        let offline = try await service.body(body.item.reference, course: 4); XCTAssertEqual(offline.summary, body.summary)
        let other = LectureService(account: 2, root: root, configuration: config)
        let separate = try await other.restore(); XCTAssertFalse(separate.configured)
        let reopened = LectureService(account: 1, root: root, configuration: config)
        let locked = try await reopened.restore(); XCTAssertTrue(locked.locked)
        let unlocked = try await reopened.connect(input); XCTAssertFalse(unlocked.locked); XCTAssertNotNil(unlocked.error)
        let source = try LectureService.source(repository: "Owner/Repo", branch: "data").2
        let indexFile = root.appendingPathComponent("1/\(source)/\(LectureCrypto.hash(f.index)).enc")
        try Data("synthetic corruption".utf8).write(to: indexFile)
        let damaged = LectureService(account: 1, root: root, configuration: config)
        _ = try await damaged.restore()
        let recovered = try await damaged.connect(input); XCTAssertFalse(recovered.locked)
        let preserved = try await damaged.body(body.item.reference, course: 4); XCTAssertEqual(preserved.summary, body.summary)
        LectureFixtureProtocol.offline = false
        let repaired = try await damaged.sync(); XCTAssertNil(repaired.error)
        XCTAssertEqual(LectureCrypto.hash(try Data(contentsOf: indexFile)), LectureCrypto.hash(f.index))
        await damaged.cancel()
        let connection = root.appendingPathComponent("1/connection.json")
        try FileManager.default.removeItem(at: connection); try FileManager.default.createDirectory(at: connection, withIntermediateDirectories: true)
        do { _ = try await reopened.bind("101", to: 8); XCTFail("failed writes must reject") } catch { }
        let unchanged = await reopened.state(); XCTAssertEqual(unchanged.bindings["101"], 4)
        await service.cancel(); await reopened.cancel(); await other.cancel()
    }
    func testLectureChangesBaselineAndFingerprintOnly() {
        let resource = ChangeResource(id: LectureReference(sourceID: "s", courseID: "c", lectureID: "l").key, kind: .lecture, courseID: 4, courseName: "示例课程", title: "第一讲", fields: ["摘要": String(repeating: "a", count: 64)])
        let initial = ChangeBatch(key: "4:lecture:s:c:generation", resources: [resource])
        var state = NativeChangeTracker.applying([initial], to: NativeLocalAccount(), now: Date())
        XCTAssertTrue(state.events.isEmpty)
        var changed = resource; changed.fields["摘要"] = String(repeating: "b", count: 64)
        let update = ChangeBatch(key: initial.key, resources: [changed])
        state = NativeChangeTracker.applying([update, update], to: state, now: Date())
        XCTAssertEqual(state.events.count, 1); XCTAssertTrue(state.events[0].resource.body.isEmpty)
        state = NativeChangeTracker.applying([ChangeBatch(key: "new-binding", resources: [changed])], to: state, now: Date())
        XCTAssertEqual(state.events.count, 1)
    }
}
