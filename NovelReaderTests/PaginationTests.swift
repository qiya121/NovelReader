//
//  PaginationTests.swift
//  NovelReaderTests
//
//  PRD §9 + 补丁 S-05：字符偏移 ↔ 页码双向映射，含不变量与 emoji 场景
//

import XCTest
import UIKit
@testable import NovelReader

final class PaginationTests: XCTestCase {

    private func makeParams(fontSize: CGFloat = 17,
                            width: CGFloat = 320,
                            height: CGFloat = 400) -> TypesettingParams {
        TypesettingParams(fontSize: fontSize,
                          lineSpacingMultiplier: 1.6,
                          fontPostScriptName: nil,
                          textAreaSize: CGSize(width: width, height: height),
                          backgroundKey: "paper_white")
    }

    private func sampleText(paragraphs: Int = 300) -> String {
        String(repeating: "这是一段用于分页测试的正文内容，需要足够长才能产生多页。\n", count: paragraphs)
    }

    func testPageRangesAreContiguousAndComplete() {
        let text = sampleText()
        let paginated = Paginator.paginate(chapterIndex: 0,
                                           chapterText: text,
                                           inlineTitleLength: 0,
                                           params: makeParams(),
                                           textColor: .black)

        XCTAssertGreaterThan(paginated.pageCount, 1)
        XCTAssertEqual(paginated.pages.first?.charRange.location, 0)
        XCTAssertEqual(paginated.pages.last?.charRange.upperBound, (text as NSString).length)

        for index in 1..<paginated.pageCount {
            XCTAssertEqual(paginated.pages[index].charRange.location,
                           paginated.pages[index - 1].charRange.upperBound,
                           "第 \(index) 页与上一页之间存在缝隙或重叠")
        }
    }

    func testOffsetToPageAndBackIsConsistent() {
        let text = sampleText()
        let paginated = Paginator.paginate(chapterIndex: 0,
                                           chapterText: text,
                                           inlineTitleLength: 0,
                                           params: makeParams(),
                                           textColor: .black)

        for page in paginated.pages {
            let start = page.charRange.location
            let resolvedPage = paginated.pageIndex(forOffset: start)
            let resolvedOffset = paginated.offset(forPage: resolvedPage)
            XCTAssertEqual(resolvedPage, page.index)
            XCTAssertEqual(resolvedOffset, start)
        }
    }

    func testOffsetAtPageBoundaryBelongsToNextPage() {
        let text = sampleText()
        let paginated = Paginator.paginate(chapterIndex: 0,
                                           chapterText: text,
                                           inlineTitleLength: 0,
                                           params: makeParams(),
                                           textColor: .black)

        guard paginated.pageCount > 1 else { return XCTFail("样本应产生多页") }
        let boundary = paginated.pages[1].charRange.location
        XCTAssertEqual(paginated.pageIndex(forOffset: boundary), 1)
        XCTAssertEqual(paginated.pageIndex(forOffset: boundary - 1), 0)
    }

    func testEmojiDoNotShiftUTF16Offsets() {
        let text = "😀😀😀开篇\n" + String(repeating: "内容😀😀\n", count: 200)

        XCTAssertEqual(TextCleaner.utf16Length(of: text), (text as NSString).length)

        let paginated = Paginator.paginate(chapterIndex: 0,
                                           chapterText: text,
                                           inlineTitleLength: 0,
                                           params: makeParams(),
                                           textColor: .black)

        XCTAssertEqual(paginated.charCount, (text as NSString).length)
        XCTAssertEqual(paginated.pages.first?.charRange.location, 0)
        XCTAssertEqual(paginated.pages.last?.charRange.upperBound, (text as NSString).length)

        for page in paginated.pages {
            let roundTrip = paginated.offset(forPage: paginated.pageIndex(forOffset: page.charRange.location))
            XCTAssertEqual(roundTrip, page.charRange.location)
        }
    }

    func testInlineTitleChangesLayoutButKeepsOffsets() {
        let text = "第1章 标题行需要占去一部分高度\n" + sampleText(paragraphs: 60)
        let withTitle = Paginator.paginate(chapterIndex: 0,
                                           chapterText: text,
                                           inlineTitleLength: 18,
                                           params: makeParams(),
                                           textColor: .black)
        XCTAssertEqual(withTitle.pages.last?.charRange.upperBound, (text as NSString).length)
        XCTAssertEqual(withTitle.pages.first?.charRange.location, 0)
    }

    func testLargerFontProducesMorePages() {
        let text = sampleText(paragraphs: 100)
        let small = Paginator.paginate(chapterIndex: 0,
                                       chapterText: text,
                                       inlineTitleLength: 0,
                                       params: makeParams(fontSize: 17),
                                       textColor: .black)
        let large = Paginator.paginate(chapterIndex: 0,
                                       chapterText: text,
                                       inlineTitleLength: 0,
                                       params: makeParams(fontSize: 24),
                                       textColor: .black)
        XCTAssertGreaterThan(large.pageCount, small.pageCount)
    }

    func testEmptyChapterStillHasOnePage() {
        let paginated = Paginator.paginate(chapterIndex: 0,
                                           chapterText: "",
                                           inlineTitleLength: 0,
                                           params: makeParams(),
                                           textColor: .black)
        XCTAssertEqual(paginated.pageCount, 1)
        XCTAssertEqual(paginated.pageIndex(forOffset: 0), 0)
    }
}
