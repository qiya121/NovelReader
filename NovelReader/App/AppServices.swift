//
//  AppServices.swift
//  NovelReader
//
//  全 App 唯一的依赖容器。V1 不需要 DI 框架，一个 singleton 足够。
//

import Foundation

final class AppServices {

    static let shared = AppServices()

    let database: AppDatabase
    let preferences: ReadingPreferences
    let store: LibraryStore
    let importer: BookImporter
    let pagination: PaginationService

    private init() {
        let database: AppDatabase
        do {
            database = try AppDatabase.makeShared()
        } catch {
            // 迁移失败属于不可恢复错误：数据目录损坏或磁盘不可写
            fatalError("数据库初始化失败：\(error)")
        }
        self.database = database
        self.preferences = ReadingPreferences()
        self.store = LibraryStore(database: database)
        self.importer = BookImporter(store: store)
        self.pagination = PaginationService()

        // 亮度只走遮罩，绝不动系统亮度
        preferences.onBrightnessChanged = { level in
            BrightnessOverlay.shared.setLevel(level)
        }

        #if DEBUG
        // UI 测试种子（Release 下整段不编译）
        UITestSeeder.seedIfNeeded(store: store, importer: importer)
        #endif
    }
}
