import SwiftUI
import WebKit

struct CourseOverviewSections: View {
    @ObservedObject var store: NativeAppStore
    @ObservedObject var lectures: LectureStore
    let course: NativeCourse
    @State private var introduction: LectureIntroduction?
    @State private var items: [LectureItem] = []
    @State private var error: String?
    private var teachers: [String] {
        if let introduction, !introduction.teachers.isEmpty { return introduction.teachers }
        return lectures.connection.courses.filter { lectures.connection.bindings[$0.id] == course.id }.map(\.teacher).filter { !$0.isEmpty }
    }
    var body: some View {
        Section("课程简介") {
            if !teachers.isEmpty { Text("教师：" + teachers.joined(separator: "、") + (introduction?.teachers.isEmpty != false ? "（iCourse）" : "")).font(.subheadline) }
            if let introduction {
                Text(introduction.description.isEmpty ? "学校暂未提供课程简介。" : introduction.description).textSelection(.enabled)
                Text("简介保存于 \(introduction.fetchedAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
            } else if error == nil { ProgressView("正在读取课程简介…") }
            if let error { Text(error).font(.footnote).foregroundStyle(.red); Button("重试课程简介") { Task { await loadIntroduction(force: true) } } }
        }
        Section("近期待办") {
            let pending = store.tasks.filter { $0.courseID == course.id && $0.status == .pending }.prefix(5)
            if pending.isEmpty { Text("这门课暂时没有待办。").foregroundStyle(.secondary) }
            ForEach(Array(pending)) { TaskNavigationRow(task: $0, store: store) }
        }
        Section("最近课堂笔记") {
            ForEach(items.prefix(3)) { item in
                NavigationLink { LectureReaderView(store: store, lectures: lectures, courseID: course.id, reference: item.reference) } label: { LectureRow(item: item) }
            }
            if lectures.connection.locked || !lectures.connection.configured {
                Text("连接并解锁订阅仓库后，可阅读本课程的课堂笔记。").font(.footnote).foregroundStyle(.secondary)
                NavigationLink("连接课堂笔记") { LectureSettingsView(store: store, lectures: lectures) }
            } else {
                if items.isEmpty { Text("暂无已关联的课堂笔记。").foregroundStyle(.secondary) }
                NavigationLink("查看全部课堂笔记") { LectureListView(store: store, lectures: lectures, course: course) }
            }
        }
        .task(id: lectures.revision) { items = (try? await lectures.page(course: course.id).items) ?? [] }
        .task(id: course.id) { await loadIntroduction() }
    }
    private func loadIntroduction(force: Bool = false) async {
        error = nil
        do { let value = try await store.lectureIntroduction(course: course, force: force); if !Task.isCancelled { introduction = value } }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
struct LectureRow: View {
    let item: LectureItem
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title).font(.headline)
            Text(item.date + " · " + (item.updated ? "摘要更新" : item.read ? "已读" : "未读")).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}
struct LectureListView: View {
    @ObservedObject var store: NativeAppStore
    @ObservedObject var lectures: LectureStore
    let course: NativeCourse
    @State private var query = ""
    @State private var offset = 0
    @State private var page = LecturePage(items: [], total: 0)
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        List {
            Section {
                if let error { Text(error).foregroundStyle(.red); Button("重试") { Task { await load() } } }
                if let message = lectures.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                if loading { ProgressView("正在读取课次…") }
                ForEach(page.items) { item in
                    NavigationLink { LectureReaderView(store: store, lectures: lectures, courseID: course.id, reference: item.reference) } label: { LectureRow(item: item) }
                }
                if page.total == 0 && !loading && error == nil { Text("暂无课堂笔记。请先确认课程关联，或等待订阅仓库生成内容。").foregroundStyle(.secondary) }
            } header: { Text(course.displayName + " · \(page.total) 次课") }
            if page.total > 50 {
                Section {
                    Button("上一页") { offset = max(0, offset - 50) }.disabled(offset == 0 || loading)
                    Text("\(offset + 1)–\(min(offset + 50, page.total)) / \(page.total)").font(.caption)
                    Button("下一页") { offset += 50 }.disabled(offset + 50 >= page.total || loading)
                }
            }
            Section { NavigationLink("连接与课程关联") { LectureSettingsView(store: store, lectures: lectures) } }
        }
        .navigationTitle("课堂笔记")
        .searchable(text: $query, prompt: "搜索课次、日期、教师")
        .onChange(of: query) { _ in offset = 0 }
        .task(id: "\(query)|\(offset)|\(lectures.revision)") {
            do { try await Task.sleep(nanoseconds: 180_000_000); await load() } catch { }
        }
        .refreshable { await lectures.sync(store: store) }
    }
    private func load() async {
        loading = true; defer { if !Task.isCancelled { loading = false } }
        do { let result = try await lectures.page(course: course.id, search: query, offset: offset); guard !Task.isCancelled else { return }; page = result; error = nil }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct LectureReaderView: View {
    @ObservedObject var store: NativeAppStore
    @ObservedObject var lectures: LectureStore
    let courseID: Int
    let reference: LectureReference
    @State private var bodyValue: LectureBody?
    @State private var error: String?
    @State private var tab = "summary"
    @State private var selection = ""
    @State private var draft: PersonalTaskSeries?
    @State private var showItems = false
    @State private var retry = 0
    @State private var readError: String?
    @State private var createdID: String?
    @State private var readerState: LectureReaderState = .loading
    @State private var readerGeneration = 0
    private var content: String {
        guard let value = bodyValue else { return "" }
        switch tab { case "transcript": return value.transcript; case "ppt": return value.pages.joined(separator: "\n\n"); default: return value.summary }
    }
    private var actions: [String] {
        guard let summary = bodyValue?.summary else { return [] }
        return LectureActions.extract(summary)
    }
    var body: some View {
        VStack(spacing: 0) {
            if let value = bodyValue {
                VStack(alignment: .leading, spacing: 8) {
                    Text(value.item.title).font(.headline)
                    Text(value.item.courseTitle + " · " + value.item.date).font(.caption).foregroundStyle(.secondary)
                    Picker("阅读内容", selection: $tab) {
                        Text("摘要").tag("summary"); Text("转写").tag("transcript"); Text("PPT 文字").tag("ppt")
                    }.pickerStyle(.segmented).accessibilityIdentifier("lecture-reading-tabs")
                    Text(tab == "summary" ? "AI 生成的摘要，请结合教师原意核对。" : "自动识别内容，可能存在遗漏或错误。").font(.caption).foregroundStyle(.secondary)
                    if let readError { Text(readError).font(.footnote).foregroundStyle(.red); Button("重试保存已读") { Task { await markRead(value) } } }
                    if let createdID, let task = store.taskIndex.byID.values.first(where: { $0.personal?.seriesID == createdID }) {
                        NavigationLink("查看刚创建的任务") { TaskDetailDestination(task: task, store: store) }
                    }
                }.padding()
                Divider()
                ZStack {
                    LectureWebText(content: content.isEmpty ? "暂无此项内容。" : content, markdown: tab == "summary", identity: reference.key + tab, selection: $selection, state: $readerState)
                        .id(readerGeneration)
                    if readerState == .loading {
                        ProgressView("正在准备正文…").padding().background(.regularMaterial).cornerRadius(8)
                            .accessibilityIdentifier("lecture-reader-loading").allowsHitTesting(false)
                    }
                    if case .failed(let message) = readerState {
                        VStack(spacing: 12) {
                            Text(message).multilineTextAlignment(.center)
                            Button("重新加载正文") { readerState = .loading; readerGeneration += 1 }
                        }.padding().background(.regularMaterial).cornerRadius(8)
                    }
                }
                Divider()
                HStack {
                    Button("选中文字建任务") { create(selection) }.disabled(selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    Button("课堂事项（\(actions.count)）") { showItems = true }.disabled(actions.isEmpty)
                }.font(.subheadline).padding().background(Color(UIColor.secondarySystemBackground))
            } else if error == nil { Spacer(); ProgressView("正在读取课堂笔记…"); Spacer() }
            if let error {
                VStack(spacing: 16) { Text(error).foregroundStyle(.red); Button("重试") { retry += 1 }; NavigationLink("检查笔记连接") { LectureSettingsView(store: store, lectures: lectures) } }.padding()
            }
        }
        .navigationTitle("课堂阅读").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { Task { await lectures.sync(store: store); retry += 1 } } label: { Label("同步笔记", systemImage: "arrow.clockwise") }.disabled(lectures.busy) }
        .task(id: "\(reference.key):\(retry):\(lectures.connection.sourceID):\(lectures.connection.locked)") {
            error = nil
            do { let result = try await lectures.body(reference, course: courseID); guard !Task.isCancelled else { return }; bodyValue = result; await markRead(result) }
            catch { if !Task.isCancelled { bodyValue = nil; self.error = error.localizedDescription } }
        }
        .onChange(of: tab) { _ in selection = ""; if readerState == .ready { readerState = .loading } }
        .sheet(item: $draft) { value in PersonalTaskEditor(store: store, initialDraft: value) }
        .confirmationDialog("选择事项创建个人任务", isPresented: $showItems, titleVisibility: .visible) {
            ForEach(actions, id: \.self) { text in Button(text) { create(text) } }
        }
    }
    private func markRead(_ value: LectureBody) async {
        do { try await lectures.read(value, course: courseID); if !Task.isCancelled { readError = nil } }
        catch { if !Task.isCancelled { readError = "已读状态未保存：\(error.localizedDescription)" } }
    }
    private func create(_ text: String) {
        guard let bodyValue else { return }
        var value = PersonalTaskSeries()
        value.title = String(text.prefix(120)); value.notes = String(text.prefix(10000))
        value.courseID = courseID; value.courseName = bodyValue.item.courseTitle
        value.lectureSource = LectureTaskSource(reference: reference, title: bodyValue.item.title)
        createdID = value.id; draft = value
    }
}
enum LectureActions {
    static func extract(_ summary: String) -> [String] {
        var relevant = false, fenced = false, result: [String] = []
        for raw in summary.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") { fenced.toggle(); continue }
            if fenced { continue }
            if line.hasPrefix("#") { relevant = line.range(of: "作业|考试|签到|考勤|待办|课堂事项|课后|通知|提醒", options: .regularExpression) != nil; continue }
            guard line.range(of: "^(?:[-*+] |[0-9]+[.、)] )", options: .regularExpression) != nil,
                  relevant || line.range(of: "作业|考试|签到|需提交|截止", options: .regularExpression) != nil else { continue }
            let text = line.replacingOccurrences(of: "^(?:[-*+] |[0-9]+[.、)] )(?:\\[[ xX]\\] )?", with: "", options: .regularExpression).replacingOccurrences(of: "**", with: "")
            if !text.isEmpty && !result.contains(text) { result.append(text) }
        }
        return Array(result.prefix(20))
    }
}

struct LectureSettingsView: View {
    @ObservedObject var store: NativeAppStore
    @ObservedObject var lectures: LectureStore
    @State private var repository = "btr2309887446-code/Fudan_iCourse_Subscriber"
    @State private var branch = "data"
    @State private var student = ""
    @State private var password = ""
    @State private var token = ""
    @State private var remember = false
    @State private var courseQuery = ""
    var body: some View {
        Form {
            Section {
                Text("将订阅仓库生成的摘要、转写和 PPT 文字带到课程中，邮件仍照常发送。")
                Text(lectures.connection.configured ? (lectures.connection.locked ? "需要解锁" : "已连接") : "尚未连接").font(.headline)
                if let date = lectures.connection.lastSynced { Text("最近同步：\(date.formatted())").font(.caption) }
            }
            Section("连接与解锁") {
                TextField("GitHub 用户名/仓库名", text: $repository).autocapitalization(.none).disableAutocorrection(true)
                TextField("数据分支", text: $branch).autocapitalization(.none).disableAutocorrection(true)
                TextField("生成笔记时的学号", text: $student).keyboardType(.numberPad)
                SecureField("生成笔记时的 UIS 密码", text: $password)
                DisclosureGroup("私有仓库访问") { SecureField("GitHub 只读令牌", text: $token) }
                Toggle("在本机记住解锁信息", isOn: $remember)
                Text("密码只用于本机解密。记住时将派生密钥保存在此设备钥匙串中。若改过 UIS 密码，请使用生成这些笔记时的密码。").font(.footnote).foregroundStyle(.secondary)
                Button(lectures.busy ? "正在处理…" : "解锁并连接") {
                    let input = LectureCredentials(repository: repository, branch: branch, student: student, password: password, token: token, remember: remember)
                    Task { await lectures.operate({ try await $0.connect(input) }, store: store); if lectures.message == nil { password = ""; token = "" } }
                }.disabled(password.isEmpty || student.isEmpty)
                Button("立即同步") { Task { await lectures.sync(store: store) } }.disabled(lectures.connection.locked)
                Button("断开连接", role: .destructive) { Task { await lectures.operate({ try await $0.disconnect() }, store: store) } }.disabled(!lectures.connection.configured)
                if lectures.busy { ProgressView() }
                if let message = lectures.message ?? lectures.connection.error { Text(message).foregroundStyle(.red).textSelection(.enabled) }
            }.disabled(lectures.busy)
            Section {
                TextField("搜索课程或粘贴 iCourse 课程链接", text: $courseQuery).autocapitalization(.none)
                ForEach(lectures.connection.courses.filter { matches($0) }) { course in
                    LectureBindingRow(store: store, lectures: lectures, external: course)
                }
                if lectures.connection.courses.isEmpty { Text("解锁后将显示可关联的课程。").foregroundStyle(.secondary) }
            } header: { Text("课程关联") } footer: { Text("首次关联由你确认。同名或跨学期课程不会自动绑定；历史笔记导入不会刷变化消息。") }
            Section { Text("打开应用或手动刷新时检查笔记。锁屏、退出应用后不保证同步；解锁后可离线阅读上次缓存。").font(.footnote).foregroundStyle(.secondary) }
            Section {
                NavigationLink("阅读组件开源许可") {
                    ScrollView { Text(Bundle.main.url(forResource: "lecture-licenses", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "许可文件不可用")
                        .font(.footnote).textSelection(.enabled).padding() }.navigationTitle("开源许可")
                }
            }
        }
        .navigationTitle("课堂笔记连接")
        .onAppear { repository = lectures.connection.repository; branch = lectures.connection.branch; remember = lectures.connection.remembered }
    }
    private func matches(_ course: LectureCourse) -> Bool {
        let query = courseQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return true }
        if let range = query.range(of: "(?:course/|course_id=|course=)[0-9]+", options: .regularExpression) {
            let id = query[range].replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression); return course.id == id
        }
        return "\(course.title) \(course.teacher) \(course.terms.joined(separator: " "))".localizedCaseInsensitiveContains(query)
    }
}
private struct LectureBindingRow: View {
    @ObservedObject var store: NativeAppStore
    @ObservedObject var lectures: LectureStore
    let external: LectureCourse
    @State private var selected: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(external.title).font(.headline)
            Text(([external.teacher] + external.terms).filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            Text(lectures.connection.bindings[external.id] == nil ? "待关联" : "已关联").font(.caption)
            if lectures.connection.bindings[external.id] == nil {
                ForEach((store.snapshot?.courses ?? []).filter { $0.displayName.localizedCaseInsensitiveContains(external.title) || external.title.localizedCaseInsensitiveContains($0.displayName) }.prefix(3)) { candidate in
                    Text("候选：\(candidate.displayName) · \(candidate.termName)，请核对后选择。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Picker("对应 eLearning 课程", selection: $selected) {
                Text("暂不关联").tag(Optional<Int>.none)
                ForEach(store.snapshot?.courses ?? []) { course in Text(course.displayName + " · " + course.termName).tag(Optional(course.id)) }
            }
            Button(selected == nil ? "解除关联" : "确认关联") {
                let id = selected
                Task { await lectures.operate({ try await $0.bind(external.id, to: id) }, store: store) }
            }.disabled(lectures.busy || selected == lectures.connection.bindings[external.id])
        }.padding(.vertical, 5)
        .onAppear { selected = lectures.connection.bindings[external.id] }
    }
}

enum LectureReaderState: Equatable { case loading, ready, failed(String) }

struct LectureWebText: UIViewRepresentable {
    var content: String; var markdown: Bool; var identity: String
    @Binding var selection: String
    @Binding var state: LectureReaderState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sizeCategory) private var sizeCategory
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "selection")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator; web.isOpaque = false; web.backgroundColor = .systemBackground
        web.accessibilityIdentifier = "lecture-web-reader"
        if let file = Bundle.main.url(forResource: "lecture-reader", withExtension: "html") { web.loadFileURL(file, allowingReadAccessTo: file) }
        else { DispatchQueue.main.async { context.coordinator.fail("缺少正文阅读组件，请重新安装应用。") } }
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) { context.coordinator.parent = self; context.coordinator.render(web) }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) { coordinator.active = false; web.configuration.userContentController.removeScriptMessageHandler(forName: "selection"); web.stopLoading(); web.navigationDelegate = nil }
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: LectureWebText
        var ready = false
        var last = ""
        var active = true
        var request = 0
        init(_ parent: LectureWebText) { self.parent = parent }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; last = ""; render(webView) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail("正文加载失败：\(error.localizedDescription)") }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail("正文加载失败：\(error.localizedDescription)") }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail("正文阅读组件已中断，请重新加载。") }
        func fail(_ message: String) { guard active else { return }; ready = false; request += 1; parent.state = .failed(message) }
        func render(_ web: WKWebView) {
            guard ready, active else { return }
            let size = UIFont.preferredFont(forTextStyle: .body).pointSize
            let payload: [String: Any] = ["text": parent.content, "markdown": parent.markdown, "key": parent.identity, "dark": parent.colorScheme == .dark, "size": size]
            guard let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8), json != last else { return }
            last = json; request += 1
            let currentRequest = request
            web.evaluateJavaScript("window.renderNote(\(json))") { [weak self] _, error in
                guard let self, self.active, currentRequest == self.request else { return }
                if let error { self.fail("正文显示失败：\(error.localizedDescription)") }
                else { self.parent.state = .ready }
            }
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let text = message.body as? String else { return }; parent.selection = String(text.prefix(10000))
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                if url.scheme == "https", url.user == nil, url.password == nil { UIApplication.shared.open(url) }
                decisionHandler(.cancel)
            } else { decisionHandler(action.request.url?.isFileURL == true ? .allow : .cancel) }
        }
    }
}
