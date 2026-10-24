import Foundation
import CryptoKit
import CommonCrypto
import SQLite3
import zlib

struct LectureReference: Codable, Hashable, Sendable {
    var sourceID: String
    var courseID: String
    var lectureID: String
    var key: String { String(data: try! JSONEncoder().encode([sourceID, courseID, lectureID]), encoding: .utf8)! }
    static func parse(_ value: String) -> Self? {
        guard let data = value.data(using: .utf8), let parts = try? JSONDecoder().decode([String].self, from: data),
              parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.count < 300 }) else { return nil }
        return Self(sourceID: parts[0], courseID: parts[1], lectureID: parts[2])
    }
}
struct LectureTaskSource: Codable, Hashable, Sendable { var reference: LectureReference; var title: String }
struct LectureCourse: Codable, Identifiable, Sendable {
    var id: String; var title: String; var teacher: String; var terms: [String] = []
}
struct LectureItem: Identifiable, Sendable {
    var reference: LectureReference; var title: String; var date: String; var courseTitle: String; var teacher: String
    var summaryHash: String; var shard: String; var read = false; var updated = false
    var id: String { reference.key }
}
struct LectureBody: Sendable { var item: LectureItem; var summary: String; var transcript: String; var pages: [String] }
struct LecturePage: Sendable { var items: [LectureItem]; var total: Int }
struct LectureIntroduction: Codable, Sendable { var description: String; var teachers: [String]; var fetchedAt = Date() }
struct LectureManifest: Codable, Sendable {
    struct Shard: Codable, Sendable { var name: String; var sha256: String; var size: Int }
    var version: Int; var shards: [Shard]
    static func decode(_ bytes: Data, password: String) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: LectureCrypto.decrypt(bytes, password: password))
        guard value.version == 4, value.shards.count <= 2000, Set(value.shards.map(\.name)).count == value.shards.count,
              value.shards.allSatisfy({ $0.name.range(of: "^[A-Za-z0-9_.-]+\\.db\\.gz\\.enc$", options: .regularExpression) != nil &&
                  $0.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil && (32...134217728).contains($0.size) }) else {
            throw NativeError.protocolFailure("笔记索引格式不支持，需要版本 4；原有缓存已保留。")
        }
        return value
    }
}
enum LectureCrypto {
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func derive(student: String, password: String) -> String { hash(Data("ICSv2:\(student):\(password)".utf8)) }
    static func decrypt(_ data: Data, password: String) throws -> Data {
        guard data.count >= 32, data.prefix(8) == Data("Salted__".utf8) else { throw NativeError.protocolFailure("笔记文件格式无效。") }
        let salt = Data(data[8..<16]), encrypted = Data(data.dropFirst(16))
        var material = [UInt8](repeating: 0, count: 48)
        let status = password.withCString { pass in salt.withUnsafeBytes { bytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass, password.utf8.count,
                                bytes.bindMemory(to: UInt8.self).baseAddress, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 100000, &material, 48)
        } }
        guard status == kCCSuccess else { throw NativeError.protocolFailure("密钥派生失败。") }
        var output = [UInt8](repeating: 0, count: encrypted.count + 16), count = 0
        let result = material.withUnsafeBytes { key in encrypted.withUnsafeBytes { bytes in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                    key.baseAddress, 32, key.baseAddress!.advanced(by: 32), bytes.baseAddress, encrypted.count, &output, output.count, &count)
        } }
        guard result == kCCSuccess else { throw NativeError.protocolFailure("笔记解锁失败，请检查生成时使用的学号和 UIS 密码。") }
        return Data(output.prefix(count))
    }
    static func gunzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw NativeError.protocolFailure("无法初始化笔记解压。") }
        defer { inflateEnd(&stream) }
        return try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)
            var result = Data(), buffer = [UInt8](repeating: 0, count: 65536)
            var status: Int32 = Z_OK
            repeat {
                status = buffer.withUnsafeMutableBytes { output in
                    stream.next_out = output.bindMemory(to: Bytef.self).baseAddress; stream.avail_out = 65536
                    return inflate(&stream, Z_NO_FLUSH)
                }
                guard status == Z_OK || status == Z_STREAM_END, result.count + 65536 <= 268435456 else { throw NativeError.protocolFailure("笔记压缩数据无效或过大。") }
                result.append(contentsOf: buffer.prefix(65536 - Int(stream.avail_out)))
            } while status != Z_STREAM_END
            return result
        }
    }
}

/// Actor-owned SQLite handles. Protected temporary files are unlinked immediately after opening.
final class LectureDatabase {
    private var db: OpaquePointer?
    init(_ data: Data) throws {
        guard data.prefix(16) == Data("SQLite format 3\0".utf8) else { throw NativeError.protocolFailure("笔记数据库格式无效。") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lecture-\(UUID().uuidString).sqlite")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        defer { try? FileManager.default.removeItem(at: url) }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(db); db = nil; throw NativeError.protocolFailure("无法打开课堂笔记数据库。")
        }
        sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 8 * 1024 * 1024)
        _ = try rows("PRAGMA query_only=ON")
    }
    deinit { sqlite3_close(db) }
    func rows(_ sql: String, _ args: [String] = []) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw NativeError.protocolFailure("笔记数据库字段不兼容。") }
        defer { sqlite3_finalize(statement) }
        for (index, arg) in args.enumerated() { _ = arg.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) } }
        var result: [[String: String]] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            var row: [String: String] = [:]
            for i in 0..<sqlite3_column_count(statement) {
                let key = String(cString: sqlite3_column_name(statement, i))
                row[key] = sqlite3_column_text(statement, i).map { String(cString: $0) } ?? ""
            }
            result.append(row); status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw NativeError.protocolFailure("笔记内容无法读取或正文过大。") }
        return result
    }
    func has(_ table: String) throws -> Bool { try !rows("SELECT name FROM sqlite_master WHERE type='table' AND name=?", [table]).isEmpty }
}

