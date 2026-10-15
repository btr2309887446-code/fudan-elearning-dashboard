import XCTest

final class NativeRunnerUITests: XCTestCase {
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
            XCTAssertTrue(app.tabBars.buttons[title].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.staticTexts["今天"].exists)
        XCTAssertTrue(app.staticTexts["未来七天"].exists)

        app.tabBars.buttons["作业"].tap()
        XCTAssertTrue(app.navigationBars["作业"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["演示作业：阅读报告"].exists)

        app.tabBars.buttons["课程"].tap()
        XCTAssertTrue(app.navigationBars["课程"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["演示课程"].exists)

        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["每日截止提醒"].exists)
    }

    func testAssignmentCalendarModeAndDetail() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing"]
        app.launch()
        app.tabBars.buttons["作业"].tap()

        let calendarButton = app.buttons["日历"]
        XCTAssertTrue(calendarButton.waitForExistence(timeout: 5))
        calendarButton.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '北京时间'")).firstMatch.exists)

        app.buttons["列表"].tap()
        let assignment = app.staticTexts["演示作业：阅读报告"]
        XCTAssertTrue(assignment.waitForExistence(timeout: 5))
        assignment.tap()
        XCTAssertTrue(app.navigationBars["作业详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["提醒与日历"].exists)
    }
}
