import SwiftUI
import UIKit

struct NativeLabeledContent: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }
}

struct NativeRootView: View {
    @StateObject var store: NativeAppStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.isBooting {
                ProgressView("正在启动…")
            } else if store.isLoggedIn || store.snapshot != nil {
                if !store.isLoggedIn && store.snapshot == nil {
                    NativeLoginView(store: store)
                } else {
                    MainTabsView(store: store)
                }
            } else {
                NativeLoginView(store: store)
            }
        }
        .tint(.blue)
        .preferredColorScheme(colorScheme)
        .task { await store.boot() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                store.ensurePersonalRange(through: Beijing.addDays(90, to: Date()))
                Task { await store.reconcileReminders() }
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch store.preferences.theme {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

struct MainTabsView: View {
    @ObservedObject var store: NativeAppStore
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationView { TodayView(store: store, selection: $selection) }
                .navigationViewStyle(.stack)
                .tabItem { Label("今日", systemImage: "sun.max") }
                .tag(0)
            TasksView(store: store)
                .tabItem { Label("任务", systemImage: "checkmark.circle") }
                .tag(1)
            CoursesView(store: store)
                .tabItem { Label("课程", systemImage: "book.closed") }
                .tag(2)
            NavigationView { ProfileView(store: store) }
                .navigationViewStyle(.stack)
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(3)
        }
        .onChange(of: store.reminderDay) { day in
            if day != nil { selection = 1 }
        }
        .sheet(item: $store.notificationTask) { task in
            NavigationView { TaskDetailDestination(task: task, store: store) }.navigationViewStyle(.stack)
        }
        .sheet(item: $store.calendarTask) { task in
            if let due = task.dueAt {
                CalendarEventEditor(title: task.title, course: task.courseName, deadline: due, url: task.url) { saved in
                    if saved { store.recordCalendarExport(task) }
                    store.calendarTask = nil
                }
                .ignoresSafeArea()
            }
        }
    }
}

struct TermChooser: View {
    @ObservedObject var store: NativeAppStore

    var body: some View {
        Menu {
            Button("当前学期") { store.setSelectedTerm("default") }
            Button("全部学期") { store.setSelectedTerm("all") }
            if let terms = store.snapshot?.terms {
                ForEach(terms) { term in
                    Button(term.name) { store.setSelectedTerm(term.id.map { "term:\($0)" } ?? "term:none") }
                }
            }
        } label: {
            Label(selectedTitle, systemImage: "chevron.down")
                .labelStyle(.titleAndIcon)
                .font(.subheadline)
        }
        .accessibilityLabel("选择学期")
    }

    private var selectedTitle: String {
        guard let snapshot = store.snapshot else { return "学期" }
        if store.preferences.selectedTerm == "all" { return "全部学期" }
        if store.preferences.selectedTerm == "default" {
            return snapshot.terms.first(where: \.isCurrent)?.name ?? snapshot.terms.first?.name ?? "当前学期"
        }
        let id = Int(store.preferences.selectedTerm.replacingOccurrences(of: "term:", with: ""))
        return snapshot.terms.first(where: { $0.id == id })?.name ?? "未指定学期"
    }
}

struct TodayView: View {
    @ObservedObject var store: NativeAppStore
    @Binding var selection: Int
    @State private var showOverdue = false

    var body: some View {
        let pending = store.selectedTasks.filter { $0.status == .pending }
        let now = Date()
        let grouped = Dictionary(grouping: pending) { $0.bucket(now: now) }
        let overdue = grouped[.overdue, default: []]
        let today = grouped[.today, default: []]
        let week = grouped[.week, default: []]
        return List {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    count("今天", today.count)
                    count("七天内", week.count)
                    count("待处理", pending.count)
                }
                .padding(.vertical, 4)
                if let error = store.errorMessage { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                if let notice = store.noticeMessage { Label(notice, systemImage: "info.circle").foregroundStyle(.secondary) }
                if let progress = store.refreshProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("正在同步：\(progress.label)").font(.subheadline)
                        ProgressView(value: Double(progress.done), total: Double(max(1, progress.total)))
                    }
                }
            } header: {
                Text(Beijing.key(Date()).replacingOccurrences(of: "-", with: "/"))
            }

            Section("变化中心") {
                NavigationLink(destination: ChangesView(store: store)) {
                    Label("变化中心 · \(store.unreadChanges) 条未读", systemImage: "bell.badge")
                }.accessibilityIdentifier("changes-center")
                ForEach(store.localAccount.events.prefix(3)) { event in
                    NavigationLink(destination: ChangeDetailView(event: event, store: store)) { ChangeRow(event: event) }
                }
                if let error = store.localError { Text(error).foregroundStyle(.red) }
            }
            if !overdue.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showOverdue) {
                        ForEach(overdue.prefix(3)) { task in
                            TaskNavigationRow(task: task, store: store)
                        }
                        if overdue.count > 3 {
                            Button("查看全部逾期作业") { openTasks(.overdue) }
                        }
                    } label: {
                        Label("\(overdue.count) 项已逾期未交", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }

            taskSection("今天截止", tasks: today, bucket: .today)
            taskSection("未来七天", tasks: week, bucket: .week)

            Section {
                if let fetched = store.snapshot?.fetchedAt {
                    Text("上次同步 \(Beijing.label(fetched, absolute: true).replacingOccurrences(of: " 截止", with: "")) · 北京时间")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("尚未同步").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("今日")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { TermChooser(store: store) }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await store.refresh() } } label: {
                    if store.isBusy { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(store.isBusy || !store.isLoggedIn)
                .accessibilityLabel("立即同步")
            }
        }
        .refreshable { await store.refresh() }
    }

    private func count(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value, format: .number).font(.title2.weight(.semibold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func taskSection(_ title: String, tasks: [NativeTask], bucket: TaskBucket) -> some View {
        Section {
            if tasks.isEmpty {
                Label("没有待交作业", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            } else {
                ForEach(tasks.prefix(bucket == .today ? 5 : 3)) { task in TaskNavigationRow(task: task, store: store) }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Button("查看全部") { openTasks(bucket) }.textCase(nil)
            }
        }
    }

    private func openTasks(_ bucket: TaskBucket) {
        store.taskBucket = bucket
        selection = 1
    }
}

struct TaskRowLabel: View {
    let task: NativeTask
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon).foregroundStyle(statusColor).font(.title3)
                .frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title).font(.body).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                Text(task.courseName).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(Beijing.label(task.dueAt)).font(.footnote).foregroundStyle(deadlineColor)
                if task.personal != nil { Text("个人任务").font(.caption).foregroundStyle(.secondary) }
                if task.hasManualDeadline { Text("手动截止").font(.caption).foregroundStyle(.secondary) }
                if task.status == .submitted { Text(task.personal != nil ? "已完成" : (task.assignment?.score == nil ? "已提交待评分" : "已评分")).font(.footnote).foregroundStyle(.secondary) }
            }
        }.padding(.vertical, 3)
    }
    private var statusIcon: String {
        if task.status == .submitted { return "checkmark.circle.fill" }
        if task.status == .ignored { return "minus.circle" }
        return task.bucket() == .overdue ? "exclamationmark.circle.fill" : "circle"
    }
    private var statusColor: Color {
        if task.bucket() == .overdue { return .red }
        if task.status == .submitted { return .green }
        return .secondary
    }
    private var deadlineColor: Color { task.status == .pending && task.bucket() == .overdue ? .red : .secondary }
}

