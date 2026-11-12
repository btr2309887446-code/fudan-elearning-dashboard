import Foundation

enum ReviewMastery: String, Codable, CaseIterable, Identifiable, Sendable {
    case unassessed, weak, familiar, confident
    var id: String { rawValue }
    var title: String { switch self { case .unassessed: "未评估"; case .weak: "需加强"; case .familiar: "基本掌握"; case .confident: "熟练" } }
    var rank: Int { switch self { case .weak: 0; case .unassessed: 1; case .familiar: 2; case .confident: 3 } }
}
struct ReviewQuestion: Codable, Equatable, Sendable { var question = ""; var answer = "" }
struct ReviewSource: Codable, Equatable, Sendable {
    var reference: LectureReference
    var title: String
    var summaryHash: String
    var quote: String
}
struct ReviewItem: Codable, Identifiable, Equatable, Sendable {
    var id = UUID().uuidString
    var title = ""
    var notes = ""
    var minutes = 30
    var extraMinutes = 0
    var mastery = ReviewMastery.unassessed
    var questions: [ReviewQuestion] = []
    var sources: [ReviewSource] = []
}
struct ReviewPlan: Codable, Identifiable, Equatable, Sendable {
    var id = UUID().uuidString
    var courseID: Int
    var title = "期末复习"
    var examDate: String?
    var items: [ReviewItem] = []
}
struct ReviewAllocation: Codable, Equatable, Sendable { var itemID: String; var minutes: Int }
struct ReviewSlot: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var planID: String
    var date: String
    var locked = false
    var allocations: [ReviewAllocation] = []
    var taskID = ""
}
struct ReviewTaskSource: Codable, Hashable, Sendable { var planID: String; var slotID: String }
struct ReviewData: Codable, Sendable {
    var version = 1
    var revision = 0
    var plans: [ReviewPlan] = []
    var slots: [ReviewSlot] = []
    // Sunday through Saturday, matching the desktop domain.
    var budget = Array(repeating: 60, count: 7)
    var finishTime = "21:00"
}
struct ReviewShortage: Identifiable, Equatable, Sendable {
    var planID: String; var minutes: Int; var reason: String
    var id: String { planID }
}
struct ReviewPreview: Equatable, Sendable {
    var revision: Int; var start: String; var slots: [ReviewSlot]
    var shortages: [ReviewShortage]; var warnings: [String]
    var added: Int; var changed: Int; var removed: Int
}
enum ReviewAction {
    case plan(ReviewPlan), remove(String), budget([Int], String), lock(String, Bool), schedule(ReviewPreview)
}

