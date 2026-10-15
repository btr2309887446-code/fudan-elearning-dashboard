import XCTest

final class NativeRunnerUITests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else { return }
        let device = ProcessInfo.processInfo.environment["SCREENSHOT_DEVICE"] ?? "simulator"
        let fileName = "\(device)-\(name).png"
        let url = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(fileName)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        add(attachment)
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try attachment.pngRepresentation.write(to: url)
        } catch {
            XCTFail("Unable to save screenshot \(fileName): \(error)")
        }
    }

    private func tab(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", title))
            .firstMatch
    }

    func testLoginUsesNativeFormControls() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--ui-testing-login"]
        app.launch()

        XCTAssertTrue(app.navigationBars["登录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["学号"].exists)
        XCTAssertTrue(app.secureTextFields["密码"].exists)
        XCTAssertTrue(app.switches["记住密码（保存在系统钥匙串）"].exists)
        XCTAssertTrue(app.buttons["登录"].exists)
    }

    func testLoginRendersAtLargeAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--ui-testing-login", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        app.launch()

        XCTAssertTrue(app.textFields["学号"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["登录"].exists)
        XCTAssertTrue(app.staticTexts["诊断日志"].exists)
    }

    func testAllFourTabsAndOverviewContent() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing"]
        app.launch()

        for title in ["今日", "作业", "课程", "我的"] {
            XCTAssertTrue(
                tab(app, title).waitForExistence(timeout: 5),
                "Missing \(title) tab. Accessibility hierarchy: \(app.debugDescription)"
            )
        }
        XCTAssertTrue(app.staticTexts["今天"].exists)
        XCTAssertTrue(app.staticTexts["未来七天"].exists)
        capture(app, "today")

        tab(app, "作业").tap()
        XCTAssertTrue(app.navigationBars["作业"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["演示作业：阅读报告"].waitForExistence(timeout: 5))
        capture(app, "assignments-list")

        tab(app, "课程").tap()
        XCTAssertTrue(app.navigationBars["课程"].waitForExistence(timeout: 5))
        let course = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '演示课程'"))
            .firstMatch
        XCTAssertTrue(course.waitForExistence(timeout: 5))
        course.tap()
        XCTAssertTrue(app.staticTexts["TEST1001 · 2026-2027 学年秋季学期"].waitForExistence(timeout: 5))
        capture(app, "course-detail")

        tab(app, "我的").tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["每日截止提醒"].exists)
        capture(app, "profile")
    }

    func testAssignmentCalendarModeAndDetail() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing"]
        app.launch()
        tab(app, "作业").tap()

        let calendarButton = app.buttons["日历"]
        XCTAssertTrue(calendarButton.waitForExistence(timeout: 5))
        calendarButton.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '北京时间'")).firstMatch.exists)
        capture(app, "assignments-calendar")

        app.buttons["列表"].tap()
        let assignment = app.staticTexts["演示作业：阅读报告"]
        XCTAssertTrue(assignment.waitForExistence(timeout: 5))
        assignment.tap()
        XCTAssertTrue(app.navigationBars["作业详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["提醒与日历"].exists)
        capture(app, "assignment-detail")
    }
}
