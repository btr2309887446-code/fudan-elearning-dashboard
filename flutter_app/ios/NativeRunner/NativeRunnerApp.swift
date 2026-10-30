import SwiftUI

@main
struct FudanELearningApp: App {
    init() { LectureDatabase.cleanStagingFiles() }
    @UIApplicationDelegateAdaptor(NativeAppDelegate.self) private var appDelegate
    @StateObject private var store = NativeAppStore()

    var body: some Scene {
        WindowGroup {
            NativeRootView(store: store)
        }
    }
}
