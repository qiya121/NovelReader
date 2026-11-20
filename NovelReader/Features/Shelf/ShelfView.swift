//
//  ShelfView.swift
//  NovelReader
//
//  首页 / 书架页（P1）。PRD §5.3
//  严格约束：首页除「导入」和「书架」外不出现任何额外 Tab 或入口。
//

import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {

    @ObservedObject var model: ShelfViewModel
    @EnvironmentObject private var preferences: ReadingPreferences

    @State private var showFileImporter = false
    @State private var showBookmarks = false
    @State private var renameTarget: Book?
    @State private var renameText = ""
    @State private var deleteTarget: Book?
    @State private var showReparseDialog = false
    @State private var reparseTarget: Book?
    @State private var readerRequest: ReaderRequest?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 0) {
                searchBar
                content
            }
        }
        .navigationTitle("书架")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.plainText, .text],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                model.handlePicked(urls: urls)
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
        // 章节模式选择（导入）
        .sheet(isPresented: Binding(get: { !model.pendingURLs.isEmpty },
                                    set: { if !$0 { model.cancelModeSelection() } })) {
            ChapterModeSheet { mode in
                model.confirmImport(mode: mode)
            }
            .presentationDetents([.height(430)])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: $showBookmarks) {
            BookmarkListView { book, offset in
                showBookmarks = false
                readerRequest = ReaderRequest(book: book, initialOffset: offset)
            }
        }
        .fullScreenCover(item: $readerRequest) { request in
            ReaderScreen(book: request.book, initialOffset: request.initialOffset)
        }
        .overlay { importOverlay }
        .alert("重命名", isPresented: renameBinding) {
            TextField("书名", text: $renameText)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("保存") {
                if let book = renameTarget {
                    model.rename(book, to: renameText)
                }
                renameTarget = nil
            }
        }
        .alert("删除《\(deleteTarget?.title ?? "")》", isPresented: deleteBinding) {
            Button("取消", role: .cancel) { deleteTarget = nil }
            Button("删除", role: .destructive) {
                if let book = deleteTarget { model.delete(book) }
                deleteTarget = nil
            }
        } message: {
            Text("删除后将同时清除该书的书签与进度，不可恢复")
        }
        .alert("该文件已导入，是否打开？", isPresented: duplicateBinding) {
            Button("取消", role: .cancel) { model.duplicateBook = nil }
            Button("打开") {
                if let book = model.duplicateBook {
                    readerRequest = ReaderRequest(book: book, initialOffset: book.lastCharOffset)
                }
                model.duplicateBook = nil
            }
        }
        .alert("提示", isPresented: errorBinding) {
            Button("我知道了", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog("重新解析章节", isPresented: $showReparseDialog, titleVisibility: .visible) {
            ForEach(ChapterMode.allCases) { mode in
                Button(mode.displayName) {
                    if let book = reparseTarget {
                        model.reparse(book, mode: mode)
                    }
                    reparseTarget = nil
                }
            }
            Button("取消", role: .cancel) { reparseTarget = nil }
        } message: {
            Text("重新解析会重建目录，阅读进度按字符位置保留。")
        }
        .onChange(of: model.bookToOpen) { book in
            guard let book else { return }
            readerRequest = ReaderRequest(book: book, initialOffset: book.lastCharOffset)
            model.bookToOpen = nil
        }
    }

    // MARK: - 搜索框

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: 0x8E8E93))
            TextField("搜索书名", text: $model.searchText)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: 0xC7C7CC))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: 0xF2F2F4))
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - 主体

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            skeleton
        } else if model.books.isEmpty {
            if model.isSearching {
                Text("没有找到相关书籍")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0x8E8E93))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ShelfEmptyView { showFileImporter = true }
            }
        } else {
            ScrollView {
                if preferences.shelfUsesListLayout {
                    LazyVStack(spacing: 12) {
                        ForEach(model.books) { book in
                            bookContainer(book) {
                                BookRowView(book: book,
                                            chapterCount: model.chapterCount(for: book),
                                            onToggleFavorite: { model.toggleFavorite(book) })
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 22) {
                        ForEach(model.books) { book in
                            bookContainer(book) {
                                BookCardView(book: book,
                                             chapterCount: model.chapterCount(for: book),
                                             onToggleFavorite: { model.toggleFavorite(book) })
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func bookContainer<Content: View>(_ book: Book,
                                              @ViewBuilder content: () -> Content) -> some View {
        Button {
            readerRequest = ReaderRequest(book: book, initialOffset: book.lastCharOffset)
        } label: {
            content()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("打开阅读") {
                readerRequest = ReaderRequest(book: book, initialOffset: book.lastCharOffset)
            }
            Button(book.isFavorite ? "取消收藏" : "收藏") {
                model.toggleFavorite(book)
            }
            Button("重命名") {
                renameText = book.title
                renameTarget = book
            }
            Button("重新解析章节") {
                reparseTarget = book
                showReparseDialog = true
            }
            Button("删除", role: .destructive) {
                deleteTarget = book
            }
        }
    }

    // MARK: - 骨架屏（PRD §8）

    private var skeleton: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 22) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: 0xF2F2F4))
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: 0xF2F2F4))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: 0xF2F2F4))
                            .frame(width: 60, height: 10)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                showBookmarks = true
            } label: {
                Image(systemName: "star")
                    .font(.system(size: 16, weight: .regular))
            }
            .disabled(model.books.isEmpty)
            .accessibilityLabel("书签列表")
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Menu {
                ForEach(BookSort.allCases) { option in
                    Button {
                        model.sort = option
                    } label: {
                        if model.sort == option {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Text(option.displayName)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 15))
            }

            Button {
                preferences.shelfUsesListLayout.toggle()
            } label: {
                Image(systemName: preferences.shelfUsesListLayout ? "square.grid.2x2" : "list.bullet")
                    .font(.system(size: 15))
            }
            .accessibilityLabel(preferences.shelfUsesListLayout ? "切换网格布局" : "切换列表布局")

            Button {
                showFileImporter = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
            }
            .accessibilityLabel("导入 TXT")
        }
    }

    // MARK: - 导入进度（PRD §8）

    @ViewBuilder
    private var importOverlay: some View {
        if model.isImporting {
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Text("正在解析《\(model.importTitle)》")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: 0x1C1C1E))
                        .lineLimit(1)

                    ProgressView(value: model.importProgress)
                        .progressViewStyle(.linear)

                    HStack {
                        Text("\(Int(model.importProgress * 100))%")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: 0x8E8E93))
                        Spacer()
                        Button("取消") {
                            model.cancelImport()
                        }
                        .font(.system(size: 13))
                    }
                }
                .padding(20)
                .frame(width: 280)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                )
            }
        }
    }

    // MARK: - 绑定

    private var renameBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private var duplicateBinding: Binding<Bool> {
        Binding(get: { model.duplicateBook != nil }, set: { if !$0 { model.duplicateBook = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

// MARK: - 章节模式选择（P4）

struct ChapterModeSheet: View {

    let onSelect: (ChapterMode) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("区分章节方式")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(hex: 0x1C1C1E))
            Text("同一本书用不同方式切分，目录会不同。选错了可以长按书架卡片重新解析。")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: 0x8E8E93))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(ChapterMode.allCases) { mode in
                Button {
                    onSelect(mode)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(mode.displayName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Color(hex: 0x1C1C1E))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: 0xC7C7CC))
                        }
                        Text(mode.summary)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: 0x8E8E93))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: 0xF2F2F4))
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
    }
}
