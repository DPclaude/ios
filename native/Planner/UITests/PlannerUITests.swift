import XCTest

@MainActor final class PlannerUITests: XCTestCase {
    func testSliceCompletesAndUndoRestoresPlan() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-data"]
        app.launch()
        XCTAssertTrue(app.buttons["addTask"].waitForExistence(timeout: 10))
        app.buttons["addTask"].tap()
        let field = app.textViews["taskText"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("划掉这一件")
        dismissKeyboardIntroduction(in: app)
        app.buttons["saveTask"].tap()
        let entrance = app.buttons["openSlice"]
        XCTAssertTrue(entrance.waitForExistence(timeout: 5))
        guard entrance.exists else { return }
        entrance.tap()
        let card = app.otherElements["slice-划掉这一件"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).press(forDuration: 0.05, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertTrue(app.buttons["undoSlice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今天的计划已完成"].waitForExistence(timeout: 5))
        app.buttons["undoSlice"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        app.buttons["closeSlice"].tap()
        XCTAssertEqual(app.buttons["toggle-划掉这一件"].label, "完成：划掉这一件")
    }
    private func dismissKeyboardIntroduction(in app: XCUIApplication) {
        let introduction = app.otherElements["UIContinuousPathIntroductionView"]
        if introduction.waitForExistence(timeout: 2) { introduction.buttons["Continue"].tap() }
    }
    func testNativeTaskLifecycle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-data"]
        app.launch()
        XCTAssertTrue(app.buttons["addTask"].waitForExistence(timeout: 10))
        app.buttons["addTask"].tap()
        let field = app.textViews["taskText"]
        XCTAssertTrue(field.waitForExistence(timeout: 3)); field.tap(); field.typeText("测试计划")
        dismissKeyboardIntroduction(in: app)
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.buttons["edit-测试计划"].waitForExistence(timeout: 3))
        app.buttons["toggle-测试计划"].tap()
        let completedRow = app.buttons["edit-测试计划"]
        for _ in 0..<3 where !completedRow.isHittable || completedRow.frame.maxY > app.buttons["addTask"].frame.minY {
            app.swipeUp()
        }
        XCTAssertEqual(app.buttons["toggle-测试计划"].label, "标为未完成：测试计划")
        completedRow.tap()
        XCTAssertTrue(app.navigationBars["编辑计划"].waitForExistence(timeout: 5))
        for _ in 0..<3 where !app.buttons["deleteTask"].exists { app.swipeUp() }
        app.buttons["deleteTask"].tap()
        XCTAssertTrue(app.buttons["undoDelete"].waitForExistence(timeout: 3))
        app.buttons["undoDelete"].tap()
        XCTAssertTrue(app.buttons["edit-测试计划"].waitForExistence(timeout: 3))
        for _ in 0..<3 where !app.staticTexts["saveComplete"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["saveComplete"].waitForExistence(timeout: 5))
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

    func testConsecutiveAddFilterDateAndEdit() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-data"]
        app.launch()
        XCTAssertTrue(app.buttons["addTask"].waitForExistence(timeout: 10))
        app.buttons["addTask"].tap()
        let field = app.textViews["taskText"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("第一件事")
        dismissKeyboardIntroduction(in: app)
        if app.buttons["dismissKeyboard"].isHittable { app.buttons["dismissKeyboard"].tap() }
        let keepAdding = app.switches["保存后继续添加"]
        for _ in 0..<4 where !keepAdding.isHittable || keepAdding.frame.maxY > app.frame.maxY - 40 { app.swipeUp() }
        XCTAssertTrue(keepAdding.isHittable, app.debugDescription)
        keepAdding.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(keepAdding.value as? String, "1")
        app.buttons["saveTask"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "")
        field.tap(); field.typeText("第二件事")
        dismissKeyboardIntroduction(in: app)
        if app.buttons["dismissKeyboard"].isHittable { app.buttons["dismissKeyboard"].tap() }
        for _ in 0..<4 where !keepAdding.isHittable || keepAdding.frame.maxY > app.frame.maxY - 40 { app.swipeUp() }
        XCTAssertTrue(keepAdding.isHittable, app.debugDescription)
        keepAdding.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(keepAdding.value as? String, "0")
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.buttons["edit-第一件事"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["edit-第二件事"].exists)
        app.buttons["工作"].tap()
        XCTAssertFalse(app.buttons["edit-第一件事"].exists)
        app.buttons["全部"].tap()
        XCTAssertTrue(app.buttons["edit-第一件事"].exists)
        app.buttons["后一天"].tap()
        XCTAssertFalse(app.buttons["edit-第一件事"].exists)
        app.buttons["前一天"].tap()
        XCTAssertTrue(app.buttons["edit-第一件事"].exists)
        app.buttons["edit-第一件事"].tap()
        XCTAssertTrue(app.navigationBars["编辑计划"].waitForExistence(timeout: 5))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.1)).tap()
        field.typeText("（修改）")
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.buttons["edit-第一件事（修改）"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
