//
//  UITestSeeder.swift
//  NovelReader
//
//  UI 测试用的种子数据。**只在 Debug 构建里存在**，Release 整段不参与编译。
//
//  为什么需要它：导入入口是系统文件选择器（跨进程 UI），XCUITest 驱动不了。
//  这里用启动参数 `-uiTestSeed` 触发，走的仍是真实的 BookImporter 管线，
//  因此顺带把「编码识别 → 清洗 → 分章 → 落库」也验了一遍。
//

#if DEBUG

import Foundation

enum UITestSeeder {

    static let launchArgument = "-uiTestSeed"

    static func seedIfNeeded(store: LibraryStore, importer: BookImporter) {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }
        // 幂等：书架已有书就不再种
        guard ((try? store.bookCount()) ?? 0) == 0 else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("UI测试样本.txt")
        guard let data = sampleText().data(using: .utf8) else { return }

        do {
            try data.write(to: url, options: .atomic)
            _ = try importer.importSingle(url: url,
                                          mode: .loose,
                                          isCancelled: { false },
                                          progress: { _ in })
            try? FileManager.default.removeItem(at: url)
        } catch {
            NSLog("[UITestSeeder] 种子导入失败：\(error)")
        }
    }

    private static func sampleText() -> String {
        var result = "《UI 测试样本》\n\n"
        for chapter in 1...6 {
            result += "第\(chapter)章 测试章节\(chapter)\n"
            for paragraph in 1...8 {
                result += "这是第\(chapter)章的第\(paragraph)段正文，用来验证分页、翻页与阅读位置恢复是否正常。"
                result += String(repeating: "正文内容", count: 12)
                result += "\n"
            }
            result += "\n"
        }
        return result
    }
}

#endif
