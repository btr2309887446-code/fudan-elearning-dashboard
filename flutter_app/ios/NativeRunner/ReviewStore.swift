import Foundation

extension NativeAppStore {
    var review: ReviewData { localAccount.review ?? ReviewData() }
    @discardableResult
    func changeReview(_ action: ReviewAction, revision: Int, account: Int?) async -> Bool {
        guard account != nil, account == snapshot?.profile.id else { return false }
        let success = await updateLocal { data in
            guard account == self.snapshot?.profile.id else { throw CancellationError() }
            if case .plan(let plan) = action, self.snapshot?.courses.contains(where: { $0.id == plan.courseID }) != true {
                throw ReviewDomain.failure("课程不可用，请重新打开课程。")
            }
            try ReviewDomain.apply(action, revision: revision, to: &data, now: self.clock.now)
            for i in data.series.indices where data.series[i].reviewSource != nil {
                data.series[i].courseName = self.snapshot?.courses.first(where: { $0.id == data.series[i].courseID })?.displayName ?? "课程复习"
            }
        }
        if success { await reconcileReminders() }
        return success
    }
}
