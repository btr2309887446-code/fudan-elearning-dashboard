import Foundation
import Combine
import UIKit

@MainActor
final class NativeClock: ObservableObject {
    @Published private(set) var now: Date
    private let read: () -> Date
    private var timer: Timer?
    private var active = false
    init(read: @escaping () -> Date = Date.init) { self.read = read; now = read() }
    func refresh() { now = read(); schedule() }
    func setActive(_ value: Bool) { active = value; refresh() }
    private func schedule() {
        timer?.invalidate(); timer = nil
        guard active else { return }
        let delay = max(0.01, 60 - now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60))
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    deinit { timer?.invalidate() }
}
