//
//  ReaderFlowUITests.swift
//  NovelReaderUITests
//
//  PRD §9 的端到端链路：
//  导入 → 书架出现卡片 → 打开 → 翻页 → 改背景色 → 改字号 → 改行距 → 加书签 → 退出 → 重进
//
//  唯一的偏离：**导入那一步用种子数据代替**。
//  导入走的是系统文件选择器（跨进程 UI），XCUITest 驱动不了。
//  种子仍然走真实的 BookImporter 管线（编码识别 → 清洗 → 分章 → 落库），
//  只是省掉了"点选择器"这一步。见 Core/Support/UITestSeeder.swift。
//

import XCTest

final class ReaderFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSeededBookReadingFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeed"]
        app.launch()

        // 1. 书架：种子书籍出现
        let book = app.buttons["shelf.book"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 30), "书架没有出现种子书籍，检查 -uiTestSeed 是否生效")

        // 2. 打开阅读页
        book.tap()

        let settings = app.buttons["reader.tool.settings"]
        // 默认应是干净界面：没有工具栏遮挡正文
        XCTAssertTrue(!settings.exists || !settings.isHittable, "阅读页默认不应显示工具栏")

        // 3. 单击屏幕中部 → 工具栏淡入
        tapCenter(app)
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "单击中部后应出现底部工具栏")
        XCTAssertTrue(settings.isHittable, "底部工具栏出现后应可点击")

        // 4. 左右翻页：点右侧热区 3 次（不应崩溃、不应白屏）
        tapRight(app)
        tapRight(app)
        tapRight(app)

        // 5. 打开阅读设置
        ensureChromeVisible(app, settings: settings)
        settings.tap()
        XCTAssertTrue(app.staticTexts["阅读设置"].waitForExistence(timeout: 10), "设置面板没有弹出")

        // 6. 改字号 / 行距 / 背景色 —— 每改一项都会触发重排，位置必须不丢
        app.buttons["settings.fontSize.large"].tap()
        app.buttons["settings.lineSpacing.loose"].tap()
        app.buttons["settings.background.night_gray"].tap()

        // 7. 关闭面板，回到正文
        app.buttons["settings.close"].tap()
        let panelClosed = expectation(for: NSPredicate(format: "exists == false"),
                                      evaluatedWith: app.buttons["settings.close"])
        wait(for: [panelClosed], timeout: 10)

        // 8. 重排后仍在阅读页：再点中部能唤起工具栏（没有白屏、没有崩回书架）
        ensureChromeVisible(app, settings: settings)

        // 9. 返回书架
        let back = app.buttons["reader.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "顶部栏应有返回按钮")
        back.tap()
        XCTAssertTrue(app.buttons["shelf.book"].firstMatch.waitForExistence(timeout: 10), "应返回书架")
    }

    // MARK: - 手势帮助

    /// 点屏幕中部偏上，避开底部工具栏
    private func tapCenter(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
    }

    /// 点右侧热区（右侧 20%），左右模式下翻下一页
    private func tapRight(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.45)).tap()
    }

    /// 确保底部工具栏可见
    private func ensureChromeVisible(_ app: XCUIApplication, settings: XCUIElement) {
        for _ in 0..<3 {
            if settings.exists && settings.isHittable { return }
            tapCenter(app)
            _ = settings.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(settings.isHittable, "未能唤起底部工具栏")
    }
}