struct TaskNavigationRow: View {
    let task: NativeTask
    let store: NativeAppStore
    var body: some View {
        NavigationLink(destination: TaskDetailDestination(task: task, store: store)) {
            TaskRowLabel(task: task)
        }
    }
}

struct EmptyState: View {
    let title: String
    let systemImage: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.tertiary)
            Text(title).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 28)
    }
}

struct TasksView: View {
    @ObservedObject var store: NativeAppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var taskSource = "all"
    @State private var creatingPersonal = false
    @State private var listLimit = 100
    @State private var calendarMode = false
    @State private var selectedCourse: Int?
    @State private var selectedTaskID: String?
    @State private var path: [String] = []
    @State private var selectedDay = Beijing.day(Date())
    @State private var month = Beijing.calendar.dateInterval(of: .month, for: Date())?.start ?? Date()

    private var status: TaskStatus { TaskStatus(rawValue: store.preferences.taskFilter) ?? .pending }
    private var filtered: [NativeTask] {
        let now = Date()
        return store.selectedTasks.filter { task in
            (taskSource == "all" || (taskSource == "personal" ? task.personal != nil : task.personal == nil)) &&
            task.status == status && (selectedCourse == nil || task.courseID == selectedCourse) &&
            (store.taskBucket == nil || task.bucket(now: now) == store.taskBucket) &&
            (search.isEmpty || "\(task.title) \(task.courseName)".localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        Group {
            if #available(iOS 16.0, *), horizontalSizeClass == .regular {
                NavigationSplitView {
                    content
                } detail: {
                    selectedDetail
                }
                .navigationSplitViewStyle(.balanced)
            } else if #available(iOS 16.0, *) {
                NavigationStack(path: $path) {
                    content
                        // Register once on a stable ancestor, outside the scrolling content.
                        .navigationDestination(for: String.self) { id in
                            if let task = store.taskIndex.byID[id] {
                                TaskDetailDestination(task: task, store: store)
                            } else {
                                EmptyState(title: "此作业已不在同步数据中。", systemImage: "doc.text")
                            }
                        }
                }
            } else if horizontalSizeClass == .regular {
                NavigationView { content; selectedDetail }.navigationViewStyle(.columns)
            } else {
                NavigationView { content }.navigationViewStyle(.stack)
            }
        }
        .sheet(isPresented: $creatingPersonal) { PersonalTaskEditor(store: store) }
        .onChange(of: month) { value in store.ensurePersonalRange(through: Beijing.calendar.date(byAdding: .month, value: 1, to: value)!) }
        .onChange(of: store.reminderDay) { value in
            guard let value, let day = Beijing.parseKey(value) else { return }
            path = []
            selectedTaskID = nil
            selectedDay = day
            month = NativeMonthGrid(month: day).firstDay
            calendarMode = true
            store.setTaskFilter(.pending)
            store.taskBucket = nil
        }
    }

    @ViewBuilder private var selectedDetail: some View {
        if let id = selectedTaskID, let task = store.taskIndex.byID[id] {
            TaskDetailDestination(task: task, store: store)
        } else {
            EmptyState(title: "选择一项任务查看详情。", systemImage: "doc.text")
        }
    }

    private var content: some View {
        listBody
            .navigationTitle("任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { listToolbar }
            .searchable(text: $search, prompt: "搜索任务或课程")
    }

    private var listToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            TermChooser(store: store)
            Button { creatingPersonal = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("新建个人任务").accessibilityIdentifier("new-personal-task")
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(store.isBusy || !store.isLoggedIn).accessibilityLabel("同步")
        }
    }

