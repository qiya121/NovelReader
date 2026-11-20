//
//  ShelfViewModel.swift
//  NovelReader
//
//  书架唯一的状态持有者。所有数据库写入都回到这里再刷新列表，
//  不做增量更新 —— 书架规模是"几百本"，全量重查比维护增量状态更可靠。
//

import Foundation
import Combine

final class ShelfViewModel: ObservableObject {

    // MARK: - 输出

    @Published private(set) var books: [Book] = []
    @Published private(set) var isLoading = true
    @Published private(set) var chapterCounts: [Int64: Int] = [:]

    @Published var sort: BookSort = .recent {
        didSet { reload() }
    }

    @Published var searchText: String = "" {
        didSet { reload() }
    }

    // MARK: - 导入

    @Published var pendingURLs: [URL] = []
    @Published var isImporting = false
    @Published var importProgress: Double = 0
    @Published var importTitle: String = ""

    @Published var duplicateBook: Book?
    @Published var errorMessage: String?
    /// 导入完成后自动打开的书
    @Published var bookToOpen: Book?

    // MARK: - 依赖

    private let store: LibraryStore
    private let importer: BookImporter
    private let textProvider: BookTextProvider

    private let cancelFlag = CancellationFlag()

    init(store: LibraryStore = AppServices.shared.store,
         importer: BookImporter = AppServices.shared.importer) {
        self.store = store
        self.importer = importer
        self.textProvider = BookTextProvider(store: store)
        reload()
    }

    // MARK: - 列表

    func reload() {
        do {
            books = try store.books(sort: sort, search: searchText)
            chapterCounts = try store.chapterCountMap()
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isEmpty: Bool {
        books.isEmpty && !isLoading
    }

    // MARK: - 导入流程

    func handlePicked(urls: [URL]) {
        let textURLs = urls.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "txt" || ext == "text" || ext.isEmpty
        }
        guard !textURLs.isEmpty else {
            errorMessage = "只支持 TXT 纯文本文件"
            return
        }
        pendingURLs = textURLs
    }

    func cancelModeSelection() {
        pendingURLs = []
    }

    /// 用户在章节模式弹窗里选完后执行导入
    func confirmImport(mode: ChapterMode) {
        let urls = pendingURLs
        pendingURLs = []
        guard !urls.isEmpty, !isImporting else { return }

        cancelFlag.reset()
        isImporting = true
        importProgress = 0
        importTitle = BookImporter.defaultTitle(for: urls[0])

        let flag = cancelFlag
        let importer = self.importer
        let total = Double(urls.count)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var importedBooks: [Book] = []
            var firstNotice: String?
            var firstDuplicate: Book?
            var firstError: String?

            for (index, url) in urls.enumerated() {
                if flag.isCancelled { break }

                DispatchQueue.main.async {
                    self?.importTitle = BookImporter.defaultTitle(for: url)
                }

                do {
                    let result = try importer.importSingle(url: url,
                                                           mode: mode,
                                                           isCancelled: { flag.isCancelled },
                                                           progress: { progress in
                        let overall = (Double(index) + progress.fraction) / total
                        DispatchQueue.main.async {
                            self?.importProgress = min(1, overall)
                        }
                    })
                    importedBooks.append(result.book)
                    if firstNotice == nil, let notice = result.notice {
                        firstNotice = notice
                    }
                } catch let duplicate as DuplicateBookError {
                    if firstDuplicate == nil { firstDuplicate = duplicate.book }
                } catch {
                    if firstError == nil { firstError = error.localizedDescription }
                }
            }

            DispatchQueue.main.async {
                self?.isImporting = false
                self?.importProgress = 0
                self?.reload()

                if let notice = firstNotice {
                    Toast.show(notice)
                }
                if let error = firstError {
                    self?.errorMessage = error
                }
                if let duplicate = firstDuplicate {
                    self?.duplicateBook = duplicate
                } else if let first = importedBooks.first {
                    self?.bookToOpen = first
                }
            }
        }
    }

    func cancelImport() {
        cancelFlag.cancel()
        isImporting = false
    }

    // MARK: - 书架操作

    func toggleFavorite(_ book: Book) {
        guard let id = book.id else { return }
        do {
            try store.setFavorite(bookID: id, isFavorite: !book.isFavorite)
            reload()
        } catch {
            errorMessage = "保存失败，请重试"
        }
    }

    func rename(_ book: Book, to title: String) {
        guard let id = book.id else { return }
        do {
            try store.rename(bookID: id, title: title)
            reload()
        } catch {
            errorMessage = "保存失败，请重试"
        }
    }

    func delete(_ book: Book) {
        guard let id = book.id else { return }
        do {
            try store.deleteBook(bookID: id)
            reload()
        } catch {
            errorMessage = "删除失败，请重试"
        }
    }

    func reparse(_ book: Book, mode: ChapterMode) {
        do {
            let result = try textProvider.reparse(book: book, mode: mode)
            reload()
            if let notice = result.notice {
                Toast.show(notice)
            } else {
                Toast.show("已重新解析：\(result.chapters.count) 章")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func bookmarkCount(for book: Book) -> Int {
        guard let id = book.id else { return 0 }
        return (try? store.bookmarkCount(bookID: id)) ?? 0
    }

    func chapterCount(for book: Book) -> Int {
        guard let id = book.id else { return 0 }
        return chapterCounts[id] ?? 0
    }
}

// MARK: - 线程安全的取消标记

final class CancellationFlag {

    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func reset() {
        lock.lock()
        value = false
        lock.unlock()
    }
}
