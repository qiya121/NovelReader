//
//  BookImporter.swift
//  NovelReader
//
//  导入管线（PRD §5.1）
//
//  顺序：读文件 → 编码识别 → 清洗 → SHA-256 去重 → 分章 → 复制进沙盒 → 落库
//  任何一步失败都必须回滚：不留 book 记录、不留 txt 文件、不留 chapters。
//

import Foundation
import CryptoKit

// MARK: - 错误

enum ImportError: LocalizedError, Equatable {
    case databaseWriteFailed
    case bookmarkLimitReached
    case cancelled
    case copyFailed
    case unrecognizedEncoding
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .databaseWriteFailed:  return "保存失败，请重试"
        case .bookmarkLimitReached: return "书签数量已达上限"
        case .cancelled:            return "已取消导入"
        case .copyFailed:           return "文件复制失败，请重试"
        case .unrecognizedEncoding: return "文件编码无法识别，请另存为 UTF-8 后重试"
        case .failed(let message):  return message
        }
    }
}

// MARK: - 进度

struct ImportProgress {
    enum Stage {
        case reading
        case cleaning
        case parsing
        case saving

        var text: String {
            switch self {
            case .reading:  return "正在读取"
            case .cleaning: return "正在整理文本"
            case .parsing:  return "正在解析"
            case .saving:   return "正在入库"
            }
        }
    }

    let stage: Stage
    /// 0~1
    let fraction: Double
}

struct ImportedBook {
    let book: Book
    /// 降级/软提示文案（章节识别为 0、章数过多等）
    let notice: String?
}

// MARK: - 导入器

final class BookImporter {

    private let store: LibraryStore

    init(store: LibraryStore) {
        self.store = store
    }

    // MARK: 单文件导入

    func importSingle(url: URL,
                      mode: ChapterMode,
                      isCancelled: () -> Bool,
                      progress: @escaping (ImportProgress) -> Void) throws -> ImportedBook {

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // 1. 读取 + 编码识别
        progress(ImportProgress(stage: .reading, fraction: 0))
        if isCancelled() { throw ImportError.cancelled }

        let decoded: DecodedText
        do {
            decoded = try TextLoader.load(from: url, progress: { value in
                progress(ImportProgress(stage: .reading, fraction: value))
            })
        } catch let error as TextLoadError {
            throw ImportError.failed(error.errorDescription ?? "读取失败")
        }

        // 2. 清洗（offset 基准在此确定）
        progress(ImportProgress(stage: .cleaning, fraction: 0.15))
        if isCancelled() { throw ImportError.cancelled }
        let cleaned = TextCleaner.clean(decoded.text)
        let charCount = TextCleaner.utf16Length(of: cleaned)
        guard charCount > 0 else {
            throw ImportError.failed("文件内容为空")
        }

        // 3. 去重哈希：输入必须是清洗后文本（补丁 R-02）
        let hash = Self.sha256(of: cleaned)
        if let existing = try? store.book(contentHash: hash) {
            throw DuplicateBookError(book: existing)
        }

        // 4. 分章
        progress(ImportProgress(stage: .parsing, fraction: 0.25))
        let title = Self.defaultTitle(for: url)
        let parseResult = ChapterParser.parse(text: cleaned,
                                              mode: mode,
                                              bookTitle: title,
                                              progress: { value in
            progress(ImportProgress(stage: .parsing, fraction: 0.25 + value * 0.55))
        })
        if isCancelled() { throw ImportError.cancelled }

        // 5. 先把文件复制进沙盒（临时名），保证落库后文件一定在
        let booksDirectory: URL
        do {
            booksDirectory = try AppPaths.ensureBooksDirectory()
        } catch {
            throw ImportError.copyFailed
        }
        let temporaryName = "importing_\(UUID().uuidString).txt"
        let temporaryURL = booksDirectory.appendingPathComponent(temporaryName)
        do {
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try FileManager.default.removeItem(at: temporaryURL)
            }
            try FileManager.default.copyItem(at: url, to: temporaryURL)
        } catch {
            throw ImportError.copyFailed
        }

        // 6. 落库（书 + 章节，单事务）
        progress(ImportProgress(stage: .saving, fraction: 0.85))
        let timestamp = AppClock.now
        let seed = Self.coverSeed(fromHash: hash)
        let placeholder = Book(id: nil,
                               title: title,
                               author: nil,
                               fileName: "",
                               storedPath: "",
                               encoding: decoded.encoding.rawValue,
                               charCount: charCount,
                               chapterMode: parseResult.effectiveMode,
                               isFavorite: false,
                               lastChapterIndex: 0,
                               lastCharOffset: 0,
                               lastPercent: 0,
                               contentHash: hash,
                               coverSeed: seed,
                               settingsOverride: nil,
                               createdAt: timestamp,
                               updatedAt: timestamp)

        let inserted: Book
        do {
            inserted = try store.insertBook(placeholder, chapters: parseResult.chapters)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw ImportError.databaseWriteFailed
        }

        // 7. 重命名为 `{bookId}_{原文件名}.txt` 并回写路径
        guard let bookID = inserted.id else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw ImportError.databaseWriteFailed
        }
        let finalName = AppPaths.storedFileName(bookID: bookID, originalName: url.lastPathComponent)
        let finalURL = booksDirectory.appendingPathComponent(finalName)
        do {
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
        } catch {
            try? store.deleteBook(bookID: bookID)
            try? FileManager.default.removeItem(at: temporaryURL)
            throw ImportError.copyFailed
        }

        var saved = inserted
        saved.fileName = finalName
        saved.storedPath = "books/\(finalName)"
        do {
            try store.updateBook(saved)
        } catch {
            // 路径回写失败：DB 与文件已不一致，回滚整体
            try? store.deleteBook(bookID: bookID)
            throw ImportError.databaseWriteFailed
        }

        progress(ImportProgress(stage: .saving, fraction: 1.0))
        return ImportedBook(book: saved, notice: parseResult.notice)
    }

    // MARK: - 工具

    /// 清洗后文本的 SHA-256（小写十六进制）
    static func sha256(of text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 补丁 R-06：取哈希前 8 个十六进制字符转 UInt32 后 % 8
    static func coverSeed(fromHash hash: String) -> Int {
        let prefix = String(hash.prefix(8))
        let value = UInt32(prefix, radix: 16) ?? 0
        return Int(value % 8)
    }

    /// 默认书名 = 文件名去扩展名
    static func defaultTitle(for url: URL) -> String {
        let name = (url.lastPathComponent as NSString).deletingPathExtension
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名" : trimmed
    }
}

// MARK: - 重复导入

/// 命中已有书籍。用独立类型而不是 ImportError 的 case，是为了把 Book 带出来。
struct DuplicateBookError: LocalizedError {
    let book: Book

    var errorDescription: String? {
        "该文件已导入，是否打开？"
    }
}