    private var filterControls: some View {
        VStack(spacing: 16) {
            Picker("显示方式", selection: $calendarMode) {
                Text("列表").tag(false)
                Text("日历").tag(true)
            }.pickerStyle(.segmented)
            Picker("任务来源", selection: $taskSource) {
                Text("全部").tag("all")
                Text("学校作业").tag("school")
                Text("个人任务").tag("personal")
            }.pickerStyle(.segmented).accessibilityIdentifier("task-source-filter")
            HStack {
                Menu {
                    ForEach(TaskStatus.allCases) { value in
                        Button { store.setTaskFilter(value) } label: {
                            if status == value { Label(value.filterTitle, systemImage: "checkmark") }
                            else { Text(value.filterTitle) }
                        }
                    }
                } label: { Label(status.filterTitle, systemImage: "line.3.horizontal.decrease.circle") }
                .accessibilityIdentifier("task-status-filter")
                Spacer()
                Menu {
                    Button("全部课程") { selectedCourse = nil }
                    ForEach(store.selectedCourses) { course in
                        Button(course.displayName) { selectedCourse = course.id }
                    }
                } label: { Label(selectedCourseName, systemImage: "book.closed") }
                .accessibilityIdentifier("task-course-filter")
                if store.taskBucket != nil {
                    Button { store.taskBucket = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("清除截止日期筛选")
                }
            }.font(.subheadline)
        }
    }

    private var listBody: some View {
        let visibleTasks = filtered
        let now = Date()
        // Keep the calendar outside UICollectionView's self-sizing List cells.
        // Its grid must not participate in recursive List height measurement.
        return VStack(spacing: 0) {
            // Keep one instance of the controls in place while the content changes.
            // Replacing the entire scroll view also replaced the Picker and reset
            // navigation-bar scroll state, which made the switch look like a jump.
            filterControls
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 4)

            ZStack(alignment: .top) {
                if calendarMode {
                    let counts = NativeDomain.taskCountsByDay(visibleTasks)
                    let dayTasks = NativeDomain.tasks(visibleTasks, on: selectedDay)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            MonthGrid(month: $month, day: $selectedDay, taskCounts: counts)
                                .padding(16)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            Text(Beijing.dayTitle(selectedDay))
                                .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 16)
                            LazyVStack(alignment: .leading, spacing: 0) {
                                if dayTasks.isEmpty {
                                    Text("这一天没有符合条件的任务。")
                                        .foregroundStyle(.secondary).padding(16)
                                }
                                ForEach(dayTasks) { task in
                                    taskRow(task).padding(16)
                                    if task.id != dayTasks.last?.id { Divider().padding(.leading, 16) }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            Text("北京时间 · 无截止时间的任务请在列表中查看")
                                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
                        }
                        .padding(16)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                    .id("task-calendar")
                    .accessibilityIdentifier("task-calendar")
                    .transition(.opacity)
                    .zIndex(1)
                } else {
                    let groups = Dictionary(grouping: visibleTasks) { $0.bucket(now: now) }
                    List {
                        if visibleTasks.isEmpty {
                            Section { EmptyState(title: "没有符合条件的任务。试试其他状态或课程。", systemImage: "magnifyingglass") }
                        }
                        ForEach(TaskBucket.allCases) { bucket in
                            if let rows = groups[bucket], !rows.isEmpty {
                                Section(bucket.title) {
                                    ForEach(rows.prefix(listLimit)) { task in taskRow(task) }
                                    if rows.count > listLimit { Button("显示更多任务") { listLimit += 100 } }
                                }
                            }
                        }
                        Section { Button("加载更多未来任务") { store.ensurePersonalRange(through: Beijing.addDays(90, to: store.personalHorizon)) } }
                        if let error = store.localError { Section { Text(error).foregroundStyle(.red) } }
                    }
                    .id("task-list")
                    .accessibilityIdentifier("task-list")
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            // Animate only the content replacement, not the controls, navigation
            // chrome or the calendar's measured row heights. Equal nonzero z-order
            // keeps the outgoing scroll view visible for the whole crossfade.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: calendarMode)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .listStyle(.insetGrouped)
        .refreshable { await store.refresh() }
    }

    @ViewBuilder private func taskRow(_ task: NativeTask) -> some View {
        if horizontalSizeClass == .regular {
            Button { selectedTaskID = task.id } label: {
                TaskRowLabel(task: task)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(selectedTaskID == task.id ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
            .accessibilityIdentifier("task-row-\(task.id)")
        } else if #available(iOS 16.0, *) {
            NavigationLink(value: task.id) { TaskRowLabel(task: task) }
                .accessibilityIdentifier("task-row-\(task.id)")
        } else {
            NavigationLink(destination: TaskDetailDestination(task: task, store: store)) {
                TaskRowLabel(task: task)
            }.accessibilityIdentifier("task-row-\(task.id)")
        }
    }

    private var selectedCourseName: String {
        guard let selectedCourse else { return "全部课程" }
        return store.selectedCourses.first(where: { $0.id == selectedCourse })?.displayName ?? "全部课程"
    }
}

struct MonthGrid: View {
    @Binding var month: Date
    @Binding var day: Date
    let taskCounts: [Date: Int]
    @ScaledMetric(relativeTo: .body) private var cellHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var weekdayHeight: CGFloat = 20
    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        let grid = NativeMonthGrid(month: month)
        let today = Beijing.day(Date())
        return VStack(spacing: 8) {
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("上个月").accessibilityIdentifier("calendar-previous-month")
                Spacer()
                Text(Beijing.monthTitle(month)).font(.headline)
                    .lineLimit(1).minimumScaleFactor(0.7).accessibilityIdentifier("calendar-month-title")
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("下个月").accessibilityIdentifier("calendar-next-month")
            }.frame(height: cellHeight)
            HStack(spacing: 2) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }.frame(height: weekdayHeight)
            // This is always 6 x 7 cells. LazyVGrid inside a self-sizing List row
            // caused UICollectionViewFeedbackLoopDebugger fatal layout loops on
            // iOS 26. Use eager, explicitly sized rows in the calendar ScrollView.
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(grid.cells[(row * 7)..<(row * 7 + 7)]) { cell in
                        dayCell(cell, today: today)
                    }
                }.frame(height: cellHeight)
            }
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func dayCell(_ cell: NativeMonthGrid.Cell, today: Date) -> some View {
        if let date = cell.date, let number = cell.number {
            let count = taskCounts[date, default: 0]
            Button { day = date } label: {
                VStack(spacing: 3) {
                    Text(String(number)).font(.body.weight(date == today ? .semibold : .regular))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Circle().fill(count > 0 ? Color.accentColor : .clear).frame(width: 4, height: 4)
                }
                .frame(maxWidth: .infinity)
                .frame(height: cellHeight)
                .foregroundStyle(date == day ? Color.white : (date == today ? Color.accentColor : Color.primary))
                .background(date == day ? Color.accentColor : Color.clear, in: Circle())
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(Beijing.fullDayTitle(date))，\(count) 项任务")
            .accessibilityIdentifier("calendar-day-\(Beijing.key(date))")
            .accessibilityAddTraits(date == day ? [.isSelected] : [])
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: cellHeight).accessibilityHidden(true)
        }
    }

    private func shiftMonth(_ value: Int) {
        guard let shifted = Beijing.calendar.date(byAdding: .month, value: value, to: month) else { return }
        let first = NativeMonthGrid(month: shifted).firstDay
        month = first
        day = first
    }
}

struct CoursesView: View {
    @ObservedObject var store: NativeAppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var search = ""
    @State private var selectedID: Int?

