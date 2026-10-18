import SwiftUI

struct ChangesView: View {
    @ObservedObject var store: NativeAppStore
    @State private var unreadOnly = false
    @State private var kind: ChangeKind?
    @State private var courseID: Int?
    private var visible: [ChangeEvent] {
        store.localAccount.events.filter { (!unreadOnly || !$0.read) && (kind == nil || $0.resource.kind == kind) && (courseID == nil || $0.resource.courseID == courseID) }
    }
    var body: some View {
        List {
            Section {
                Toggle("仅看未读", isOn: $unreadOnly)
                Picker("类型", selection: $kind) {
                    Text("全部类型").tag(Optional<ChangeKind>.none)
                    ForEach(ChangeKind.allCases) { Text($0.title).tag(Optional($0)) }
                }
                Picker("课程", selection: $courseID) {
                    Text("全部课程").tag(Optional<Int>.none)
                    ForEach(store.snapshot?.courses ?? []) { Text($0.displayName).tag(Optional($0.id)) }
                }
                Button("将当前结果全部标为已读") { let ids = Set(visible.map(\.id)); Task { await store.markChangesRead(ids) } }
                    .disabled(store.localSaving || visible.isEmpty)
            }
            if visible.isEmpty {
                Section { EmptyState(title: "暂无变化。首次成功同步只建立基线，后续更新会在这里出现。", systemImage: "tray") }
            }
            ForEach(visible) { event in
                NavigationLink(destination: ChangeDetailView(event: event, store: store)) { ChangeRow(event: event) }
                    .accessibilityIdentifier("change-\(event.id)")
            }
            if let warning = store.noticeMessage { Section("同步提示") { Text(warning).font(.footnote) } }
            if let error = store.localError { Section { Text(error).foregroundStyle(.red) } }
            Section {
                Text("在应用同步后发现变化；保留最近 180 天、最多 2,000 条。未读状态只在本机记录。")
            }.font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("变化中心")
            .refreshable { await store.refresh() }
    }
}

struct ChangeRow: View {
    let event: ChangeEvent
    var body: some View {
        HStack(alignment: .top) {
            Circle().fill(event.read ? Color.clear : Color.accentColor).frame(width: 7, height: 7).padding(.top, 7)
            VStack(alignment: .leading, spacing: 5) {
                Text(event.title).foregroundStyle(.primary)
                Text(event.resource.courseName).font(.subheadline).foregroundStyle(.secondary)
                Text("发现于 " + Beijing.label(event.discoveredAt, absolute: true).replacingOccurrences(of: " 截止", with: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.read ? "已读" : "未读")，\(event.title)，\(event.resource.courseName)")
    }
}

struct ChangeDetailView: View {
    let event: ChangeEvent
    @ObservedObject var store: NativeAppStore
    private var course: NativeCourse? { store.snapshot?.courses.first { $0.id == event.resource.courseID } }
    private var assignment: NativeTask? {
        guard let id = event.resource.assignmentID else { return nil }
        return store.taskIndex.byID[NativeDomain.assignmentKey(event.resource.courseID, id)]
    }
    var body: some View {
        List {
            Section {
                Text(event.title).font(.headline)
                Text(event.resource.courseName).foregroundStyle(.secondary)
                if let date = Beijing.parse(event.resource.publishedAt) {
                    Text("学校发布时间：" + Beijing.label(date, absolute: true).replacingOccurrences(of: " 截止", with: ""))
                }
            }
            ForEach(event.changes, id: \.self) { field in
                Section(field) {
                    if field == "说明" || field == "正文" {
                        if let old = event.before { Text("此前").font(.caption); Text(old.body.isEmpty ? "无正文" : old.body) }
                        Text("现在").font(.caption)
                        Text(event.resource.body.isEmpty ? "无正文" : event.resource.body).textSelection(.enabled)
                    } else {
                        if let old = event.before { NativeLabeledContent(title: "此前", value: label(old.fields[field], field: field)) }
                        NativeLabeledContent(title: "现在", value: label(event.resource.fields[field], field: field))
                    }
                }
            }
            if assignment?.hasManualDeadline == true {
                Section { Text("此作业当前使用手动截止时间。学校时间的变化不会覆盖你的设置。").font(.footnote) }
            }
            if let assignment { Section { NavigationLink("查看作业") { AssignmentDetailView(task: assignment, store: store) } } }
            if let url = event.resource.url.flatMap(URL.init(string:)), ["https", "http"].contains(url.scheme ?? "") {
                Section { Link("查看学校原文", destination: url) }
            }
            if event.resource.kind == .file, let course { NativeFilesView(store: store, course: course) }
        }.navigationTitle("变化详情")
            .task { await store.markChangesRead([event.id]) }
    }
    private func label(_ text: String?, field: String) -> String {
        guard let text else { return "未设置" }
        if field == "截止时间", let seconds = Double(text) { return Beijing.label(Date(timeIntervalSince1970: seconds), absolute: true) }
        return text
    }
}
