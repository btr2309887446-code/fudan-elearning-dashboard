import XCTest
@testable import NativeRunner

final class PersonalAndChangeTests: XCTestCase {
    private func date(_ value: String) -> Date { Beijing.parse(value + "T12:00:00+08:00")! }

    func testMonthlyRepeatsClampMonthEndAndKeepAnchorAcrossLeapYear() {
        var series = PersonalTaskSeries(title: "月末复盘", dueAt: date("2024-01-31"), repeatRule: .monthly)
        XCTAssertEqual(series.dates(through: date("2024-04-30")).compactMap { $0.map(Beijing.key) }, ["2024-01-31", "2024-02-29", "2024-03-31", "2024-04-30"])
        series.endDate = date("2024-02-29")
        XCTAssertEqual(series.dates(through: date("2024-04-30")).count, 2)
    }

    func testWeeklyOccurrencesAreIndependentAndSingleExceptionMovesDeadline() throws {
        var series = PersonalTaskSeries(title: "复习", dueAt: date("2026-10-19"), repeatRule: .weekly, weekdays: [2, 6], checklist: [PersonalChecklistItem(title: "阅读")])
        let dates = series.dates(through: date("2026-10-30")).compactMap { $0.map(Beijing.key) }
        XCTAssertEqual(dates, ["2026-10-19", "2026-10-23", "2026-10-26", "2026-10-30"])
        series.exceptions["2026-10-19"] = PersonalOccurrenceState(completed: true, checked: [series.checklist[0].id])
        var moved = series.withoutExceptions
        moved.repeatRule = .none
        moved.dueAt = date("2026-10-24")
        series.exceptions["2026-10-23"] = PersonalOccurrenceState(override: moved)
        let items = series.occurrences(through: date("2026-10-30"))
        XCTAssertTrue(items[0].completed)
        XCTAssertFalse(items[1].completed)
        XCTAssertTrue(items[1].checked.isEmpty)
        XCTAssertEqual(items[1].dueAt, date("2026-10-24"))
        XCTAssertEqual(items[1].key, "2026-10-23")
        XCTAssertEqual(items[2].nativeTask.bucket(now: date("2026-11-01")), .overdue)
        XCTAssertTrue(NativeTaskIndex(tasks: items.map(\.nativeTask)).pendingByCourse.isEmpty)
    }

    func testRemindersFollowEachOccurrenceAndExcludeCompletedPastAndDeleted() {
        var series = PersonalTaskSeries(title: "每日阅读", dueAt: date("2026-10-19"), repeatRule: .daily, reminderMinutes: [0, 60, 1440])
        series.exceptions["2026-10-20"] = PersonalOccurrenceState(completed: true)
        series.exceptions["2026-10-21"] = PersonalOccurrenceState(deleted: true)
        let now = date("2026-10-18")
        let notifications = PersonalNotificationPlan.make(series: [series], now: now, account: 7)
        XCTAssertTrue(notifications.allSatisfy { $0.at > now && $0.at <= Beijing.addDays(30, to: now) })
        XCTAssertFalse(notifications.contains { $0.taskID.hasSuffix("2026-10-20") || $0.taskID.hasSuffix("2026-10-21") })
        XCTAssertEqual(notifications.filter { $0.taskID.hasSuffix("2026-10-19") }.count, 2)
        XCTAssertEqual(Set(notifications.map(\.id)).count, notifications.count)
    }

    func testChangeBaselineNoFloodAndFailureRecoveryDeduplicates() {
        let resource = ChangeResource(id: "1", kind: .assignment, courseID: 4, courseName: "数学", title: "作业", fields: ["截止时间": "无截止时间", "标题": "作业"])
        var state = NativeChangeTracker.applying([ChangeBatch(key: "4:assignment", resources: [resource])], to: NativeLocalAccount(), now: date("2026-10-18"))
        XCTAssertTrue(state.events.isEmpty)
        state = NativeChangeTracker.applying([], to: state, now: date("2026-10-19"))
        state = NativeChangeTracker.applying([ChangeBatch(key: "4:assignment", resources: [])], to: state, now: date("2026-10-20"))
        state = NativeChangeTracker.applying([ChangeBatch(key: "4:assignment", resources: [resource])], to: state, now: date("2026-10-21"))
        XCTAssertTrue(state.events.isEmpty)
        var updated = resource
        updated.fields["截止时间"] = "123"
        updated.fields["标题"] = "新标题"
        state = NativeChangeTracker.applying([ChangeBatch(key: "4:assignment", resources: [updated])], to: state, now: date("2026-10-22"))
        XCTAssertEqual(state.events.count, 1)
        XCTAssertEqual(state.events[0].changes.count, 2)
        state.events[0].read = true
        state = NativeChangeTracker.applying([ChangeBatch(key: "4:assignment", resources: [updated])], to: state, now: date("2026-10-23"))
        XCTAssertEqual(state.events.count, 1)
        XCTAssertTrue(state.events[0].read)
    }