    private var courses: [NativeCourse] {
        store.selectedCourses.filter {
            search.isEmpty || "\($0.displayName) \($0.courseCode)".localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        Group {
            if #available(iOS 16.0, *), horizontalSizeClass == .regular {
                NavigationSplitView {
                    courseList
                        .navigationTitle("课程")
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) { TermChooser(store: store) }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                                    .disabled(store.isBusy || !store.isLoggedIn).accessibilityLabel("同步")
                            }
                        }
                } detail: {
                    if let course = courses.first(where: { $0.id == selectedID }) {
                        CourseDetailView(store: store, course: course)
                    } else { EmptyState(title: "选择一门课程查看作业、成绩与文件。", systemImage: "book.closed") }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                if horizontalSizeClass == .regular {
                    NavigationView {
                        courseList
                            .navigationTitle("课程")
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) { TermChooser(store: store) }
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                                        .disabled(store.isBusy || !store.isLoggedIn).accessibilityLabel("同步")
                                }
                            }
                        if let course = courses.first(where: { $0.id == selectedID }) {
                            CourseDetailView(store: store, course: course)
                        } else {
                            EmptyState(title: "选择一门课程查看作业、成绩与文件。", systemImage: "book.closed")
                        }
                    }
                    .navigationViewStyle(.columns)
                } else {
                    NavigationView {
                        courseList
                            .navigationTitle("课程")
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) { TermChooser(store: store) }
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                                        .disabled(store.isBusy || !store.isLoggedIn).accessibilityLabel("同步")
                                }
                            }
                    }
                    .navigationViewStyle(.stack)
                }
            }
        }
        .searchable(text: $search, prompt: "搜索课程")
        .onChange(of: store.preferences.selectedTerm) { _ in selectedID = nil }
    }

    private var courseList: some View {
        List {
            Section {
                NavigationLink(destination: ScoresView(store: store)) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("成绩概览")
                            Text("查看当前学期的得分与趋势").font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "chart.bar.xaxis").foregroundStyle(.blue) }
                }
            }
            Section("我的课程") {
                if courses.isEmpty { EmptyState(title: "没有找到课程。试试切换学期或清除搜索。", systemImage: "book") }
                else {
                    ForEach(courses) { course in
                        if horizontalSizeClass == .regular {
                            Button {
                                selectedID = course.id
                            } label: {
                                courseRow(course)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel(course.displayName)
                                    .accessibilityIdentifier("course-row-\(course.id)")
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(destination: CourseDetailView(store: store, course: course)) {
                                courseRow(course)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel(course.displayName)
                                    .accessibilityIdentifier("course-row-\(course.id)")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.refresh() }
    }

    private func courseRow(_ course: NativeCourse) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed").foregroundStyle(.blue).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(course.displayName)
                Text("\(course.courseCode) · \(course.termName)").font(.subheadline).foregroundStyle(.secondary)
                Text("\(store.taskIndex.pendingByCourse[course.id, default: 0]) 项待交")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct CourseDetailView: View {
    @ObservedObject var store: NativeAppStore
    let course: NativeCourse
    @State private var section = 0
    @State private var taskFilter: TaskStatus?

    private var assignments: [NativeAssignment] {
        (store.snapshot?.assignments ?? []).filter { $0.courseID == course.id }
            .filter { row in
                guard let taskFilter else { return true }
                if taskFilter == .ignored { return store.preferences.ignoredAssignments.contains(NativeDomain.assignmentKey(row.courseID, row.id)) }
                if taskFilter == .submitted { return row.isCompleted }
                return !row.isCompleted && !store.preferences.ignoredAssignments.contains(NativeDomain.assignmentKey(row.courseID, row.id))
            }
    }

    var body: some View {
        List {
            Section {
                Text(course.courseCode.isEmpty ? course.termName : "\(course.courseCode) · \(course.termName)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("课程内容", selection: $section) {
                    Text("作业").tag(0)
                    Text("成绩").tag(1)
                    Text("文件").tag(2)
                }.pickerStyle(.segmented)
            }

            if section == 0 {
                Section {
                    Menu {
                        Button("全部作业") { taskFilter = nil }
                        ForEach(TaskStatus.allCases) { value in Button(value.title) { taskFilter = value } }
                    } label: { Label(taskFilter?.title ?? "未提交", systemImage: "line.3.horizontal.decrease.circle") }
                    if assignments.isEmpty { Text("这个范围内没有作业。").foregroundStyle(.secondary) }
                    ForEach(assignments) { assignment in
                        if let task = store.taskIndex.byID[NativeDomain.assignmentKey(assignment.courseID, assignment.id)] {
                            TaskNavigationRow(task: task, store: store)
                        }
                    }
                } header: { Text("作业") }
            } else if section == 1 {
                Section("eLearning 当前得分") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(score(course.currentScore)).font(.largeTitle.weight(.semibold))
                        Text("分").foregroundStyle(.secondary)
                    }
                    Text("\(course.gradedCount) / \(course.assignmentCount) 项已评分").font(.subheadline).foregroundStyle(.secondary)
                    Text("按作业分组权重计算；不代表教务处正式成绩。").font(.footnote).foregroundStyle(.secondary)
                    if let final = course.finalScore { NativeLabeledContent(title: "最终得分", value: score(final)) }
                }
                Section("得分趋势") { ScoreTrendChart(assignments: assignments) }
                Section("作业分组") {
                    ForEach(groupSummaries, id: \.name) { group in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(group.name); Spacer(); Text(group.weight > 0 ? "权重 \(Int(group.weight.rounded()))%" : "")
                                    .foregroundStyle(.secondary) }
                            Text(group.possible > 0 ? "\(score(group.percent))% · \(score(group.earned)) / \(score(group.possible)) 分" : "尚未评分")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if group.possible > 0 { ProgressView(value: max(0, min(1, group.percent / 100))) }
                        }.padding(.vertical, 3)
                    }
                }
            } else {
                NativeFilesView(store: store, course: course)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(course.displayName)
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await store.refresh() }
    }

    private struct GroupSummary {
        var name: String
        var weight: Double
        var earned: Double
        var possible: Double
        var percent: Double { possible > 0 ? earned / possible * 100 : 0 }
    }

    private var groupSummaries: [GroupSummary] {
        let groups = Dictionary(grouping: (store.snapshot?.assignments ?? []).filter { $0.courseID == course.id }, by: \.groupID)
        return groups.values.map { rows in
            let first = rows[0]
            let graded = rows.filter { !$0.excused && !$0.omitFromFinalGrade && $0.score != nil && ($0.pointsPossible ?? 0) > 0 }
            return GroupSummary(name: first.groupName, weight: first.groupWeight,
                                earned: graded.reduce(0) { $0 + ($1.score ?? 0) },
                                possible: graded.reduce(0) { $0 + ($1.pointsPossible ?? 0) })
        }.sorted { $0.weight == $1.weight ? $0.name < $1.name : $0.weight > $1.weight }
    }

    private func score(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

struct ScoreTrendChart: View {
    let assignments: [NativeAssignment]
    private var values: [Double] { assignments.compactMap { row in
        guard let score = row.score, let possible = row.pointsPossible, possible > 0, !row.excused else { return nil }
        return score / possible * 100
    }.reversed() }

    var body: some View {
        if values.isEmpty {
            Text("暂无已评分作业").foregroundStyle(.secondary)
        } else {
            GeometryReader { proxy in
                let points = values.enumerated().map { index, value in
                    CGPoint(x: values.count == 1 ? proxy.size.width / 2 : proxy.size.width * CGFloat(index) / CGFloat(values.count - 1),
                            y: proxy.size.height * (1 - CGFloat(max(0, min(100, value))) / 100))
                }
                ZStack {
                    ForEach([0.0, 0.5, 1.0], id: \.self) { fraction in
                        Path { path in
                            let y = proxy.size.height * fraction
                            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        }.stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        Circle().fill(Color.accentColor).frame(width: 6, height: 6).position(point)
                    }
                }
            }
            .frame(height: 140)
            HStack { Text("最近 \(values.count) 项"); Spacer(); Text("当前 \(values.last.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—")%") }
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ScoresView: View {
    @ObservedObject var store: NativeAppStore
    private var courses: [NativeCourse] { store.selectedCourses }
    private var scored: [Double] { courses.compactMap(\.currentScore) }
    private var average: Double? { scored.isEmpty ? nil : scored.reduce(0, +) / Double(scored.count) }

    var body: some View {
        List {
            Section {
                NativeLabeledContent(title: "平均得分", value: average.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "—")
                Text("\(scored.count) 门课程已有得分 · 仅为 eLearning 教学数据")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("各课程得分") {
                ForEach(courses) { course in
                    NavigationLink(destination: CourseDetailView(store: store, course: course).onAppear { }) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(course.displayName)
                            Text(course.currentScore.map { "\($0.formatted(.number.precision(.fractionLength(0...2)))) 分" } ?? "暂无已评分作业")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("成绩概览")
    }
}

struct NativeFilesView: View {
    @ObservedObject var store: NativeAppStore
    let course: NativeCourse
    @State private var tree: NativeFileNode?
    @State private var selected: Set<Int> = []
    @State private var selecting = false
    @State private var loading = true

    var body: some View {
        Section {
            HStack {
                Button(selecting ? "完成选择" : "选择文件") {
                    selecting.toggle()
                    if !selecting { selected.removeAll() }
                }.disabled(loading || store.isDownloading)
                Spacer()
                Button("下载本课全部") { download(ids: nil) }
                    .disabled(loading || store.isDownloading || (tree.map { NativeFileTree.flatten($0).isEmpty } ?? true))
            }
            if let tree {
                Text("\(NativeFileTree.flatten(tree).count) 个文件 · \(byteSize(NativeFileTree.flatten(tree).reduce(0) { $0 + $1.size }))")
                    .font(.footnote).foregroundStyle(.secondary)
                if tree.children.isEmpty { EmptyState(title: "这门课还没有上传任何文件。", systemImage: "folder") }
                ForEach(tree.children) { node in
                    NativeFileNodeRow(node: node, selecting: selecting, selected: $selected) { file in download(ids: [file.id]) }
                }
            } else if loading {
                ProgressView("正在读取课程文件…")
            } else {
                ContentUnavailableViewFallback(message: store.fileError ?? "无法读取课程文件。", icon: "exclamationmark.folder")
                Button("重试") { Task { await load(force: true) } }
            }
            if let progress = store.downloadProgress {
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(store.isDownloading ? "正在下载：\(progress.currentName)" : "下载结果"); Spacer(); Text("\(progress.completed + progress.skipped) / \(progress.total)") }
                    ProgressView(value: progress.bytesTotal > 0 ? Double(progress.bytesReceived) / Double(progress.bytesTotal) : 0)
                    Text("完成 \(progress.completed) 个，跳过 \(progress.skipped) 个，失败 \(progress.failed) 个 · 可在「文件」App 的 eLearning 文件夹中查看")
                        .font(.footnote).foregroundStyle(.secondary)
                    if store.isDownloading { Button("取消下载", role: .destructive) { store.cancelDownload() } }
                }
            }
            if selecting {
                NativeLabeledContent(title: "已选文件", value: "\(selected.count)")
                Button("下载选中") { download(ids: selected) }
                    .disabled(selected.isEmpty || store.isDownloading)
            }
            if let error = store.fileError { Text(error).foregroundStyle(.red).font(.footnote) }
        } header: { Text("课程文件") }
        .task { if tree == nil { await load() } }
    }

    private func load(force: Bool = false) async {
        loading = true
        do { tree = try await store.loadFiles(courseID: course.id, force: force); store.fileError = nil }
        catch { store.fileError = error.localizedDescription }
        loading = false
    }

    private func download(ids: Set<Int>?) {
        guard let tree else { return }
        Task { await store.download(courseID: course.id, courseName: course.displayName,
                                    termName: course.termName, tree: tree, selectedIDs: ids) }
    }

    private func byteSize(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct NativeFileNodeRow: View {
    let node: NativeFileNode
    let selecting: Bool
    @Binding var selected: Set<Int>
    let onDownload: (NativeFile) -> Void

    var body: some View {
        if let file = node.file {
            Button {
                if selecting {
                    if selected.contains(file.id) { selected.remove(file.id) } else { selected.insert(file.id) }
                } else { onDownload(file) }
            } label: {
                HStack {
                    if selecting { Image(systemName: selected.contains(file.id) ? "checkmark.circle.fill" : "circle") }
                    Image(systemName: icon(file.contentType)).foregroundStyle(.secondary)
                    Text(file.name).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)
        } else {
            DisclosureGroup {
                ForEach(node.children) { child in
                    NativeFileNodeRow(node: child, selecting: selecting, selected: $selected, onDownload: onDownload)
                }
            } label: {
                Label(node.name, systemImage: "folder").foregroundStyle(.primary)
            }
        }
    }

    private func icon(_ type: String?) -> String {
        let value = type ?? ""
        if value.contains("pdf") { return "doc.richtext" }
        if value.hasPrefix("image/") { return "photo" }
        if value.hasPrefix("video/") { return "film" }
        if value.contains("zip") || value.contains("compressed") { return "doc.zipper" }
        return "doc"
    }
}

struct ContentUnavailableViewFallback: View {
    let message: String
    let icon: String
    var body: some View { Label(message, systemImage: icon).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding() }
}

struct NativeLoginView: View {
    @ObservedObject var store: NativeAppStore
    @State private var username: String
    @State private var password = ""
    @State private var captcha = ""
    @State private var remember: Bool
    @State private var obscure = true
    @State private var captchaRequired = false
    @State private var captchaImage: String?
    @State private var preparedFor = ""
    @State private var preparing = false
    @FocusState private var focus: Field?

    private enum Field { case username, password, captcha }

    init(store: NativeAppStore) {
        self.store = store
        _username = State(initialValue: store.preferences.rememberedUsername)
        _remember = State(initialValue: store.preferences.rememberPassword)
        _password = State(initialValue: store.rememberedPassword() ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("eLearning 学习看板", systemImage: "graduationcap.fill")
                            .font(.title2.weight(.semibold)).foregroundStyle(.blue)
                        Text("使用复旦 UIS 学号和密码登录。数据直接来自 eLearning 官方接口，密码只发送至复旦统一身份认证。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }

                if let notice = store.noticeMessage { Section { Label(notice, systemImage: "info.circle").foregroundStyle(.secondary) } }
                if let error = store.errorMessage { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }

                Section("复旦统一身份认证") {
                    TextField("学号", text: $username)
                        .keyboardType(.numberPad)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                        .onChange(of: focus) { value in if value != .username { Task { await checkCaptcha() } } }
                    HStack {
                        Group {
                            if obscure {
                                SecureField("密码", text: $password).textContentType(.password)
                            } else {
                                TextField("密码", text: $password).textContentType(.password)
                            }
                        }
                        .focused($focus, equals: .password)
                        .submitLabel(captchaRequired ? .next : .go)
                        .onSubmit { if captchaRequired { focus = .captcha } else { Task { await submit() } } }
                        Button { obscure.toggle() } label: { Image(systemName: obscure ? "eye" : "eye.slash") }
                            .buttonStyle(.plain).accessibilityLabel(obscure ? "显示密码" : "隐藏密码")
                    }

                    if captchaRequired {
                        HStack {
                            TextField("验证码", text: $captcha)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .focused($focus, equals: .captcha)
                            if let captchaImage, let url = URL(string: captchaImage) {
                                AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
                                    .frame(width: 100, height: 44)
                                    .onTapGesture { Task { await checkCaptcha(force: true) } }
                                    .accessibilityLabel("验证码图片，轻点刷新")
                            }
                        }
                    }
                    Toggle("记住密码（保存在系统钥匙串）", isOn: $remember)
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if store.isBusy { ProgressView().padding(.trailing, 6) }
                            Text(store.isBusy ? "正在验证身份…" : "登录").fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(store.isBusy || preparing)
                }
                Section {
                    Text("多次输错密码后，学校认证系统可能要求验证码或临时锁定账号。本应用会在提交前先确认是否需要验证码，尽量避免浪费尝试次数。")
                        .font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("诊断日志") { DiagnosticsView(store: store) }
                }
            }
            .navigationTitle("登录")
            .toolbar {
                ToolbarItem(placement: .keyboard) { Button("完成") { focus = nil } }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func checkCaptcha(force: Bool = false) async {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, force || name != preparedFor, !preparing else { return }
        preparedFor = name
        preparing = true
        defer { preparing = false }
        do {
            let result = try await store.prepareLogin(username: name)
            captchaRequired = result.captchaRequired
            captchaImage = result.captchaImage
        } catch {
            // Login preparation is retried when the user submits.
        }
    }

    private func submit() async {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !password.isEmpty else {
            store.errorMessage = "请填写学号和密码。"
            return
        }
        if captchaRequired && captcha.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.errorMessage = "请输入图中验证码。"
            return
        }
        focus = nil
        let success = await store.submitLogin(username: name, password: password,
                                              captcha: captchaRequired ? captcha.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                                              remember: remember)
        if !success { await checkCaptcha(force: true) }
    }
}

struct AssignmentDetailView: View {
    @ObservedObject private var store: NativeAppStore
    let task: NativeTask
    @State private var detail: NativeAssignmentDetail?
    @State private var loading = true
    @State private var error: String?
    @State private var confirmCalendar = false
    @State private var editingDeadline = false

    init(task: NativeTask, store: NativeAppStore) {
        self.task = task
        _store = ObservedObject(wrappedValue: store)
    }

    private var currentTask: NativeTask { store.taskIndex.byID[task.id] ?? task }
    private var isReminderOn: Bool {
        store.preferences.remindersEnabled && !store.preferences.mutedTasks.contains(task.id)
    }
    private var canRemind: Bool {
        guard let due = currentTask.dueAt, let snapshot = store.snapshot,
              let course = snapshot.courses.first(where: { $0.id == currentTask.courseID }) else { return false }
        return currentTask.status == .pending && course.termID == NativeDomain.defaultTermID(in: snapshot) && due > Date()
    }

    var body: some View {
        List {
            Section {
                Text(currentTask.courseName).font(.subheadline).foregroundStyle(.secondary)
                NativeLabeledContent(title: "状态", value: status)
                NativeLabeledContent(title: "截止时间", value: Beijing.label(currentTask.dueAt, absolute: true))
                if currentTask.hasManualDeadline {
                    Text("当前使用手动截止时间").font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("manual-deadline-active")
                    NativeLabeledContent(title: "学校截止时间", value: Beijing.label(store.schoolDeadline(for: task.id), absolute: true))
                }
                Button(currentTask.hasManualDeadline ? "修改手动截止时间" : "设置手动截止时间") {
                    editingDeadline = true
                }
                .accessibilityIdentifier("edit-manual-deadline")
                if let assignment = currentTask.assignment, let score = assignment.score {
                    NativeLabeledContent(title: "得分", value: "\(score.formatted(.number.precision(.fractionLength(0...2)))) / \(assignment.pointsPossible.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "—")")
                }
            }

            if loading {
                Section { ProgressView("正在读取作业说明…") }
            } else if let error {
                Section("作业说明") {
                    Text("完整说明暂时无法读取，当前显示缓存摘录。\n\(error)").font(.subheadline).foregroundStyle(.secondary)
                    Button("重试") { Task { await load() } }
                }
            }

            if let summary = detail?.summary, !summary.isEmpty {
                Section("AI 摘要") { Text(summary).textSelection(.enabled) }
            }
            if let summaryError = detail?.summaryError {
                Section { Text(summaryError).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("作业说明") {
                Text(detail?.description.isEmpty == false ? detail!.description : "这项作业没有文字说明，请前往 eLearning 查看附件或提交要求。")
                    .textSelection(.enabled)
            }
            if let links = detail?.links, !links.isEmpty {
                Section("链接与附件入口") {
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                        Link(destination: link.url) { Label(link.label, systemImage: "arrow.up.right.square") }
                    }
                }
            }

            Section("提醒与日历") {
                if canRemind {
                    Toggle("此作业提醒", isOn: Binding(get: { isReminderOn }, set: { enabled in
                        Task { await store.setTaskReminder(currentTask, enabled: enabled) }
                    }))
                    Text(store.preferences.remindersEnabled ? "包含在截止日的汇总提醒中" : "开启后将允许当前学期作业提醒")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if currentTask.dueAt != nil {
                    let exported = store.preferences.calendarExports[task.id]
                    let changed = exported != nil && exported != ISO8601DateFormatter().string(from: currentTask.dueAt!)
                    Button {
                        if exported != nil { confirmCalendar = true }
                        else { Task { _ = await store.presentCalendarEditor(for: currentTask) } }
                    } label: {
                        Label(changed ? "截止已变化，重新添加" : (exported == nil ? "添加到系统日历" : "已添加到系统日历"), systemImage: "calendar.badge.plus")
                    }
                    Text("单向添加，截止变化后需重新添加").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("没有截止时间的作业无法安排提醒或导出日历").font(.footnote).foregroundStyle(.secondary)
                }
                if let assignment = currentTask.assignment {
                    Toggle("无需提交", isOn: Binding(get: { currentTask.status == .ignored }, set: { _ in
                        Task { await store.toggleIgnored(assignment) }
                    }))
                    Text("从待交任务和提醒中移除，不影响成绩").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("作业详情")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let url = currentTask.url {
                Link(destination: url) {
                    Text("前往 eLearning").font(.body.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.top, 8)
                .background(.bar)
            }
        }
        .task(id: task.id) { await load() }
        .sheet(isPresented: $editingDeadline) {
            ManualDeadlineEditor(task: currentTask, store: store)
        }
        .confirmationDialog(calendarConfirmationTitle, isPresented: $confirmCalendar, titleVisibility: .visible) {
            Button("继续添加") { Task { _ = await store.presentCalendarEditor(for: currentTask) } }
            Button("取消", role: .cancel) { }
        } message: {
            Text(calendarConfirmationMessage)
        }
        .alert("日历操作失败", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var status: String {
        if currentTask.status == .ignored { return "无需提交" }
        if currentTask.status == .submitted {
            if currentTask.assignment?.excused == true { return "已免除" }
            return currentTask.assignment?.score == nil ? "已提交待评分" : "已评分"
        }
        return currentTask.bucket() == .overdue ? "已逾期未交" : "未提交"
    }

    private var calendarChanged: Bool {
        guard let due = currentTask.dueAt, let prior = store.preferences.calendarExports[task.id] else { return false }
        return prior != ISO8601DateFormatter().string(from: due)
    }

    private var calendarConfirmationTitle: String {
        calendarChanged ? "截止时间已变化" : "再次添加到日历？"
    }

    private var calendarConfirmationMessage: String {
        calendarChanged
            ? "系统日历中的旧事件不会自动更新。请在日历中删除旧事件后重新添加。"
            : "此作业已添加过。再次保存会创建另一条日历事件。"
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { detail = try await store.loadAssignmentDetail(task) }
        catch let loadError {
            error = loadError.localizedDescription
            detail = NativeAssignmentDetail(description: task.assignment?.descriptionExcerpt ?? "", summary: "", summaryError: nil, links: [])
        }
    }
}

private struct ManualDeadlineEditor: View {
    let task: NativeTask
    @ObservedObject var store: NativeAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var saving = false

    init(task: NativeTask, store: NativeAppStore) {
        self.task = task
        self.store = store
        let tomorrow = Beijing.addDays(1, to: Beijing.day(Date()))
        let suggested = Beijing.calendar.date(bySettingHour: 23, minute: 59, second: 0, of: tomorrow) ?? tomorrow
        _date = State(initialValue: task.dueAt ?? suggested)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(task.title)
                    DatePicker("截止日期与时间", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, Beijing.timeZone)
                        .environment(\.calendar, Beijing.calendar)
                        .accessibilityIdentifier("manual-deadline-picker")
                } footer: {
                    Text("北京时间。保存后用于本机的作业排序、月历和已开启的提醒，不修改学校记录。")
                }
                if task.hasManualDeadline {
                    Section {
                        Button("清除手动截止时间", role: .destructive) { save(nil) }
                            .accessibilityIdentifier("clear-manual-deadline")
                    } footer: {
                        Text("清除后恢复学校截止时间；学校未设置时恢复为无截止时间。")
                    }
                }
            }
            .disabled(saving)
            .navigationTitle("手动截止时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save(date) }.disabled(saving)
                        .accessibilityIdentifier("save-manual-deadline")
                }
            }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(saving)
    }

    private func save(_ value: Date?) {
        saving = true
        Task {
            await store.setManualDeadline(for: task.id, date: value)
            dismiss()
        }
    }
}

struct ProfileView: View {
    @ObservedObject var store: NativeAppStore
    @State private var showLogout = false
    @State private var showLogin = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.snapshot?.profile.name ?? "复旦同学").font(.title2.weight(.semibold))
                    Text(store.isLoggedIn ? "复旦统一身份认证" : "离线查看上次同步内容")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }

            Section("个人任务提醒") {
                Toggle("个人任务提醒", isOn: Binding(get: { store.localAccount.personalRemindersEnabled }, set: { value in
                    Task { await store.setPersonalReminders(value) }
                }))
                Text("学校与个人提醒合计安排未来 30 天内最近 60 条，打开应用时补充。长期不打开应用可能无法持续提醒。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let error = store.localError { Text(error).foregroundStyle(.red) }
            }
            Section("作业提醒") {
                Toggle("每日截止提醒", isOn: Binding(get: { store.preferences.remindersEnabled }, set: { value in
                    Task { await store.setRemindersEnabled(value) }
                }))
                Text("当天 08:00 汇总提醒。08:00 及以前截止的作业，在前一天 20:00 提醒。\n提醒依据上次同步的内容，提交作业或老师修改截止后，请再次同步。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let notice = store.reminderNotice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                if store.reminderPermissionDenied {
                    Link("打开 iPhone 通知设置", destination: URL(string: UIApplication.openSettingsURLString)!)
                }
            }

            Section("外观与同步") {
                Picker("外观", selection: Binding(get: { store.preferences.theme }, set: store.setTheme)) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                Picker("同步范围", selection: Binding(get: { store.preferences.refreshScope }, set: store.setRefreshScope)) {
                    Text("当前学期").tag("current")
                    Text("全部学期").tag("all")
                }
                Button { Task { await store.refresh(force: true) } } label: {
                    HStack {
                        Text(store.isBusy ? "正在同步…" : "立即同步")
                        Spacer()
                        if store.isBusy { ProgressView() } else { Image(systemName: "arrow.clockwise").foregroundStyle(.secondary) }
                    }
                }.disabled(store.isBusy || !store.isLoggedIn)
                if let error = store.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                if !store.isLoggedIn {
                    Button("重新登录") { showLogin = true }
                }
            }

            Section("作业摘要与帮助") {
                NavigationLink("作业摘要配置") { SummarySettingsView(store: store) }
                NavigationLink("诊断日志") { DiagnosticsView(store: store) }
                Link("使用帮助", destination: URL(string: "https://github.com/btr2309887446-code/fudan-elearning-dashboard/blob/master/docs/ios.md")!)
            }

            Section {
                Button("退出登录", role: .destructive) { showLogout = true }
                    .disabled(!store.isLoggedIn)
            } footer: {
                Text("非官方校园工具 · 成绩来自 eLearning。系统日历导出为单向添加，不自动更新或删除。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("我的")
        .confirmationDialog("退出登录？", isPresented: $showLogout, titleVisibility: .visible) {
            Button("退出", role: .destructive) { Task { await store.logout() } }
            Button("取消", role: .cancel) { }
        } message: {
            Text("将清除本机登录状态、缓存数据和已安排的作业提醒。")
        }
        .sheet(isPresented: $showLogin) { NativeLoginView(store: store) }
    }
}

struct SummarySettingsView: View {
    @ObservedObject var store: NativeAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var baseURL: String
    @State private var model: String
    @State private var key: String
    @State private var error: String?

    init(store: NativeAppStore) {
        self.store = store
        _enabled = State(initialValue: store.preferences.llm.enabled)
        _baseURL = State(initialValue: store.preferences.llm.baseURL)
        _model = State(initialValue: store.preferences.llm.model)
        _key = State(initialValue: NativeSecrets.read("native.llm.apiKey") ?? "")
    }

    var body: some View {
        Form {
            Section {
                Toggle("启用 AI 摘要", isOn: $enabled)
            }
            Section("接口地址") {
                TextField("https://…/v1", text: $baseURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section("模型名称") { TextField("deepseek-chat", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled() }
            Section("接口密钥") { SecureField("API Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled() }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section {
                Text("使用已有的兼容接口配置。保存不会发起请求；查看较长作业说明时才会生成摘要。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("作业摘要配置")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") { save() }
            }
        }
    }

    private func save() {
        if enabled {
            guard let url = URL(string: baseURL), url.scheme == "https", url.host != nil,
                  !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                error = "开启摘要时，请填写 HTTPS 接口地址、模型名称和密钥。"
                return
            }
        }
        store.setLLM(enabled: enabled, baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                     model: model.trimmingCharacters(in: .whitespacesAndNewlines), apiKey: key)
        dismiss()
    }
}

struct DiagnosticsView: View {
    @ObservedObject var store: NativeAppStore
    @State private var copied = false

    var body: some View {
        List {
            Section {
                Text(store.logs.isEmpty ? "暂无诊断信息" : store.logs.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
        }
        .navigationTitle("诊断日志")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    UIPasteboard.general.string = store.logs.joined(separator: "\n")
                    copied = true
                } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .accessibilityLabel("复制诊断日志")
            }
        }
    }
}
