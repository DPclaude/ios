import XCTest

@MainActor final class PlannerUITests: XCTestCase {
    func testNativeTaskLifecycle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-data"]
        app.launch()
        XCTAssertTrue(app.buttons["addTask"].waitForExistence(timeout: 10))
        app.buttons["addTask"].tap()
        let field = app.textViews["taskText"]
        XCTAssertTrue(field.waitForExistence(timeout: 3)); field.tap(); field.typeText("测试计划")
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.buttons["edit-测试计划"].waitForExistence(timeout: 3))
        app.buttons["toggle-测试计划"].tap()
        app.buttons["edit-测试计划"].tap()
        app.buttons["deleteTask"].tap()
        XCTAssertTrue(app.buttons["undoDelete"].waitForExistence(timeout: 3))
        app.buttons["undoDelete"].tap()
        XCTAssertTrue(app.buttons["edit-测试计划"].waitForExistence(timeout: 3))
        app.terminate(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["edit-测试计划"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    func testDarkModeAndLargeText() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--dark", "--large-text"]
        app.launch()
        XCTAssertTrue(app.buttons["addTask"].waitForExistence(timeout: 10))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.buttons["exportBackup"].waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
