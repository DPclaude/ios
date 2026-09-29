import XCTest

@MainActor final class PlannerUITests: XCTestCase {
    func testGoalStagesCanBeCreatedCompletedAndReopened() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-data"]; app.launch()
        XCTAssertTrue(app.buttons["openGoals"].waitForExistence(timeout: 10))
        app.buttons["openGoals"].tap()
        app.buttons["addGoal"].tap()
        let title = app.textFields["goalTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("完成我的作品")
        app.textFields["stageTitle-0"].tap(); app.textFields["stageTitle-0"].typeText("完成初稿")
        dismissKeyboardIntroduction(in: app)
        if app.buttons["goalDismissKeyboard"].isHittable { app.buttons["goalDismissKeyboard"].tap() }
        app.buttons["saveGoal"].tap()
        XCTAssertTrue(app.buttons["goal-完成我的作品"].waitForExistence(timeout: 5))
        app.buttons["goal-完成我的作品"].tap()
        XCTAssertTrue(app.buttons["goalToggle-完成初稿"].waitForExistence(timeout: 5))
        app.buttons["goalToggle-完成初稿"].tap()
        XCTAssertTrue(app.staticTexts["已完成 1 / 1 阶段"].waitForExistence(timeout: 5))
        app.buttons["editGoal"].tap()
        app.buttons["addStage"].tap()
        let second = app.textFields["stageTitle-1"]
        for _ in 0..<3 where !second.isHittable { app.swipeUp() }
        XCTAssertTrue(second.waitForExistence(timeout: 5)); second.tap(); second.typeText("打磨并交付")
        if app.buttons["goalDismissKeyboard"].isHittable { app.buttons["goalDismissKeyboard"].tap() }
        app.buttons["saveGoal"].tap()
        XCTAssertTrue(app.staticTexts["已完成 1 / 2 阶段"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "长期目标与阶段"; shot.lifetime = .keepAlways; add(shot)
        app.terminate(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["openGoals"].waitForExistence(timeout: 10)); app.buttons["openGoals"].tap()
        app.buttons["goal-完成我的作品"].tap()
        XCTAssertTrue(app.staticTexts["已完成 1 / 2 阶段"].waitForExistence(timeout: 5))
    }
    func testWidgetAddRouteResetsWarmEditorAndDismissesSlice() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-data"]; app.launch()
        XCTAssertTrue(app.buttons["addTask"].waitForExistence(timeout: 10))
        app.buttons["后一天"].tap(); app.buttons["addTask"].tap()
        let field = app.textViews["taskText"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("旧日期草稿")
        dismissKeyboardIntroduction(in: app)
        app.open(URL(string: "planner://add")!)
        let empty = NSPredicate(format: "value == %@", "")
        expectation(for: empty, evaluatedWith: field); waitForExpectations(timeout: 5)
        field.tap(); field.typeText("从组件新增今天")
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.buttons["edit-从组件新增今天"].waitForExistence(timeout: 5))
        app.buttons["今天"].tap()
        XCTAssertTrue(app.buttons["edit-从组件新增今天"].exists)
        app.buttons["openSlice"].tap()
        XCTAssertTrue(app.buttons["closeSlice"].waitForExistence(timeout: 5))
        app.open(URL(string: "planner://add")!)
        XCTAssertTrue(app.textViews["taskText"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["closeSlice"].exists)
    }
    func testNativeDragReorderingPersists() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-data"]; app.launch()
        XCTAssertTrue(app.buttons["addTask"].waitForExistence(timeout: 10))
        for title in ["排序甲", "排序乙"] {
            app.buttons["addTask"].tap()
            let field = app.textViews["taskText"]
            XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(title)
            dismissKeyboardIntroduction(in: app); app.buttons["saveTask"].tap()
            XCTAssertTrue(app.buttons["edit-\(title)"].waitForExistence(timeout: 5))
        }
        app.buttons["reorderPlans"].tap()
        let first = app.cells.containing(.button, identifier: "edit-排序甲").firstMatch
        let second = app.cells.containing(.button, identifier: "edit-排序乙").firstMatch
        XCTAssertTrue(first.exists); XCTAssertTrue(second.exists)
        XCTAssertEqual(app.buttons["reorderPlans"].label, "完成排序")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Native reorder controls"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "排序把手"; before.lifetime = .keepAlways; add(before)
        let handles = second.buttons.matching(NSPredicate(format: "identifier != %@ AND identifier != %@", "edit-排序乙", "toggle-排序乙"))
        XCTAssertEqual(handles.count, 1, app.debugDescription)
        guard handles.count == 1 else { return }
        handles.element(boundBy: 0).press(forDuration: 1, thenDragTo: first, withVelocity: .slow, thenHoldForDuration: 1)
        app.buttons["reorderPlans"].tap()
        XCTAssertLessThan(app.buttons["edit-排序乙"].frame.minY, app.buttons["edit-排序甲"].frame.minY)
        app.terminate(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["edit-排序甲"].waitForExistence(timeout: 10))
        XCTAssertLessThan(app.buttons["edit-排序乙"].frame.minY, app.buttons["edit-排序甲"].frame.minY)
    }
    func testImportantFlagAndEarlierReminderPersistWithoutDefaultCategory() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-data"]
        app.launch()
        XCTAssertTrue(app.buttons["addTask"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["默认"].exists)
        app.buttons["addTask"].tap()
        let field = app.textViews["taskText"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("重要证件")
        dismissKeyboardIntroduction(in: app)
        if app.buttons["dismissKeyboard"].isHittable { app.buttons["dismissKeyboard"].tap() }
        let important = app.switches["importantToggle"]
        XCTAssertTrue(important.waitForExistence(timeout: 3))
        important.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(important.value as? String, "1")
        XCTAssertTrue(app.switches["reminderToggle"].isHittable)
        XCTAssertFalse(app.staticTexts["默认"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "新增计划-重要与提醒"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.buttons["edit-重要证件"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["edit-重要证件"].waitForExistence(timeout: 10))
        app.buttons["edit-重要证件"].tap()
        XCTAssertEqual(important.value as? String, "1")
    }
    func testPerPlanReminderPersistsInEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-data"]
        app.launch()
        XCTAssertTrue(app.buttons["addTask"].waitForExistence(timeout: 10))
        app.buttons["addTask"].tap()
        let field = app.textViews["taskText"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("提醒测试")
        dismissKeyboardIntroduction(in: app)
        if app.buttons["dismissKeyboard"].isHittable { app.buttons["dismissKeyboard"].tap() }
        let reminder = app.switches["reminderToggle"]
        for _ in 0..<4 where !reminder.isHittable { app.swipeUp() }
        XCTAssertTrue(reminder.waitForExistence(timeout: 3))
        guard reminder.exists else { return }
        reminder.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(reminder.value as? String, "1")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.buttons["edit-提醒测试"].waitForExistence(timeout: 5))
        app.buttons["edit-提醒测试"].tap()
        for _ in 0..<4 where !reminder.isHittable { app.swipeUp() }
        XCTAssertEqual(reminder.value as? String, "1")
    }
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
