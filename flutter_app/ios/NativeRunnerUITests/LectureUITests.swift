import XCTest
import UIKit

final class LectureUITests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = (UIDevice.current.userInterfaceIdiom == .pad ? "iPad-" : "iPhone-") + name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testCourseReaderAndTaskDraft() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let courses = app.descendants(matching: .any).matching(NSPredicate(format: "label == '课程'")).firstMatch
        XCTAssertTrue(courses.waitForExistence(timeout: 10)); courses.tap()
        let course = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '演示课程'")).firstMatch
        XCTAssertTrue(course.waitForExistence(timeout: 5)); course.tap()
        XCTAssertTrue(app.staticTexts["课程简介"].waitForExistence(timeout: 5))
        capture(app, "lecture-course-overview")
        let latest = app.staticTexts["第 4 讲 · 核心概念与应用"]
        for _ in 0..<5 { if latest.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(latest.waitForExistence(timeout: 5)); latest.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["AI 生成的摘要，请结合教师原意核对。"].exists)
        // WebKit may cold-start slowly on a newly booted simulator. Wait for actual content,
        // not merely the native WKWebView container, before capturing or switching tabs.
        XCTAssertTrue(app.webViews.staticTexts["这是虚构课堂笔记。"].waitForExistence(timeout: 30))
        capture(app, "lecture-summary")
        app.buttons["转写"].tap()
        XCTAssertTrue(app.webViews.staticTexts["本课次原始转写使用虚构内容，仅供界面测试。"].waitForExistence(timeout: 5))
        capture(app, "lecture-transcript")
        app.buttons["PPT 文字"].tap()
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS '第 1 页'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["摘要"].tap()
        app.buttons["转写"].tap()
        app.buttons["PPT 文字"].tap()
        app.buttons["摘要"].tap()
        XCTAssertTrue(app.webViews.staticTexts["这是虚构课堂笔记。"].waitForExistence(timeout: 10))
        app.buttons["课堂事项（2）"].tap()
        let action = app.buttons["阅读本章并整理三个疑问，下次课讨论。"]
        XCTAssertTrue(action.waitForExistence(timeout: 5)); action.tap()
        let title = app.textFields["personal-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); XCTAssertTrue((title.value as? String)?.contains("阅读本章") == true)
        XCTAssertEqual(app.switches["personal-has-deadline"].value as? String, "0")
        capture(app, "lecture-task-draft")
        app.buttons["personal-save"].tap()
        let viewTask = app.buttons["查看刚创建的任务"]
        XCTAssertTrue(viewTask.waitForExistence(timeout: 5)); viewTask.tap()
        XCTAssertTrue(app.navigationBars["个人任务"].waitForExistence(timeout: 5))
        capture(app, "lecture-task-source")
    }
}
