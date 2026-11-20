//
//  Migrations.swift
//  NovelReader
//
//  迁移文件按 v1_initial、v2_... 顺序命名。
//  【禁止修改已发布迁移】——只能追加新的 registerMigration。
//

import Foundation
import GRDB

extension AppDatabase {

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in

            // MARK: books
            try db.create(table: "books") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("author", .text)
                t.column("file_name", .text).notNull()
                t.column("stored_path", .text).notNull()
                t.column("encoding", .text).notNull()
                t.column("char_count", .integer).notNull().defaults(to: 0)
                t.column("chapter_mode", .text).notNull()
                t.column("is_favorite", .boolean).notNull().defaults(to: false)
                t.column("last_chapter_index", .integer).notNull().defaults(to: 0)
                t.column("last_char_offset", .integer).notNull().defaults(to: 0)
                t.column("last_percent", .double).notNull().defaults(to: 0)
                // 补丁 R-02：去重哈希，输入为「清洗后文本」的 SHA-256
                t.column("content_hash", .text).notNull().defaults(to: "")
                // 补丁 R-06：封面底色索引 0..7
                t.column("cover_seed", .integer).notNull().defaults(to: 0)
                // 单书设置覆盖，NULL = 跟随全局（V1 不写入）
                t.column("settings_override", .text)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(index: "idx_books_is_favorite", on: "books", columns: ["is_favorite"])
            try db.create(index: "idx_books_updated_at", on: "books", columns: ["updated_at"])
            // 补丁 R-02：普通索引，不加唯一约束（删除后重导必须允许）
            try db.create(index: "idx_books_content_hash", on: "books", columns: ["content_hash"])

            // MARK: chapters
            try db.create(table: "chapters") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("book_id", .integer)
                    .notNull()
                    .references("books", onDelete: .cascade)
                // 补丁 S-01：列名用 chapter_index，避免 SQL 保留字 index
                t.column("chapter_index", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("start_offset", .integer).notNull()
                t.column("end_offset", .integer).notNull()
                t.column("char_count", .integer).notNull()
            }
            try db.create(index: "idx_chapters_book_index",
                          on: "chapters",
                          columns: ["book_id", "chapter_index"],
                          unique: true)

            // MARK: bookmarks
            try db.create(table: "bookmarks") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("book_id", .integer)
                    .notNull()
                    .references("books", onDelete: .cascade)
                t.column("chapter_index", .integer).notNull()
                t.column("char_offset", .integer).notNull()
                t.column("excerpt", .text).notNull()
                t.column("chapter_title", .text).notNull()
                t.column("created_at", .text).notNull()
            }
            // 同一 book_id + char_offset 只允许一条（PRD §4.3）
            try db.create(index: "idx_bookmarks_unique_anchor",
                          on: "bookmarks",
                          columns: ["book_id", "char_offset"],
                          unique: true)
            try db.create(index: "idx_bookmarks_book_created",
                          on: "bookmarks",
                          columns: ["book_id", "created_at"])
        }

        return migrator
    }
}