final class LectureEngine {
    private var databases: [String: LectureDatabase] = [:]
    private var hashes: [String: String] = [:]
    private var courseShards: [String: [LectureCourse]] = [:]
    private var entries: [String: [LectureItem]] = [:]
    private var demoBodies: [String: LectureBody] = [:]
    let source: String
    init(source: String) { self.source = source }
    func load(_ name: String, data: Data, password: String, hash: String) throws {
        guard LectureCrypto.hash(data) == hash else { throw NativeError.protocolFailure("笔记分片校验失败。") }
        if hashes[name] == hash { return }
        let db = try LectureDatabase(LectureCrypto.gunzip(LectureCrypto.decrypt(data, password: password)))
        let rawCourses = try db.rows("SELECT course_id,title,teacher FROM courses")
        var courses = rawCourses.map { LectureCourse(id: $0["course_id"]!, title: $0["title"]!, teacher: $0["teacher"]!) }
        if try db.has("all_courses") {
            for row in try db.rows("SELECT course_id,term,teacher FROM all_courses") {
                if let index = courses.firstIndex(where: { $0.id == row["course_id"] }) {
                    if let term = row["term"], !courses[index].terms.contains(term) { courses[index].terms.append(term) }
                    if courses[index].teacher.isEmpty { courses[index].teacher = row["teacher"] ?? "" }
                }
            }
        }
        let rows = try db.rows("SELECT sub_id,course_id,sub_title,date,summary FROM lectures")
        let items = rows.map { row -> LectureItem in
            let id = row["course_id"]!, course = courses.first { $0.id == id }, summary = row["summary"]!.trimmingCharacters(in: .whitespacesAndNewlines)
            return LectureItem(reference: LectureReference(sourceID: source, courseID: id, lectureID: row["sub_id"]!), title: row["sub_title"]!, date: row["date"]!, courseTitle: course?.title ?? "", teacher: course?.teacher ?? "", summaryHash: summary.isEmpty ? "" : LectureCrypto.hash(Data(summary.utf8)), shard: name)
        }
        databases[name] = db; courseShards[name] = courses; entries[name] = items; hashes[name] = hash
    }
    func retain(_ names: Set<String>) {
        databases = databases.filter { names.contains($0.key) }; hashes = hashes.filter { names.contains($0.key) }
        entries = entries.filter { names.contains($0.key) }; courseShards = courseShards.filter { names.contains($0.key) }
    }
    var courses: [LectureCourse] { var result: [String: LectureCourse] = [:]; for c in courseShards.keys.sorted().flatMap({ courseShards[$0]! }) { result[c.id] = c }; return result.values.sorted { $0.title < $1.title } }
    var items: [LectureItem] { var result: [String: LectureItem] = [:]; for item in entries.keys.sorted().flatMap({ entries[$0]! }) { result[item.id] = item }; return result.values.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date } }
    func body(_ ref: LectureReference) throws -> LectureBody {
        guard let item = items.first(where: { $0.reference == ref }) else { throw NativeError.protocolFailure("课堂笔记不存在，请重新同步。") }
        if let body = demoBodies[item.id] { return body }
        guard let db = databases[item.shard], let row = try db.rows("SELECT summary,transcript FROM lectures WHERE course_id=? AND sub_id=?", [ref.courseID, ref.lectureID]).first else { throw NativeError.protocolFailure("课堂正文不可用。") }
        let pages = try db.has("ppt_pages") ? db.rows("SELECT page_num,text FROM ppt_pages WHERE sub_id=? ORDER BY page_num", [ref.lectureID]).map { "第 \($0["page_num"] ?? "") 页\n\($0["text"] ?? "")" } : []
        return LectureBody(item: item, summary: row["summary"] ?? "", transcript: row["transcript"] ?? "", pages: pages)
    }
    func demo(_ courses: [NativeCourse]) {
        courseShards["demo"] = courses.map { LectureCourse(id: "demo-\($0.id)", title: $0.displayName, teacher: "示例教师", terms: [$0.termName]) }
        entries["demo"] = courses.flatMap { course in (1...4).map { index in
            let summary = "## 课堂事项\n\n- 阅读本章并整理三个疑问，下次课讨论。\n- 完成课堂练习，日期以教师通知为准。\n\n## 本节重点\n\n这是虚构课堂笔记。\n\n$$f(x)=\\sum_{k=0}^{n}a_kx^k$$\n\n| 内容 | 复习建议 |\n| --- | --- |\n| 核心概念 | 用自己的话解释 |"
            let item = LectureItem(reference: LectureReference(sourceID: source, courseID: "demo-\(course.id)", lectureID: "demo-\(course.id)-\(index)"), title: "第 \(index) 讲 · 核心概念与应用", date: "2026-10-\(10 + index)", courseTitle: course.displayName, teacher: "示例教师", summaryHash: LectureCrypto.hash(Data(summary.utf8)), shard: "demo")
            demoBodies[item.id] = LectureBody(item: item, summary: summary, transcript: "本课次原始转写使用虚构内容，仅供界面测试。", pages: ["第 1 页\n核心概念与应用", "第 2 页\n示例与练习"])
            return item
        } }
    }
}
