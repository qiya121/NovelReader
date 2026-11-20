//
//  ChapterParserTests.swift
//  NovelReaderTests
//
//  PRD §5.2 + 补丁 R-03：三种模式 + 5 条防误判
//

import XCTest
@testable import NovelReader

final class ChapterParserTests: XCTestCase {

    private let bookTitle = "测试书"

    private func body(_ length: Int) -> String {
        String(repeating: "正", count: length)
    }

    // MARK: - 严格模式

    func testStrictFindsArabicChapters() {
        let text = """
        第1章 开始
        \(body(200))
        第2章 继续
        \(body(200))
        第3章 结束
        \(body(200))
        """
        let result = ChapterParser.parse(text: text, mode: .strict, bookTitle: bookTitle)

        XCTAssertEqual(result.effectiveMode, .strict)
        XCTAssertFalse(result.didDegrade)
        XCTAssertEqual(result.chapters.count, 3)
        XCTAssertEqual(result.chapters[0].title, "第1章 开始")
        XCTAssertEqual(result.chapters[0].startOffset, 0)
    }

    func testStrictIgnoresChineseNumerals() {
        let text = """
        第一章 开始
        \(body(300))
        """
        let result = ChapterParser.parse(text: text, mode: .strict, bookTitle: bookTitle)

        XCTAssertTrue(result.didDegrade)
        XCTAssertEqual(result.effectiveMode, .none)
        XCTAssertEqual(result.chapters.count, 1)
        XCTAssertEqual(result.chapters[0].title, bookTitle)
        XCTAssertNotNil(result.notice)
    }

    func testStrictIgnoresOtherQuantifiers() {
        let text = """
        第1节 开始
        \(body(300))
        第2节 继续
        \(body(300))
        """
        let result = ChapterParser.parse(text: text, mode: .strict, bookTitle: bookTitle)

        XCTAssertTrue(result.didDegrade)
        XCTAssertEqual(result.chapters.count, 1)
    }

    // MARK: - 宽松模式

    func testLooseAcceptsChineseNumeral() {
        let text = """
        第一章 起风
        \(body(300))
        第二章 落雨
        \(body(300))
        """
        let result = ChapterParser.parse(text: text, mode: .loose, bookTitle: bookTitle)

        XCTAssertEqual(result.effectiveMode, .loose)
        XCTAssertEqual(result.chapters.count, 2)
        XCTAssertEqual(result.chapters[1].title, "第二章 落雨")
    }

    func testLooseAcceptsEnglishChapter() {
        let text = """
        Chapter 1
        \(body(300))
        Chapter 2
        \(body(300))
        """
        let result = ChapterParser.parse(text: text, mode: .loose, bookTitle: bookTitle)

        XCTAssertEqual(result.chapters.count, 2)
    }

    func testLooseAcceptsKeywordLines() {
        let text = """
        楔子
        \(body(300))
        第一章 正文
        \(body(300))
        番外 之后
        \(body(300))
        """
        let result = ChapterParser.parse(text: text, mode: .loose, bookTitle: bookTitle)

        XCTAssertEqual(result.chapters.count, 3)
        XCTAssertEqual(result.chapters[0].title, "楔子")
        XCTAssertEqual(result.chapters[2].title, "番外 之后")
    }

    // MARK: - 防误判

    func testLooseRejectsInlineChapterMention() {
        let text = """
        他说：第一章很好看。
        \(body(300))
        她笑了笑，没有接话。
        \(body(300))
        """
        let result = ChapterParser.parse(text: text, mode: .loose, bookTitle: bookTitle)

        XCTAssertEqual(result.chapters.count, 1)
        XCTAssertEqual(result.chapters[0].title, bookTitle)
    }

    func testLooseDropsDenseMatches() {
        let text = """
        第1章 甲
        \(body(50))
        第2章 乙
        \(body(300))
        """
        let result = ChapterParser.parse(text: text, mode: .loose, bookTitle: bookTitle)

        // 两章间距 50 < 100，后一个被丢弃
        XCTAssertEqual(result.chapters.count, 1)
        XCTAssertEqual(result.chapters[0].title, "第1章 甲")
    }

    func testLooseCollapsesCrowdedChapterLines() {
        // 每 30 字就出现一行"1.标题"：不是真章节，而是被切碎的正文。
        // 间距 < 100 的候选全部被丢弃，最终只保留第一个。
        var text = ""
        for index in 0..<40 {
            text += "\(index + 1).短标题\n"
            text += body(20) + "\n"
        }
        let result = ChapterParser.parse(text: text, mode: .loose, bookTitle: bookTitle)

        XCTAssertEqual(result.chapters.count, 1)
    }

    func testLooseKeepsManyChaptersWithoutDegrading() {
        var text = ""
        for index in 0..<2100 {
            text += "第\(index + 1)章 标题\n"
            text += body(120) + "\n"
        }
        let result = ChapterParser.parse(text: text, mode: .loose, bookTitle: bookTitle)

        // 补丁 R-03：章数超 2000 但平均长度正常 → 保留结果，只给软提示
        XCTAssertFalse(result.didDegrade)
        XCTAssertEqual(result.chapters.count, 2100)
        XCTAssertNotNil(result.notice)
    }

    // MARK: - 不区分模式

    func testNoneModeReturnsWholeBookAsOneChapter() {
        let text = "没有任何章节标记的正文。\n" + body(500)
        let result = ChapterParser.parse(text: text, mode: .none, bookTitle: bookTitle)

        XCTAssertEqual(result.effectiveMode, .none)
        XCTAssertEqual(result.chapters.count, 1)
        XCTAssertEqual(result.chapters[0].title, bookTitle)
        XCTAssertEqual(result.chapters[0].startOffset, 0)
        XCTAssertEqual(result.chapters[0].endOffset, (text as NSString).length)
    }

    // MARK: - 前言行

    func testPreambleChapterInsertedWhenLong() {
        let text = body(600) + "\n第1章 正式开始\n" + body(300)
        let result = ChapterParser.parse(text: text, mode: .loose, bookTitle: bookTitle)

        XCTAssertEqual(result.chapters.count, 2)
        XCTAssertEqual(result.chapters[0].title, ChapterParser.preambleTitle)
        XCTAssertEqual(result.chapters[0].startOffset, 0)
        XCTAssertEqual(result.chapters[1].title, "第1章 正式开始")
    }

    func testFirstChapterStartsAtZeroWhenPreambleIsShort() {
        let text = "短前言\n第1章 开始\n" + body(300)
        let result = ChapterParser.parse(text: text, mode: .loose, bookTitle: bookTitle)

        XCTAssertEqual(result.chapters.count, 1)
        XCTAssertEqual(result.chapters[0].startOffset, 0)
    }

    // MARK: - 区间完整性

    func testChapterRangesAreContiguousAndComplete() {
        let text = """
        第1章 一
        \(body(300))
        第2章 二
        \(body(300))
        第3章 三
        \(body(300))
        """
        let result = ChapterParser.parse(text: text, mode: .loose, bookTitle: bookTitle)
        let total = (text as NSString).length

        XCTAssertEqual(result.chapters.first?.startOffset, 0)
        XCTAssertEqual(result.chapters.last?.endOffset, total)
        for index in 1..<result.chapters.count {
            XCTAssertEqual(result.chapters[index].startOffset, result.chapters[index - 1].endOffset)
        }
    }
}