    func testZeroGradePublicationWithdrawalAndFullBodyFingerprint() {
        var row = ChangeResource(id: "1", kind: .grade, courseID: 4, courseName: "数学", title: "作业", fields: ["成绩": "未评分"])
        var saved = NativeChangeTracker.applying([ChangeBatch(key: "grade", resources: [row])], to: NativeLocalAccount(), now: date("2026-10-18"))
        row.fields["成绩"] = "0.0"
        saved = NativeChangeTracker.applying([ChangeBatch(key: "grade", resources: [row])], to: saved, now: date("2026-10-19"))
        row.fields["成绩"] = "未评分"
        saved = NativeChangeTracker.applying([ChangeBatch(key: "grade", resources: [row])], to: saved, now: date("2026-10-20"))
        XCTAssertEqual(saved.events.count, 2)
        XCTAssertNotEqual(NativeChangeTracker.fingerprint(String(repeating: "a", count: 700) + "1"), NativeChangeTracker.fingerprint(String(repeating: "a", count: 700) + "2"))
        XCTAssertEqual(NativeChangeTracker.fingerprint("a  b\n c"), NativeChangeTracker.fingerprint("a b c"))
    }

    func testPersistenceIsAccountScopedAndCorruptionDoesNotOverwrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = NativeLocalRepository(root: root)
        var saved = NativeLocalAccount()
        saved.series = [PersonalTaskSeries(title: "离线任务")]
        try await repository.save(saved, account: 1)
        let restored = try await repository.load(account: 1)
        let other = try await repository.load(account: 2)
        XCTAssertEqual(restored.series[0].title, "离线任务")
        XCTAssertTrue(other.series.isEmpty)
        let broken = root.appendingPathComponent("1.json")
        try Data("broken".utf8).write(to: broken)
        do { _ = try await repository.load(account: 1); XCTFail("Must report corruption") } catch { }
        XCTAssertEqual(try String(contentsOf: broken, encoding: .utf8), "broken")
    }

    @MainActor
    func testStoreSplitFollowingKeepsEarlierHistoryAndAccountIsolation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = NativeAppStore(defaults: defaults, localRepository: NativeLocalRepository(root: root))
        var snapshot = NativeSnapshot(fetchedAt: Date(), profile: NativeProfile(id: 1, name: "测试"), courses: [], terms: [], assignments: [], todo: [], warnings: [], reusedCourseCount: 0)
        await store.applySnapshot(snapshot)
        let draft = PersonalTaskSeries(title: "练习", dueAt: date("2026-10-19"), repeatRule: .daily)
        let success = await store.savePersonal(draft)
        XCTAssertTrue(success)
        let original = try XCTUnwrap(store.tasks.first { $0.personal?.key == "2026-10-19" }?.personal)
        await store.changePersonalState(original, completed: true)
        let second = try XCTUnwrap(store.tasks.first { $0.personal?.key == "2026-10-20" }?.personal)
        var edited = second.task
        edited.title = "新练习"; edited.dueAt = second.dueAt
        let split = await store.savePersonal(edited, occurrence: second, following: true)
        XCTAssertTrue(split)
        XCTAssertEqual(store.tasks.filter { $0.personal?.key == "2026-10-20" }.count, 1)
        XCTAssertTrue(store.taskIndex.byID[original.id]?.personal?.completed == true)
        snapshot.profile.id = 2
        await store.applySnapshot(snapshot)
        XCTAssertTrue(store.tasks.isEmpty)
        snapshot.profile.id = 1
        await store.applySnapshot(snapshot)
        XCTAssertEqual(store.localAccount.series.count, 2)
    }
}
