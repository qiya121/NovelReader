//
//  TextCleanerTests.swift
//  NovelReaderTests
//
//  PRD §5.1-4：清洗规则顺序固定，且禁止删除正文内容
//

import XCTest
@testable import NovelReader

final class TextCleanerTests: XCTestCase {

    func testNormalizesCRLF() {
        XCTAssertEqual(TextCleaner.clean("第一行\r\n第二行"), "第一行\n第二行")
    }

    func testNormalizesCROnly() {
        XCTAssertEqual(TextCleaner.clean("第一行\r第二行"), "第一行\n第二行")
    }

    func testRemovesBOMAndZeroWidthCharacters() {
        let raw = "\u{FEFF}正\u{200B}文\u{200F}内容"
        XCTAssertEqual(TextCleaner.clean(raw), "正文内容")
    }

    func testTrimsTrailingSpacesOnEveryLine() {
        let raw = "第一行   \n第二行\u{3000}\u{3000}\n第三行"
        XCTAssertEqual(TextCleaner.clean(raw), "第一行\n第二行\n第三行")
    }

    func testCompressesMoreThanTwoBlankLines() {
        let raw = "第一段\n\n\n\n第二段"
        XCTAssertEqual(TextCleaner.clean(raw), "第一段\n\n第二段")
    }

    func testKeepsSingleBlankLine() {
        let raw = "第一段\n\n第二段"
        XCTAssertEqual(TextCleaner.clean(raw), raw)
    }

    func testConvertsTabsToFourSpaces() {
        XCTAssertEqual(TextCleaner.clean("标题\t正文"), "标题    正文")
    }

    func testDoesNotDeleteContent() {
        let raw = "他说：“第一章很好看。”\n她笑了笑。"
        XCTAssertEqual(TextCleaner.clean(raw), raw)
    }

    func testUTF16LengthMatchesNSString() {
        let text = "正文😀内容"
        XCTAssertEqual(TextCleaner.utf16Length(of: text), (text as NSString).length)
        // 一个 emoji 占两个 UTF-16 单元
        XCTAssertEqual(TextCleaner.utf16Length(of: text), 6)
    }

    func testCleaningIsDeterministic() {
        let raw = "甲\r\n\r\n\r\n\r\n乙\t丙   \n"
        let first = TextCleaner.clean(raw)
        let second = TextCleaner.clean(raw)
        XCTAssertEqual(first, second)
    }
}
