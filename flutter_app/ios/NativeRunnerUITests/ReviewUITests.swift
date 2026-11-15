import XCTest

final class ReviewUITests: XCTestCase {
    func testCreatePlanAndKnowledgePoint() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let courses = app.descendants(matching: .any).matching(NSPredicate(format: "label == '课程'")).firstMatch
        XCTAssertTrue(courses.waitForExistence(timeout: 10)); courses.tap()
        let course = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '演示课程'")).firstMatch
        XCTAssertTrue(course.waitForExistence(timeout: 5)); course.tap()
        let entry = app.buttons["course-review-entry"]
        for _ in 0..<5 { if entry.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        app.buttons["review-new-plan"].tap()
        XCTAssertTrue(app.textFields["review-plan-title"].waitForExistence(timeout: 5))
        app.buttons["review-plan-save"].tap()
        let plan = app.staticTexts["期末复习"]
        XCTAssertTrue(plan.waitForExistence(timeout: 5)); plan.tap()
        app.buttons["review-add-item"].tap()
        let title = app.textFields["review-item-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Synthetic knowledge")
        app.buttons["review-item-save"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic knowledge"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "review-plan"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
