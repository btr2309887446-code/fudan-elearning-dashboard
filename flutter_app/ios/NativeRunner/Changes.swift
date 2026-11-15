import Foundation
import CryptoKit

enum ChangeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case assignment, grade, announcement, file, lecture
    var id: String { rawValue }
    var title: String { switch self { case .assignment: "作业"; case .grade: "成绩"; case .announcement: "公告"; case .file: "文件"; case .lecture: "课堂笔记" } }
}

struct ChangeResource: Codable, Hashable, Sendable {
    var id: String
    var kind: ChangeKind
    var courseID: Int
    var courseName: String
    var title: String
    var fields: [String: String]
    var body: String = ""
    var url: String?
    var publishedAt: String?
    var assignmentID: Int?
}

struct ChangeBatch: Codable, Sendable {
    var key: String
    var resources: [ChangeResource]
}

struct ChangeEvent: Codable, Identifiable, Sendable {
    var id = UUID().uuidString
    var resource: ChangeResource
    var before: ChangeResource?
    var changes: [String]
    var discoveredAt: Date
    var read = false
    var title: String { before == nil ? "新增\(resource.kind.title)：\(resource.title)" : "\(resource.kind.title)更新：\(resource.title)" }
}

enum NativeChangeTracker {
    static func normalized(_ input: String) -> String {
        input.replacingOccurrences(of: "([?&])(?:verifier|token|expires|signature)=[^&\"'\\s<>]*", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func fingerprint(_ input: String) -> String {
        SHA256.hash(data: Data(normalized(input).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func applying(_ batches: [ChangeBatch], to saved: NativeLocalAccount, now: Date) -> NativeLocalAccount {
        var value = saved
        for batch in batches {
            let previous = value.baselines[batch.key]
            var merged = previous ?? [:]
            for resource in batch.resources {
                let old = previous?[resource.id]
                if previous != nil {
                    let changed = resource.fields.keys.sorted().filter { old?.fields[$0] != resource.fields[$0] }
                    // A grade baseline may contain ungraded assignments; only publication is a new grade.
                    let emptyGrade = resource.kind == .grade && resource.fields["成绩"] == "未评分"
                    if old == nil || !changed.isEmpty {
                        if !(emptyGrade && (old == nil || old?.fields["成绩"] == "未评分")) {
                            value.events.append(ChangeEvent(resource: resource, before: old, changes: changed, discoveredAt: now))
                        }
                    }
                }
                merged[resource.id] = resource
            }
            value.baselines[batch.key] = merged
        }
        let cutoff = Beijing.addDays(-180, to: now)
        value.events = Array(value.events.filter { $0.discoveredAt >= cutoff }.sorted { $0.discoveredAt > $1.discoveredAt }.prefix(2000))
        return value
    }
}

extension CanvasAPI {
    func changeResources(courseID: Int, courseName: String, kind: ChangeKind) async throws -> ChangeBatch {
        let path = kind == .announcement ? "/api/v1/courses/\(courseID)/discussion_topics" : "/api/v1/courses/\(courseID)/files"
        var query = [URLQueryItem(name: "per_page", value: "100")]
        if kind == .announcement { query.append(URLQueryItem(name: "only_announcements", value: "true")) }
        let items = try await pages(path, query: query)
        let resources = items.compactMap { raw -> ChangeResource? in
            guard let id = CanvasJSON.int(raw["id"]), !CanvasJSON.bool(raw["hidden"]), !CanvasJSON.bool(raw["locked_for_user"]) else { return nil }
            if kind == .announcement {
                guard let posted = CanvasJSON.string(raw["posted_at"]), let date = Beijing.parse(posted), date <= Date() else { return nil }
                let title = CanvasJSON.string(raw["title"]) ?? "公告"
                let html = CanvasJSON.string(raw["message"]) ?? ""
                return ChangeResource(id: String(id), kind: kind, courseID: courseID, courseName: courseName, title: title,
                                      fields: ["标题": title, "正文": NativeChangeTracker.fingerprint(html)],
                                      body: NativeDomain.summarize(html), url: CanvasJSON.string(raw["html_url"]), publishedAt: posted)
            }
            let name = CanvasJSON.string(raw["display_name"]) ?? CanvasJSON.string(raw["filename"]) ?? "文件"
            return ChangeResource(id: String(id), kind: kind, courseID: courseID, courseName: courseName, title: name,
                                  fields: ["名称": name, "大小": String(CanvasJSON.int(raw["size"]) ?? 0),
                                           "更新时间": CanvasJSON.string(raw["updated_at"]) ?? "", "文件夹": String(CanvasJSON.int(raw["folder_id"]) ?? 0)])
        }
        return ChangeBatch(key: "\(courseID):\(kind.rawValue)", resources: resources)
    }
}
