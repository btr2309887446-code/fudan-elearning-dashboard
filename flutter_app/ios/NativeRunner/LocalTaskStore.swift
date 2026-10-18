import Foundation

extension NativeAppStore {
    func openPendingPersonalNotification() {
        guard let (account, id) = pendingPersonalNotification, let currentAccount = snapshot?.profile.id else { return }
        pendingPersonalNotification = nil
        guard currentAccount == account else { return }
        if let key = id.split(separator: ":").last, let date = Beijing.parseKey(String(key)) { ensurePersonalRange(through: Beijing.addDays(1, to: date)) }
        notificationTask = tasks.first { $0.id == id }
    }
    var unreadChanges: Int { localAccount.events.filter { !$0.read }.count }

    @discardableResult
    func updateLocal(_ transform: (inout NativeLocalAccount) -> Void) async -> Bool {
        guard let account = snapshot?.profile.id, account == localAccountID, !localLoadFailed else { return false }
        while localSaving {
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        guard snapshot?.profile.id == account, localAccountID == account else { return false }
        localSaving = true
        defer { localSaving = false }
        var next = localAccount
        transform(&next)
        do {
            if !ProcessInfo.processInfo.arguments.contains("--ui-testing") { try await localRepository.save(next, account: account) }
            guard snapshot?.profile.id == account, localAccountID == account else { return false }
            localAccount = next
            localError = nil
            rebuildTaskIndex()
            return true
        } catch {
            localError = "未能保存，原有数据已保留：\(error.localizedDescription)"
            return false
        }
    }

    func recordChanges(_ batches: [ChangeBatch], account: Int) async {
        guard snapshot?.profile.id == account else { return }
        await updateLocal { $0 = NativeChangeTracker.applying(batches, to: $0, now: Date()) }
    }

    func markChangesRead(_ ids: Set<String>) async {
        await updateLocal { value in
            for i in value.events.indices where ids.contains(value.events[i].id) { value.events[i].read = true }
        }
    }

    func ensurePersonalRange(through date: Date) {
        if date > personalHorizon { personalHorizon = date; rebuildTaskIndex() }
    }

    func savePersonal(_ draft: PersonalTaskSeries, occurrence: PersonalOccurrence? = nil, following: Bool = false) async -> Bool {
        guard let editingAccount = snapshot?.profile.id else { return false }
        var draft = draft.withoutExceptions
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let due = draft.dueAt { draft.dueAt = Date(timeIntervalSince1970: floor(due.timeIntervalSince1970 / 60) * 60) }
        guard !draft.title.isEmpty else { localError = "请输入任务标题。"; return false }
        if draft.dueAt == nil { draft.repeatRule = .none; draft.reminderMinutes = [] }
        if draft.repeatRule == .weekly && draft.weekdays.isEmpty { localError = "请至少选择一个星期。"; return false }
        if let end = draft.endDate, let due = draft.dueAt, Beijing.day(end) < Beijing.day(due) {
            localError = "重复结束日期不能早于首次截止日期。"; return false
        }
        draft.reminderMinutes = Array(Set(draft.reminderMinutes.filter { $0 >= 0 && $0 <= 366 * 1440 })).sorted().prefix(5).map { $0 }
        if !draft.reminderMinutes.isEmpty {
            do {
                if try await NativeNotifications.requestPermission() == false { reminderNotice = "通知权限未开启，任务仍会保存。请到系统设置允许通知。" }
            } catch { reminderNotice = "提醒权限请求失败，任务仍会保存。" }
        }
        guard snapshot?.profile.id == editingAccount else { return false }
        let success = await updateLocal { value in
            guard let occurrence, let index = value.series.firstIndex(where: { $0.id == occurrence.seriesID }) else {
                value.series.append(draft); return
            }
            let old = value.series[index]
            if old.repeatRule == .none {
                draft.id = old.id
                if draft.repeatRule == .none { draft.exceptions = old.exceptions }
                else if let state = old.exceptions["single"] { draft.exceptions[draft.occurrenceKey(draft.dueAt)] = state }
                value.series[index] = draft
            } else if following, let date = occurrence.scheduledAt {
                value.series[index].endDate = Beijing.addDays(-1, to: Beijing.day(date))
                // All earlier occurrences retain their original identities and completion records.
                draft.id = UUID().uuidString
                draft.exceptions = [:]
                value.series.append(draft)
            } else {
                draft.repeatRule = .none
                var state = value.series[index].exceptions[occurrence.key] ?? PersonalOccurrenceState()
                state.override = draft
                value.series[index].exceptions[occurrence.key] = state
            }
        }
        if success { await reconcileReminders() }
        return success
    }

    func changePersonalState(_ occurrence: PersonalOccurrence, completed: Bool? = nil, checklistID: String? = nil) async {
        let success = await updateLocal { value in
            guard let i = value.series.firstIndex(where: { $0.id == occurrence.seriesID }) else { return }
            var state = value.series[i].exceptions[occurrence.key] ?? PersonalOccurrenceState()
            if let completed { state.completed = completed }
            if let checklistID {
                if state.checked.contains(checklistID) { state.checked.remove(checklistID) } else { state.checked.insert(checklistID) }
            }
            value.series[i].exceptions[occurrence.key] = state
        }
        if success { await reconcileReminders() }
    }

    func deletePersonal(_ occurrence: PersonalOccurrence, following: Bool) async -> Bool {
        let success = await updateLocal { value in
            guard let i = value.series.firstIndex(where: { $0.id == occurrence.seriesID }) else { return }
            if value.series[i].repeatRule == .none { value.series.remove(at: i) }
            else if following, let date = occurrence.scheduledAt { value.series[i].endDate = Beijing.addDays(-1, to: Beijing.day(date)) }
            else {
                var state = value.series[i].exceptions[occurrence.key] ?? PersonalOccurrenceState()
                state.deleted = true
                value.series[i].exceptions[occurrence.key] = state
            }
        }
        if success { await reconcileReminders() }
        return success
    }

    func setPersonalReminders(_ enabled: Bool) async {
        if enabled {
            do { guard try await NativeNotifications.requestPermission() else { reminderNotice = "通知权限未开启。"; return } }
            catch { reminderNotice = error.localizedDescription; return }
        }
        if await updateLocal({ $0.personalRemindersEnabled = enabled }) { await reconcileReminders() }
    }
}

struct PersonalNotification: Sendable {
    var id: String
    var at: Date
    var account: Int
    var taskID: String
    var title: String
}

enum PersonalNotificationPlan {
    static func make(series: [PersonalTaskSeries], now: Date, account: Int) -> [PersonalNotification] {
        let horizon = Beijing.addDays(30, to: now)
        // A reminder can fall in the window even when its deadline is farther away.
        let maxLead = series.flatMap { [$0.reminderMinutes.max() ?? 0] + $0.exceptions.values.compactMap { $0.override?.reminderMinutes.max() } }.max() ?? 0
        return series.flatMap { $0.occurrences(through: horizon.addingTimeInterval(Double(maxLead) * 60)) }.flatMap { occurrence -> [PersonalNotification] in
            guard !occurrence.completed, let due = occurrence.dueAt else { return [] }
            return occurrence.task.reminderMinutes.compactMap { lead in
                let at = due.addingTimeInterval(-Double(lead) * 60)
                guard at > now, at <= horizon else { return nil }
                return PersonalNotification(id: "personal-\(account)-\(occurrence.id)-\(lead)", at: at, account: account,
                                            taskID: occurrence.id, title: occurrence.task.title)
            }
        }.sorted { $0.at < $1.at }
    }
}
