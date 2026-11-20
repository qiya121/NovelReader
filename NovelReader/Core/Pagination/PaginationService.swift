//
//  PaginationService.swift
//  NovelReader
//
//  分页服务：负责取章节正文、算出标题行长度、管理分页缓存。
//
//  缓存 key = (bookId, chapterIndex, 排版参数指纹)，见 PRD §6。
//  排版参数一变（字号/行距/字体/尺寸/背景），指纹自动变，旧缓存自然失效。
//

import UIKit

final class PaginationService {

    /// 一次阅读会话需要的上下文
    final class Context {
        let book: Book
        let fullText: String
        let chapters: [Chapter]
        private let ns: NSString

        init(book: Book, fullText: String, chapters: [Chapter]) {
            self.book = book
            self.fullText = fullText
            self.chapters = chapters
            self.ns = fullText as NSString
        }

        var fullTextLength: Int { ns.length }

        func chapterText(at index: Int) -> String {
            guard chapters.indices.contains(index) else { return "" }
            let chapter = chapters[index]
            let location = max(0, min(chapter.startOffset, ns.length))
            let length = max(0, min(chapter.charCount, ns.length - location))
            guard length > 0 else { return "" }
            return ns.substring(with: NSRange(location: location, length: length))
        }
    }

    private let cache = NSCache<NSString, PaginatedChapter>()

    init(cacheLimit: Int = 6) {
        cache.countLimit = cacheLimit
    }

    // MARK: - 取分页结果

    func paginatedChapter(index: Int,
                          context: Context,
                          params: TypesettingParams,
                          textColor: UIColor) -> PaginatedChapter {

        guard context.chapters.indices.contains(index) else {
            return Paginator.paginate(chapterIndex: index,
                                      chapterText: "",
                                      inlineTitleLength: 0,
                                      params: params,
                                      textColor: textColor)
        }

        let key = cacheKey(bookID: context.book.id ?? 0, chapterIndex: index, fingerprint: params.fingerprint)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let chapter = context.chapters[index]
        let text = context.chapterText(at: index)
        let titleLength = inlineTitleLength(for: chapter, mode: context.book.chapterMode, chapterText: text)

        let paginated = Paginator.paginate(chapterIndex: index,
                                            chapterText: text,
                                            inlineTitleLength: titleLength,
                                            params: params,
                                            textColor: textColor)
        cache.setObject(paginated, forKey: key)
        return paginated
    }

    func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - 标题行长度

    /// 首行（标题行）含换行符的 UTF-16 长度。
    /// 返回 0 表示本章没有可见标题（不分章模式 / 「正文开始前」）。
    func inlineTitleLength(for chapter: Chapter, mode: ChapterMode, chapterText: String) -> Int {
        guard mode != .none else { return 0 }
        guard chapter.title != ChapterParser.preambleTitle else { return 0 }

        let ns = chapterText as NSString
        guard ns.length > 0 else { return 0 }

        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                        for: NSRange(location: 0, length: 0))
        return min(max(lineEnd, 0), ns.length)
    }

    // MARK: - 全书总页数（后台计算，用于进度按钮的「全书 P 页」）

    /// 注意：在新线程调用。返回 nil 表示已完成但被取消。
    func totalPageCount(context: Context,
                        params: TypesettingParams,
                        textColor: UIColor,
                        isCancelled: () -> Bool,
                        progress: ((Double) -> Void)? = nil) -> Int? {

        var total = 0
        let count = context.chapters.count
        guard count > 0 else { return 0 }

        for index in 0..<count {
            if isCancelled() { return nil }
            let chapter = context.chapters[index]
            let text = context.chapterText(at: index)
            let titleLength = inlineTitleLength(for: chapter,
                                                mode: context.book.chapterMode,
                                                chapterText: text)
            let paginated = Paginator.paginate(chapterIndex: index,
                                               chapterText: text,
                                               inlineTitleLength: titleLength,
                                               params: params,
                                               textColor: textColor)
            total += paginated.pageCount
            if index % 10 == 0 {
                progress?(Double(index + 1) / Double(count))
            }
        }
        return total
    }

    private func cacheKey(bookID: Int64, chapterIndex: Int, fingerprint: String) -> NSString {
        "\(bookID)-\(chapterIndex)-\(fingerprint)" as NSString
    }
}
