import Flutter
import UIKit
import EventKit
import EventKitUI
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CalendarExportPlugin") {
      CalendarExportPlugin.register(with: registrar)
    }
  }
}

/// Presents the system event editor. The app never reads existing events.
final class CalendarExportPlugin: NSObject, FlutterPlugin, EKEventEditViewDelegate {
  private let eventStore = EKEventStore()
  private var pendingResult: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "cn.edu.fudan.elearning/calendar", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(CalendarExportPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "add" else { result(FlutterMethodNotImplemented); return }
    guard pendingResult == nil else { result("unavailable"); return }
    guard let args = call.arguments as? [String: Any],
          let title = args["title"] as? String,
          let seconds = args["due"] as? Double, seconds.isFinite else {
      result("unavailable"); return
    }
    pendingResult = result
    if #available(iOS 17.0, *) {
      presentEditor(args, title: title, seconds: seconds)
    } else {
      eventStore.requestAccess(to: .event) { [weak self] granted, _ in
        DispatchQueue.main.async {
          guard let self = self else { return }
          if granted { self.presentEditor(args, title: title, seconds: seconds) }
          else { self.finish("denied") }
        }
      }
    }
  }

  private func presentEditor(_ args: [String: Any], title: String, seconds: Double) {
    guard let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
      var presenter = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
      finish("unavailable"); return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    let event = EKEvent(eventStore: eventStore)
    event.title = title
    event.startDate = Date(timeIntervalSince1970: seconds)
    event.endDate = event.startDate.addingTimeInterval(60)
    event.timeZone = TimeZone(identifier: "Asia/Shanghai")
    event.notes = "课程：\(args["course"] as? String ?? "")\n此事件表示作业截止时刻。后续截止变化不会自动更新此事件。"
    if let url = args["url"] as? String { event.url = URL(string: url) }
    // Only older systems require authorization and a default calendar.
    if #available(iOS 17.0, *) {} else { event.calendar = eventStore.defaultCalendarForNewEvents }
    let editor = EKEventEditViewController()
    editor.isModalInPresentation = true
    editor.eventStore = eventStore
    editor.event = event
    editor.editViewDelegate = self
    presenter.present(editor, animated: true)
  }

  func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
    controller.dismiss(animated: true) { [weak self] in
      self?.finish(action == .saved ? "saved" : "cancelled")
    }
  }

  private func finish(_ value: String) {
    let callback = pendingResult
    pendingResult = nil
    callback?(value)
  }
}
