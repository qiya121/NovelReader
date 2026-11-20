//
//  LibraryStore.swift
//  NovelReader
//
//  所有数据库读写都从这里走，Feature 层不直接写 SQL。
//

import Foundation
import GRDB

enum BookSort: String, CaseIterable, Identifiable {
    case recent        // 最近阅读
    case importedAt    // 导入时间
    case title         // 书名升序
    case favorites     // 仅看收藏

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recent:     return "最近阅读"
        case .importedAt: return "导入时间"
        case .title:      return "书名升序"
        case .favorites:  return "仅看收藏"
        }
    }
}

final class LibraryStore {

    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    var databaseReader: any DatabaseReader { database.reader }

    // MARK: - 书架查询

    func books(sort: BookSort, search: String = "") throws -> [Book] {
        try database.read { db in
            try Self.fetchBooks(db, sort: sort, search: search)
        }
    }

    /// 纯查询实现，放在静态方法里，便于在 ValueObservation / 单测中直接复用
    static func fetchBooks(_ db: Database, sort: BookSort, search: String = "") throws -> [Book] {
        let keyword = search.trimmingCharacters(in: .whitespacesAndNewlines)

        var sql = "SELECT * FROM books"
        var conditions: [String] = []

        if sort == .favorites {
            conditions.append("is_favorite = 1")
        }
        if !keyword.isEmpty {
            conditions.append("title LIKE :keyword")
        }
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }
        switch sort {
        case .recent, .favorites:
            sql += " ORDER BY updated_at DESC"
        case .importedAt:
            sql += " ORDER BY created_at DESC"
        case .title:
            sql += " ORDER BY title COLLATE NOCASE ASC"
        }

        let arguments: StatementArguments = keyword.isEmpty
            ? []
            : ["keyword": "%\(keyword)%"]

