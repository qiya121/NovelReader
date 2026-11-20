//
//  BookTextProvider.swift
//  NovelReader
//
//  从沙盒里把书读回内存：解码 + 清洗。
//  清洗是确定性操作，同一份文件两次清洗结果一致 —— 这是"offset 永远指向同一处"的前提。
//

import Foundation

final class BookTextProvider {

    private let store: LibraryStore

    init(store: LibraryStore) {
        self.store = store
    }

    /// 读取清洗后的全文（offset 基准）
    func cleanedText(for book: Book) throws -> String {
        let url = AppPaths.absoluteURL(forStoredPath: book.storedPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImportError.failed("原文件已丢失，请重新导入")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw ImportError.failed("文件读取失败")
        }
        let decoded = try TextLoader.decode(data)
        return TextCleaner.clean(decoded.text)
    }

    /// 重新解析章节（长按书架卡片 → 重新解析章节）
    func reparse(book: Book, mode: ChapterMode) throws -> ChapterParseResult {
        let text = try cleanedText(for: book)
        let result = ChapterParser.parse(text: text,
                                         mode: mode,
                                         bookTitle: book.title)
        _ = try store.replaceChapters(bookID: book.id ?? 0,
                                      mode: result.effectiveMode,
                                      parseResult: result,
                                      charCount: book.charCount)
        return result
    }
}