enum ReviewDomain {
    static func failure(_ message: String) -> NativeError { .protocolFailure(message) }
    static func validDay(_ value: String) -> Date? {
        guard value.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil,
              let date = Beijing.parseKey(value), Beijing.key(date) == value else { return nil }
        return date
    }
    static func validate(_ plan: ReviewPlan) throws -> ReviewPlan {
        guard !plan.id.isEmpty, plan.id.count <= 100, plan.courseID >= 0,
              !plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, plan.title.count <= 200,
              plan.items.count <= 1000, Set(plan.items.map(\.id)).count == plan.items.count,
              plan.examDate == nil || validDay(plan.examDate!) != nil else { throw failure("复习计划格式无效，每份最多 1,000 个知识点。") }
        for item in plan.items {
            guard !item.id.isEmpty, item.id.count <= 100, !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.title.count <= 500, item.notes.count <= 12000, (1...1440).contains(item.minutes),
                  (0...100000).contains(item.extraMinutes), item.questions.count <= 10, item.sources.count <= 20,
                  item.questions.allSatisfy({ !$0.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.question.count <= 4000 && $0.answer.count <= 12000 }),
                  item.sources.allSatisfy({ LectureReference.parse($0.reference.key) != nil && !$0.title.isEmpty && $0.title.count <= 500 && $0.summaryHash.count <= 100 && $0.quote.count <= 2000 })
            else { throw failure("知识点、自测题或来源格式无效，请检查标题与预计用时。") }
        }
        var result = plan
        result.title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
    static func active(_ slot: ReviewSlot, _ data: NativeLocalAccount) -> Bool {
        guard let task = data.series.first(where: { $0.id == slot.taskID }) else { return false }
        return task.exceptions["single"]?.deleted != true
    }
    static func completed(_ slot: ReviewSlot, _ data: NativeLocalAccount) -> Bool {
        data.series.first(where: { $0.id == slot.taskID })?.exceptions["single"]?.completed == true
    }
    static func reviewed(_ item: String, plan: String, data: NativeLocalAccount) -> Int {
        (data.review?.slots ?? []).filter { $0.planID == plan && completed($0, data) }
            .flatMap(\.allocations).filter { $0.itemID == item }.reduce(0) { $0 + $1.minutes }
    }
    static func deadline(_ day: String, time: String) -> Date? {
        guard let date = validDay(day) else { return nil }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return Beijing.calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)
    }
    static func preview(_ data: NativeLocalAccount, start: String, now: Date) throws -> ReviewPreview {
        let review = data.review ?? ReviewData()
        guard review.version == 1, let begin = validDay(start), start >= Beijing.key(now), review.budget.count == 7,
              review.budget.allSatisfy({ (0...720).contains($0) }), deadline(start, time: review.finishTime) != nil else { throw failure("排期开始日期或每日预算无效。") }
        let keep = review.slots.filter { completed($0, data) || ($0.locked && active($0, data)) }
        var capacity: [String: Int] = [:], warnings: [String] = []
        var slots: [String: ReviewSlot] = [:], shortages: [ReviewShortage] = []
        let plans = review.plans.sorted { ($0.examDate ?? "9999", $0.id) < ($1.examDate ?? "9999", $1.id) }
        for plan in plans {
            let exam = plan.examDate.flatMap(validDay)
            if let exam, exam.timeIntervalSince(begin) > 730 * 86400 { throw failure("排期范围最多两年，请调整开始日期。") }
            var missing = 0
            let items = plan.items.enumerated().sorted { ($0.element.mastery.rank, $0.offset) < ($1.element.mastery.rank, $1.offset) }
            for entry in items {
                let item = entry.element
                let reserved = keep.filter { $0.planID == plan.id }.flatMap(\.allocations).filter { $0.itemID == item.id }.reduce(0) { $0 + $1.minutes }
                var left = max(0, item.minutes + item.extraMinutes - reserved), day = begin
                while left > 0, let exam, day < exam {
                    let date = Beijing.key(day)
                    defer { day = Beijing.addDays(1, to: day) }
                    if capacity[date] == nil {
                        let used = keep.filter { $0.date == date }.flatMap(\.allocations).reduce(0) { $0 + $1.minutes }
                        let budget = review.budget[Beijing.calendar.component(.weekday, from: day) - 1]
                        if used > budget { warnings.append("\(date) 已完成或锁定安排超出预算 \(used - budget) 分钟") }
                        capacity[date] = max(0, budget - used)
                    }
                    guard let due = deadline(date, time: review.finishTime), due > now, let available = capacity[date], available > 0 else { continue }
                    if keep.contains(where: { s in s.date == date && review.plans.first(where: { $0.id == s.planID })?.courseID == plan.courseID }) { continue }
                    let amount = min(left, available), id = "\(plan.id):\(date)"
                    var slot = slots[id] ?? ReviewSlot(id: id, planID: plan.id, date: date)
                    slot.allocations.append(ReviewAllocation(itemID: item.id, minutes: amount)); slots[id] = slot
                    left -= amount; capacity[date] = available - amount
                }
                missing += left
            }
            if missing > 0 { shortages.append(ReviewShortage(planID: plan.id, minutes: missing, reason: plan.examDate == nil ? "未设置考试日期" : plan.examDate! <= start ? "考试前已无可用日期" : "可用时间不足")) }
        }
        let next = slots.values.sorted { ($0.date, $0.planID) < ($1.date, $1.planID) }
        let previous = review.slots.filter { !keep.contains($0) && active($0, data) }
        return ReviewPreview(revision: review.revision, start: start, slots: next, shortages: shortages, warnings: warnings,
                             added: next.filter { n in !previous.contains { $0.id == n.id } }.count,
                             changed: next.filter { n in previous.contains { $0.id == n.id && $0.allocations != n.allocations } }.count,
                             removed: previous.filter { p in !next.contains { $0.id == p.id } }.count)
    }
    // Call on a copy, then persist the account once. A thrown error must discard the copy.
    static func apply(_ action: ReviewAction, revision: Int, to data: inout NativeLocalAccount, now: Date, uuid: () -> String = { UUID().uuidString }) throws {
        var review = data.review ?? ReviewData()
        guard review.version == 1, review.revision == revision else { throw failure("复习计划已变化，请重新查看后保存。") }
        func task(_ slots: [ReviewSlot], previous: PersonalTaskSeries?) throws -> PersonalTaskSeries {
            guard let first = slots.first, let plan = review.plans.first(where: { $0.id == first.planID }), let due = deadline(first.date, time: review.finishTime) else { throw failure("复习安排关联不完整。") }
            var result = PersonalTaskSeries()
            let minutes = slots.flatMap(\.allocations).reduce(0) { $0 + $1.minutes }
            let names = slots.compactMap { s in review.plans.first { $0.id == s.planID }?.title }.joined(separator: " / ")
            result.id = first.taskID; result.courseID = plan.courseID; result.title = "复习 · \(String(names.prefix(400)))（\(minutes) 分钟）"
            result.notes = slots.flatMap { slot in slot.allocations.map { allocation in
                let p = review.plans.first { $0.id == slot.planID }
                return "\(p?.title ?? "复习") · \(p?.items.first { $0.id == allocation.itemID }?.title ?? "已移除知识点") · \(allocation.minutes) 分钟"
            }}.joined(separator: "\n")
            result.dueAt = due; result.createdAt = previous?.createdAt ?? now; result.exceptions = previous?.exceptions ?? [:]
            result.reviewSource = ReviewTaskSource(planID: plan.id, slotID: first.id)
            return result
        }
        switch action {
        case .plan(let input):
            let plan = try validate(input)
            if let i = review.plans.firstIndex(where: { $0.id == plan.id }) {
                guard review.plans[i].courseID == plan.courseID else { throw failure("不能更换已有计划的课程。") }
                let removed = Set(review.plans[i].items.map(\.id)).subtracting(plan.items.map(\.id))
                guard !review.slots.contains(where: { $0.planID == plan.id && active($0, data) && !completed($0, data) && $0.allocations.contains { removed.contains($0.itemID) } }) else { throw failure("请先取消该知识点的未完成安排，再删除知识点。") }
                review.plans[i] = plan
            } else { guard review.plans.count < 200 else { throw failure("最多保存 200 个复习计划。") }; review.plans.append(plan) }
        case .remove(let id):
            guard review.plans.contains(where: { $0.id == id }) else { throw failure("复习计划不存在。") }
            let taskIDs = Set(review.slots.filter { $0.planID == id }.map(\.taskID))
            review.slots.removeAll { $0.planID == id }; review.plans.removeAll { $0.id == id }
            data.series = try data.series.compactMap { old in
                guard taskIDs.contains(old.id) else { return old }
                let remaining = review.slots.filter { $0.taskID == old.id }
                return remaining.isEmpty ? nil : try task(remaining, previous: old)
            }
        case .budget(let values, let time):
            guard values.count == 7, values.allSatisfy({ (0...720).contains($0) }), time.range(of: "^([01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil else { throw failure("每日预算或完成时间无效。") }
            review.budget = values; review.finishTime = time
        case .lock(let id, let locked):
            guard let selected = review.slots.first(where: { $0.id == id }) else { throw failure("复习安排不存在。") }
            for i in review.slots.indices where review.slots[i].taskID == selected.taskID { review.slots[i].locked = locked }
        case .schedule(let expected):
            let preview = try preview(data, start: expected.start, now: now)
            guard preview == expected else { throw failure("可用复习时间已变化，请重新预览排期。") }
            let keep = review.slots.filter { completed($0, data) || ($0.locked && active($0, data)) }
            let keepIDs = Set(keep.map(\.taskID)), old = Dictionary(uniqueKeysWithValues: data.series.map { ($0.id, $0) })
            data.series.removeAll { $0.reviewSource != nil && !keepIDs.contains($0.id) }
            var groups: [String: [ReviewSlot]] = [:], order: [String] = []
            for var slot in preview.slots {
                guard let plan = review.plans.first(where: { $0.id == slot.planID }) else { throw failure("复习计划不存在。") }
                let group = "\(plan.courseID):\(slot.date)"
                let previous = review.slots.first { s in s.date == slot.date && review.plans.first { $0.id == s.planID }?.courseID == plan.courseID }
                slot.taskID = groups[group]?.first?.taskID ?? previous?.taskID ?? uuid()
                if groups[group] == nil { order.append(group) }
                groups[group, default: []].append(slot)
            }
            let next = order.flatMap { groups[$0] ?? [] }
            for key in order {
                let rows = groups[key]!
                var previous = old[rows[0].taskID]; previous?.exceptions = [:]
                data.series.append(try task(rows, previous: previous))
            }
            review.slots = keep + next
        }
        review.revision += 1; data.review = review
    }
}
