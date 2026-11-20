//
//  Paginator.swift
//  NovelReader
//
//  分页引擎（PRD §6 + 补丁 R-04）
//
//  实现口径（必须遵守，见补丁 R-04）：
//    按页顺序追加 NSTextContainer → ensureLayout(for:) → glyphRange(for: container)
//    → characterRange(forGlyphRange:) 得到每页字符区间。
//  禁止"估算每页字数 + 二分查找"或"按固定字数切片"。
//
//  分页结果保留 NSLayoutManager 与各 NSTextContainer，
//  渲染时直接按容器绘制 glyph，**不重新排版子串**——
//  否则页首的半段文字会被当成新段落，重新套用首行缩进，导致页码与正文错位。
//

import UIKit

// MARK: - 单页

struct PageSlice: Equatable {
    let index: Int
    /// 相对章节文本起点的字符区间（UTF-16）
    let charRange: NSRange
    let glyphRange: NSRange
}

// MARK: - 已分页的章节

final class PaginatedChapter {

    let chapterIndex: Int
    /// 章节正文（不含标题以外的任何加工）
    let text: String
    let attributedText: NSAttributedString
    let textStorage: NSTextStorage
    let layoutManager: NSLayoutManager
    let containers: [NSTextContainer]
    let pages: [PageSlice]
    let paramsFingerprint: String
    let charCount: Int

    init(chapterIndex: Int,
         text: String,
         attributedText: NSAttributedString,
         textStorage: NSTextStorage,
         layoutManager: NSLayoutManager,
         containers: [NSTextContainer],
         pages: [PageSlice],
         paramsFingerprint: String) {
        self.chapterIndex = chapterIndex
        self.text = text
        self.attributedText = attributedText
        self.textStorage = textStorage
        self.layoutManager = layoutManager
        self.containers = containers
        self.pages = pages
        self.paramsFingerprint = paramsFingerprint
        self.charCount = (text as NSString).length
    }

    var pageCount: Int { pages.count }
    var lastPageIndex: Int { max(0, pages.count - 1) }

    /// 章内偏移 → 页码
    func pageIndex(forOffset offset: Int) -> Int {
        guard !pages.isEmpty else { return 0 }
        let clamped = min(max(offset, 0), charCount)
        for page in pages where clamped < NSMaxRange(page.charRange) {
            return page.index
        }
        return pages.count - 1
    }

    /// 页码 → 章内起始偏移
    func offset(forPage index: Int) -> Int {
        guard !pages.isEmpty else { return 0 }
        let clamped = min(max(index, 0), pages.count - 1)
        return pages[clamped].charRange.location
    }

    func page(at index: Int) -> PageSlice? {
        guard pages.indices.contains(index) else { return nil }
        return pages[index]
    }

    /// 该页在全文中的起始偏移（调用方加章节 startOffset）
    func globalOffset(forPage index: Int, chapterStart: Int) -> Int {
        chapterStart + offset(forPage: index)
    }
}

// MARK: - 引擎

enum Paginator {

    /// 安全上限：一页至少 1 个字符，正常章节不会接近这个数字
    private static let maxPageGuard = 20_000

    /// 对单章正文分页
    /// - Parameters:
    ///   - chapterText: 章节文本（从章节 startOffset 到 endOffset 的子串）
    ///   - inlineTitleLength: 首行标题（含换行）的 UTF-16 长度，0 表示本章没有标题行
    static func paginate(chapterIndex: Int,
                         chapterText: String,
                         inlineTitleLength: Int,
                         params: TypesettingParams,
                         textColor: UIColor) -> PaginatedChapter {

        let attributed = TextStyler.attributedString(chapterText,
                                                     params: params,
                                                     color: textColor,
                                                     inlineTitleLength: inlineTitleLength)
        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        let width = max(1, params.textAreaSize.width)
        let height = max(1, params.textAreaSize.height)

        var containers: [NSTextContainer] = []
        var pages: [PageSlice] = []
        var guardCounter = 0

        while guardCounter < maxPageGuard {
            let container = NSTextContainer(size: CGSize(width: width, height: height))
            container.lineFragmentPadding = 0
            container.maximumNumberOfLines = 0
            container.widthTracksTextView = false
            container.heightTracksTextView = false

            layoutManager.addTextContainer(container)
            layoutManager.ensureLayout(for: container)

            let glyphRange = layoutManager.glyphRange(for: container)
            if glyphRange.length == 0 {
                // 文本已排完（或空章节），不再追加空容器
                layoutManager.removeTextContainer(at: containers.count)
                break
            }

            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange,
                                                        actualGlyphRange: nil)
            containers.append(container)
            pages.append(PageSlice(index: pages.count,
                                   charRange: charRange,
                                   glyphRange: glyphRange))

            if NSMaxRange(glyphRange) >= layoutManager.numberOfGlyphs { break }
            guardCounter += 1
        }

        if pages.isEmpty {
            // 空章节兜底：保证至少一页，且页码映射不崩
            let container = NSTextContainer(size: CGSize(width: width, height: height))
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            containers.append(container)
            pages.append(PageSlice(index: 0,
                                   charRange: NSRange(location: 0, length: 0),
                                   glyphRange: NSRange(location: 0, length: 0)))
        }

        return PaginatedChapter(chapterIndex: chapterIndex,
                                text: chapterText,
                                attributedText: attributed,
                                textStorage: storage,
                                layoutManager: layoutManager,
                                containers: containers,
                                pages: pages,
                                paramsFingerprint: params.fingerprint)
    }
}
