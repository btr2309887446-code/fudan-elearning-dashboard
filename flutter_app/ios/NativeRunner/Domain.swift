import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case submitted
    case ignored

    var id: String { rawValue }
    var title: String {
        switch self {
        case .pending: "未提交"
        case .submitted: "已提交"
        case .ignored: "无需提交"
        }
    }
}

enum TaskBucket: String, CaseIterable, Identifiable {
    case overdue, today, week, later, undated

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overdue: "已逾期未交"
        case .today: "今天截止"
        case .week: "未来七天"
        case .later: "其他日期"
        case .undated: "无截止时间"
        }
    }
}

struct NativeProfile: Codable {
    var id: Int
    var name: String
    var loginID: String?
    var primaryEmail: String?
}

struct NativeTerm: Codable, Identifiable {
    var id: Int?
    var name: String
    var startAt: String?
    var endAt: String?
    var isCurrent = false
    var courseCount = 0
}

struct NativeCourse: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var displayName: String
    var courseCode: String
    var termName: String
    var termID: Int?
    var termStartAt: String?
    var termEndAt: String?
    var nickname: String?
    var startAt: String?
    var endAt: String?
    var currentScore: Double?
    var finalScore: Double?
    var currentGrade: String?
    var finalGrade: String?
    var earnedPoints: Double?
    var possiblePointsGraded: Double?
    var assignmentCount: Int
    var submittedCount: Int
    var gradedCount: Int
    var missingCount: Int
    var lateCount: Int
    var upcomingCount: Int
}

struct NativeAssignment: Codable, Identifiable, Hashable {
    var id: Int
    var courseID: Int
    var courseName: String
    var name: String
    var groupID: Int
    var groupName: String
    var dueAt: String?
    var pointsPossible: Double?
    var groupWeight: Double
    var score: Double?
    var grade: String?
    var submittedAt: String?
    var gradedAt: String?
    var workflowState: String
    var late: Bool
    var missing: Bool
    var excused: Bool
    var omitFromFinalGrade: Bool
    var htmlURL: String?
    var descriptionExcerpt: String?

    var isCompleted: Bool {
        excused || score != nil || submittedAt != nil ||
        ["submitted", "graded", "pending_review", "complete", "graded_pending"].contains(workflowState.lowercased())
    }
}

struct NativeTodo: Codable, Identifiable {
    var id: String { "\(courseID ?? 0):\(assignmentID ?? 0):\(title)" }
    var title: String
    var courseName: String
    var kind: String
    var courseID: Int?
    var assignmentID: Int?
    var dueAt: String?
    var pointsPossible: Double?
    var htmlURL: String?
}

struct NativeSnapshot: Codable {
    var fetchedAt: Date
    var profile: NativeProfile
    var courses: [NativeCourse]
    var terms: [NativeTerm]
    var assignments: [NativeAssignment]
    var todo: [NativeTodo]
    var warnings: [String]
    var reusedCourseCount: Int
}

struct NativeTask: Identifiable, Hashable {
    var id: String
    var title: String
    var courseName: String
    var courseID: Int?
    var status: TaskStatus
    var dueAt: Date?
    var url: URL?
    var assignment: NativeAssignment?

    func bucket(now: Date = Date()) -> TaskBucket {
        guard let dueAt else { return .undated }
        if status == .pending && dueAt <= now { return .overdue }
        let dueDay = Beijing.day(dueAt)
        let today = Beijing.day(now)
        if dueDay == today { return .today }
        if dueDay > today && dueDay < Beijing.addDays(8, to: today) { return .week }
        return .later
    }
}

struct NativeLLMConfig: Codable {
    var baseURL = "https://api.deepseek.com/v1"
    var model = "deepseek-chat"
    var enabled = false
}

struct NativePreferences: Codable {
    var theme = "system"
    var selectedTerm = "default"
    var refreshScope = "current"
    var taskFilter = TaskStatus.pending.rawValue
    var remindersEnabled = false
    var mutedTasks: Set<String> = []
    var ignoredAssignments: Set<String> = []
    var calendarExports: [String: String] = [:]
    var rememberedUsername = ""
    var rememberPassword = false
    var llm = NativeLLMConfig()
}

enum Beijing {
    static let timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }

    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: raw)
    }

    static func day(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func addDays(_ count: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: count, to: date) ?? date
    }

    static func key(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func parseKey(_ value: String) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value), key(date) == value else { return nil }
        return date
    }

    static func label(_ date: Date?, now: Date = Date(), absolute: Bool = false) -> String {
        guard let date else { return "无截止时间" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = absolute ? "yyyy/M/d HH:mm" : "M月d日 HH:mm"
        let prefix: String
        if absolute { prefix = "" }
        else if day(date) == day(now) { prefix = "今天 " }
        else if day(date) == addDays(1, to: day(now)) { prefix = "明天 " }
        else { prefix = "" }
        return "\(prefix)\(formatter.string(from: date)) 截止"
    }
}

enum NativeDomain {
    static func assignmentKey(_ courseID: Int, _ assignmentID: Int) -> String {
        "\(courseID):\(assignmentID)"
    }

    static func defaultTermID(in snapshot: NativeSnapshot) -> Int? {
        snapshot.terms.first(where: \.isCurrent)?.id ?? snapshot.terms.first?.id
    }

