//
//  LibraryStoreTests.swift
//  NovelReaderTests
//
//  PRD §9：书签去重；§4：级联删除；补丁 R-02：按 content_hash 去重
//

import XCTest
import GRDB
@testable import NovelReader

final class LibraryStoreTests: XCTestCase {

    private func makeStore() throws -> LibraryStore {
        let database = try AppDatabase.inMemory()
        return LibraryStore(database: database)
    }

    private func makeBook(hash: String = "hash-1",
                          charCount: Int = 300,
                          mode: ChapterMode = .strict) -> Book {
        Book(id: nil,
             title: "测试书",
             author: nil,
             fileName: "1_测试书.txt",
             storedPath: "",
             encoding: "utf8",
             charCount: charCount,
             chapterMode: mode,
             isFavorite: false,
             lastChapterIndex: 0,
             lastCharOffset: 0,
             lastPercent: 0,
             contentHash: hash,
             coverSeed: 3,
             settingsOverride: nil,
             createdAt: AppClock.now,
             updatedAt: AppClock.now)
    }

    private func chapters(count: Int = 3, charCount: Int = 300) -> [ParsedChapter] {
        let size = charCount / count
        return (0..<count).map { index in
            ParsedChapter(index: index,
                          title: "第\(index + 1)章",
                          startOffset: index * size,
                          endOffset: index == count - 1 ? charCount : (index + 1) * size)
        }
    }

    // MARK: - 书签去重

    func testDuplicateBookmarkIsRejected() throws {
        let store = try makeStore()
        let book = try store.insertBook(makeBook(), chapters: chapters())
        let bookID = try XCTUnwrap(book.id)

        _ = try store.addBookmark(bookID: bookID,
                                  chapterIndex: 0,
                                  charOffset: 10,
                                  chapterTitle: "第1章",
                                  excerpt: "摘录")
        _ = try store.addBookmark(bookID: bookID,
                                  chapterIndex: 0,
                                  charOffset: 10,
                                  chapterTitle: "第1章",
                                  excerpt: "摘录")

        XCTAssertEqual(try store.bookmarks(bookID: bookID).count, 1)
    }

    func testRemoveBookmarkByAnchor() throws {
        let store = try makeStore()
        let book = try store.insertBook(makeBook(), chapters: chapters())
        let bookID = try XCTUnwrap(book.id)

        _ = try store.addBookmark(bookID: bookID,
                                  chapterIndex: 0,
                                  charOffset: 20,
                                  chapterTitle: "第1章",
                                  excerpt: "摘录")
        try store.removeBookmark(bookID: bookID, charOffset: 20)

        XCTAssertTrue(try store.bookmarks(bookID: bookID).isEmpty)
        XCTAssertNil(try store.bookmark(bookID: bookID, charOffset: 20))
    }

    // MARK: - 级联删除

    func testCascadeDeleteRemovesChaptersAndBookmarks() throws {
        let store = try makeStore()
        let book = try store.insertBook(makeBook(), chapters: chapters())
        let bookID = try XCTUnwrap(book.id)

        _ = try store.addBookmark(bookID: bookID,
                                  chapterIndex: 0,
                                  charOffset: 30,
                                  chapterTitle: "第1章",
                                  excerpt: "摘录")

        try store.deleteBook(bookID: bookID)

        XCTAssertTrue(try store.chapters(bookID: bookID).isEmpty)
        XCTAssertEqual(try store.bookmarkCount(bookID: bookID), 0)
        XCTAssertNil(try store.book(bookID: bookID))
    }

    // MARK: - 去重哈希

    func testFindBookByContentHash() throws {
        let store = try makeStore()
        _ = try store.insertBook(makeBook(hash: "abc123"), chapters: chapters())

        XCTAssertNotNil(try store.book(contentHash: "abc123"))
        XCTAssertNil(try store.book(contentHash: "not-exist"))
        XCTAssertNil(try store.book(contentHash: ""))
    }

    // MARK: - 进度

    func testSaveProgressUpdatesPercent() throws {
        let store = try makeStore()
        let book = try store.insertBook(makeBook(charCount: 1000), chapters: chapters())
        let bookID = try XCTUnwrap(book.id)

        try store.saveProgress(bookID: bookID, chapterIndex: 2, charOffset: 500, percent: 0.5)

        let updated = try XCTUnwrap(try store.book(bookID: bookID))
        XCTAssertEqual(updated.lastCharOffset, 500)
        XCTAssertEqual(updated.lastChapterIndex, 2)
        XCTAssertEqual(updated.lastPercent, 0.5, accuracy: 0.0001)
    }

    // MARK: - 重新解析后偏移映射

    func testChapterIndexMappingFindsContainingChapter() {
        let list = [
            ParsedChapter(index: 0, title: "一", startOffset: 0, endOffset: 100),
            ParsedChapter(index: 1, title: "二", startOffset: 100, endOffset: 200)
        ]
        XCTAssertEqual(LibraryStore.chapterIndex(forOffset: 0, in: list), 0)
        XCTAssertEqual(LibraryStore.chapterIndex(forOffset: 99, in: list), 0)
        XCTAssertEqual(LibraryStore.chapterIndex(forOffset: 100, in: list), 1)
        XCTAssertEqual(LibraryStore.chapterIndex(forOffset: 999, in: list), 1)
    }

    // MARK: - 书签上限

    func testBookmarkLimitIsEnforced() throws {
        let store = try makeStore()
        let book = try store.insertBook(makeBook(), chapters: chapters())
        let bookID = try XCTUnwrap(book.id)

        for offset in 0..<Bookmark.maxCountPerBook {
            _ = try store.addBookmark(bookID: bookID,
                                      chapterIndex: 0,
                                      charOffset: offset,
                                      chapterTitle: "第1章",
                                      excerpt: "摘录")
        }
        XCTAssertThrowsError(try store.addBookmark(bookID: bookID,
                                                   chapterIndex: 0,
                                                   charOffset: 99_999,
                                                   chapterTitle: "第1章",
                                                   excerpt: "摘录"))
    }
}
