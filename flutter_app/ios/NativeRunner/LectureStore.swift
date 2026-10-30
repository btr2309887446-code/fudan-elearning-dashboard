import Foundation
import SwiftUI

@MainActor
final class LectureStore: ObservableObject {
    @Published private(set) var connection = LectureConnection()
    @Published private(set) var busy = false
    @Published var message: String?
    @Published private(set) var revision = 0
    private(set) var account: Int?
    private var generation = 0
    private var service: LectureService?
    func activate(account: Int?, demo: [NativeCourse]? = nil) async {
        guard self.account != account else { return }
        generation += 1; let token = generation
        let old = service; service = nil; self.account = account; connection = LectureConnection(); message = nil; busy = false
        await old?.cancel()
        guard token == generation, let account else { return }
        let current = LectureService(account: account); service = current
        do { let state = try await current.restore(demo: demo); guard token == generation else { return }; connection = state; revision += 1 }
        catch { if token == generation { message = error.localizedDescription } }
    }
    func operate(_ action: @escaping (LectureService) async throws -> LectureConnection, store: NativeAppStore) async {
        guard !busy, let service, account == store.snapshot?.profile.id else { return }
        busy = true; message = nil; let token = generation
        defer { if token == generation { busy = false } }
        do {
            let result = try await action(service)
            guard token == generation, account == store.snapshot?.profile.id else { return }
            connection = result; message = result.error; revision += 1
            let batches = try await service.batches(courses: store.snapshot?.courses ?? [])
            guard token == generation, let account else { return }
            await store.recordChanges(batches, account: account)
            if let error = store.localError { message = "笔记可阅读，但变化记录未保存：\(error)" }
        } catch { if token == generation { message = error.localizedDescription } }
    }
    func sync(store: NativeAppStore) async { await operate({ try await $0.sync() }, store: store) }
    func page(course: Int, search: String = "", offset: Int = 0) async throws -> LecturePage {
        guard let service else { throw NativeError.protocolFailure("课堂笔记正在初始化，请稍候。") }
        let token = generation; let page = try await service.page(course: course, search: search, offset: offset)
        guard token == generation else { throw CancellationError() }; return page
    }
    func body(_ reference: LectureReference, course: Int) async throws -> LectureBody {
        guard let service else { throw NativeError.protocolFailure("请先连接课堂笔记。") }
        let token = generation; let body = try await service.body(reference, course: course)
        guard token == generation else { throw CancellationError() }; return body
    }
    func read(_ body: LectureBody, course: Int) async throws {
        guard let service else { throw CancellationError() }
        let token = generation
        try await service.read(body.item.reference, course: course, hash: body.item.summaryHash)
        guard token == generation else { throw CancellationError() }; revision += 1
    }
}

extension NativeAppStore {
    func lectureIntroduction(course: NativeCourse, force: Bool = false) async throws -> LectureIntroduction {
        guard let account = snapshot?.profile.id else { throw NativeError.protocolFailure("请先登录。") }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return LectureIntroduction(description: "这是虚构课程简介，介绍核心概念与课堂讨论。", teachers: ["示例教师"]) }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Classroom/\(account)", isDirectory: true)
        let file = directory.appendingPathComponent("intro-\(course.id).json")
        let cached = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(LectureIntroduction.self, from: $0) }
        if !force, let cached, Date().timeIntervalSince(cached.fetchedAt) < 86400 { return cached }
        do {
            let api = CanvasAPI(http: NativeHTTP(cookies: cookies))
            let raw = try await api.get("/api/v1/courses/\(course.id)", query: [URLQueryItem(name: "include[]", value: "syllabus_body"), URLQueryItem(name: "include[]", value: "teachers")])
            guard snapshot?.profile.id == account else { throw CancellationError() }
            guard let value = raw as? [String: Any], CanvasJSON.int(value["id"]) == course.id else { throw NativeError.protocolFailure("课程简介响应不匹配。") }
            let teachers = (value["teachers"] as? [[String: Any]] ?? []).compactMap { CanvasJSON.string($0["display_name"]) ?? CanvasJSON.string($0["name"]) }
            let result = LectureIntroduction(description: NativeDomain.summarize(CanvasJSON.string(value["syllabus_body"]) ?? ""), teachers: Array(Set(teachers)).sorted())
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(result).write(to: file, options: [.atomic, .completeFileProtection])
            return result
        } catch { if snapshot?.profile.id == account, let cached { return cached }; throw error }
    }
}