    static func tasks(in snapshot: NativeSnapshot, ignored: Set<String> = []) -> [NativeTask] {
        var values: [String: NativeTask] = [:]
        for row in snapshot.assignments {
            let key = assignmentKey(row.courseID, row.id)
            let status: TaskStatus = ignored.contains(key) ? .ignored : (row.isCompleted ? .submitted : .pending)
            values[key] = NativeTask(id: key, title: row.name, courseName: row.courseName,
                                     courseID: row.courseID, status: status,
                                     dueAt: Beijing.parse(row.dueAt), url: row.htmlURL.flatMap(URL.init(string:)),
                                     assignment: row)
        }
        for item in snapshot.todo {
            let explicit = item.courseID.flatMap { courseID in item.assignmentID.map { assignmentKey(courseID, $0) } }
            if let explicit, values[explicit] != nil { continue }
            if explicit == nil, values.values.contains(where: {
                $0.title == item.title && $0.courseID == item.courseID && $0.dueAt == Beijing.parse(item.dueAt)
            }) { continue }
            let key = explicit ?? "todo:\(item.courseID ?? 0):\(item.htmlURL ?? "\(item.title):\(item.dueAt ?? "")")"
            guard values[key] == nil else { continue }
            values[key] = NativeTask(id: key, title: item.title, courseName: item.courseName,
                                     courseID: item.courseID,
                                     status: ignored.contains(key) ? .ignored : .pending,
                                     dueAt: Beijing.parse(item.dueAt), url: item.htmlURL.flatMap(URL.init(string:)),
                                     assignment: nil)
        }
        return values.values.sorted {
            switch ($0.dueAt, $1.dueAt) {
            case let (a?, b?): a == b ? $0.id < $1.id : a < b
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): $0.id < $1.id
            }
        }
    }

    static func summarize(_ raw: String?) -> String {
        guard var text = raw, !text.isEmpty else { return "" }
        text = text.replacingOccurrences(of: #"<(script|style|head|noscript)[\s\S]*?</\1>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<\s*br\s*/?>|</\s*(p|div|li|tr|h[1-6]|section|article|blockquote|pre)\s*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<\s*li\b[^>]*>"#, with: "\n· ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        let entities: [(String, String)] = [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"), ("&nbsp;", " ")]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value, options: .caseInsensitive) }
        // Decode numeric HTML entities instead of dropping them. Canvas descriptions
        // commonly use &#x2022; and &#8220; for punctuation and bullets.
        if let regex = try? NSRegularExpression(pattern: #"&#(?:x([0-9a-fA-F]+)|(\d+));"#) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            var pieces: [String] = []
            var cursor = text.startIndex
            for match in matches {
                guard let range = Range(match.range, in: text) else { continue }
                pieces.append(String(text[cursor..<range.lowerBound]))
                let hexRange = Range(match.range(at: 1), in: text)
                let decimalRange = Range(match.range(at: 2), in: text)
                let hex = hexRange.map { String(text[$0]) }
                let decimal = decimalRange.map { String(text[$0]) }
                if let number = Int(hex ?? decimal ?? "", radix: hex == nil ? 10 : 16),
                   (0...0x10FFFF).contains(number),
                   let scalar = UnicodeScalar(UInt32(number)) {
                    pieces.append(String(scalar))
                } else {
                    pieces.append(String(text[range]))
                }
                cursor = range.upperBound
            }
            if !matches.isEmpty {
                pieces.append(String(text[cursor...]))
                text = pieces.joined()
            }
        }
        return text.components(separatedBy: .newlines).map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func truncate(_ raw: String, limit: Int = 100) -> String {
        let text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard text.count > limit else { return text }
        let prefix = String(text.prefix(max(1, limit - 1)))
        let marks = ["。", "！", "？", "；", ". ", "! ", "? ", "; "]
        let boundary = marks.compactMap { prefix.range(of: $0, options: .backwards).map { prefix.distance(from: prefix.startIndex, to: $0.lowerBound) } }.max()
        if let boundary, boundary >= Int(Double(limit) * 0.6) {
            return String(prefix.prefix(boundary + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func weightedScore(_ groups: [(weight: Double, earned: Double, possible: Double)]) -> Double? {
        let graded = groups.filter { $0.possible > 0 }
        guard !graded.isEmpty else { return nil }
        let totalWeight = graded.reduce(0.0) { $0 + max(0, $1.weight) }
        if totalWeight > 0 {
            return graded.reduce(0.0) { $0 + ($1.earned / $1.possible) * max(0, $1.weight) } / totalWeight * 100
        }
        let earned = graded.reduce(0.0) { $0 + $1.earned }
        let possible = graded.reduce(0.0) { $0 + $1.possible }
        return possible > 0 ? earned / possible * 100 : nil
    }
}

enum CanvasJSON {
    static func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
    static func double(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    static func string(_ value: Any?) -> String? { value as? String }
    static func bool(_ value: Any?) -> Bool { (value as? NSNumber)?.boolValue ?? false }
    static func object(_ value: Any?) -> [String: Any] { value as? [String: Any] ?? [:] }
    static func array(_ value: Any?) -> [[String: Any]] { value as? [[String: Any]] ?? [] }
}
