import SwiftUI
import SwiftData

@main
struct LabBookApp: App {
    var body: some Scene {
        WindowGroup {
            ExperimentListView()
        }
        .modelContainer(for: Measurement.self)
    }
}
