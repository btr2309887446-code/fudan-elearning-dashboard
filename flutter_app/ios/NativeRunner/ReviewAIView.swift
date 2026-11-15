import SwiftUI

struct ReviewAIView: View {
    @ObservedObject var store: NativeAppStore
    @ObservedObject var lectures: LectureStore
    @Environment(\.dismiss) private var dismiss
    @State private var plan: ReviewPlan
    @State private var revision: Int
    @State private var page: [LectureItem] = []
    @State private var total = 0
    @State private var selected: Set<String> = []
    @State private var batches: [ReviewAIBatch] = []
    @State private var next = 0
    @State private var suggestions: [ReviewItem] = []
    @State private var excluded: Set<String> = []
    @State private var busy = false
    @State private var saving = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    @State private var preparedConfig: NativeLLMConfig?
    private let account: Int?
    init(store: NativeAppStore, lectures: LectureStore, plan: ReviewPlan) {
        self.store = store; self.lectures = lectures; account = store.snapshot?.profile.id
        _plan = State(initialValue: plan); _revision = State(initialValue: store.review.revision)
    }
    var body: some View {
        NavigationView {
            List {
                Section("只使用你选择的课堂摘要") {
                    Text("不会发送转写或 PPT。先核对服务与材料，再手动生成；可能产生模型费用。生成内容需自行检查。").font(.caption).foregroundStyle(.secondary)
                    ForEach(page) { item in
                        Toggle(item.title, isOn: Binding(get: { selected.contains(item.id) }, set: { value in
                            if value { selected.insert(item.id) } else { selected.remove(item.id) }; batches = []; next = 0
                        })).disabled(busy || !suggestions.isEmpty)
                    }
                    if page.count < total { Button("加载更多课次") { operation = Task { await loadPage() } }.disabled(busy) }
                    Button("检查材料和服务") { prepare() }.disabled(busy || selected.isEmpty || !suggestions.isEmpty)
                }
                if !batches.isEmpty, let config = preparedConfig {
                    Section("发送前确认") {
                        Text("服务：\(config.baseURL)\n模型：\(config.model)").textSelection(.enabled)
                        Text("\(selected.count) 次课 · \(batches.reduce(0) { $0 + $1.text.count }) 字 · \(batches.count) 批；已完成 \(next) 批")
                        if next < batches.count { Button(busy ? "生成中…" : "确认发送并继续生成") { generate() }.disabled(busy) }
                        if busy { Button("停止，保留成功结果") { operation?.cancel() } }
                    }
                }
                if !suggestions.isEmpty {
                    Section("编辑并选择要保存的建议") {
                        ForEach(suggestions.indices, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 8) {
                                let id = suggestions[i].id
                                Toggle("加入计划", isOn: Binding(get: { !excluded.contains(id) }, set: { if $0 { excluded.remove(id) } else { excluded.insert(id) } }))
                                TextField("知识点标题", text: $suggestions[i].title)
                                TextEditor(text: $suggestions[i].notes).frame(minHeight: 60).accessibilityLabel("建议备注")
                                Stepper("预计 \(suggestions[i].minutes) 分钟", value: $suggestions[i].minutes, in: 1...1440)
                                ForEach(suggestions[i].questions.indices, id: \.self) { q in
                                    TextField("自测题", text: $suggestions[i].questions[q].question)
                                    TextEditor(text: $suggestions[i].questions[q].answer).frame(minHeight: 60).accessibilityLabel("参考答案")
                                }
                                ForEach(Array(suggestions[i].sources.enumerated()), id: \.offset) { _, source in Text("\(source.title)：\(source.quote)").font(.caption).textSelection(.enabled) }
                            }
                        }
                        Button(saving ? "保存中…" : "保存选中的建议") { save() }.disabled(busy || saving || suggestions.allSatisfy { excluded.contains($0.id) })
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("摘要生成复习建议")
                .toolbar { Button("关闭") { operation?.cancel(); dismiss() }.disabled(saving) }
                .task { await loadPage() }
                .onDisappear { operation?.cancel() }
                .onChange(of: lectures.account) { _ in operation?.cancel(); dismiss() }
        }.navigationViewStyle(.stack).interactiveDismissDisabled(saving)
    }
    private func check(_ source: ReviewSource? = nil) throws {
        try Task.checkCancellation()
        guard account != nil, store.snapshot?.profile.id == account, lectures.account == account else { throw CancellationError() }
        if let source { guard lectures.connection.sourceID == source.reference.sourceID, lectures.connection.bindings[source.reference.courseID] == plan.courseID else { throw ReviewDomain.failure("课堂来源或关联已变化，请重新打开生成页面。") } }
    }
    private func loadPage() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try check(); let result = try await lectures.page(course: plan.courseID, offset: page.count); try check(); page += result.items; total = result.total }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func prepare() {
        guard !busy else { return }; busy = true; error = nil
        operation = Task {
            defer { busy = false }
            do {
                try check(); var bodies: [LectureBody] = []
                for item in page where selected.contains(item.id) { bodies.append(try await lectures.body(item.reference, course: plan.courseID)); try check() }
                batches = try ReviewAI.batches(bodies); preparedConfig = store.preferences.llm; next = 0
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func generate() {
        guard !busy, let config = preparedConfig else { return }; busy = true; error = nil
        operation = Task {
            defer { busy = false }
            do {
                while next < batches.count {
                    let batch = batches[next]; try check(batch.source)
                    let before = try await lectures.body(batch.source.reference, course: plan.courseID)
                    guard before.item.summaryHash == batch.source.summaryHash else { throw ReviewDomain.failure("摘要已更新，已成功结果保留；请保存或关闭后重新选择材料。") }
                    let items = try await ReviewAI.generate(batch, config: config, key: NativeSecrets.read("native.llm.apiKey") ?? "")
                    try check(batch.source)
                    let after = try await lectures.body(batch.source.reference, course: plan.courseID)
                    guard after.item.summaryHash == batch.source.summaryHash else { throw ReviewDomain.failure("生成期间摘要已更新，本批结果未采用。") }
                    try check(batch.source)
                    for item in items where !suggestions.contains(where: { $0.title == item.title && $0.sources == item.sources }) { suggestions.append(item) }
                    next += 1
                }
            } catch { if Task.isCancelled { self.error = "已停止，成功结果保留，可继续剩余批次。" } else { self.error = error.localizedDescription } }
        }
    }
    private func save() {
        guard !saving, !busy else { return }; saving = true; error = nil
        operation = Task {
            defer { saving = false }
            do {
                try check(); var draft = plan
                let chosen = suggestions.filter { !excluded.contains($0.id) }
                for source in chosen.flatMap(\.sources) { try check(source) }
                draft.items += chosen
                if await store.changeReview(.plan(draft), revision: revision, account: account) { dismiss() }
                else { error = store.localError ?? "账号已变化，未保存。" }
            } catch { self.error = error.localizedDescription }
        }
    }
}
