import SwiftUI

struct TaskDetailDestination: View {
    let task: NativeTask
    @ObservedObject var store: NativeAppStore
    var body: some View {
        if let personal = task.personal { PersonalTaskDetail(occurrence: personal, store: store) }
        else { AssignmentDetailView(task: task, store: store) }
    }
}

struct PersonalTaskDetail: View {
    let occurrence: PersonalOccurrence
    @ObservedObject var store: NativeAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var choosingEdit = false
    @State private var choosingDelete = false
    @State private var following = false
    private var current: PersonalOccurrence { store.taskIndex.byID[occurrence.id]?.personal ?? occurrence }
    private var repeated: Bool { (store.localAccount.series.first { $0.id == occurrence.seriesID }?.repeatRule ?? .none) != .none }

    var body: some View {
        List {
            Section {
                Text(current.task.title).font(.headline)
                NativeLabeledContent(title: "课程", value: current.task.courseName)
                NativeLabeledContent(title: "截止时间", value: Beijing.label(current.dueAt, absolute: true))
                Button(current.completed ? "恢复为未完成" : "标记完成") {
                    Task { await store.changePersonalState(current, completed: !current.completed) }
                }.accessibilityIdentifier("personal-complete")
                if repeated { Text("每一期独立完成，未完成的往期任务会保留。").font(.footnote).foregroundStyle(.secondary) }
            }
            if !current.task.notes.isEmpty { Section("备注") { Text(current.task.notes).textSelection(.enabled) } }
            if let source = current.task.lectureSource, let courseID = current.task.courseID {
                Section("课堂来源") { NavigationLink(source.title) { LectureReaderView(store: store, lectures: store.lectures, courseID: courseID, reference: source.reference) } }
            }
            if !current.task.checklist.isEmpty {
                Section("子任务 \(current.checked.count)/\(current.task.checklist.count)") {
                    ForEach(current.task.checklist) { item in
                        Button { Task { await store.changePersonalState(current, checklistID: item.id) } } label: {
                            Label(item.title, systemImage: current.checked.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(current.checked.contains(item.id) ? Color.secondary : Color.primary)
                        }
                    }
                }
            }
            Section("提醒与日历") {
                if current.task.reminderMinutes.isEmpty { Text("未设置提醒").foregroundStyle(.secondary) }
                ForEach(current.task.reminderMinutes, id: \.self) { Text($0 == 0 ? "截止时提醒" : "提前 \($0) 分钟") }
                if let notice = store.reminderNotice { Text(notice).foregroundStyle(.secondary) }
                if current.dueAt != nil {
                    Button("添加本次任务到系统日历") { Task { _ = await store.presentCalendarEditor(for: current.nativeTask) } }
                    Text("单向添加；修改任务后需自行更新系统日历。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let error = store.localError { Section { Text(error).foregroundStyle(.red) } }
            Section { Button("删除任务", role: .destructive) { choosingDelete = true } }
        }
        .navigationTitle("个人任务")
        .toolbar { Button("编辑") { if repeated { choosingEdit = true } else { following = false; editing = true } } }
        .disabled(store.localSaving)
        .confirmationDialog("编辑重复任务", isPresented: $choosingEdit, titleVisibility: .visible) {
            Button("仅这一次") { following = false; editing = true }
            Button("这一次及以后") { following = true; editing = true }
        }
        .confirmationDialog("删除后无法恢复", isPresented: $choosingDelete, titleVisibility: .visible) {
            Button(repeated ? "仅删除这一次" : "删除任务", role: .destructive) { remove(false) }
            if repeated { Button("删除这一次及以后", role: .destructive) { remove(true) } }
        }
        .sheet(isPresented: $editing) { PersonalTaskEditor(store: store, occurrence: current, following: following) }
    }
    private func remove(_ all: Bool) {
        Task { if await store.deletePersonal(current, following: all) { dismiss() } }
    }
}

struct PersonalTaskEditor: View {
    @ObservedObject var store: NativeAppStore
    var occurrence: PersonalOccurrence?
    var following: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PersonalTaskSeries
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var hasEnd: Bool
    @State private var endDate: Date
    @State private var checklistText = ""
    @State private var reminderDate: Date
    @State private var addingReminder = false
    @State private var saving = false
    @State private var validation: String?

    init(store: NativeAppStore, occurrence: PersonalOccurrence? = nil, following: Bool = false, initialDraft: PersonalTaskSeries? = nil) {
        self.store = store; self.occurrence = occurrence; self.following = following
        var value = occurrence?.task.withoutExceptions ?? initialDraft ?? PersonalTaskSeries()
        if let occurrence { value.dueAt = occurrence.dueAt }
        if following, let parent = store.localAccount.series.first(where: { $0.id == occurrence?.seriesID }) {
            value.repeatRule = parent.repeatRule; value.weekdays = parent.weekdays; value.endDate = parent.endDate
        }
        if occurrence != nil && !following { value.repeatRule = .none }
        let defaultDue = Beijing.calendar.date(bySettingHour: 23, minute: 59, second: 0, of: Beijing.addDays(1, to: Date()))!
        let date = value.dueAt ?? defaultDue
        _draft = State(initialValue: value)
        _hasDeadline = State(initialValue: value.dueAt != nil)
        _deadline = State(initialValue: date)
        _hasEnd = State(initialValue: value.endDate != nil)
        _endDate = State(initialValue: value.endDate ?? Beijing.addDays(90, to: date))
        _reminderDate = State(initialValue: date.addingTimeInterval(-3600))
    }

    private var mayRepeat: Bool { occurrence == nil || following || store.localAccount.series.first(where: { $0.id == occurrence?.seriesID })?.repeatRule == PersonalRepeat.none }

    var body: some View {
        NavigationView {
            Form {
                Section("任务") {
                    TextField("任务标题", text: $draft.title).accessibilityIdentifier("personal-title")
                    Text("备注").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $draft.notes).frame(minHeight: 72).accessibilityIdentifier("personal-notes")
                    Picker("关联课程", selection: $draft.courseID) {
                        Text("不关联课程").tag(Optional<Int>.none)
                        ForEach(store.snapshot?.courses ?? []) { course in Text(course.displayName).tag(Optional(course.id)) }
                    }
                    Toggle("设置截止时间", isOn: $hasDeadline).accessibilityIdentifier("personal-has-deadline")
                    if hasDeadline {
                        DatePicker("截止日期与时间", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
                            .accessibilityIdentifier("personal-deadline")
                    }
                }
                if hasDeadline && mayRepeat { recurrenceSection }
                Section("子任务清单") {
                    ForEach($draft.checklist) { $item in TextField("子任务标题", text: $item.title) }
                        .onDelete { draft.checklist.remove(atOffsets: $0) }
                        .onMove { draft.checklist.move(fromOffsets: $0, toOffset: $1) }
                    HStack {
                        TextField("添加子任务", text: $checklistText).accessibilityIdentifier("personal-subtask")
                        Button("添加") {
                            let title = checklistText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !title.isEmpty { draft.checklist.append(PersonalChecklistItem(title: title)); checklistText = "" }
                        }.disabled(checklistText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if !draft.checklist.isEmpty { EditButton() }
                }
                if hasDeadline { reminderSection }
                if let text = validation ?? store.localError { Section { Text(text).foregroundStyle(.red) } }
                Section {
                    Text("北京时间 · 仅保存在本机当前账号。重复任务各期独立，提醒随截止时间移动。")
                    Text("提醒安排未来 30 天内最近 60 条，打开应用时补充；长期不打开应用可能无法持续提醒。")
                }.font(.footnote).foregroundStyle(.secondary)
            }
            .environment(\.timeZone, Beijing.timeZone).environment(\.calendar, Beijing.calendar)
            .navigationTitle(occurrence == nil ? "新建个人任务" : "编辑个人任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(saving || store.localSaving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("personal-save")
                }
            }
            .disabled(saving)
        }.navigationViewStyle(.stack).interactiveDismissDisabled(saving)
    }

    private var recurrenceSection: some View {
        Section("重复") {
            Picker("重复规则", selection: $draft.repeatRule) {
                ForEach(PersonalRepeat.allCases) { Text($0.title).tag($0) }
            }
            if draft.repeatRule == .weekly {
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                    Toggle(["", "星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"][day], isOn: Binding(
                        get: { draft.weekdays.contains(day) }, set: { if $0 { draft.weekdays.insert(day) } else { draft.weekdays.remove(day) } }))
                }
            }
            if draft.repeatRule != .none {
                Toggle("设置结束日期", isOn: $hasEnd)
                if hasEnd { DatePicker("结束日期", selection: $endDate, in: Beijing.day(deadline)..., displayedComponents: .date) }
                if draft.repeatRule == .monthly { Text("每月按首次日期重复；没有该日期时取月末。").font(.footnote) }
            }
        }
    }

    private var reminderSection: some View {
        Section("提醒（最多 5 个）") {
            ForEach(draft.reminderMinutes.sorted(), id: \.self) { lead in
                HStack {
                    Text(lead == 0 ? "截止时" : "提前 \(lead) 分钟")
                    Spacer()
                    Button(role: .destructive) { draft.reminderMinutes.removeAll { $0 == lead } } label: { Image(systemName: "minus.circle") }
                }
            }
            if draft.reminderMinutes.count < 5 {
                Menu("添加常用提醒") {
                    ForEach([0, 15, 60, 1440], id: \.self) { value in
                        Button(value == 0 ? "截止时" : "提前 \(value) 分钟") { addReminder(value) }
                    }
                }
                Toggle("自定义提醒时刻", isOn: $addingReminder)
                if addingReminder {
                    DatePicker("提醒时刻", selection: $reminderDate, in: deadline.addingTimeInterval(-366 * 86400)...deadline, displayedComponents: [.date, .hourAndMinute])
                    Button("添加此提醒") {
                        addReminder(max(0, Int((deadline.timeIntervalSince(reminderDate) / 60).rounded())))
                        addingReminder = false
                    }
                    Text("保存为相对截止时间的提前量，重复时自动沿用；已过去的提醒不补发。").font(.footnote)
                }
            }
        }
    }
    private func addReminder(_ minutes: Int) {
        if !draft.reminderMinutes.contains(minutes), draft.reminderMinutes.count < 5 { draft.reminderMinutes.append(minutes) }
    }
    private func save() {
        draft.dueAt = hasDeadline ? deadline : nil
        draft.endDate = hasEnd && draft.repeatRule != .none ? endDate : nil
        draft.checklist = draft.checklist.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let id = draft.courseID { draft.courseName = store.snapshot?.courses.first { $0.id == id }?.displayName ?? draft.courseName }
        else { draft.courseName = "个人任务" }
        saving = true
        Task {
            if await store.savePersonal(draft, occurrence: occurrence, following: following) { dismiss() }
            saving = false
        }
    }
}
