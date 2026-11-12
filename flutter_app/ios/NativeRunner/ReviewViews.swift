import SwiftUI

struct ReviewCourseView: View {
    @ObservedObject var store: NativeAppStore
    let courseID: Int
    @State private var draft: ReviewPlan?
    var body: some View {
        List {
            Section {
                Text("整理知识点、自测，再按考试日期安排复习。完成任务与自评掌握程度分别记录。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("新建复习计划") { draft = ReviewPlan(courseID: courseID) }.accessibilityIdentifier("review-new-plan")
                NavigationLink("跨课程排期") { ReviewScheduleView(store: store) }
            }
            Section("本课程计划") {
                let plans = store.review.plans.filter { $0.courseID == courseID }
                if plans.isEmpty { Text("暂无计划，可以先整理知识点，考试日期以后再填。").foregroundStyle(.secondary) }
                ForEach(plans) { plan in
                    NavigationLink { ReviewPlanView(store: store, courseID: courseID, planID: plan.id) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(plan.title)
                            Text("\(plan.items.count) 个知识点 · \(plan.examDate.map { "考试 \($0)" } ?? "未设考试日期")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("课程复习")
        .sheet(item: $draft) { ReviewPlanEditor(store: store, initial: $0) }
    }
}

struct ReviewPlanEditor: View {
    @ObservedObject var store: NativeAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ReviewPlan
    @State private var hasExam: Bool
    @State private var exam: Date
    @State private var saving = false
    @State private var error: String?
    @State private var revision: Int
    private let account: Int?
    init(store: NativeAppStore, initial: ReviewPlan) {
        self.store = store; account = store.snapshot?.profile.id
        _draft = State(initialValue: initial); _hasExam = State(initialValue: initial.examDate != nil)
        _exam = State(initialValue: initial.examDate.flatMap(ReviewDomain.validDay) ?? Beijing.addDays(14, to: store.now))
        _revision = State(initialValue: store.review.revision)
    }
    var body: some View {
        NavigationView {
            Form {
                TextField("计划名称", text: $draft.title).accessibilityIdentifier("review-plan-title")
                Toggle("设置考试日期", isOn: $hasExam).accessibilityIdentifier("review-has-exam")
                if hasExam { DatePicker("考试日期", selection: $exam, displayedComponents: .date).environment(\.timeZone, Beijing.calendar.timeZone) }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("复习计划")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中…" : "保存") {
                        guard !saving else { return }; saving = true; draft.examDate = hasExam ? Beijing.key(exam) : nil
                        Task { if await store.changeReview(.plan(draft), revision: revision, account: account) { dismiss() } else { error = store.localError ?? "账号已变化，请重新打开计划。" }; saving = false }
                    }.disabled(saving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("review-plan-save")
                }
            }
            .disabled(saving)
        }.navigationViewStyle(.stack).interactiveDismissDisabled(saving)
    }
}

struct ReviewPlanView: View {
    @ObservedObject var store: NativeAppStore
    let courseID: Int
    let planID: String
    @Environment(\.dismiss) private var dismiss
    @State private var editingPlan: ReviewPlan?
    @State private var editingItem: ReviewItem?
    @State private var quiz: ReviewItem?
    @State private var deleting = false
    @State private var ai = false
    @State private var search = ""
    @State private var limit = 50
    private var plan: ReviewPlan? { store.review.plans.first { $0.id == planID && $0.courseID == courseID } }
    var body: some View {
        List {
            if let plan {
                Section {
                    Text(plan.examDate.map { "考试日期：\($0)" } ?? "尚未设置考试日期，仍可整理与自测。")
                    Button("编辑计划") { editingPlan = plan }
                    Button("添加知识点") { editingItem = ReviewItem() }.accessibilityIdentifier("review-add-item")
                    Button("从课堂摘要生成建议") { ai = true }
                    NavigationLink("跨课程排期") { ReviewScheduleView(store: store) }
                }
                Section("知识点") {
                    let filtered = plan.items.filter { search.isEmpty || ($0.title + $0.notes).localizedCaseInsensitiveContains(search) }
                    if filtered.isEmpty { Text("没有符合条件的知识点。").foregroundStyle(.secondary) }
                    ForEach(Array(filtered.prefix(limit))) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(item.title).font(.headline)
                            Text("预计 \(item.minutes + item.extraMinutes) 分钟 · 已完成 \(ReviewDomain.reviewed(item.id, plan: plan.id, data: store.localAccount)) 分钟").font(.caption).foregroundStyle(.secondary)
                            if !item.notes.isEmpty { Text(item.notes).font(.subheadline).textSelection(.enabled) }
                            Menu {
                                ForEach(ReviewMastery.allCases) { mastery in Button(mastery.title) { change(item) { $0.mastery = mastery } } }
                            } label: { Label(item.mastery.title, systemImage: "checkmark.seal") }
                            HStack {
                                Button("编辑") { editingItem = item }
                                Spacer()
                                Button("自测（\(item.questions.count)）") { quiz = item }.disabled(item.questions.isEmpty)
                                Spacer()
                                Button("再复习一次") { change(item) { $0.extraMinutes += $0.minutes } }
                            }.buttonStyle(.borderless)
                            ForEach(Array(item.sources.enumerated()), id: \.offset) { _, source in
                                ReviewSourceLink(store: store, courseID: courseID, source: source)
                            }
                        }.padding(.vertical, 5)
                    }
                    if filtered.count > limit { Button("显示更多知识点") { limit += 50 } }
                }
                Section("已安排") {
                    let slots = store.review.slots.filter { $0.planID == planID && ReviewDomain.active($0, store.localAccount) }
                    if slots.isEmpty { Text("暂无安排，请先预览跨课程排期。").foregroundStyle(.secondary) }
                    ForEach(Array(slots.prefix(limit))) { slot in
                        VStack(alignment: .leading, spacing: 8) {
                            let done = ReviewDomain.completed(slot, store.localAccount)
                            Text("\(slot.date) · \(slot.allocations.reduce(0) { $0 + $1.minutes }) 分钟 · \(done ? "已完成" : "待复习")")
                            if let task = store.taskIndex.byID["personal:\(slot.taskID):single"] { NavigationLink("查看任务") { TaskDetailDestination(task: task, store: store) } }
                            Button(slot.locked ? "解除锁定" : "锁定安排") { mutate(.lock(slot.id, !slot.locked)) }.disabled(done)
                        }
                    }
                    if slots.count > limit { Button("显示更多安排") { limit += 50 } }
                }
                if let error = store.localError { Section { Text(error).foregroundStyle(.red) } }
                Section { Button("删除计划", role: .destructive) { deleting = true } }
            } else { Text("计划已移除或当前账号不可用。").foregroundStyle(.secondary) }
        }
        .navigationTitle(plan?.title ?? "复习计划")
        .searchable(text: $search, prompt: "搜索知识点")
        .onChange(of: search) { _ in limit = 50 }
        .disabled(store.localSaving)
        .sheet(item: $editingPlan) { ReviewPlanEditor(store: store, initial: $0) }
        .sheet(item: $editingItem) { item in if let plan { ReviewItemEditor(store: store, plan: plan, item: item) } }
        .sheet(item: $quiz) { ReviewQuizView(item: $0) }
        .sheet(isPresented: $ai) { if let plan { ReviewAIView(store: store, lectures: store.lectures, plan: plan) } }
        .confirmationDialog("删除「\(plan?.title ?? "复习计划")」及其复习安排？同课合并任务中其他计划的部分会保留。", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除计划和对应安排", role: .destructive) {
                let revision = store.review.revision, account = store.snapshot?.profile.id
                Task { if await store.changeReview(.remove(planID), revision: revision, account: account) { dismiss() } }
            }
        }
    }
    private func mutate(_ action: ReviewAction) {
        let revision = store.review.revision, account = store.snapshot?.profile.id
        Task { await store.changeReview(action, revision: revision, account: account) }
    }
    private func change(_ item: ReviewItem, _ transform: (inout ReviewItem) -> Void) {
        guard var plan, let index = plan.items.firstIndex(where: { $0.id == item.id }) else { return }
        transform(&plan.items[index]); mutate(.plan(plan))
    }
}

struct ReviewSourceLink: View {
    @ObservedObject var store: NativeAppStore
    let courseID: Int
    let source: ReviewSource
    @State private var status: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NavigationLink(source.title) { LectureReaderView(store: store, lectures: store.lectures, courseID: courseID, reference: source.reference) }
            if !source.quote.isEmpty { Text("来源摘录：\(source.quote)").font(.caption).textSelection(.enabled) }
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
        }.task(id: store.lectures.revision) {
            do { let body = try await store.lectures.body(source.reference, course: courseID)
                if !Task.isCancelled { status = body.item.summaryHash == source.summaryHash ? nil : "来源摘要已更新，原复习内容保留，请自行核对。" }
            } catch { if !Task.isCancelled { status = "来源暂不可读，已保存的复习内容仍可使用。" } }
        }
    }
}

