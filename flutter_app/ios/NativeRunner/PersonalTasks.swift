import Foundation

enum PersonalRepeat: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, daily, weekly, monthly
    var id: String { rawValue }
    var title: String {
        switch self { case .none: "不重复"; case .daily: "每天"; case .weekly: "每周"; case .monthly: "每月" }
    }
}

struct PersonalChecklistItem: Codable, Identifiable, Hashable, Sendable {
    var id = UUID().uuidString
    var title: String
}

struct PersonalTaskSeries: Codable, Identifiable, Hashable, Sendable {
    var id = UUID().uuidString
    var title = ""
    var notes = ""
    var courseID: Int?
    var courseName = "个人任务"
    var dueAt: Date?
    var createdAt = Date()
    var repeatRule = PersonalRepeat.none
    var weekdays: Set<Int> = []
    var endDate: Date?
    var checklist: [PersonalChecklistItem] = []
    // Minutes before the occurrence deadline, not absolute notification dates.
    var reminderMinutes: [Int] = []
    var exceptions: [String: PersonalOccurrenceState] = [:]

    func dates(through end: Date) -> [Date?] {
        guard let dueAt, repeatRule != .none else { return [dueAt] }
        let limit = min(end, endDate.map { Beijing.addDays(1, to: Beijing.day($0)).addingTimeInterval(-1) } ?? end)
        guard dueAt <= limit else { return [] }
        let calendar = Beijing.calendar
        let time = calendar.dateComponents([.hour, .minute], from: dueAt)
        var day = Beijing.day(dueAt)
        var result: [Date?] = []
        let originalDay = calendar.component(.day, from: dueAt)
        while day <= limit {
            let matches: Bool
            switch repeatRule {
            case .none, .daily: matches = true
            case .weekly: matches = weekdays.contains(calendar.component(.weekday, from: day))
            case .monthly:
                matches = calendar.component(.day, from: day) == min(originalDay, calendar.range(of: .day, in: .month, for: day)!.count)
            }
            if matches, let date = calendar.date(bySettingHour: time.hour ?? 23, minute: time.minute ?? 59, second: 0, of: day), date >= dueAt, date <= limit {
                result.append(date)
            }
            day = Beijing.addDays(1, to: day)
        }
        return result
    }

    func occurrenceKey(_ date: Date?) -> String { repeatRule == .none ? "single" : date.map(Beijing.key) ?? "single" }

    func occurrences(through end: Date) -> [PersonalOccurrence] {
        var candidates = dates(through: end)
        let existing = Set(candidates.map(occurrenceKey))
        // A future occurrence may have been individually moved into the visible window.
        for (key, state) in exceptions where !existing.contains(key) {
            if let override = state.override, let due = override.dueAt, due <= end,
               let originalDay = Beijing.parseKey(key), let anchor = dueAt {
                let parts = Beijing.calendar.dateComponents([.hour, .minute], from: anchor)
                if let original = Beijing.calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: originalDay),
                   original >= anchor, endDate == nil || Beijing.day(original) <= Beijing.day(endDate!) {
                    candidates.append(original)
                }
            }
        }
        return candidates.compactMap { date in
            let key = occurrenceKey(date)
            let state = exceptions[key] ?? PersonalOccurrenceState()
            guard !state.deleted else { return nil }
            let occurrence = PersonalOccurrence(seriesID: id, key: key, scheduledAt: date, task: state.override ?? self.withoutExceptions,
                                      completed: state.completed, checked: state.checked)
            guard occurrence.dueAt == nil || occurrence.dueAt! <= end else { return nil }
            return occurrence
        }
    }

    var withoutExceptions: PersonalTaskSeries { var copy = self; copy.exceptions = [:]; return copy }
}

struct PersonalOccurrenceState: Codable, Hashable, Sendable {
    var completed = false
    var checked: Set<String> = []
    var deleted = false
    var override: PersonalTaskSeries?
}

struct PersonalOccurrence: Identifiable, Hashable, Sendable {
    var seriesID: String
    var key: String
    var scheduledAt: Date?
    var task: PersonalTaskSeries
    var completed: Bool
    var checked: Set<String>
    var id: String { "personal:\(seriesID):\(key)" }
    var dueAt: Date? { task.repeatRule == .none ? task.dueAt : scheduledAt }
    var nativeTask: NativeTask {
        NativeTask(id: id, title: task.title, courseName: task.courseName, courseID: task.courseID,
                   status: completed ? .submitted : .pending, dueAt: dueAt, url: nil, assignment: nil, personal: self)
    }
}

struct NativeLocalAccount: Codable, Sendable {
    var version = 1
    var series: [PersonalTaskSeries] = []
    var baselines: [String: [String: ChangeResource]] = [:]
    var events: [ChangeEvent] = []
    var personalRemindersEnabled = true
}

actor NativeLocalRepository {
    private let root: URL
    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NativeLocal", isDirectory: true)) { self.root = root }
    func load(account: Int) throws -> NativeLocalAccount {
        let url = root.appendingPathComponent("\(account).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return NativeLocalAccount() }
        let value = try JSONDecoder().decode(NativeLocalAccount.self, from: Data(contentsOf: url))
        guard value.version == 1 else { throw NativeError.protocolFailure("本地任务数据版本不受支持，请升级应用。") }
        return value
    }
    func save(_ value: NativeLocalAccount, account: Int) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent("\(account).json"), options: .atomic)
    }
}
