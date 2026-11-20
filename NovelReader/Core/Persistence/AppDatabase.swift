//
//  AppDatabase.swift
//  NovelReader
//
//  GRDB 数据库入口。全 App 只有这一个 `DatabaseWriter`。
//
//  约束（PRD §4 / 补丁 S-02）：
//  - 数据库文件固定在 `Application Support/novelreader.db`，不做多实例；
//  - `PRAGMA foreign_keys` 必须为 ON，否则 `ON DELETE CASCADE` 静默失效。
//

import Foundation
import GRDB

final class AppDatabase {

    let writer: any DatabaseWriter

    var reader: any DatabaseReader { writer }

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    // MARK: - 工厂

    /// 生产环境：落在 Application Support
    static func makeShared() throws -> AppDatabase {
        let fileManager = FileManager.default
        let support = AppPaths.applicationSupport
        if !fileManager.fileExists(atPath: support.path) {
            try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        }

        var configuration = Configuration()
        // 补丁 S-02：级联删除依赖此项，禁止改为 false
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(2)

        let queue = try DatabaseQueue(path: AppPaths.databaseURL.path, configuration: configuration)
        return try AppDatabase(queue)
    }

    /// 单测用：纯内存库，每个用例一份，互不污染
    static func inMemory() throws -> AppDatabase {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: configuration)
        return try AppDatabase(queue)
    }

    // MARK: - 便捷读写

    func write<T>(_ block: @escaping (Database) throws -> T) throws -> T {
        try writer.write(block)
    }

    func read<T>(_ block: (Database) throws -> T) throws -> T {
        try reader.read(block)
    }
}