struct ReviewItemEditor: View {
    @ObservedObject var store: NativeAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var plan: ReviewPlan
    @State private var item: ReviewItem
    @State private var revision: Int
    @State private var saving = false
    @State private var deleting = false
    @State private var error: String?
    private let account: Int?
    init(store: NativeAppStore, plan: ReviewPlan, item: ReviewItem) {
        self.store = store; account = store.snapshot?.profile.id
        _plan = State(initialValue: plan); _item = State(initialValue: item); _revision = State(initialValue: store.review.revision)
    }
    var body: some View {
        NavigationView {
            Form {
                Section("知识点") {
                    TextField("标题", text: $item.title).accessibilityIdentifier("review-item-title")
                    TextEditor(text: $item.notes).frame(minHeight: 80).accessibilityLabel("知识点备注")
                    Stepper("预计 \(item.minutes) 分钟", value: $item.minutes, in: 1...1440, step: 5)
                    Picker("掌握程度", selection: $item.mastery) { ForEach(ReviewMastery.allCases) { Text($0.title).tag($0) } }
                }
                Section("自测题，最多 10 题") {
                    ForEach(item.questions.indices, id: \.self) { index in
                        VStack(alignment: .leading) {
                            Text("第 \(index + 1) 题").font(.caption)
                            TextField("题目（支持 Markdown 与公式）", text: $item.questions[index].question).accessibilityIdentifier("review-question-\(index)")
                            TextEditor(text: $item.questions[index].answer).frame(minHeight: 80).accessibilityLabel("第 \(index + 1) 题答案")
                            Button("删除此题", role: .destructive) { item.questions.remove(at: index) }
                        }
                    }
                    Button("添加自测题") { item.questions.append(ReviewQuestion()) }.disabled(item.questions.count >= 10)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if plan.items.contains(where: { $0.id == item.id }) { Section { Button("删除知识点", role: .destructive) { deleting = true } } }
            }
            .navigationTitle("知识点")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "保存中…" : "保存") { save(remove: false) }.disabled(saving || item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("review-item-save") }
            }.disabled(saving)
            .confirmationDialog("删除这个知识点及自测题？", isPresented: $deleting, titleVisibility: .visible) { Button("删除", role: .destructive) { save(remove: true) } }
        }.navigationViewStyle(.stack).interactiveDismissDisabled(saving)
    }
    private func save(remove: Bool) {
        guard !saving else { return }; saving = true
        var next = plan
        if remove { next.items.removeAll { $0.id == item.id } }
        else if let i = next.items.firstIndex(where: { $0.id == item.id }) { next.items[i] = item }
        else { next.items.append(item) }
        Task { if await store.changeReview(.plan(next), revision: revision, account: account) { dismiss() } else { error = store.localError ?? "账号已变化。" }; saving = false }
    }
}

