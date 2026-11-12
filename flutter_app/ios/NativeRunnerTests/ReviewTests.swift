import XCTest
@testable import NativeRunner

final class ReviewTests: XCTestCase {
    private let start = "2026-11-13"
    private var now: Date { Beijing.parse("2026-11-13T12:00:00+08:00")! }
    private func plan(_ id: String, course: Int = 1, minutes: Int = 90) -> ReviewPlan {
        ReviewPlan(id: id, courseID: course, examDate: "2026-11-16", items: [ReviewItem(id: id + "-item", title: "知识点", minutes: minutes)])
    }
    func testSharedBudgetMergesCourseDayAndPreservesOtherPlansOnDelete() throws {
        var data = NativeLocalAccount()
        try ReviewDomain.apply(.plan(plan("a", minutes: 30)), revision: 0, to: &data, now: now)
        try ReviewDomain.apply(.plan(plan("b", minutes: 30)), revision: 1, to: &data, now: now)
        let preview = try ReviewDomain.preview(data, start: start, now: now)
        XCTAssertEqual(preview.slots.count, 2)
        try ReviewDomain.apply(.schedule(preview), revision: 2, to: &data, now: now)
        XCTAssertEqual(data.series.count, 1)
        XCTAssertEqual(Set(data.review!.slots.map(\.taskID)).count, 1)
        try ReviewDomain.apply(.remove("a"), revision: 3, to: &data, now: now)
        XCTAssertEqual(data.series.count, 1)
        XCTAssertEqual(data.series[0].reviewSource?.planID, "b")
        XCTAssertTrue(data.series[0].title.contains("30 分钟"))
    }
    func testBudgetShortageCompletionUndoAndLock() throws {
        var data = NativeLocalAccount()
        try ReviewDomain.apply(.plan(plan("a", minutes: 200)), revision: 0, to: &data, now: now)
        let preview = try ReviewDomain.preview(data, start: start, now: now)
        XCTAssertEqual(preview.shortages.first?.minutes, 20)
        XCTAssertEqual(preview.slots.map { $0.allocations.reduce(0) { $0 + $1.minutes } }, [60, 60, 60])
        try ReviewDomain.apply(.schedule(preview), revision: 1, to: &data, now: now)
        data.series[0].exceptions["single"] = PersonalOccurrenceState(completed: true)
        XCTAssertEqual(ReviewDomain.reviewed("a-item", plan: "a", data: data), 60)
        XCTAssertEqual(data.review?.plans[0].items[0].mastery, .unassessed)
        let retained = try ReviewDomain.preview(data, start: start, now: now)
        XCTAssertFalse(retained.slots.contains { $0.date == start })
        data.series[0].exceptions["single"]?.completed = false
        XCTAssertEqual(ReviewDomain.reviewed("a-item", plan: "a", data: data), 0)
        try ReviewDomain.apply(.lock(data.review!.slots[0].id, true), revision: 2, to: &data, now: now)
        XCTAssertFalse(try ReviewDomain.preview(data, start: start, now: now).slots.contains { $0.date == start })
    }
    func testStalePreviewAndPassedTimeNeverCreateOverdueTasks() throws {
        var data = NativeLocalAccount()
        try ReviewDomain.apply(.plan(plan("a")), revision: 0, to: &data, now: now)
        let preview = try ReviewDomain.preview(data, start: start, now: now)
        let evening = Beijing.parse("2026-11-13T21:01:00+08:00")!
        XCTAssertThrowsError(try ReviewDomain.apply(.schedule(preview), revision: 1, to: &data, now: evening))
        XCTAssertTrue(data.series.isEmpty)
        XCTAssertEqual(try ReviewDomain.preview(data, start: start, now: evening).slots.first?.date, "2026-11-14")
        XCTAssertThrowsError(try ReviewDomain.apply(.plan(plan("b")), revision: 0, to: &data, now: now))
    }
    func testLegacyDataAndAccountIsolation() async throws {
        let bytes = Data(#"{"version":1,"series":[],"baselines":{},"events":[],"personalRemindersEnabled":true}"#.utf8)
        var data = try JSONDecoder().decode(NativeLocalAccount.self, from: bytes)
        XCTAssertNil(data.review)
        try ReviewDomain.apply(.plan(plan("a")), revision: 0, to: &data, now: now)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = NativeLocalRepository(root: root)
        try await repo.save(data, account: 1)
        let restored = try await repo.load(account: 1), other = try await repo.load(account: 2)
        XCTAssertEqual(restored.review?.plans.count, 1); XCTAssertNil(other.review)
    }
    func testAIRejectsInventedQuotesAndPreservesAllChunks() throws {
        let ref = LectureReference(sourceID: "demo", courseID: "course", lectureID: "lecture")
        let item = LectureItem(reference: ref, title: "示例课", date: start, courseTitle: "示例", teacher: "", summaryHash: "hash", shard: "demo")
        let summary = String(repeating: "原始课堂内容", count: 3000)
        let batches = try ReviewAI.batches([LectureBody(item: item, summary: summary, transcript: "不应发送", pages: [])])
        XCTAssertEqual(batches.map(\.text).joined(), summary)
        let valid = #"{"items":[{"title":"知识点","notes":"","minutes":30,"questions":[],"quote":"原始课堂内容"}]}"#
        XCTAssertEqual(try ReviewAI.decode(valid, batch: batches[0]).count, 1)
        XCTAssertThrowsError(try ReviewAI.decode(valid.replacingOccurrences(of: "原始课堂内容", with: "编造的来源摘录"), batch: batches[0]))
    }
}
