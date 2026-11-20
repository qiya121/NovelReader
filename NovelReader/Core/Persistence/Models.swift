//
//  Models.swift
//  NovelReader
//
//  数据模型。字段与 docs/PRD.md §4 + docs/PRD-changes-v1.1.md 逐一对齐。
//
//  【基准 G-01】所有 offset / charCount 的单位是 UTF-16 code unit（NSRange 语义），
//  不是 Swift String 的 Character 数量。任何换算只允许走 String.utf16 或 NSString。
//

import Foundation
import GRDB

// MARK: - 章节区分方式（PRD §5.2）

enum ChapterMode: String, Codable, CaseIterable, Identifiable {
    /// 严格：只认「第X章」
    case strict
    /// 宽松：额外接受中文数字、其他量词、Chapter 1、楔子/番外等
    case loose
    /// 不区分：整本作为一章
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strict: return "严格"
        case .loose:  return "宽松"
        case .none:   return "不区分"
        }
    }

    /// 导入弹窗（P4）的副标题文案
    var summary: String {
        switch self {
        case .strict:
            return "只识别「第X章」这样的行。目录最干净，漏识别的风险也最高。"
        case .loose:
            return "兼容「第一章」「第 1 节」「Chapter 1」「楔子」「番外」等常见写法。适合大多数网络小说。"
        case .none:
            return "不切分章节，整本当一本书读，仍然会正常分页。"
        }
    }
}

// MARK: - books（PRD §4.1）

struct Book: Codable, Equatable, Hashable, Identifiable {
    var id: Int64?
    var title: String
    var author: String?
    /// 沙盒内备份文件名，如 `1_三体.txt`
    var fileName: String
    /// 相对 Documents 的路径，如 `books/1_三体.txt`
    var storedPath: String
    /// 实际采用的编码：`utf8` / `utf16` / `gb18030`
    var encoding: String
    /// 正文字符总数（UTF-16 单位）
    var charCount: Int
    var chapterMode: ChapterMode
    var isFavorite: Bool
    var lastChapterIndex: Int
    var lastCharOffset: Int
    /// 0~1
    var lastPercent: Double
    /// 清洗后文本的 SHA-256（PRD 补丁 R-02）
    var contentHash: String
    /// 封面底色索引 0..7（PRD 补丁 R-06）
    var coverSeed: Int
    /// 单书设置覆盖 JSON，NULL 表示跟随全局（V1 不写入）
    var settingsOverride: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, author, encoding
        case fileName = "file_name"
        case storedPath = "stored_path"
        case charCount = "char_count"
        case chapterMode = "chapter_mode"
        case isFavorite = "is_favorite"
        case lastChapterIndex = "last_chapter_index"
        case lastCharOffset = "last_char_offset"
        case lastPercent = "last_percent"
        case contentHash = "content_hash"
        case coverSeed = "cover_seed"
        case settingsOverride = "settings_override"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension Book: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "books"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// 书架展示用的整数百分比
    var progressPercent: Int {
        Int((min(max(lastPercent, 0), 1) * 100).rounded())
    }

    /// 书名首字（封面占位）
    var initialCharacter: String {
        guard let first = title.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "书"
        }
        return String(first)
    }
}

// MARK: - chapters（PRD §4.2，列名按补丁 S-01 改为 chapter_index）

struct Chapter: Codable, Equatable, Hashable, Identifiable {
    var id: Int64?
    var bookID: Int64
    /// 章节序号，从 0 开始，书内唯一。对应列 `chapter_index`
    var index: Int
    var title: String
    /// 在「清洗后全文」中的起始偏移（UTF-16）
    var startOffset: Int
    /// 结束偏移（不含）
    var endOffset: Int
    var charCount: Int

    enum CodingKeys: String, CodingKey {
        case id, title
        case bookID = "book_id"
        case indexColumn = "chapter_index"
        case startOffset = "start_offset"
        case endOffset = "end_offset"
        case charCount = "char_count"
    }

    init(id: Int64? = nil,
         bookID: Int64,
         index: Int,
         title: String,
         startOffset: Int,
         endOffset: Int,
         charCount: Int) {
        self.id = id
        self.bookID = bookID
        self.index = index
        self.title = title
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.charCount = charCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int64.self, forKey: .id)
        bookID = try container.decode(Int64.self, forKey: .bookID)
        index = try container.decode(Int.self, forKey: .indexColumn)
        title = try container.decode(String.self, forKey: .title)
        startOffset = try container.decode(Int.self, forKey: .startOffset)
        endOffset = try container.decode(Int.self, forKey: .endOffset)
        charCount = try container.decode(Int.self, forKey: .charCount)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(bookID, forKey: .bookID)
        try container.encode(index, forKey: .indexColumn)
        try container.encode(title, forKey: .title)
        try container.encode(startOffset, forKey: .startOffset)
        try container.encode(endOffset, forKey: .endOffset)
        try container.encode(charCount, forKey: .charCount)
    }
}

extension Chapter: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "chapters"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var range: NSRange {
        NSRange(location: startOffset, length: charCount)
    }
}

// MARK: - bookmarks（PRD §4.3）

struct Bookmark: Codable, Equatable, Hashable, Identifiable {
    var id: Int64?
    var bookID: Int64
    var chapterIndex: Int
    /// 书签锚定的绝对字符偏移（UTF-16）
    var charOffset: Int
    /// 该位置起前 30 个字符的摘要
    var excerpt: String
    /// 冗余存储，删除章节后仍能显示
    var chapterTitle: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, excerpt
        case bookID = "book_id"
        case chapterIndex = "chapter_index"
        case charOffset = "char_offset"
        case chapterTitle = "chapter_title"
        case createdAt = "created_at"
    }
}

extension Bookmark: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "bookmarks"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    static let maxCountPerBook = 500
}

// MARK: - 书签列表的联合视图（P6 用，不落库）

struct BookmarkGroup: Identifiable, Equatable {
    var bookID: Int64
    var bookTitle: String
    var book: Book
    var bookmarks: [Bookmark]

    var id: Int64 { bookID }
}

// MARK: - 阅读位置的中间结构（不落库）

/// 章节内的阅读位置
struct ReaderAnchor: Equatable {
    var chapterIndex: Int
    /// 全书绝对偏移（UTF-16）
    var offset: Int
}