        return try Book.fetchAll(db, sql: sql, arguments: arguments)
    }

    func book(id: Int64) throws -> Book? {
        try database.read { db in
            try Book.fetchOne(db, key: id)
        }
    }

    func book(contentHash: String) throws -> Book? {
        guard !contentHash.isEmpty else { return nil }
        return try database.read { db in
            try Book.filter(Column("content_hash") == contentHash).fetchOne(db)
        }
    }

    func bookCount() throws -> Int {
        try database.read { db in try Book.fetchCount(db) }
    }

    // MARK: - 章节

    func chapters(bookID: Int64) throws -> [Chapter] {
        try database.read { db in
            try Chapter
                .filter(Column("book_id") == bookID)
                .order(Column("chapter_index"))
                .fetchAll(db)
        }
    }

    /// 书架一次取回所有书的章节数，避免每张卡片各查一次
    func chapterCountMap() throws -> [Int64: Int] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT book_id, COUNT(*) AS total FROM chapters GROUP BY book_id
                """)
            var result: [Int64: Int] = [:]
            for row in rows {
                let bookID: Int64 = row["book_id"]
                let total: Int = row["total"]
                result[bookID] = total
            }
            return result
        }
    }

    // MARK: - 书签

    func bookmarks(bookID: Int64) throws -> [Bookmark] {
        try database.read { db in
            try Bookmark
                .filter(Column("book_id") == bookID)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    /// 书签列表页（P6）：按书籍分组，书籍按最近更新排序
    func bookmarkGroups() throws -> [BookmarkGroup] {
        try database.read { db in
            let books = try Book
                .filter(sql: "id IN (SELECT DISTINCT book_id FROM bookmarks)")
                .order(Column("updated_at").desc)
                .fetchAll(db)

            return try books.map { book in
                let bookmarkList = try Bookmark
                    .filter(Column("book_id") == book.id)
                    .order(Column("created_at").desc)
                    .fetchAll(db)
                return BookmarkGroup(bookID: book.id ?? 0,
                                     bookTitle: book.title,
                                     book: book,
                                     bookmarks: bookmarkList)
            }
        }
    }

    func bookmark(bookID: Int64, charOffset: Int) throws -> Bookmark? {
        try database.read { db in
            try Bookmark
                .filter(Column("book_id") == bookID && Column("char_offset") == charOffset)
                .fetchOne(db)
        }
    }

    func bookmarkCount(bookID: Int64) throws -> Int {
        try database.read { db in
            try Bookmark.filter(Column("book_id") == bookID).fetchCount(db)
        }
    }

    // MARK: - 写入

    /// 导入落库：书 + 全部章节，单事务，失败整体回滚
    func insertBook(_ book: Book, chapters: [ParsedChapter]) throws -> Book {
        try database.write { db in
            var record = book
            try record.insert(db)

            guard let bookID = record.id else {
                throw ImportError.databaseWriteFailed
            }
            for chapter in chapters {
                var row = Chapter(bookID: bookID,
                                  index: chapter.index,
                                  title: chapter.title,
                                  startOffset: chapter.startOffset,
                                  endOffset: chapter.endOffset,
                                  charCount: chapter.charCount)
                try row.insert(db)
            }
            return record
        }
    }

    func updateBook(_ book: Book) throws {
        var record = book
        record.updatedAt = AppClock.now
        try database.write { db in
            try record.update(db)
        }
    }

    @discardableResult
    func setFavorite(bookID: Int64, isFavorite: Bool) throws -> Bool {
        try database.write { db in
            try db.execute(sql: """
                UPDATE books SET is_favorite = ?, updated_at = ? WHERE id = ?
                """,
                arguments: [isFavorite, AppClock.now, bookID])
            return isFavorite
        }
    }

    func rename(bookID: Int64, title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try database.write { db in
            try db.execute(sql: "UPDATE books SET title = ?, updated_at = ? WHERE id = ?",
                           arguments: [trimmed, AppClock.now, bookID])
        }
    }

    /// 删除书籍：DB 级联删除 chapters / bookmarks，再删沙盒文件
    func deleteBook(bookID: Int64) throws {
        let book = try self.book(id: bookID)
        try database.write { db in
            try db.execute(sql: "DELETE FROM books WHERE id = ?", arguments: [bookID])
        }
        if let storedPath = book?.storedPath, !storedPath.isEmpty {
            let url = AppPaths.absoluteURL(forStoredPath: storedPath)
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 保存阅读进度（PRD §5.5：翻页后 500ms 内写入）
    func saveProgress(bookID: Int64, chapterIndex: Int, charOffset: Int, percent: Double) throws {
        let clampedPercent = min(max(percent, 0), 1)
        try database.write { db in
            try db.execute(sql: """
                UPDATE books
                SET last_chapter_index = ?, last_char_offset = ?, last_percent = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [chapterIndex, charOffset, clampedPercent, AppClock.now, bookID])
        }
    }

    /// 重新解析章节：替换全部章节，并按字符偏移把进度映射回最近章节
    func replaceChapters(bookID: Int64,
                         mode: ChapterMode,
                         parseResult: ChapterParseResult,
                         charCount: Int) throws -> Int {

        try database.write { db in
            guard let book = try Book.fetchOne(db, key: bookID) else {
                throw ImportError.databaseWriteFailed
            }
            let offset = book.lastCharOffset

            try db.execute(sql: "DELETE FROM chapters WHERE book_id = ?", arguments: [bookID])
            for chapter in parseResult.chapters {
                var row = Chapter(bookID: bookID,
                                  index: chapter.index,
                                  title: chapter.title,
                                  startOffset: chapter.startOffset,
                                  endOffset: chapter.endOffset,
                                  charCount: chapter.charCount)
                try row.insert(db)
            }

            // 偏移落在被删除区间 → 映射到「起点 ≥ 上次值」的最近章节
            let mappedIndex = Self.chapterIndex(forOffset: offset, in: parseResult.chapters)
            let percent = charCount > 0 ? min(1, Double(offset) / Double(charCount)) : 0

            try db.execute(sql: """
                UPDATE books
                SET chapter_mode = ?, last_chapter_index = ?, last_percent = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [mode.rawValue, mappedIndex, percent, AppClock.now, bookID])

            return mappedIndex
        }
    }

    static func chapterIndex(forOffset offset: Int, in chapters: [ParsedChapter]) -> Int {
        guard !chapters.isEmpty else { return 0 }
        for chapter in chapters where offset < chapter.endOffset {
            return chapter.index
        }
        return chapters.last?.index ?? 0
    }

    // MARK: - 书签写入

    /// 添加书签，重复锚点直接返回已有记录（幂等）
    func addBookmark(bookID: Int64,
                     chapterIndex: Int,
                     charOffset: Int,
                     chapterTitle: String,
                     excerpt: String) throws -> Bookmark {

        if let existing = try bookmark(bookID: bookID, charOffset: charOffset) {
            return existing
        }
        let count = try bookmarkCount(bookID: bookID)
        guard count < Bookmark.maxCountPerBook else {
            throw ImportError.bookmarkLimitReached
        }

        var record = Bookmark(id: nil,
                              bookID: bookID,
                              chapterIndex: chapterIndex,
                              charOffset: charOffset,
                              excerpt: excerpt,
                              chapterTitle: chapterTitle,
                              createdAt: AppClock.now)
        try database.write { db in
            try record.insert(db)
        }
        return record
    }

    func removeBookmark(bookID: Int64, charOffset: Int) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM bookmarks WHERE book_id = ? AND char_offset = ?",
                           arguments: [bookID, charOffset])
        }
    }

    func deleteBookmark(id: Int64) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM bookmarks WHERE id = ?", arguments: [id])
        }
    }

    func removeAllBookmarks(bookID: Int64) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM bookmarks WHERE book_id = ?", arguments: [bookID])
        }
    }
}
