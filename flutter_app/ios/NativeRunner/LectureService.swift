import Foundation
import Security

struct LectureConnection: Sendable {
    var repository = "btr2309887446-code/Fudan_iCourse_Subscriber"
    var branch = "data"
    var sourceID = ""
    var configured = false
    var locked = true
    var remembered = false
    var courses: [LectureCourse] = []
    var bindings: [String: Int] = [:]
    var lastSynced: Date?
    var error: String?
}
struct LectureCredentials: Sendable {
    var repository: String; var branch: String; var student: String; var password: String; var token: String; var remember: Bool
}
private struct LectureSaved: Codable {
    var version = 1
    var repository: String; var branch: String; var sourceID: String
    var configured = true
    var secretID: String?
    var bindings: [String: Int] = [:]
    var generations: [String: String] = [:]
    var reads: [String: String] = [:]
    var shards: [String: LectureManifest.Shard] = [:]
    var indexHash: String?
    var lastSynced: Date?
}
private struct LectureSecret: Codable { var password: String; var token: String }
enum LectureKeychain {
    private static var service: String { (Bundle.main.bundleIdentifier ?? "elearning") + ".classroom" }
    static func write(_ value: Data, id: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id]
        var item = query
        item[kSecValueData as String] = value
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw NativeError.protocolFailure("无法保存解锁信息到钥匙串（\(status)），请关闭记住选项后重试。") }
    }
    static func read(_ id: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess else { return nil }
        return value as? Data
    }
    static func remove(_ id: String?) {
        guard let id else { return }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id] as CFDictionary)
    }
}