struct ReviewQuizView: View {
    let item: ReviewItem
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var answer = false
    @State private var selection = ""
    @State private var reader = LectureReaderState.loading
    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                if item.questions.indices.contains(index) {
                    Text("第 \(index + 1) / \(item.questions.count) 题").font(.headline)
                    let question = item.questions[index]
                    LectureWebText(content: question.question + (answer ? "\n\n---\n\n参考答案\n\n" + question.answer : ""), markdown: true,
                                   identity: "quiz:\(item.id):\(index):\(answer)", selection: $selection, state: $reader)
                    if case .failed(let message) = reader { Text(message).foregroundStyle(.red) }
                    HStack {
                        Button("上一题") { index -= 1; answer = false }.disabled(index == 0)
                        Spacer()
                        Button(answer ? "隐藏答案" : "显示答案") { answer.toggle() }.accessibilityIdentifier("review-reveal-answer")
                        Spacer()
                        Button("下一题") { index += 1; answer = false }.disabled(index + 1 == item.questions.count)
                    }.padding(.horizontal)
                    Text("参考答案仅供自查，不自动评分或修改掌握程度。").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.vertical).navigationTitle("自测")
                .toolbar { Button("关闭") { dismiss() } }
        }.navigationViewStyle(.stack)
    }
}

