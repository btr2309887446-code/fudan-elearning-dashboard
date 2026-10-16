import XCTest
import UIKit

final class NativeRunnerUITests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(device)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
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
        XCTAssertTrue(app.buttons["calendar-next-month"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["calendar-month-title"].exists)
        capture(app, "assignments-calendar")

        app.buttons["列表"].tap()
        let assignment = app.staticTexts["演示作业：阅读报告"]
        XCTAssertTrue(assignment.waitForExistence(timeout: 5))
        assignment.tap()
        XCTAssertTrue(app.navigationBars["作业详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["提醒与日历"].exists)
        capture(app, "assignment-detail")
    }
    func testLargeAssignmentListScrollingPerformance() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Performance regression targets the reported iOS 26 environment") }
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--ui-testing-large-data"]
        app.launch()
        XCTAssertTrue(tab(app, "作业").waitForExistence(timeout: 15))
        tab(app, "作业").tap()
        let list = app.descendants(matching: .any).matching(identifier: "task-list").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            list.swipeUp(velocity: .fast)
            stopMeasuring()
            list.swipeDown(velocity: .fast)
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testCalendarSurvivesLargeHistoryRepeatedSwitchesAndNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--ui-testing-large-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(tab(app, "作业").waitForExistence(timeout: 15))
        tab(app, "作业").tap()
        XCTAssertTrue(app.buttons["日历"].waitForExistence(timeout: 5))
        for _ in 0..<6 {
            app.buttons["日历"].tap()
            let next = app.buttons["calendar-next-month"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["calendar-month-title"].label.contains("年"))
            next.tap()
            app.buttons["calendar-previous-month"].tap()
            let dates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "calendar-day-"))
            XCTAssertGreaterThanOrEqual(dates.count, 28)
            dates.element(boundBy: 14).tap()
            XCTAssertEqual(app.state, .runningForeground)
            app.buttons["列表"].tap()
            XCTAssertTrue(app.buttons["日历"].waitForExistence(timeout: 5))
        }
        // Narrow to the retained fixture only after exercising the full dataset.
        app.buttons["task-course-filter"].tap()
        app.buttons["演示课程"].tap()
        let assignment = app.staticTexts["演示作业：阅读报告"]
        XCTAssertTrue(assignment.waitForExistence(timeout: 5))
        assignment.tap()
        XCTAssertTrue(app.navigationBars["作业详情"].waitForExistence(timeout: 5))
        let back = app.navigationBars["作业详情"].buttons.firstMatch
        if back.exists && back.isHittable { back.tap() }
        // A new tab round trip must preserve a valid task navigation container.
        tab(app, "今日").tap()
        tab(app, "作业").tap()
        if !app.buttons["日历"].isHittable && back.exists && back.isHittable { back.tap() }
        XCTAssertTrue(app.buttons["日历"].waitForExistence(timeout: 5))
        app.buttons["日历"].tap()
        XCTAssertTrue(app.buttons["calendar-next-month"].waitForExistence(timeout: 5))
        capture(app, "large-data-calendar")
        XCTAssertEqual(app.state, .runningForeground)
    }

}