actor LectureService {
    let account: Int
    private let root: URL
    private let session: URLSession
    private var cancelled = false
    private var busy = false
    private var saved: LectureSaved?
    private var secret: LectureSecret?
    private var engine: LectureEngine?
    private var error: String?
    private var isDemo = false
    init(account: Int, root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Classroom", isDirectory: true), configuration: URLSessionConfiguration = .ephemeral) {
        self.account = account; self.root = root.appendingPathComponent(String(account), isDirectory: true)
        configuration.timeoutIntervalForRequest = 45; configuration.timeoutIntervalForResource = 180
        session = URLSession(configuration: configuration)
    }
    func cancel() { cancelled = true; session.invalidateAndCancel(); secret = nil; engine = nil }
    private func check() throws { if cancelled || Task.isCancelled { throw CancellationError() } }
    static func source(repository: String, branch: String) throws -> (String, String, String) {
        var repo = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        if repo.hasPrefix("https://github.com/") { repo = String(repo.dropFirst(19)) }
        if repo.hasSuffix("/") { repo.removeLast() }; if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        let branch = branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "data" : branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard repo.range(of: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", options: .regularExpression) != nil, !repo.contains(".."),
              branch.count <= 200, branch.range(of: "^[A-Za-z0-9_./-]+$", options: .regularExpression) != nil, !branch.contains(".."), !branch.hasPrefix("/"), !branch.hasSuffix("/") else { throw NativeError.protocolFailure("请输入有效的 GitHub 用户名/仓库名和分支。") }
        return (repo, branch, String(LectureCrypto.hash(Data("\(repo.lowercased())\n\(branch)".utf8)).prefix(32)))
    }
    private func folder(_ value: LectureSaved) -> URL { root.appendingPathComponent(value.sourceID, isDirectory: true) }
    private func blob(_ value: LectureSaved, _ hash: String) throws -> URL {
        guard hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw NativeError.protocolFailure("笔记缓存索引损坏。") }
        return folder(value).appendingPathComponent(hash + ".enc")
    }
    private func write(_ data: Data, to url: URL) throws {
        try check(); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        var target = url; var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true; try? target.setResourceValues(attributes)
    }
    private func persist(_ value: LectureSaved) throws {
        if isDemo { return }
        // A single authoritative file makes binding/read-state commits atomic.
        try write(JSONEncoder().encode(value), to: root.appendingPathComponent("connection.json"))
    }
    func state() -> LectureConnection {
        guard let value = saved else { return LectureConnection(error: error) }
        return LectureConnection(repository: value.repository, branch: value.branch, sourceID: value.sourceID,
            configured: value.configured, locked: secret == nil, remembered: value.secretID != nil,
            courses: engine?.courses ?? [], bindings: value.bindings, lastSynced: value.lastSynced, error: error)
    }
    func restore(demo: [NativeCourse]? = nil) throws -> LectureConnection {
        try check()
        if let demo {
            isDemo = true
            saved = LectureSaved(repository: "demo/classroom", branch: "data", sourceID: "demo")
            for c in demo { saved?.bindings["demo-\(c.id)"] = c.id; saved?.generations["demo-\(c.id)"] = "demo" }
            secret = LectureSecret(password: "demo", token: ""); engine = LectureEngine(source: "demo"); engine?.demo(demo)
            return state()
        }
        let file = root.appendingPathComponent("connection.json")
        if !FileManager.default.fileExists(atPath: file.path) { return state() }
        let value = try JSONDecoder().decode(LectureSaved.self, from: Data(contentsOf: file))
        guard value.version == 1, try Self.source(repository: value.repository, branch: value.branch).2 == value.sourceID else { throw NativeError.protocolFailure("笔记配置版本不支持，原文件已保留。") }
        saved = value
        if value.configured, let id = value.secretID, let data = LectureKeychain.read(id), let key = try? JSONDecoder().decode(LectureSecret.self, from: data) {
            do { let cached = try hydrate(value, key: key); secret = key; engine = cached }
            catch { self.error = "请重新解锁课堂笔记：\(error.localizedDescription)" }
        }
        return state()
    }
    private func hydrate(_ value: LectureSaved, key: LectureSecret) throws -> LectureEngine {
        guard let indexHash = value.indexHash else { throw NativeError.protocolFailure("暂无本地笔记缓存，请联网同步。") }
        _ = try LectureManifest.decode(Data(contentsOf: blob(value, indexHash)), password: key.password)
        let result = LectureEngine(source: value.sourceID)
        var failures = 0
        for shard in value.shards.values.sorted(by: { $0.name < $1.name }) {
            try check()
            do { try result.load(shard.name, data: Data(contentsOf: blob(value, shard.sha256)), password: key.password, hash: shard.sha256) }
            catch { failures += 1 }
        }
        if failures > 0 { error = "\(failures) 个缓存分片无法读取，请同步重试。" }
        return result
    }
    func connect(_ input: LectureCredentials) async throws -> LectureConnection {
        try check(); guard !busy else { throw NativeError.protocolFailure("正在同步笔记，请稍候。") }
        if isDemo { return state() }
        busy = true; defer { busy = false }
        let source = try Self.source(repository: input.repository, branch: input.branch)
        guard !input.student.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !input.password.isEmpty else { throw NativeError.protocolFailure("请输入生成笔记时的学号与 UIS 密码。") }
        let key = LectureSecret(password: LectureCrypto.derive(student: input.student.trimmingCharacters(in: .whitespacesAndNewlines), password: input.password), token: input.token.trimmingCharacters(in: .whitespacesAndNewlines))
        var value = saved?.sourceID == source.2 ? saved! : LectureSaved(repository: source.0, branch: source.1, sourceID: source.2)
        value.configured = true
        let candidate = (try? hydrate(value, key: key)) ?? LectureEngine(source: value.sourceID)
        var warning: String?
        do { (value, warning) = try await download(value, key: key, into: candidate) }
        catch { try check(); _ = try hydrate(value, key: key); warning = "已解锁缓存；在线同步失败：\(error.localizedDescription)" }
        try check()
        if saved?.sourceID == value.sourceID { value.reads = saved?.reads ?? value.reads }
        let oldSecret = saved?.secretID
        value.secretID = input.remember ? "\(account):\(value.sourceID):\(UUID().uuidString)" : nil
        if let id = value.secretID { try LectureKeychain.write(JSONEncoder().encode(key), id: id) }
        do { try persist(value) } catch { LectureKeychain.remove(value.secretID); throw error }
        saved = value; secret = key; engine = candidate; error = warning; LectureKeychain.remove(oldSecret)
        return state()
    }
    func disconnect() throws -> LectureConnection {
        if isDemo { return state() }
        try check(); guard !busy else { throw NativeError.protocolFailure("请等待笔记同步完成。") }
        guard var value = saved else { return state() }
        let old = value.secretID; value.secretID = nil; value.configured = false
        try persist(value); saved = value; secret = nil; engine = nil; error = nil; LectureKeychain.remove(old)
        return state()
    }
    private func bytes(_ value: LectureSaved, key: LectureSecret, path: String, raw: Bool = false, limit: Int = 134217728) async throws -> Data {
        try check()
        let url = URL(string: "https://api.github.com/repos/\(value.repository)/\(path)")!
        var request = URLRequest(url: url)
        request.setValue(raw ? "application/vnd.github.raw+json" : "application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if !key.token.isEmpty { request.setValue("Bearer \(key.token)", forHTTPHeaderField: "Authorization") }
        let (stream, response) = try await session.bytes(for: request)
        try check()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw NativeError.protocolFailure("无法读取 GitHub 笔记，请检查网络、数据分支或私有仓库令牌。") }
        guard response.expectedContentLength <= limit else { throw NativeError.protocolFailure("笔记分片过大。") }
        var data = Data()
        for try await byte in stream { data.append(byte); if data.count > limit { throw NativeError.protocolFailure("笔记分片过大。") }; if data.count % 65536 == 0 { try check() } }
        try check(); return data
    }
    private func json(_ value: LectureSaved, key: LectureSecret, path: String) async throws -> [String: Any] {
        let data = try await bytes(value, key: key, path: path, limit: 16777216)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NativeError.protocolFailure("GitHub 响应格式无效。") }; return result
    }
    private func download(_ original: LectureSaved, key: LectureSecret, into candidate: LectureEngine) async throws -> (LectureSaved, String?) {
        var value = original
        let ref = try await json(value, key: key, path: "git/ref/heads/\(value.branch)")
        guard let object = ref["object"] as? [String: Any], let commitID = object["sha"] as? String, validSHA(commitID) else { throw NativeError.protocolFailure("笔记分支无效。") }
        let commit = try await json(value, key: key, path: "git/commits/\(commitID)")
        guard let treeRef = commit["tree"] as? [String: Any], let treeID = treeRef["sha"] as? String, validSHA(treeID) else { throw NativeError.protocolFailure("笔记提交无效。") }
        let tree = try await json(value, key: key, path: "git/trees/\(treeID)?recursive=1")
        guard tree["truncated"] as? Bool != true, let rows = tree["tree"] as? [[String: Any]] else { throw NativeError.protocolFailure("笔记目录不完整。") }
        var files: [String: String] = [:]
        for row in rows { if row["type"] as? String == "blob", let name = row["path"] as? String, let hash = row["sha"] as? String, validSHA(hash) { files[name] = hash } }
        guard let indexID = files["data/icourse-index.enc"] else { throw NativeError.protocolFailure("未找到加密笔记索引，请先运行订阅仓库。") }
        let encrypted = try await bytes(value, key: key, path: "git/blobs/\(indexID)", raw: true, limit: 4194304)
        let index = try LectureManifest.decode(encrypted, password: key.password)
        var failures: [String] = []
        for shard in index.shards {
            do {
                let location = try blob(value, shard.sha256)
                var data = (try? Data(contentsOf: location)) ?? Data()
                if data.count != shard.size || LectureCrypto.hash(data) != shard.sha256 {
                    guard let hash = files["data/shards/\(shard.name)"] else { throw NativeError.protocolFailure("提交缺少分片。") }
                    data = try await bytes(value, key: key, path: "git/blobs/\(hash)", raw: true)
                }
                try check()
                guard data.count == shard.size else { throw NativeError.protocolFailure("笔记分片大小不符。") }
                try candidate.load(shard.name, data: data, password: key.password, hash: shard.sha256)
                try write(data, to: location); value.shards[shard.name] = shard
            } catch { try check(); failures.append(error.localizedDescription) }
        }
        if !index.shards.isEmpty, failures.count == index.shards.count { throw NativeError.protocolFailure("所有分片读取失败：\(failures[0])") }
        if failures.isEmpty { let names = Set(index.shards.map(\.name)); candidate.retain(names); value.shards = value.shards.filter { names.contains($0.key) } }
        value.indexHash = LectureCrypto.hash(encrypted)
        try write(encrypted, to: blob(value, value.indexHash!)); value.lastSynced = Date()
        return (value, failures.isEmpty ? nil : "\(failures.count) 个分片失败，已保留旧内容。\(failures[0])")
    }
    private func validSHA(_ value: String) -> Bool { value.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil }
    func sync() async throws -> LectureConnection {
        try check(); if isDemo { return state() }
        guard !busy else { throw NativeError.protocolFailure("正在同步课堂笔记。") }
        guard let value = saved, value.configured, let key = secret, let engine else { return state() }
        busy = true; defer { busy = false }
        do {
            var (next, warning) = try await download(value, key: key, into: engine)
            // Reading can occur while network requests suspend this actor.
            next.reads = saved?.reads ?? next.reads
            try persist(next); saved = next; error = warning
        }
        catch { try check(); self.error = error.localizedDescription }
        return state()
    }
    func bind(_ external: String, to course: Int?) throws -> LectureConnection {
        try check(); guard !busy, var value = saved, engine?.courses.contains(where: { $0.id == external }) == true else { throw NativeError.protocolFailure("请先解锁笔记并等待同步完成。") }
        if value.bindings[external] == course { return state() }
        value.bindings[external] = course; value.generations[external] = UUID().uuidString
        try persist(value); saved = value; return state()
    }
    func page(course: Int, search: String = "", offset: Int = 0) throws -> LecturePage {
        try check(); guard let saved, saved.configured, secret != nil, let engine else { throw NativeError.protocolFailure("请在课堂笔记设置中解锁。") }
        let items = engine.items.filter { saved.bindings[$0.reference.courseID] == course && (search.isEmpty || "\($0.title) \($0.date) \($0.teacher) \($0.courseTitle)".localizedCaseInsensitiveContains(search)) }
        return LecturePage(items: items.dropFirst(max(0, offset)).prefix(50).map { decorate($0, saved) }, total: items.count)
    }
    private func decorate(_ item: LectureItem, _ saved: LectureSaved) -> LectureItem {
        var item = item; let previous = saved.reads[item.id]; let hash = item.summaryHash.isEmpty ? "empty" : item.summaryHash
        item.read = previous == hash; item.updated = previous != nil && previous != hash; return item
    }
    func body(_ reference: LectureReference, course: Int) throws -> LectureBody {
        try check(); guard let saved, saved.configured, secret != nil, reference.sourceID == saved.sourceID, saved.bindings[reference.courseID] == course, let engine else { throw NativeError.protocolFailure("笔记来源已断开或课程关联已调整。") }
        var body = try engine.body(reference); body.item = decorate(body.item, saved); return body
    }
    func read(_ reference: LectureReference, course: Int, hash: String) throws {
        let body = try body(reference, course: course)
        guard body.item.summaryHash == hash, var value = saved else { return }
        value.reads[reference.key] = hash.isEmpty ? "empty" : hash
        try persist(value); saved = value
    }
    func batches(courses: [NativeCourse]) throws -> [ChangeBatch] {
        try check(); guard let saved, saved.configured, secret != nil, let engine else { return [] }
        // Partial sync keeps all baselines unchanged; recovered content is compared on the next successful sync.
        if error != nil { return [] }
        return saved.bindings.compactMap { external, canvas in
            guard let course = courses.first(where: { $0.id == canvas }) else { return nil }
            let resources = engine.items.filter { $0.reference.courseID == external && !$0.summaryHash.isEmpty }.map {
                ChangeResource(id: $0.id, kind: .lecture, courseID: canvas, courseName: course.displayName, title: $0.title, fields: ["摘要": $0.summaryHash])
            }
            return ChangeBatch(key: "\(canvas):lecture:\(saved.sourceID):\(external):\(saved.generations[external] ?? "initial")", resources: resources)
        }
    }
}
