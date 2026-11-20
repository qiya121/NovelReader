//
//  BookmarkListView.swift
//  NovelReader
//
//  书签列表页（P6）—— 书架页左上角 ☆ 进入（PRD §5.4）
//  单本书时只有一个分组；多本书时按书分组。
//

import SwiftUI

struct BookmarkListView: View {

    /// (书籍, 绝对字符偏移)
    let onOpen: (Book, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var groups: [BookmarkGroup] = []
    @State private var clearTarget: BookmarkGroup?
    @State private var errorMessage: String?

    private let store = AppServices.shared.store

    private var isEmpty: Bool { groups.isEmpty }

    var body: some View {
        Group {
            if isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("书签")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .confirmationDialog("清空《\(clearTarget?.bookTitle ?? "")》的全部书签？",
                            isPresented: Binding(get: { clearTarget != nil },
                                                 set: { if !$0 { clearTarget = nil } }),
                            titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                if let group = clearTarget { clear(group) }
                clearTarget = nil
            }
            Button("取消", role: .cancel) { clearTarget = nil }
        } message: {
            Text("清空后不可恢复")
        }
    }

    private var list: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.bookmarks) { bookmark in
                        Button {
                            onOpen(group.book, bookmark.charOffset)
                        } label: {
                            row(bookmark)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(bookmark)
                            } label: {
                                Text("删除")
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text(group.bookTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: 0x1C1C1E))
                            .lineLimit(1)
                        Text("\(group.bookmarks.count)")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: 0x8E8E93))
                        Spacer(minLength: 8)
                        Button("清空") {
                            clearTarget = group
                        }
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: 0x8E8E93))
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func row(_ bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bookmark.excerpt)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: 0x1C1C1E))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                Text(bookmark.chapterTitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0x8E8E93))
                    .lineLimit(1)
                Text("·")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0xC7C7CC))
                Text(AppClock.shortDisplay(bookmark.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0x8E8E93))
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bookmark")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(Color(hex: 0xB0B0B5))
            Text("还没有书签，阅读时点底部书签按钮即可添加")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: 0x8E8E93))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 数据

    private func reload() {
        do {
            let all = try store.bookmarkGroups()
            groups = all.filter { !$0.bookmarks.isEmpty }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ bookmark: Bookmark) {
        guard let id = bookmark.id else { return }
        try? store.deleteBookmark(id: id)
        reload()
    }

    private func clear(_ group: BookmarkGroup) {
        try? store.removeAllBookmarks(bookID: group.bookID)
        reload()
    }
}

// MARK: - 阅读页内的书签浮层

struct ReaderBookmarkSheet: View {

    let bookID: Int64
    var onClose: () -> Void = { }
    let onSelect: (Bookmark) -> Void

    @State private var bookmarks: [Bookmark] = []

    private let store = AppServices.shared.store

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("书签")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: 0x1C1C1E))
                Text("\(bookmarks.count)/\(Bookmark.maxCountPerBook)")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0x8E8E93))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: 0x8E8E93))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            if bookmarks.isEmpty {
                Spacer()
                Text("还没有书签，阅读时点底部书签按钮即可添加")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0x8E8E93))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(bookmarks) { bookmark in
                            Button {
                                onSelect(bookmark)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(bookmark.excerpt)
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(hex: 0x1C1C1E))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    HStack(spacing: 6) {
                                        Text(bookmark.chapterTitle)
                                        Text("·")
                                        Text(AppClock.shortDisplay(bookmark.createdAt))
                                    }
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: 0x8E8E93))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Color.white)
        .onAppear(perform: reload)
    }

    private func reload() {
        bookmarks = (try? store.bookmarks(bookID: bookID)) ?? []
    }
}
