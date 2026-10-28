import Foundation
import Combine
import SwiftUI
import UIKit

struct NativeAssignmentDetail {
    var description: String
    var summary: String
    var summaryError: String?
    var links: [(label: String, url: URL)]
}

@MainActor
final class NativeAppStore: ObservableObject {
    let lectures = LectureStore()
    let clock: NativeClock
    @Published private(set) var now: Date
    private var clockObservation: AnyCancellable?
    private let sessionVault: NativeSessionVault
    @Published private(set) var snapshot: NativeSnapshot?
    @Published private(set) var taskIndex = NativeTaskIndex()
    @Published var localAccount = NativeLocalAccount()
    @Published var localSaving = false
    @Published var localError: String?
    @Published var personalHorizon = Beijing.addDays(90, to: Date())
    @Published var notificationTask: NativeTask?
    var localAccountID: Int?
    var localLoadFailed = false
    let localRepository: NativeLocalRepository
    var pendingPersonalNotification: (Int, String)?
    private var reminderReconcileRunning = false
    private var reminderNeedsUpdate = false
    private var sourceTaskIndex = NativeTaskIndex()
    private var manualDeadlinesByAccount: [String: [String: Date]] = [:]
    private let deadlinesKey = "native.manualDeadlines.v1"
    private var snapshotGeneration = 0
    private var sessionGeneration = 0
    private var cachedSnapshotData: Data?
    @Published private(set) var preferences: NativePreferences
    @Published private(set) var cookies: [NativeCookie] = []
    @Published var isBooting = true
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published var credentialWarning: String?
    @Published var refreshProgress: (done: Int, total: Int, label: String)?
    @Published var downloadProgress: NativeDownloadProgress?
    @Published var isDownloading = false
    @Published var reminderNotice: String?
    @Published var reminderPermissionDenied = false
    @Published var reminderDay: String?
    @Published var taskBucket: TaskBucket?
    @Published var calendarTask: NativeTask?
    @Published var fileError: String?
    @Published var logs: [String] = []

    private let defaults: UserDefaults
    private let authenticator = NativeUISAuthenticator()
    private let uiTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    private let uiTestingLogin = ProcessInfo.processInfo.arguments.contains("--ui-testing-login")
    private var fileTrees: [Int: NativeFileNode] = [:]
    private var downloader: NativeDownloader?
    private var cookieKey = "native.cookies.v1"
    private var snapshotKey = "native.snapshot.v1"
    private var prefsKey = "native.preferences.v1"