struct ReviewScheduleView: View {
    @ObservedObject var store: NativeAppStore
    @State private var budget: [Int]
    @State private var finish: Date
    @State private var start: Date
    @State private var revision: Int
    @State private var preview: ReviewPreview?
    @State private var error: String?
    @State private var result: String?
    @State private var busy = false
    @State private var limit = 100
    private let account: Int?
    init(store: NativeAppStore) {
        self.store = store; account = store.snapshot?.profile.id
        _budget = State(initialValue: store.review.budget); _revision = State(initialValue: store.review.revision)
        _start = State(initialValue: store.now)
        _finish = State(initialValue: ReviewDomain.deadline(Beijing.key(store.now), time: store.review.finishTime) ?? store.now)
    }
    private var time: String { let c = Beijing.calendar.dateComponents([.hour, .minute], from: finish); return String(format: "%02d:%02d", c.hour ?? 21, c.minute ?? 0) }
    var body: some View {
        List {
            Section("所有课程共用的预算") {
                Text("零分钟表示当天不可用。保留已完成和锁定任务，考试当天不安排复习。").font(.caption).foregroundStyle(.secondary)
                ForEach(0..<7, id: \.self) { i in Stepper("\(["周日", "周一", "周二", "周三", "周四", "周五", "周六"][i])：\(budget[i]) 分钟", value: $budget[i], in: 0...720, step: 15) }
                DatePicker("计划完成时间", selection: $finish, displayedComponents: .hourAndMinute).environment(\.timeZone, Beijing.calendar.timeZone)
                DatePicker("开始日期", selection: $start, displayedComponents: .date).environment(\.timeZone, Beijing.calendar.timeZone)
                Button(busy ? "处理中…" : "保存预算并预览排期") { buildPreview() }.accessibilityIdentifier("review-preview")
            }
            if let preview {
                Section("预览，不会立即创建任务") {
                    Text("新增 \(preview.added) 项 · 调整 \(preview.changed) 项 · 移除旧安排 \(preview.removed) 项")
                    ForEach(preview.shortages) { shortage in Text("\(name(shortage.planID))：缺少 \(shortage.minutes) 分钟（\(shortage.reason)）").foregroundStyle(.orange) }
                    ForEach(preview.warnings, id: \.self) { Text($0).foregroundStyle(.orange) }
                    ForEach(Array(preview.slots.prefix(limit))) { slot in
                        VStack(alignment: .leading) {
                            Text("\(slot.date) · \(name(slot.planID))")
                            Text("\(slot.allocations.reduce(0) { $0 + $1.minutes }) 分钟").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if preview.slots.count > limit { Button("显示更多安排") { limit += 100 } }
                    Button("确认并生成个人任务") { confirm(preview) }.accessibilityIdentifier("review-confirm-schedule")
                    Text("同一课程同一天合并为一个任务。旧的未完成、未锁定安排按此预览替换。").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let result { Section { Text(result).accessibilityIdentifier("review-schedule-result") } }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }.navigationTitle("跨课程排期").disabled(busy || store.localSaving)
            .onChange(of: budget) { _ in preview = nil }.onChange(of: finish) { _ in preview = nil }.onChange(of: start) { _ in preview = nil }
    }
    private func name(_ id: String) -> String { store.review.plans.first { $0.id == id }?.title ?? "已删除计划" }
    private func buildPreview() {
        guard !busy else { return }; busy = true; error = nil; result = nil; preview = nil
        Task {
            defer { busy = false }
            guard await store.changeReview(.budget(budget, time), revision: revision, account: account) else { error = store.localError ?? "账号已变化。"; return }
            revision = store.review.revision
            do { preview = try ReviewDomain.preview(store.localAccount, start: Beijing.key(start), now: store.clock.now) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func confirm(_ preview: ReviewPreview) {
        guard !busy else { return }; busy = true; error = nil
        Task {
            defer { busy = false }
            if await store.changeReview(.schedule(preview), revision: preview.revision, account: account) {
                self.preview = nil; revision = store.review.revision; result = "复习安排已保存，可在个人任务中完成或撤销。"
            } else { error = store.localError ?? "账号已变化。" }
        }
    }
}
