import SwiftUI

@main
struct FudanELearningApp: App {
    @UIApplicationDelegateAdaptor(NativeAppDelegate.self) private var appDelegate
    @StateObject private var store = NativeAppStore()

    var body: some Scene {
        WindowGroup {
            NativeRootView(store: store)
        }
    }
}