    init(defaults: UserDefaults = .standard, localRepository: NativeLocalRepository = NativeLocalRepository(), sessionVault: NativeSessionVault = .live, clock: NativeClock? = nil) {
        let clock = clock ?? NativeClock()
        self.clock = clock; self.now = clock.now; self.sessionVault = sessionVault
        self.defaults = defaults
        self.localRepository = localRepository
        NativeFreshStart.run(defaults: defaults)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            preferences = NativePreferences()
        } else if let data = defaults.data(forKey: "native.preferences.v1"),
           let saved = try? JSONDecoder().decode(NativePreferences.self, from: data) {
            preferences = saved
        } else {
            preferences = NativePreferences()
        }
        if uiTesting {
            snapshot = uiTestingLogin ? nil : Self.uiTestSnapshot()
            cookies = []
        } else {
            if let data = defaults.data(forKey: deadlinesKey) {
                manualDeadlinesByAccount = (try? JSONDecoder().decode([String: [String: Date]].self, from: data)) ?? [:]
            }
            if let data = defaults.data(forKey: "native.snapshot.v1") {
                cachedSnapshotData = data
            }
            do { cookies = try sessionVault.restore(from: defaults) }
            catch {
                // A failed migration preserves the old session for this running process.
                if !defaults.bool(forKey: "native.session.revoked"), let data = defaults.data(forKey: "native.cookies.v1") { cookies = (try? JSONDecoder().decode([NativeCookie].self, from: data)) ?? [] }
                credentialWarning = error.localizedDescription
            }
        }
        clockObservation = clock.$now.dropFirst().sink { [weak self] date in
            guard let self else { return }
            self.now = date
            self.ensurePersonalRange(through: Beijing.addDays(90, to: date))
        }
        NativeNotificationRouter.shared.install { [weak self] day in
            self?.reminderDay = day
        }
        NativeNotificationRouter.shared.installTask { [weak self] account, id in
            guard let self else { return }
            self.pendingPersonalNotification = (account, id)
            self.openPendingPersonalNotification()
        }
    }

    private func persistCookies(_ value: [NativeCookie]) {
        guard !uiTesting else { return }
        do { try sessionVault.save(value, defaults: defaults); credentialWarning = nil }
        catch { credentialWarning = error.localizedDescription }
    }
    private func clearCookies() {
        guard !uiTesting else { return }
        do { try sessionVault.clear(defaults: defaults); credentialWarning = nil }
        catch { credentialWarning = error.localizedDescription }
    }
    var isLoggedIn: Bool { !cookies.isEmpty }
    // Accessed by many SwiftUI bodies; never parse or sort from this getter.
    var tasks: [NativeTask] { taskIndex.tasks }

    @discardableResult
    func applySnapshot(_ value: NativeSnapshot) async -> Bool {
        snapshotGeneration += 1
        let generation = snapshotGeneration
        let prepared = await Task.detached(priority: .userInitiated) {
            NativeTaskIndex(snapshot: value)
        }.value
        if localAccountID != value.profile.id {
            do {
                let saved = uiTesting ? NativeLocalAccount() : try await localRepository.load(account: value.profile.id)
                guard generation == snapshotGeneration else { return false }
                localAccount = saved
                if uiTesting && ProcessInfo.processInfo.arguments.contains("--ui-testing-changes") {
                    let old = ChangeResource(id: "8", kind: .assignment, courseID: 4, courseName: "演示课程", title: "截止时间调整", fields: ["截止时间": "无截止时间"])
                    var updated = old
                    updated.fields["截止时间"] = String(Date().addingTimeInterval(86400).timeIntervalSince1970)
                    localAccount.events = [ChangeEvent(id: "fixture-change", resource: updated, before: old, changes: ["截止时间"], discoveredAt: Date())]
                }
                localAccountID = value.profile.id
                localLoadFailed = false
                localError = nil
            } catch {
                guard generation == snapshotGeneration else { return false }
                localAccount = NativeLocalAccount()
                localAccountID = value.profile.id
                localLoadFailed = true
                localError = "无法读取本地任务，原文件已保留：\(error.localizedDescription)"
            }
        }
        guard generation == snapshotGeneration, !Task.isCancelled else { return false }
        sourceTaskIndex = prepared
        snapshot = value
        await lectures.activate(account: value.profile.id, demo: uiTesting ? value.courses : nil)
        guard generation == snapshotGeneration else { return false }
        rebuildTaskIndex()
        openPendingPersonalNotification()
        return true
    }

    func manualDeadline(for taskID: String) -> Date? {
        guard let account = snapshot?.profile.id else { return nil }
        return manualDeadlinesByAccount[String(account)]?[taskID]
    }

    func schoolDeadline(for taskID: String) -> Date? { sourceTaskIndex.byID[taskID]?.dueAt }

    func setManualDeadline(for taskID: String, date: Date?) async {
        guard let account = snapshot?.profile.id, sourceTaskIndex.byID[taskID] != nil,
              date?.timeIntervalSince1970.isFinite != false else { return }
        var deadlines = manualDeadlinesByAccount[String(account), default: [:]]
        deadlines[taskID] = date
        manualDeadlinesByAccount[String(account)] = deadlines
        if !uiTesting, let data = try? JSONEncoder().encode(manualDeadlinesByAccount) {
            defaults.set(data, forKey: deadlinesKey)
        }
        rebuildTaskIndex()
        await reconcileReminders()
    }

    func rebuildTaskIndex() {
        let deadlines = snapshot.map { manualDeadlinesByAccount[String($0.profile.id), default: [:]] } ?? [:]
        let school = sourceTaskIndex.applyingIgnored(preferences.ignoredAssignments).applyingDeadlines(deadlines).tasks
        let personal = localAccount.series.flatMap { $0.occurrences(through: personalHorizon).map(\.nativeTask) }
        taskIndex = NativeTaskIndex(tasks: (school + personal).sorted(by: NativeDomain.taskPrecedes))
    }

    private func clearSnapshot() {
        snapshotGeneration += 1
        snapshot = nil
        sourceTaskIndex = NativeTaskIndex()
        taskIndex = NativeTaskIndex()
        cachedSnapshotData = nil
        localAccountID = nil
        localAccount = NativeLocalAccount()
        notificationTask = nil
    }

    var defaultTermID: Int? { snapshot.map(NativeDomain.defaultTermID(in:)) ?? nil }
    var currentTasks: [NativeTask] {
        guard let id = defaultTermID else { return tasks }
        let ids = Set(snapshot?.courses.filter { $0.termID == id }.map(\.id) ?? [])
        return tasks.filter { task in
            if task.personal != nil, let id = task.courseID, snapshot?.courses.contains(where: { $0.id == id }) == false { return true }
            return task.courseID.map(ids.contains) ?? true
        }
    }
    var selectedCourses: [NativeCourse] {
        guard let snapshot else { return [] }
        switch preferences.selectedTerm {
        case "all": return snapshot.courses
        case "default":
            guard let id = NativeDomain.defaultTermID(in: snapshot) else { return snapshot.courses }
            return snapshot.courses.filter { $0.termID == id }
        default:
            if preferences.selectedTerm == "term:none" { return snapshot.courses.filter { $0.termID == nil } }
            guard let id = Int(preferences.selectedTerm.replacingOccurrences(of: "term:", with: "")) else { return snapshot.courses }
            return snapshot.courses.filter { $0.termID == id }
        }
    }
    var selectedTasks: [NativeTask] {
        let ids = Set(selectedCourses.map(\.id))
        return tasks.filter { task in
            if task.personal != nil, let id = task.courseID, snapshot?.courses.contains(where: { $0.id == id }) == false { return true }
            return task.courseID.map(ids.contains) ?? true
        }
    }

    func setSelectedTerm(_ token: String) {
        preferences.selectedTerm = token
        persistPreferences()
    }

    func boot() async {
        guard isBooting else { return }
        defer { isBooting = false }
        if let data = cachedSnapshotData {
            cachedSnapshotData = nil
            if let cached = await Task.detached(priority: .userInitiated, operation: {
                try? JSONDecoder().decode(NativeSnapshot.self, from: data)
            }).value { await applySnapshot(cached) }
        } else if let snapshot {
            await applySnapshot(snapshot)
        }
        if uiTesting { return }
        if isLoggedIn {
            do {
                let api = CanvasAPI(http: NativeHTTP(cookies: cookies))
                _ = try await api.get("/api/v1/users/self/profile")
                try await refresh()
            } catch {
                if isAuthFailure(error) {
                    cookies = []
                    clearCookies()
                    noticeMessage = "登录状态已失效，请重新登录。你仍可查看上次同步的数据。"
                } else if snapshot == nil {
                    errorMessage = error.localizedDescription
                }
            }
        }
        await reconcileReminders()
        if !lectures.connection.locked, Date().timeIntervalSince(lectures.connection.lastSynced ?? .distantPast) >= 900 {
            Task { await lectures.sync(store: self) }
        }
    }

    func prepareLogin(username: String) async throws -> NativeUISAuthenticator.Preparation {
        errorMessage = nil
        do {
            return try await authenticator.prepare(username: username.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            appendLog("UIS 登录预检失败：\(error.localizedDescription)")
            appendLoginTrace(authenticator.trace)
            throw error
        }
    }

    func submitLogin(username: String, password: String, captcha: String?, remember: Bool) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        errorMessage = nil
        noticeMessage = nil
        var authTraceLogged = false
        var failedProfileTrace: [NativeHTTPTrace] = []
        defer { isBusy = false }
        do {
            appendLog("UIS 登录开始：\(redacted(username))")
            let (newCookies, _) = try await authenticator.complete(username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                    password: password, captcha: captcha)
            let cookieSummary = newCookies.map { "\($0.domain):\($0.name)" }.sorted().joined(separator: ", ")
            appendLog("UIS 认证返回 Canvas；会话 Cookie \(newCookies.count) 条：\(cookieSummary.isEmpty ? "（空）" : cookieSummary)")
            let profileHTTP = NativeHTTP(cookies: newCookies)
            let api = CanvasAPI(http: profileHTTP)
            do {
                _ = try await api.get("/api/v1/users/self/profile")
            } catch {
                failedProfileTrace = profileHTTP.trace
                throw NativeError.protocolFailure("Canvas 登录态校验失败（Cookie \(newCookies.count) 条）：\(error.localizedDescription)")
            }
            appendLoginTrace(authenticator.trace)
            authTraceLogged = true
            appendLoginTrace(profileHTTP.trace)
            cookies = newCookies
            persistCookies(newCookies)
            preferences.rememberedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            preferences.rememberPassword = remember
            NativeSecrets.write(remember ? password : nil, account: "native.password")
            persistPreferences()
            sessionGeneration += 1
            clearSnapshot()
            isBusy = false
            await refresh(force: true)
            return snapshot != nil
        } catch {
            errorMessage = error.localizedDescription
            appendLog("登录失败：\(error.localizedDescription)")
            if !authTraceLogged { appendLoginTrace(authenticator.trace) }
            appendLoginTrace(failedProfileTrace)
            return false
        }
    }

    func refresh(force: Bool = false) async {
        guard !isBusy else { return }
        guard isLoggedIn else { await lectures.sync(store: self); return }
        isBusy = true
        errorMessage = nil
        refreshProgress = nil
        let session = sessionGeneration
        defer { isBusy = false; refreshProgress = nil }
        do {
            let api = CanvasAPI(http: NativeHTTP(cookies: cookies))
            let fresh = try await api.buildSnapshot(previous: snapshot, full: force, scope: preferences.refreshScope) { [weak self] done, total, label in
                Task { @MainActor in self?.refreshProgress = (done, total, label) }
            }
            guard session == sessionGeneration, isLoggedIn else { return }
            guard await applySnapshot(fresh) else { return }
            if !localLoadFailed {
                await recordChanges(fresh.changeBatches ?? [], account: fresh.profile.id)
            }
            let encoded = try await Task.detached(priority: .utility) { try JSONEncoder().encode(fresh) }.value
            guard session == sessionGeneration, isLoggedIn else { return }
            defaults.set(encoded, forKey: snapshotKey)
            persistCookies(cookies)
            noticeMessage = fresh.warnings.isEmpty ? nil : fresh.warnings.joined(separator: "\n")
            appendLog("同步完成：\(fresh.courses.count) 门课程，\(fresh.assignments.count) 项作业")
            await reconcileReminders()
        } catch {
            if isAuthFailure(error) {
                cookies = []
                clearCookies()
                noticeMessage = "登录状态已失效，请重新登录。"
            } else {
                errorMessage = error.localizedDescription
            }
            appendLog("同步失败：\(error.localizedDescription)")
        }
        if session == sessionGeneration { await lectures.sync(store: self) }
    }

    func setTheme(_ value: String) {
        preferences.theme = value
        persistPreferences()
    }

    func setRefreshScope(_ value: String) {
        preferences.refreshScope = value == "all" ? "all" : "current"
        persistPreferences()
    }

    func setTaskFilter(_ value: TaskStatus) {
        preferences.taskFilter = value.rawValue
        persistPreferences()
    }

    func setRemindersEnabled(_ enabled: Bool) async {
        reminderNotice = nil
        if enabled {
            do {
                guard try await NativeNotifications.requestPermission() else {
                    reminderPermissionDenied = true
                    reminderNotice = "通知权限未开启。请在 iPhone 设置中允许通知。"
                    return
                }
            } catch {
                reminderNotice = "暂时无法开启提醒，请稍后重试。"
                return
            }
        }
        reminderPermissionDenied = false
        preferences.remindersEnabled = enabled
        persistPreferences()
        await reconcileReminders()
    }

    func toggleTaskReminder(_ task: NativeTask) async {
        if preferences.mutedTasks.contains(task.id) { preferences.mutedTasks.remove(task.id) }
        else { preferences.mutedTasks.insert(task.id) }
        persistPreferences()
        await reconcileReminders()
    }

    func setTaskReminder(_ task: NativeTask, enabled: Bool) async {
        if enabled {
            if !preferences.remindersEnabled { await setRemindersEnabled(true) }
            if preferences.remindersEnabled { preferences.mutedTasks.remove(task.id) }
        } else {
            preferences.mutedTasks.insert(task.id)
        }
        persistPreferences()
        await reconcileReminders()
    }

    func reconcileReminders() async {
        reminderNeedsUpdate = true
        guard !reminderReconcileRunning else { return }
        reminderReconcileRunning = true
        defer { reminderReconcileRunning = false }
        while reminderNeedsUpdate {
            reminderNeedsUpdate = false
            guard let snapshot else { NativeNotifications.cancelAll(); continue }
            let termID = NativeDomain.defaultTermID(in: snapshot)
            let ids = Set(snapshot.courses.filter { termID == nil || $0.termID == termID }.map(\.id))
            let schoolTasks = self.tasks.filter { $0.personal == nil && ($0.courseID.map(ids.contains) ?? true) }
            let school = preferences.remindersEnabled ? NativeReminderPlanner.make(tasks: schoolTasks, now: Date(), account: String(snapshot.profile.id), muted: preferences.mutedTasks) : []
            let personal = localAccount.personalRemindersEnabled ? PersonalNotificationPlan.make(series: localAccount.series, now: Date(), account: snapshot.profile.id) : []
            do { try await NativeNotifications.replace(with: school, personal: personal) }
            catch { reminderNotice = "提醒安排失败，请在「我的」中重新开启。" }
        }
    }

    func toggleIgnored(_ assignment: NativeAssignment) async {
        let key = NativeDomain.assignmentKey(assignment.courseID, assignment.id)
        if preferences.ignoredAssignments.contains(key) { preferences.ignoredAssignments.remove(key) }
        else { preferences.ignoredAssignments.insert(key) }
        rebuildTaskIndex()
        persistPreferences()
        await reconcileReminders()
    }

    func recordCalendarExport(_ task: NativeTask) {
        guard let due = task.dueAt else { return }
        preferences.calendarExports[task.id] = ISO8601DateFormatter().string(from: due)
        persistPreferences()
    }

    func presentCalendarEditor(for task: NativeTask) async -> Bool {
        if #available(iOS 17.0, *) {
            calendarTask = task
            return true
        }
        do {
            guard try await NativeCalendarAccess.request() else {
                errorMessage = "日历权限未开启。请在 iPhone 设置中允许访问日历后重试。"
                return false
            }
            calendarTask = task
            return true
        } catch {
            errorMessage = "暂时无法打开系统日历，请稍后重试。"
            return false
        }
    }

    func loadAssignmentDetail(_ task: NativeTask) async throws -> NativeAssignmentDetail {
        guard let row = task.assignment else { return NativeAssignmentDetail(description: "", summary: "", summaryError: nil, links: []) }
        if uiTesting {
            return NativeAssignmentDetail(description: NativeDomain.summarize(row.descriptionExcerpt),
                                          summary: "", summaryError: nil, links: [])
        }
        let api = CanvasAPI(http: NativeHTTP(cookies: cookies))
        let result = try await api.assignment(courseID: row.courseID, assignmentID: row.id)
        let raw = CanvasJSON.string(result["description"]) ?? row.descriptionExcerpt ?? ""
        let plain = NativeDomain.summarize(raw)
        let key = NativeSecrets.read("native.llm.apiKey") ?? ""
        let (summary, summaryError) = await NativeSummary.generate(title: task.title, description: raw, config: preferences.llm, apiKey: key)
        let links = Self.extractLinks(from: raw).compactMap { label, link -> (label: String, url: URL)? in
            guard let resolved = URL(string: link, relativeTo: URL(string: "https://elearning.fudan.edu.cn")),
                  ["https", "http"].contains(resolved.scheme?.lowercased() ?? "") else { return nil }
            return (label, resolved.absoluteURL)
        }
        return NativeAssignmentDetail(description: plain, summary: summary, summaryError: summaryError, links: links)
    }

    func loadFiles(courseID: Int, force: Bool = false) async throws -> NativeFileNode {
        if !force, let cached = fileTrees[courseID] { return cached }
        if uiTesting {
            let file = NativeFile(id: 9001, name: "课程资料.pdf", url: URL(string: "https://example.com/course-material")!,
                                  size: 1024, contentType: "application/pdf", folderID: 11, hidden: false)
            let tree = NativeFileTree.build(
                folders: [NativeFileFolder(id: 11, name: "课件", parentID: nil, position: 1)],
                files: [file]
            )
            fileTrees[courseID] = tree
            return tree
        }
        let api = CanvasAPI(http: NativeHTTP(cookies: cookies))
        let tree = try await api.courseFiles(courseID)
        fileTrees[courseID] = tree
        return tree
    }

    func download(courseID: Int, courseName: String, termName: String, tree: NativeFileNode, selectedIDs: Set<Int>? = nil) async {
        guard !isDownloading else { return }
        let nodes = NativeFileTree.flattenNodes(tree).filter { node in
            guard let id = node.file?.id else { return false }
            return selectedIDs == nil || selectedIDs!.contains(id)
        }
        let targets = NativeDownloadPaths.plan(term: termName, course: courseName, nodes: nodes)
        guard !targets.isEmpty else { return }
        if uiTesting {
            let total = targets.reduce(Int64(0)) { $0 + $1.file.size }
            downloadProgress = NativeDownloadProgress(total: targets.count, completed: targets.count,
                                                      bytesReceived: total, bytesTotal: total)
            return
        }
        isDownloading = true
        fileError = nil
        var progress = NativeDownloadProgress(total: targets.count, bytesTotal: targets.reduce(0) { $0 + $1.file.size })
        downloadProgress = progress
        let service = NativeDownloader()
        downloader = service
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("eLearning", isDirectory: true)
        for target in targets {
            if Task.isCancelled { break }
            let file = target.file
            progress.currentName = file.name
            progress.currentTotal = file.size
            progress.currentReceived = 0
            downloadProgress = progress
            let destination = documents.appendingPathComponent(target.relativePath)
            if let size = try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber,
               size.int64Value == file.size {
                progress.skipped += 1
                progress.bytesReceived += file.size
                downloadProgress = progress
                continue
            }
            do {
                _ = try await service.download(file, destination: destination, cookies: cookies) { [weak self] written, expected in
                    Task { @MainActor in
                        guard let self else { return }
                        var current = self.downloadProgress ?? NativeDownloadProgress()
                        let old = current.currentReceived
                        current.currentReceived = written
                        current.currentTotal = expected > 0 ? expected : file.size
                        current.bytesReceived += max(0, written - old)
                        self.downloadProgress = current
                    }
                }
                progress.completed += 1
            } catch is CancellationError {
                break
            } catch {
                progress.failed += 1
                fileError = error.localizedDescription
            }
            progress = downloadProgress ?? progress
            progress.completed = min(progress.completed, targets.count)
            downloadProgress = progress
        }
        progress = downloadProgress ?? progress
        progress.currentName = ""
        downloadProgress = progress
        downloader = nil
        isDownloading = false
    }

    func cancelDownload() { downloader?.cancel() }

    func openReminderDay(_ day: String) {
        reminderDay = day
        taskBucket = nil
    }

    func clearReminderDay() { reminderDay = nil }

    func logout() async {
        sessionGeneration += 1
        cookies = []
        clearSnapshot()
        await lectures.activate(account: nil)
        preferences.remindersEnabled = false
        preferences.mutedTasks = []
        preferences.calendarExports = [:]
        preferences.rememberPassword = false
        clearCookies()
        defaults.removeObject(forKey: snapshotKey)
        NativeSecrets.write(nil, account: "native.password")
        await reconcileReminders()
        persistPreferences()
        fileTrees = [:]
        errorMessage = nil
        noticeMessage = nil
    }

    func setLLM(enabled: Bool, baseURL: String, model: String, apiKey: String) {
        preferences.llm = NativeLLMConfig(baseURL: baseURL, model: model, enabled: enabled)
        NativeSecrets.write(apiKey, account: "native.llm.apiKey")
        persistPreferences()
    }

    func rememberedPassword() -> String? { NativeSecrets.read("native.password") }

    func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = Beijing.timeZone
        formatter.dateFormat = "MM-dd HH:mm:ss"
        let safe = message.replacingOccurrences(of: #"(?i)(password|token|cookie|authorization)\s*[:=]\s*\S+"#,
                                                with: "$1=[已隐藏]", options: .regularExpression)
        logs.append("\(formatter.string(from: Date())) \(safe)")
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
    }

    private func appendLoginTrace(_ trace: [NativeHTTPTrace]) {
        for item in trace.suffix(80) {
            var fields = ["HTTP \(item.phase) \(item.method) \(item.url) -> \(item.status)"]
            if !item.setCookieNames.isEmpty { fields.append("Set-Cookie[\(item.setCookieNames.sorted().joined(separator: ","))]") }
            if !item.sentCookieNames.isEmpty { fields.append("Cookie[\(item.sentCookieNames.sorted().joined(separator: ","))]") }
            if let location = item.location { fields.append("Location=\(location)") }
            if let origin = item.origin { fields.append("Origin=\(origin)") }
            if let referer = item.referer { fields.append("Referer=\(referer)") }
            if !item.bodyShape.isEmpty {
                let shape = item.bodyShape.keys.sorted().map { key in
                    "\(key){\(item.bodyShape[key, default: []].sorted().joined(separator: ","))}"
                }.joined(separator: ",")
                fields.append("BodyFields[\(shape)]")
            }
            if let code = item.authCode { fields.append("authCode=\(code)") }
            if let present = item.loginTokenPresent { fields.append("loginTokenPresent=\(present)") }
            if let required = item.secondFactorRequired { fields.append("secondFactorRequired=\(required)") }
            if let found = item.ticketFound { fields.append("ticketFound=\(found)") }
            if let host = item.ticketHost { fields.append("ticketHost=\(host)") }
            appendLog(fields.joined(separator: " | "))
        }
    }

    private func persistPreferences() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: prefsKey) }
    }

    private func isAuthFailure(_ error: Error) -> Bool {
        guard let native = error as? NativeError else { return false }
        if case .authExpired = native { return true }
        if case let .http(code, _) = native { return code == 401 || code == 403 }
        return false
    }

    private func redacted(_ value: String) -> String {
        guard value.count > 4 else { return "****" }
        return String(value.prefix(2)) + "***" + String(value.suffix(2))
    }

    private static func extractLinks(from html: String) -> [(String, String)] {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<a\b[^>]*href\s*=\s*['\"]([^'\"]+)['\"][^>]*>(.*?)</a>"#) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var links: [(String, String)] = []
        var seen: Set<String> = []
        for match in regex.matches(in: html, range: range) where match.numberOfRanges > 2 {
            guard let urlRange = Range(match.range(at: 1), in: html), let labelRange = Range(match.range(at: 2), in: html) else { continue }
            let url = String(html[urlRange]).replacingOccurrences(of: "&amp;", with: "&")
            guard seen.insert(url).inserted else { continue }
            let label = NativeDomain.summarize(String(html[labelRange]))
            links.append((label.isEmpty ? url : label, url))
        }
        return links
    }

    private static func uiTestSnapshot() -> NativeSnapshot {
        let now = Date()
        let start = Beijing.addDays(-30, to: now)
        let end = Beijing.addDays(120, to: now)
        let formatter = ISO8601DateFormatter()
        let term = NativeTerm(id: 2026, name: "2026-2027 学年秋季学期",
                              startAt: formatter.string(from: start), endAt: formatter.string(from: end),
                              isCurrent: true, courseCount: 1)
        let course = NativeCourse(id: 1001, name: "演示课程", displayName: "演示课程", courseCode: "TEST1001",
                                  termName: term.name, termID: term.id, termStartAt: term.startAt,
                                  termEndAt: term.endAt, nickname: nil, startAt: nil, endAt: nil,
                                  currentScore: 88, finalScore: nil, currentGrade: nil, finalGrade: nil,
                                  earnedPoints: 88, possiblePointsGraded: 100, assignmentCount: 1,
                                  submittedCount: 0, gradedCount: 1, missingCount: 0, lateCount: 0, upcomingCount: 1)
        let due = Beijing.addDays(1, to: Beijing.day(now)).addingTimeInterval(10 * 60 * 60)
        let assignment = NativeAssignment(id: 2001, courseID: course.id, courseName: course.displayName,
                                          name: "演示作业：阅读报告", groupID: 1, groupName: "平时作业",
                                          dueAt: formatter.string(from: due), pointsPossible: 100,
                                          groupWeight: 100, score: nil, grade: nil, submittedAt: nil,
                                          gradedAt: nil, workflowState: "unsubmitted", late: false,
                                          missing: false, excused: false, omitFromFinalGrade: false,
                                          htmlURL: "https://elearning.fudan.edu.cn",
                                          descriptionExcerpt: "<p>请阅读课程材料并提交一份简短报告。</p><p>格式要求：PDF &#8220;附件&#8221;。</p>")
        var courses = [course]
        var assignments = [assignment]
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-undated") { assignments[0].dueAt = nil }
        var terms = [term]
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-large-data") {
            var historical = term
            historical.id = 2025
            historical.name = "历史学期"
            historical.isCurrent = false
            terms.append(historical)
            for index in 0..<24 {
                var extra = course
                extra.id = 1100 + index
                extra.name = "压力测试课程 \(index)"
                extra.displayName = extra.name
                extra.termID = index < 12 ? term.id : historical.id
                extra.termName = index < 12 ? term.name : historical.name
                courses.append(extra)
                for offset in 0..<100 {
                    var row = assignment
                    row.id = 10000 + index * 100 + offset
                    row.courseID = extra.id
                    row.courseName = extra.name
                    row.name = "压力测试作业 \(index)-\(offset)"
                    row.dueAt = offset % 17 == 0 ? nil : formatter.string(from: Beijing.addDays(offset - 20, to: due))
                    row.workflowState = offset % 4 == 0 ? "submitted" : "unsubmitted"
                    assignments.append(row)
                }
            }
        }
        return NativeSnapshot(fetchedAt: now, profile: NativeProfile(id: 1, name: "测试同学"),
                              courses: courses, terms: terms, assignments: assignments, todo: [],
                              warnings: [], reusedCourseCount: 0)
    }
}
