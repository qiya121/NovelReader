//
//  AppPaths.swift
//  NovelReader
//
//  沙盒内所有路径的唯一出口。
//  约束（PRD §2 / §5.1-2）：只允许读写 App 沙盒，禁止访问沙盒外路径。
//

import Foundation

enum AppPaths {

    /// Documents 目录
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// `Documents/books/` —— 导入时复制的 TXT 备份目录
    static var booksDirectory: URL {
        documents.appendingPathComponent("books", isDirectory: true)
    }

    /// `Application Support/` —— 数据库所在目录
    static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var databaseURL: URL {
        applicationSupport.appendingPathComponent("novelreader.db")
    }

    /// 确保 `Documents/books/` 存在
    @discardableResult
    static func ensureBooksDirectory() throws -> URL {
        let url = booksDirectory
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// 把 `books.stored_path`（相对 Documents 的路径）还原为绝对 URL
    static func absoluteURL(forStoredPath path: String) -> URL {
        documents.appendingPathComponent(path)
    }

    /// 生成沙盒内的存储文件名：`{bookId}_{原文件名}.txt`
    static func storedFileName(bookID: Int64, originalName: String) -> String {
        let base = (originalName as NSString).deletingPathExtension
        let safe = base
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let finalBase = safe.isEmpty ? "未命名" : safe
        return "\(bookID)_\(finalBase).txt"
    }
}
